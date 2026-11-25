#!/usr/bin/env python3
"""Starts linux-wallpaperengine for a scene project (called by WallpaperPickerState).

  wallpaperengine_run.py <project folder> [more linux-wallpaperengine arguments ...]

Why: Wallpaper Engine stores colors as 0..1 values. But linux-wallpaperengine reads values without a
decimal point ("1 1 1") as 0..255 -> white becomes 1/255, so almost black (e.g. a missing
white background in workshop item 3546094127). Such colors are passed again here as "1.0 1.0 1.0" with
--set-property. Then exec: the process stays the same, Quickshell can end it.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def color_fixes(folder):
    try:
        props = json.loads((Path(folder) / 'project.json').read_text())['general']['properties']
    except (OSError, ValueError, KeyError, TypeError):
        return []
    args = []
    for name, prop in props.items():
        if not isinstance(prop, dict) or prop.get('type') != 'color':
            continue
        value = str(prop.get('value', '')).strip()
        parts = value.split()
        # Only clear cases: whole numbers 0/1 without a point. Real 0..255 values stay untouched.
        if parts and '.' not in value and all(p in ('0', '1') for p in parts):
            args += ['--set-property', f'{name}=' + ' '.join(p + '.0' for p in parts)]
    return args


def stop_orphans():
    """Quickshell does not end the renderer when it restarts itself -> it would keep running as an orphan
    and double next to the new one. One PID file per start; only orphans are ended (parent
    no longer qs). The old scene of a running change still belongs to qs and stays until
    Quickshell ends it itself after the handover."""
    piddir = Path(os.environ.get('XDG_RUNTIME_DIR') or '/tmp') / 'quickshell-wallpaperengine'
    piddir.mkdir(exist_ok=True)
    for entry in piddir.iterdir():
        try:
            pid = int(entry.name)
            # Only end it if the PID really still belongs to linux-wallpaperengine
            if b'linux-wallpaperengine' not in Path(f'/proc/{pid}/cmdline').read_bytes():
                raise OSError
            ppid = int(Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[1])
            if Path(f'/proc/{ppid}/comm').read_text().strip() == 'qs':
                continue
            os.kill(pid, 15)
        except (OSError, ValueError, IndexError):
            pass
        entry.unlink(missing_ok=True)
    # exec keeps the PID -> our own PID is the renderer's
    (piddir / str(os.getpid())).touch()


def cursor_shim_env():
    """The cursor over the scene should follow the wal colors: the engine loads the cursor theme only once
    at start (before the color change) -> scripts/cursor_follow_shim.c via LD_PRELOAD reloads left_ptr
    as soon as the theme file has changed. It is built per machine into the cache; if that fails,
    the engine simply starts without the shim (then the cursor keeps the color from the start, as before)."""
    src = Path(__file__).with_name('cursor_follow_shim.c')
    out = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'quickshell' / 'cursor_follow_shim.so'
    try:
        if not out.exists() or out.stat().st_mtime < src.stat().st_mtime:
            out.parent.mkdir(parents=True, exist_ok=True)
            tmp = out.with_name(out.name + '.tmp')
            subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-o', str(tmp), str(src), '-ldl'],
                           check=True, capture_output=True, timeout=30)
            os.replace(tmp, out)
    except (OSError, subprocess.SubprocessError):
        return
    preload = os.environ.get('LD_PRELOAD', '')
    if str(out) not in preload.split():
        os.environ['LD_PRELOAD'] = f'{out} {preload}'.strip()


if __name__ == '__main__':
    folder, extra = sys.argv[1], sys.argv[2:]
    stop_orphans()
    cursor_shim_env()
    # Properties before --screen-root, so they apply to all monitors
    if not shutil.which('linux-wallpaperengine'):
        # One clear line for the notification instead of a traceback
        print('Scenes need linux-wallpaperengine, which is not installed.', file=sys.stderr)
        sys.exit(127)
    cmd = ['linux-wallpaperengine', *color_fixes(folder), *extra, folder]
    os.execvp(cmd[0], cmd)
