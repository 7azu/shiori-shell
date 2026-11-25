#!/usr/bin/env python3
"""Facts for the settings window (services/SettingsState.qml): what is installed, which folders exist.

  settings_probe.py [<folder> ...]   -> JSON {programs: {command: bool}, paths: {folder: bool},
                                              optional: [{cmd, what, ok}], info: {host, shell, quickshell, hyprland}}

The optional programs are the ones install.sh lists as optional (PROGRAMS there); keep both lists in step.
"""
import json
import os
import shutil
import socket
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))

OPTIONAL = [
    ("cava", "audio visualizer"), ("mpd", "music"), ("mpc", "music"), ("rmpc", "music player"),
    ("mpv", "video playback"), ("yt-dlp", "downloads"), ("HandBrakeCLI", "video compression"),
    ("uv", "language tool Python packages"), ("rclone", "sync"), ("gocryptfs", "encrypted vault"),
    ("nft", "VPN killswitch"), ("linux-wallpaperengine", "Wallpaper Engine backgrounds"),
    ("bluetoothctl", "bluetooth"), ("upower", "battery"), ("yazi", "file manager"), ("nvim", "editor"),
    ("tmux", "terminal multiplexer"), ("fcitx5", "input method"), ("claude", "Claude usage icon"),
    ("codex", "Codex usage icon"), ("openrgb", "RGB colors from the wallpaper"), ("starship", "prompt"),
    ("hyprsunset", "night light"),
]
# Looked up for rows of the window ("needs"), beyond the optional list
ALSO = ["cliphist", "nmcli"]


def first_line(cmd, cwd=None):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=5, cwd=cwd).stdout.strip()
        return out.splitlines()[0] if out else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def main(argv):
    programs = {cmd: shutil.which(cmd) is not None for cmd in [c for c, _ in OPTIONAL] + ALSO}
    shell_dir = os.path.dirname(os.path.realpath(HERE))
    info = {
        "host": socket.gethostname(),
        "shell": first_line(["git", "log", "-1", "--format=%h, %cd", "--date=short"], cwd=shell_dir),
        # "Quickshell 0.3.2 (revision ...)" -> "0.3.2"
        "quickshell": " ".join(first_line(["qs", "--version"]).split()[1:2]),
        "hyprland": " ".join(first_line(["Hyprland", "--version"]).split()[1:2]),
    }
    print(json.dumps({
        "programs": programs,
        "paths": {p: os.path.isdir(p) for p in argv},
        "optional": [{"cmd": cmd, "what": what, "ok": programs[cmd]} for cmd, what in OPTIONAL],
        "info": info,
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
