#!/usr/bin/env python3
"""Write the Steam colors (Millennium, theme "Minimal Dark") from a palette - like wal, just earlier.

    steam_colors.py '["#rrggbb", ... 16 colors]'

Fills the same templates as wal (~/.config/wal/templates/steam-colors.css and steam-webkit.css) and
writes them where wal writes them: ~/.cache/wal/steam-colors.css is a link to Millennium's
Quick CSS, the plugin "pywal live" reloads it on every change. Quickshell calls this at the start of the
wallpaper wave (services/TerminalColorFade.qml, steamFade): before, the colors only came from wal after the
wave, so late and without a crossfade. wal writes the same content afterwards.
Unchanged content -> the file stays untouched (no reload).
"""
import json
import re
import sys
from pathlib import Path

HOME = Path.home()
TEMPLATES = HOME / ".config/wal/templates"
TARGETS = {
    "steam-colors.css": HOME / ".cache/wal/steam-colors.css",
    "steam-webkit.css": HOME / ".cache/wal/steam-webkit.css",
}


def fill(template, colors):
    def sub(m):
        name, mod = m.group(1), m.group(2)
        value = colors.get(name)
        if value is None:
            return m.group(0)
        if mod == "rgb":
            h = value.lstrip("#")
            return ",".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))
        if mod == "strip":
            return value.lstrip("#")
        return value

    # Like wal: {{ }} = real braces, {name} / {name.mod} = color
    out = re.sub(r"(?<!\{)\{([a-z0-9_]+)(?:\.([a-z_]+))?\}(?!\})", sub, template)
    return out.replace("{{", "{").replace("}}", "}")


def main():
    palette = json.loads(sys.argv[1])
    if len(palette) < 16:
        sys.exit("need 16 colors")
    colors = {f"color{i}": c for i, c in enumerate(palette[:16])}
    # wal: background/foreground = color0 / color15
    colors.update(background=colors["color0"], foreground=colors["color15"], cursor=colors["color15"])
    for name, target in TARGETS.items():
        src = TEMPLATES / name
        if not src.exists():
            continue
        text = fill(src.read_text(), colors)
        # Follow the link (Quick CSS), write in place: Millennium watches the file itself
        dest = target.resolve() if target.is_symlink() else target
        try:
            if dest.read_text() == text:
                continue
        except OSError:
            pass
        dest.write_text(text)


if __name__ == "__main__":
    main()
