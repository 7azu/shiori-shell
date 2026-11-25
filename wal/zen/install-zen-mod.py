#!/usr/bin/env python3
"""Installs the Zen mod "Transparent Zen" (by sameerasw) from Zen's official mod store into Zen profiles,
the same files Zen itself writes when the mod is installed from the store: chrome/zen-themes/<id>/
(chrome.css, preferences.json, readme.md) and an entry in zen-themes.json. Zen builds its mod stylesheet
from these on the next start. The mod takes the wallpaper color from the prefs that wallpaper-apps.sh and
zen-live set (user-prefs.js switches its background color on).

    install-zen-mod.py <profile dir> [...]

A profile that already has the mod is left alone (also when it was switched off by hand).
"""
import json
import sys
import urllib.request
from pathlib import Path

MOD_ID = "642854b5-88b4-4c40-b256-e035532109df"
STORE = f"https://raw.githubusercontent.com/zen-browser/theme-store/main/themes/{MOD_ID}"


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read()


def main(profiles):
    if not profiles:
        return 0
    meta, files = None, {}
    for profile in map(Path, profiles):
        themes_json = profile / "zen-themes.json"
        try:
            themes = json.loads(themes_json.read_text()) if themes_json.exists() else {}
        except (OSError, ValueError):
            print(f"{themes_json} is unreadable, left alone", file=sys.stderr)
            continue
        if MOD_ID in themes:
            continue
        if meta is None:
            meta = json.loads(fetch(f"{STORE}/theme.json"))
            files = {"chrome.css": fetch(meta["style"])}
            for key, name in (("preferences", "preferences.json"), ("readme", "readme.md")):
                if meta.get(key):
                    files[name] = fetch(meta[key])
        folder = profile / "chrome" / "zen-themes" / MOD_ID
        folder.mkdir(parents=True, exist_ok=True)
        for name, data in files.items():
            (folder / name).write_bytes(data)
        themes[MOD_ID] = {**meta, "enabled": True}
        themes_json.write_text(json.dumps(themes, indent=2))
        print(f"Transparent Zen installed in {profile}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
