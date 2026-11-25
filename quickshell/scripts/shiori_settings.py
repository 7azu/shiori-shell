#!/usr/bin/env python3
"""Settings of shiori-shell for scripts (the QML side is services/Settings.qml, same rules).

Defaults: defaults/settings.json in the shell folder. Your own values: ~/.config/shiori-shell/settings.json,
merged over the defaults key by key. In paths, ~, $HOME and the XDG user folders ($PICTURES, $MUSIC,
$DOCUMENTS, $DOWNLOAD, $VIDEOS, $DESKTOP from ~/.config/user-dirs.dirs) are expanded.

  shiori_settings.py folder <key>     print one folder (empty line if unset)
  shiori_settings.py dump             print all settings as JSON

From Python: import shiori_settings; shiori_settings.folder("music")
"""
import json
import os
import re
import sys

HOME = os.path.expanduser("~")
SHELL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULTS = os.path.join(SHELL_DIR, "defaults", "settings.json")
USER = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "shiori-shell", "settings.json")

XDG_FALLBACK = {"PICTURES": "Pictures", "MUSIC": "Music", "DOCUMENTS": "Documents",
                "DOWNLOAD": "Downloads", "VIDEOS": "Videos", "DESKTOP": "Desktop"}


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def user_dirs():
    dirs = {k: os.path.join(HOME, v) for k, v in XDG_FALLBACK.items()}
    path = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "user-dirs.dirs")
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r'\s*XDG_([A-Z]+)_DIR="(.*)"', line)
                if m:
                    dirs[m.group(1)] = m.group(2).replace("$HOME", HOME)
    except OSError:
        pass
    return dirs


def expand(path, dirs=None):
    if not path:
        return ""
    dirs = dirs or user_dirs()
    if path == "~" or path.startswith("~/"):
        path = HOME + path[1:]
    path = re.sub(r"\$([A-Z]+)", lambda m: HOME if m.group(1) == "HOME" else dirs.get(m.group(1), m.group(0)), path)
    return path.rstrip("/") or "/"


def load():
    settings = _read(DEFAULTS)
    for key, value in _read(USER).items():
        if isinstance(value, dict) and isinstance(settings.get(key), dict):
            settings[key] = {**settings[key], **value}
        else:
            settings[key] = value
    return settings


def folder(key):
    return expand(load().get("folders", {}).get(key, ""))


def language_folders():
    dirs = user_dirs()
    return {name: expand(p, dirs) for name, p in load().get("languageFolders", {}).items()}


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "folder":
        print(folder(sys.argv[2]))
    elif len(sys.argv) == 2 and sys.argv[1] == "dump":
        print(json.dumps(load(), ensure_ascii=False, indent=2))
    else:
        print((__doc__ or "").strip(), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
