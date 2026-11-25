#!/usr/bin/env python3
"""Builds a Chromium theme (unpacked extension) for Helium from the wal colors.

Output: ~/.cache/wal/helium-theme/manifest.json. Helium loads it with --load-extension
(flag in ~/.config/helium-browser-flags.conf); apply-helium-color.sh reloads it live.
"""
import json
import os

home = os.path.expanduser("~")
wal = json.load(open(f"{home}/.cache/wal/colors.json"))
c = {k: v for k, v in wal["colors"].items()}
bg, fg = wal["special"]["background"], wal["special"]["foreground"]


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def mix(a, b, t):
    """t share of b in a (0..1)."""
    return [round(x + (y - x) * t) for x, y in zip(rgb(a), rgb(b))]


colors = {
    # Window bar + inactive tabs: wal background (like Zen)
    "frame":                      rgb(bg),
    "frame_inactive":             rgb(bg),
    "frame_incognito":            mix(bg, c["color1"], 0.15),
    "frame_incognito_inactive":   mix(bg, c["color1"], 0.15),
    "background_tab":             rgb(bg),
    "background_tab_inactive":    rgb(bg),
    # active tab + toolbar: a touch lighter, so the tab stands out
    "toolbar":                    mix(bg, fg, 0.07),
    # Address bar: between the bar and the toolbar
    "omnibox_background":         mix(bg, fg, 0.12),
    "omnibox_text":               rgb(fg),
    # Text & icons: wal foreground, inactive tabs dimmed
    "tab_text":                   rgb(fg),
    "tab_background_text":        rgb(c["color8"]),
    "tab_background_text_inactive": rgb(c["color8"]),
    "toolbar_text":               rgb(fg),
    "toolbar_button_icon":        rgb(fg),
    "bookmark_text":              rgb(fg),
    # New tab
    "ntp_background":             rgb(bg),
    "ntp_text":                   rgb(fg),
    "ntp_link":                   rgb(c["color5"]),
    "ntp_header":                 rgb(c["color5"]),
}

out = f"{home}/.cache/wal/helium-theme"
os.makedirs(out, exist_ok=True)
manifest = {
    "manifest_version": 3,
    "name": "wal",
    "version": "1.0",
    "description": "pywal-Farben (generiert von ~/.config/wal/helium/gen-helium-theme.py)",
    "theme": {"colors": colors},
}
with open(f"{out}/manifest.json", "w") as f:
    json.dump(manifest, f, indent=1)
