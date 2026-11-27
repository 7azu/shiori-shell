#!/usr/bin/env python3
"""Writes the hypridle configuration from the settings ("idle" in settings.json) and prints its path.

  idle_config.py            write $XDG_RUNTIME_DIR/shiori-hypridle.conf
  idle_config.py --print    only print the configuration

Steps, each in minutes without input (defaults in quickshell/defaults/settings.json). Each has a
switch "<step>On" (the settings window shows it beside the minutes); off or 0 minutes = the step is off:
  dim        the screen turns darker softly (Quickshell overlay, services/IdleState.qml)
  lock       lock screen
  screenOff  monitors off (back on with any input)
  suspend    standby
Videos, games, calls and "Keep awake" (screen dropdown) hold all steps back: they inhibit idle.

Started by hypr/scripts/idle.sh at login and again by IdleState when a value changes.
For tests: SHIORI_SETTINGS = another settings.json, SHIORI_IDLE_OUT = another output file.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
DEFAULTS = os.path.join(HERE, "..", "defaults", "settings.json")
KEYS = ("dim", "lock", "screenOff", "suspend")


def read_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def minutes():
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    own = read_json(os.environ.get("SHIORI_SETTINGS") or os.path.join(config, "shiori-shell", "settings.json"))
    base = read_json(DEFAULTS).get("idle", {})
    mine = own.get("idle", {}) if isinstance(own.get("idle"), dict) else {}
    out = {}
    for key in KEYS:
        value = mine.get(key, base.get(key, 0))
        try:
            out[key] = max(0, int(round(float(value))))
        except (TypeError, ValueError):
            out[key] = int(base.get(key, 0) or 0)
        if mine.get(key + "On", base.get(key + "On", True)) is False:
            out[key] = 0
    return out


def config(steps):
    home = os.path.expanduser("~")
    dpms_on = "hyprctl dispatch 'hl.dsp.dpms({action = \"on\"})'"
    lines = [
        "# Written by quickshell/scripts/idle_config.py from the settings (\"idle\"); changes here are overwritten.",
        "general {",
        f"    lock_cmd = {home}/.config/hypr/scripts/lock.sh",
        "    before_sleep_cmd = loginctl lock-session",
        # Monitors on after waking up; the fan colors again (the USB controller is re-initialized on resume)
        f"    after_sleep_cmd = {dpms_on}; sleep 3; systemctl --user restart openrgb.service",
        "}",
    ]

    def listener(mins, on_timeout, on_resume=None, note=""):
        lines.extend(["", f"# {note}", "listener {", f"    timeout = {mins * 60}", f"    on-timeout = {on_timeout}"])
        if on_resume:
            lines.append(f"    on-resume = {on_resume}")
        lines.append("}")

    if steps["dim"]:
        listener(steps["dim"], "qs ipc call idle dim", "qs ipc call idle undim", f"darker after {steps['dim']} min")
    if steps["lock"]:
        listener(steps["lock"], "loginctl lock-session", None, f"lock after {steps['lock']} min")
    if steps["screenOff"]:
        listener(steps["screenOff"], "hyprctl dispatch 'hl.dsp.dpms({action = \"off\"})'", dpms_on,
                 f"monitors off after {steps['screenOff']} min")
    if steps["suspend"]:
        listener(steps["suspend"], "systemctl suspend", None, f"standby after {steps['suspend']} min")
    return "\n".join(lines) + "\n"


def main():
    text = config(minutes())
    if "--print" in sys.argv:
        sys.stdout.write(text)
        return
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    out = os.environ.get("SHIORI_IDLE_OUT") or os.path.join(runtime, "shiori-hypridle.conf")
    with open(out, "w") as fh:
        fh.write(text)
    print(out)


if __name__ == "__main__":
    main()
