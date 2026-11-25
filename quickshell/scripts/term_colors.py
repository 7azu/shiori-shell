#!/usr/bin/env python3
"""Set terminal colors live (for services/TerminalColorFade.qml).

On a wallpaper change wal colors the terminals (kitty ...) only when it is done itself - after the
wallpaper wave, in one step. But Quickshell knows the target palette from the start and fades its
own colors step by step (WalColors). This script gets every step as a line and writes the same
escape sequences as wal (~/.cache/wal/sequences) to all of the user's terminals: so the terminals fade
in sync. When wal comes afterwards, it only sets the same final colors.

Input (stdin), per line: 16 colors "#rrggbb" (color0 .. color15), separated by spaces.
Background = color0, foreground = color15 (as with wal).
"""

import os
import re
import sys
import subprocess
import time
from pathlib import Path

HEX = re.compile(r"#[0-9a-fA-F]{6}")


def osc(code, value):
    return f"\033]{code};{value}\033\\"


def pane_sequences(cs):
    # Keep tmux's default background inherited from Kitty. OSC 11 would turn
    # default cells into explicit RGB cells, racing Kitty's independent fade.
    return "".join(osc(4, f"{i};{c}") for i, c in enumerate(cs)).encode()


def tmux_panes():
    try:
        result = subprocess.run(
            ["tmux", "list-panes", "-a", "-F", "#{pane_tty}"],
            capture_output=True, text=True, timeout=0.3,
        )
        if result.returncode == 0:
            return set(result.stdout.splitlines())
    except (OSError, subprocess.TimeoutExpired):
        pass
    return set()


def sequences(cs):
    fg, bg = cs[15], cs[0]
    out = [osc(4, f"{i};{c}") for i, c in enumerate(cs)]
    # like wal: foreground/background, cursor, mouse, selection, extra colors 232/256, border (urxvt)
    out += [osc(10, fg), osc(11, bg), osc(12, fg), osc(13, fg), osc(17, fg), osc(19, bg),
            osc(4, f"232;{bg}"), osc(4, f"256;{fg}"), osc(708, bg)]
    return "".join(out).encode()


def terminals():
    uid = os.getuid()
    for name in os.listdir("/dev/pts"):
        if not name.isdigit():
            continue
        path = "/dev/pts/" + name
        try:
            if os.stat(path).st_uid == uid:
                yield path
        except OSError:
            pass


def main():
    # Atomic frames for Neovim: no RPC process or signal per animation step.
    frame = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "wal" / "terminal-frame"
    frame.parent.mkdir(parents=True, exist_ok=True)
    panes, reset_panes = set(), set()
    last_scan = 0.0
    for line in sys.stdin:
        cs = line.split()
        if len(cs) != 16 or not all(HEX.fullmatch(c) for c in cs):
            continue
        try:
            temporary = frame.with_name(frame.name + "." + str(os.getpid()))
            temporary.write_text(" ".join(cs) + "\n")
            temporary.replace(frame)
        except OSError:
            pass
        now = time.monotonic()
        if now - last_scan > 1.0:
            panes = tmux_panes()
            reset_panes.intersection_update(panes)
            last_scan = now
        data = sequences(cs)
        pane_data = pane_sequences(cs)
        for path in terminals():
            try:
                # non-blocking: a hanging terminal must not hold up the fade
                fd = os.open(path, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
                try:
                    if path in panes:
                        # Clear overrides left by the previous helper once.
                        reset = b"" if path in reset_panes else (osc(110, "") + osc(111, "")).encode()
                        os.write(fd, reset + pane_data)
                        reset_panes.add(path)
                    else:
                        os.write(fd, data)
                finally:
                    os.close(fd)
            except OSError:
                pass


if __name__ == "__main__":
    main()
