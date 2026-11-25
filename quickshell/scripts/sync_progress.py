#!/usr/bin/env python3
"""Progress of the sync scripts for the sync dropdown of the Quickshell bar.

Every sync entry writes its state to
$XDG_RUNTIME_DIR/sync-progress/<id>.json; Quickshell (services/SyncProgress.qml) reads the files
while a sync runs or the dropdown is open. Content:

  run      start of the run (Unix seconds)     time     last change
  state    running | ok | error | offline | locked | 2fa
  step, steps, label    current step (1-based), count, its text
  pct, detail           progress within the step (git: percent, size | speed)
  up, down              the first files per direction as [status, path], upCount/downCount = all
  summary               result text after the run
  owner                 PID of the shell's run (shiori_sync.py run), kept by start: while a file says
                        "running" but this process is gone, the run was killed (shiori_sync.py check)

From the shell:
  sync_progress.py start <id> [<steps>]
  sync_progress.py step <id> <step> <text>
  sync_progress.py files <id> up|down [--strip PREFIX]   (stdin: output of git diff --name-status)
  sync_progress.py done <id> <state> [<result>]
  sync_progress.py run <id> -- git fetch --progress ...   (take the percentage from git, the exit code stays)
      SYNC_PROGRESS_STALL=<seconds> in the environment: stop the command after that long without any
      output (stalled connection), exit code 124

From Python (git_sync.py): import sync_progress; sync_progress.start("notes", 5) ...
Errors while writing are ignored: the display must never hold up the sync.
"""

import json
import os
import re
import select
import subprocess
import sys
import time
from pathlib import Path

SHOWN_FILES = 6
DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "sync-progress"
GIT_PROGRESS = re.compile(
    r"(Receiving|Writing) objects:\s+(\d+)%\s*\(\d+/\d+\)(?:,\s*([\d.]+ \w+))?(?:\s*\|\s*([\d.]+ \w+/s))?")


def _path(part):
    return DIR / (part + ".json")


def _load(part):
    try:
        return json.loads(_path(part).read_text())
    except (OSError, ValueError):
        return {}


def _save(part, data):
    try:
        DIR.mkdir(parents=True, exist_ok=True)
        data["time"] = time.time()
        tmp = _path(part).with_suffix(".tmp")
        tmp.write_text(json.dumps(data, separators=(",", ":")))
        tmp.replace(_path(part))
    except OSError:
        pass


def update(part, **fields):
    data = _load(part)
    data.update(fields)
    _save(part, data)


def alive(pid):
    return bool(pid) and os.path.exists(f"/proc/{pid}")


def stale(data):
    """The file still says running, but the run of the shell that owned it is gone (killed)."""
    return data.get("state") == "running" and bool(data.get("owner")) and not alive(data["owner"])


def start(part, steps=0, owner=None):
    data = {"run": time.time(), "state": "running", "step": 0, "steps": steps, "label": "Starting",
            "pct": -1, "detail": "", "up": [], "upCount": 0, "down": [], "downCount": 0, "summary": ""}
    # A sync script that reports its own start inside a run of the shell keeps that run's owner
    old = _load(part)
    if not owner and old.get("state") == "running" and alive(old.get("owner")):
        owner = old["owner"]
    if owner:
        data["owner"] = owner
    _save(part, data)


def step(part, number, label):
    update(part, step=number, label=label, pct=-1, detail="")


def files(part, direction, entries, strip=""):
    """entries: [(status, path), ...] as from git diff --name-status (R100 -> R)."""
    shown = [[kind[:1], path[len(strip):] if strip and path.startswith(strip) else path]
             for kind, path in entries[:SHOWN_FILES]]
    update(part, **{direction: shown, direction + "Count": len(entries)})


def done(part, state, summary=""):
    update(part, state=state, summary=summary, pct=-1, detail="")


def parse_name_status(text):
    entries = []
    for line in text.splitlines():
        cols = line.split("\t")
        if len(cols) >= 2 and cols[0]:
            entries.append((cols[0], cols[-1]))
    return entries


def run(part, cmd, timeout=None):
    """Starts cmd (git fetch/push with --progress) and takes over its percentage display. Other output
    on stderr is passed through. Returns the exit code. timeout = seconds without any output (a stalled
    connection) -> subprocess.TimeoutExpired; a transfer that still reports progress is never cut off,
    however long it takes."""
    proc = subprocess.Popen(cmd, stderr=subprocess.PIPE)
    buffer = b""
    last_write = 0.0
    last = None
    assert proc.stderr is not None
    fd = proc.stderr.fileno()
    while True:
        ready, _, _ = select.select([fd], [], [], timeout or None)
        if not ready:
            proc.kill()
            proc.wait()
            raise subprocess.TimeoutExpired(cmd, timeout or 0)
        chunk = os.read(fd, 4096)
        if not chunk:
            break
        buffer += chunk
        # git overwrites its progress line with \r, finished lines end with \n
        *lines, buffer = re.split(rb"[\r\n]", buffer)
        for raw in lines:
            line = raw.decode(errors="replace")
            match = GIT_PROGRESS.search(line)
            if not match:
                if line.strip() and not re.search(r"\d+%", line):
                    sys.stderr.write(line + "\n")
                continue
            pct = int(match.group(2))
            detail = " · ".join(x for x in (match.group(3), match.group(4)) if x)
            now = time.monotonic()
            if (pct, detail) != last and (now - last_write > 0.25 or pct == 100):
                update(part, pct=pct, detail=detail)
                last_write, last = now, (pct, detail)
    return proc.wait()


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 64
    command, part = argv[0], argv[1]
    if command == "run":
        cmd = argv[3:] if argv[2:3] == ["--"] else argv[2:]
        try:
            stall = float(os.environ.get("SYNC_PROGRESS_STALL") or 0)
        except ValueError:
            stall = 0
        try:
            return run(part, cmd, timeout=stall or None)
        except subprocess.TimeoutExpired:
            return 124
        except OSError:
            return 127
    if command == "start":
        start(part, int(argv[2]) if len(argv) > 2 else 0)
    elif command == "step":
        step(part, int(argv[2]), argv[3])
    elif command == "files":
        strip = argv[argv.index("--strip") + 1] if "--strip" in argv else ""
        files(part, argv[2], parse_name_status(sys.stdin.read()), strip)
    elif command == "done":
        done(part, argv[2], argv[3] if len(argv) > 3 else "")
    else:
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
