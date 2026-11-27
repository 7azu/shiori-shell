#!/usr/bin/env python3
"""Which tray programs can be brought up with a click, and which only have a menu (services/TrayState.qml).

One JSON line: {"menuOnly": ["steam", ...]}   ids of the programs without an "Activate" action.

A tray program (StatusNotifierItem) may offer "Activate" (a click brings its window up). Programs built on
AppIndicator (Steam, many Electron apps) do not: all they have is their menu, and a click that asks them
to activate does nothing. Quickshell does not tell the two apart, so this asks D-Bus: the tray host lists
the registered programs, and each one's interface shows whether it has the method.

Uses busctl (part of systemd). Anything that fails counts as "can be activated", the old behavior.
"""

import json
import re
import subprocess
import sys

WATCHER = "org.kde.StatusNotifierWatcher"
ITEM = "org.kde.StatusNotifierItem"


def busctl(*args):
    try:
        done = subprocess.run(["busctl", "--user", *args], capture_output=True, text=True, timeout=4)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout if done.returncode == 0 else ""


def registered():
    """[(bus name, object path)] of the programs in the tray."""
    out = busctl("get-property", WATCHER, "/StatusNotifierWatcher", WATCHER, "RegisteredStatusNotifierItems")
    items = []
    for entry in re.findall(r'"([^"]+)"', out):
        # ":1.59/org/ayatana/NotificationItem/steam", or only a bus name (then the usual path)
        cut = entry.find("/")
        items.append((entry, "/StatusNotifierItem") if cut == -1 else (entry[:cut], entry[cut:]))
    return items


def main():
    menu_only = []
    for name, path in registered():
        methods = busctl("introspect", name, path, ITEM)
        if not methods:
            continue
        has_activate = any(line.split()[:2] == [".Activate", "method"] for line in methods.splitlines())
        found = re.search(r'"([^"]*)"', busctl("get-property", name, path, ITEM, "Id"))
        if found and not has_activate:
            menu_only.append(found.group(1))
    json.dump({"menuOnly": menu_only}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
