#!/usr/bin/env python3
"""Read the signed-in Codex account limits via the CLI app-server protocol."""

import json
import os
import selectors
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from media.mediakit.system import user_bin_dirs

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "quickshell" / "codex-limits.json"


class LimitError(Exception):
    pass


def send(process, message):
    process.stdin.write(json.dumps(message).encode() + b"\n")
    process.stdin.flush()


def responses(process, deadline):
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        pending = b""
        while selector.select(max(0, deadline - time.monotonic())):
            if time.monotonic() >= deadline:
                break
            data = os.read(process.stdout.fileno(), 65536)
            if not data:
                raise LimitError("Codex app-server closed the connection")
            lines = (pending + data).split(b"\n")
            pending = lines.pop()
            for line in lines:
                try:
                    packet = json.loads(line)
                except ValueError:
                    continue
                if isinstance(packet, dict):
                    yield packet
        raise LimitError("Codex limit request timed out")


def fetch():
    user_bin_dirs()
    codex = shutil.which("codex")
    if not codex:
        raise LimitError("Codex CLI not found in Quickshell's PATH")

    # Stdio is the app-server default, including older CLI releases.
    process = subprocess.Popen(
        [codex, "app-server"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    try:
        send(process, {"id": 0, "method": "initialize", "params": {
            "clientInfo": {"name": "quickshell", "version": "1.0"},
        }})
        for packet in responses(process, time.monotonic() + 8):
            if packet.get("id") == 0:
                if "error" in packet:
                    raise LimitError("Codex app-server initialization failed")
                send(process, {"method": "initialized"})
                send(process, {"id": 1, "method": "account/rateLimits/read"})
            elif packet.get("id") == 1:
                if "error" in packet:
                    error = packet.get("error") or {}
                    message = str(error.get("message", "")).lower()
                    if "429" in message:
                        raise LimitError("Codex account rate limited")
                    if error.get("code") == -32601:
                        raise LimitError("Codex CLI does not support account limit requests")
                    if any(word in message for word in ("401", "sign in", "logged in", "authentication")):
                        raise LimitError("Codex account sign-in required")
                    raise LimitError("Codex account limits unavailable")
                return packet.get("result") or {}
    finally:
        process.terminate()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdin.close()
        process.stdout.close()


def normalize(result):
    snapshot = (result.get("rateLimitsByLimitId") or {}).get("codex") or result.get("rateLimits") or {}
    if snapshot.get("limitId") not in (None, "codex"):
        raise LimitError("No Codex limit windows returned")
    windows = {}
    for name in ("primary", "secondary"):
        window = snapshot.get(name)
        if isinstance(window, dict) and isinstance(window.get("usedPercent"), (int, float)):
            windows[name] = {
                "used_percent": window["usedPercent"],
                "resets_at": window.get("resetsAt"),
                "window_minutes": window.get("windowDurationMins"),
            }
    if not windows:
        raise LimitError("No Codex limit windows returned")
    return {"updated": time.time(), **windows}


def write_cache(limits):
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=CACHE.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(limits, stream)
        temporary.replace(CACHE)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def main():
    try:
        limits = normalize(fetch())
    except (LimitError, OSError) as error:
        print(json.dumps({"ok": False, "error": str(error) if isinstance(error, LimitError) else "Codex CLI unavailable"}))
        return

    try:
        write_cache(limits)
    except OSError:
        pass
    print(json.dumps({"ok": True, "limits": limits}))


if __name__ == "__main__":
    main()
