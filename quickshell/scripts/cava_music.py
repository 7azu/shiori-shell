#!/usr/bin/env python3
"""cava for the music only (for CavaService.qml).

Under PipeWire, cava itself can only capture the whole output monitor (so also Discord etc.).
Instead this script records ONLY the stream of the active music player with pw-record and
passes it to cava via stdin (fifo input). cava's output (raw ascii) goes to stdout, but only
while someone is watching: CavaService writes "1"/"0" to stdin (audio dropdown open/closed). When closed,
cava keeps running (autosens stays settled), the 60 lines/s are dropped here instead of in Quickshell,
and the stream is looked up less often.

Player choice as in AudioState.qml: a playing non-browser player before a playing browser.
Stream mapping: by the process ID of the MPRIS player, otherwise by name (mpd, spotify, firefox ...).
If nothing plays, silence is sent -> the bars fade out softly.

Usage: cava_music.py <bars> <noise_reduction>
"""

import ctypes
import json
import os
import re
import select
import signal
import subprocess
import sys
import threading
import time

RATE = 48000
CHANNELS = 2
BYTES_PER_FRAME = 2 * CHANNELS  # s16
SILENCE_CHUNK = b"\0" * (RATE // 20 * BYTES_PER_FRAME)  # 50 ms
BROWSERS = ("firefox", "zen", "chrom", "brave", "vivaldi", "librewolf", "floorp")
RESOLVE_INTERVAL = 2.0
RESOLVE_INTERVAL_IDLE = 6.0  # nobody is watching


def die_with_parent():
    """Child processes (cava, pw-record) die with it, even if this script is killed hard.
    SIGKILL instead of SIGTERM: cava catches SIGTERM and then stayed behind as an orphan (one per Quickshell restart)."""
    try:
        ctypes.CDLL("libc.so.6").prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG
    except OSError:
        pass


def run(cmd, timeout=2):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def playing_player():
    """Bus name (without prefix) of the playing player; non-browsers preferred."""
    # One call for all players (before: one for the list and one per player)
    playing = []
    for line in run(["playerctl", "-a", "status", "--format", "{{playerInstance}}\t{{status}}"]).splitlines():
        name, _, status = line.partition("\t")
        if name.strip() and status.strip() == "Playing":
            playing.append(name.strip())
    for p in playing:
        if not any(b in p.lower() for b in BROWSERS):
            return p
    return playing[0] if playing else None


def player_pid(name):
    out = run(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
               "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", "org.mpris.MediaPlayer2." + name])
    m = re.search(r"u (\d+)", out)
    return int(m.group(1)) if m else None


def output_streams():
    # pactl only returns the playback streams (a few hundred bytes); pw-dump printed the
    # whole graph every time (several hundred KB of JSON every 2 s)
    try:
        data = json.loads(run(["pactl", "-f", "json", "list", "sink-inputs"], timeout=3) or "[]")
    except ValueError:
        return []
    streams = []
    for o in data:
        p = o.get("properties") or {}
        serial = p.get("object.serial")
        if serial is None:
            continue
        streams.append({"serial": str(serial), "pid": p.get("application.process.id"),
                        "names": " ".join(str(p.get(k, "")) for k in ("application.name", "application.process.binary",
                                                                     "node.name")).lower(),
                        "running": not o.get("corked", False)})
    return streams


def resolve_target():
    player = playing_player()
    if not player:
        return None
    streams = output_streams()
    pid = player_pid(player)
    cands = [s for s in streams if pid is not None and str(s["pid"]) == str(pid)]
    if not cands:
        base = player.split(".")[0].lower()  # "firefox.instance_1_12" -> "firefox"
        cands = [s for s in streams if base and base in s["names"]]
    if not cands:
        return None
    cands.sort(key=lambda s: 0 if s["running"] else 1)
    return cands[0]["serial"]


def main():
    # The script itself also dies with Quickshell: otherwise it stayed behind as an orphan
    # (parent systemd) together with the pw-record recording after every Quickshell restart
    die_with_parent()
    bars = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    noise = int(sys.argv[2]) if len(sys.argv) > 2 else 77
    # own file per variant: CavaService (dropdown ring) and DesktopCavaService run at the same time with
    # different bands - with a shared file each cava read what the other one had written last
    run_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    conf = os.path.join(run_dir, f"qs-cava-music-{bars}-{noise}.conf")
    with open(conf, "w") as fh:
        fh.write("\n".join([
            "[general]", f"bars={bars}", "framerate=60", "autosens=1", "sleep_timer=0",
            "lower_cutoff_freq=50", "higher_cutoff_freq=10000",
            "[input]", "method=fifo", "source=/dev/stdin", f"sample_rate={RATE}", "sample_bits=16",
            "[output]", "method=raw", "raw_target=/dev/stdout", "data_format=ascii", "ascii_max_range=1000",
            "channels=mono", "mono_option=average",
            "[smoothing]", f"noise_reduction={noise}", ""]))
    # Quickshell ends the script with SIGTERM -> clean up properly (finally below)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    cava = subprocess.Popen(["cava", "-p", conf], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            preexec_fn=die_with_parent)

    # watched: is someone watching right now? Without control over stdin (called by hand) always yes
    state = {"target": None, "rec": None, "watched": True}
    lock = threading.Lock()

    def control():
        for line in sys.stdin:
            cmd = line.strip()
            if cmd in ("0", "1"):
                state["watched"] = cmd == "1"

    def forward():
        out = sys.stdout.buffer
        try:
            for line in cava.stdout:
                if state["watched"]:
                    out.write(line)
                    out.flush()
        except (BrokenPipeError, ValueError):
            pass

    if not sys.stdin.isatty():
        threading.Thread(target=control, daemon=True).start()
    threading.Thread(target=forward, daemon=True).start()

    def resolver():
        while cava.poll() is None:
            target = resolve_target()
            with lock:
                if target != state["target"]:
                    if state["rec"]:
                        state["rec"].kill()
                        state["rec"].wait()
                        state["rec"] = None
                    state["target"] = target
                    if target:
                        state["rec"] = subprocess.Popen(
                            ["pw-record", "--target", target, "--raw", "--format", "s16", "--rate", str(RATE),
                             "--channels", str(CHANNELS), "-P", "{ node.name = \"qs-cava-music\" node.dont-reconnect = true }", "-"],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, preexec_fn=die_with_parent)
            time.sleep(RESOLVE_INTERVAL if state["watched"] else RESOLVE_INTERVAL_IDLE)

    threading.Thread(target=resolver, daemon=True).start()

    # Feeder: recorder data to cava; without data -> silence in real time, so cava keeps running
    try:
        while cava.poll() is None:
            with lock:
                rec = state["rec"]
            data = b""
            if rec and rec.poll() is None:
                r, _, _ = select.select([rec.stdout], [], [], 0.05)
                if r:
                    data = os.read(rec.stdout.fileno(), 16384)
            else:
                time.sleep(0.05)
            cava.stdin.write(data if data else SILENCE_CHUNK)
            cava.stdin.flush()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        with lock:
            if state["rec"]:
                state["rec"].kill()
        cava.kill()


if __name__ == "__main__":
    main()
