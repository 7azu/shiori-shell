#!/usr/bin/env python3
"""Switch the Steam theme "Minimal Dark" (Millennium) to pywal colors.

The theme only sets part of its colors via --minimal_dark_* variables, the rest
(~600 different values, e.g. #121212, #dcdedf, Steam blue) is fixed in the CSS files
and so stayed the same with every wallpaper. This script replaces the fixed colors with
expressions with three variables that the wal templates set:

    --wal_bg  {background}    --wal_fg  {foreground}    --wal_accent  {color4}

  - gray/black: position between the theme background (#121212) and text (#dcdedf) in OKLab
    -> the same mix of wal background and foreground (gradations + contrast stay)
  - blue/turquoise/purple (Steam accent): hue and saturation of color4, lightness as in the original
  - red/green/yellow/orange (errors, discounts, status), pure black/white, transparent: stay
Every variable has the original as the fallback value -> without wal colors everything looks as before.

Client windows get the variables via elements/config.css or Quick CSS (reloaded live
by the plugin "pywal live"), the store (webkit.css) via the import elements/wal-webkit.css.

Idempotent: patched files carry a marker line with a version; the originals lie in
~/.local/state/wal-steam/orig. New/updated theme files (without a marker) are backed up as a new
original and patched. Runs on every wallpaper change (wallpaper-apps.sh).
Steam only loads patched files after a restart; afterwards it recolors live.

    patch-theme.py [--theme DIR] [--state DIR] [--force]
"""

import argparse
import math
import os
import re
import sys
from pathlib import Path

VERSION = 1
MARKER = "/* wal-patched v{} - ~/.config/wal/steam/patch-theme.py, Original: {} */\n"
MARKER_RE = re.compile(r"\A/\* wal-patched v(\d+) ")
WEBKIT_IMPORT = '@import url("elements/wal-webkit.css");\n'

HOME = Path.home()
DEFAULT_THEME = HOME / ".local/share/Steam/millennium/themes/Minimal-Dark-for-Steam"
DEFAULT_STATE = HOME / ".local/state/wal-steam"
WAL_WEBKIT = HOME / ".cache/wal/steam-webkit.css"

# Background and foreground of the theme, against which the gray tones are measured
REF_BG = "#121212"
REF_FG = "#dcdedf"
NEUTRAL_C = 0.04            # OKLab chroma below this = gray tone
ACCENT_HUE = (170, 330)     # OKLab hue: turquoise over blue to purple
ACCENT_REF_C = 0.17         # chroma of Steam blue (#1a9fff), the scale for paler tones


# ---------- Colors ----------

def srgb_to_oklab(r, g, b):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = lin(r), lin(g), lin(b)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, a, bb


def hex_to_rgba(h):
    h = h[1:]
    if len(h) in (3, 4):
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    return r, g, b, a


def parse_num(tok, scale):
    """Number or percent; scale = value for 100%."""
    if tok.endswith("%"):
        return float(tok[:-1]) / 100 * scale
    return float(tok)


def parse_func(name, args):
    """rgb()/rgba()/hsl()/hsla() with comma or space syntax -> (r, g, b, a) or None."""
    toks = [t for t in re.split(r"[\s,/]+", args.strip()) if t]
    if len(toks) not in (3, 4):
        return None
    try:
        alpha = parse_num(toks[3], 1) if len(toks) == 4 else 1.0
        if name.startswith("rgb"):
            r, g, b = (parse_num(t, 255) for t in toks[:3])
        else:
            hue = float(toks[0].removesuffix("deg"))
            s = parse_num(toks[1], 1) if toks[1].endswith("%") else float(toks[1]) / 100
            l = parse_num(toks[2], 1) if toks[2].endswith("%") else float(toks[2]) / 100
            k = lambda n: (n + hue / 30) % 12
            f = lambda n: l - s * min(l, 1 - l) * max(-1, min(k(n) - 3, 9 - k(n), 1))
            r, g, b = (f(n) * 255 for n in (0, 8, 4))
    except ValueError:
        return None
    return r, g, b, max(0.0, min(1.0, alpha))


def pct(x):
    return f"{max(0.0, min(100.0, x * 100)):.1f}".rstrip("0").rstrip(".") + "%"


REF_BG_L = srgb_to_oklab(*hex_to_rgba(REF_BG)[:3])[0]
REF_FG_L = srgb_to_oklab(*hex_to_rgba(REF_FG)[:3])[0]
BG = f"var(--wal_bg, {REF_BG})"
FG = f"var(--wal_fg, {REF_FG})"


def with_alpha(expr, a):
    return expr if a >= 0.999 else f"color-mix(in oklab, {expr} {pct(a)}, transparent)"


def map_color(r, g, b, a):
    """CSS expression with wal variables, or None = the color stays."""
    if a <= 0.001:
        return None
    rgb = tuple(round(c) for c in (r, g, b))
    if rgb in ((0, 0, 0), (255, 255, 255)):
        return None
    L, oa, ob = srgb_to_oklab(*rgb)
    C = math.hypot(oa, ob)

    if C < NEUTRAL_C:
        t = (L - REF_BG_L) / (REF_FG_L - REF_BG_L)
        if t < 0:
            expr = f"color-mix(in oklab, {BG}, #000 {pct((REF_BG_L - L) / REF_BG_L)})"
        elif t > 1:
            expr = f"color-mix(in oklab, {FG}, #fff {pct((L - REF_FG_L) / (1 - REF_FG_L))})"
        else:
            expr = f"color-mix(in oklab, {BG}, {FG} {pct(t)})"
        return with_alpha(expr, a)

    hue = math.degrees(math.atan2(ob, oa)) % 360
    if ACCENT_HUE[0] <= hue <= ACCENT_HUE[1]:
        # The fallback has chroma ACCENT_REF_C -> times k gives exactly the original again
        k = C / ACCENT_REF_C
        fallback = f"oklch({L:.3f} {ACCENT_REF_C} {hue:.1f})"
        alpha = "" if a >= 0.999 else f" / {a:.3f}".rstrip("0").rstrip(".")
        return f"oklch(from var(--wal_accent, {fallback}) {L:.3f} calc(c * {k:.3f}) h{alpha})"
    return None


# ---------- CSS ----------

# Hide comments, strings and url(...) (data URIs!) first, so neither their ; { }
# nor colors in them are touched
MASK_RE = re.compile(r"""/\*.*?\*/|url\(\s*(?:"[^"]*"|'[^']*'|[^)]*)\s*\)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'""", re.S)
COLOR_RE = re.compile(r"(?<![\w#-])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})(?![\w-])"
                      r"|\b(rgba?|hsla?)\(([^()]*)\)", re.I)


def replace_colors(value, stats):
    def sub(m):
        if m.group(1):
            rgba = parse_func(m.group(1).lower(), m.group(2))
        else:
            rgba = hex_to_rgba(m.group(0))
        expr = map_color(*rgba) if rgba else None
        stats["kept" if expr is None else "mapped"] += 1
        return m.group(0) if expr is None else expr
    return COLOR_RE.sub(sub, value)


def patch_css(text, stats):
    masked = []

    def mask(m):
        masked.append(m.group(0))
        return f"\x00{len(masked) - 1}\x00"

    body = MASK_RE.sub(mask, text)
    # Sections before "{" are selectors/at-rules (#abc could be IDs there) -> only
    # declarations (before ";" or "}") and in them only the value after the first ":"
    parts = re.split(r"([{};])", body)
    for i in range(0, len(parts), 2):
        end = parts[i + 1] if i + 1 < len(parts) else ""
        seg = parts[i]
        if end == "{" or ":" not in seg:
            continue
        prop, value = seg.split(":", 1)
        parts[i] = prop + ":" + replace_colors(value, stats)
    body = "".join(parts)
    return re.sub(r"\x00(\d+)\x00", lambda m: masked[int(m.group(1))], body)


# ---------- Files ----------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--theme", type=Path, default=DEFAULT_THEME)
    ap.add_argument("--state", type=Path, default=DEFAULT_STATE)
    ap.add_argument("--force", action="store_true", help="re-patch all files from the originals")
    args = ap.parse_args()

    theme, orig_dir = args.theme, args.state / "orig"
    if not (theme / "skin.json").is_file():
        return 0  # theme not installed -> nothing to do

    patched, problems = 0, []
    stats = {"mapped": 0, "kept": 0}
    for path in sorted(theme.rglob("*.css")):
        rel = path.relative_to(theme)
        # Symlinks: config.css (wal template) and wal-webkit.css; .bak = old backups
        if path.is_symlink() or ".bak" in path.name:
            continue
        text = path.read_text(encoding="utf-8", errors="surrogateescape")
        orig = orig_dir / rel
        m = MARKER_RE.match(text)
        if m:
            if int(m.group(1)) == VERSION and not args.force:
                continue
            if not orig.is_file():
                problems.append(f"{rel}: patched, but the original is missing ({orig})")
                continue
            text = orig.read_text(encoding="utf-8", errors="surrogateescape")
        else:
            # unknown file or theme update -> that is the new original
            orig.parent.mkdir(parents=True, exist_ok=True)
            orig.write_text(text, encoding="utf-8", errors="surrogateescape")

        out = patch_css(text, stats)
        if rel == Path("webkit.css"):
            out = WEBKIT_IMPORT + out  # @import must come before all rules (a comment before it is ok)
        path.write_text(MARKER.format(VERSION, orig) + out, encoding="utf-8", errors="surrogateescape")
        patched += 1

    # Store variables: webkit.css imports this file, wal writes it (template steam-webkit.css)
    link = theme / "elements/wal-webkit.css"
    if not (link.is_symlink() and os.readlink(link) == str(WAL_WEBKIT)):
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to(WAL_WEBKIT)

    for p in problems:
        print(p, file=sys.stderr)
    if patched:
        print(f"{patched} file(s) patched ({stats['mapped']} colors switched to wal, "
              f"{stats['kept']} kept fixed on purpose) - restart Steam")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
