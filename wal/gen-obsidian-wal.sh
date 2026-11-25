#!/bin/bash
# Generates an Obsidian snippet from the current wal colors

# Usage: gen-obsidian-wal.sh [/path/to/vault]
# Without a path: all vaults Obsidian knows (~/.config/obsidian/obsidian.json),
# so a moved vault is no longer written into nothing.
# Set the accent color (otherwise the strongest wal slot is taken):
#   OBSIDIAN_ACCENT=color5 gen-obsidian-wal.sh
# Palette directly instead of from colors.json (16 colors as a JSON list, as with wal: background = color0,
# foreground = color15):  gen-obsidian-wal.sh --palette '["#261f1f", ...]' [/path/to/vault]
# This is how Quickshell calls it already at the start of the wallpaper wave and crossfades Obsidian with a still image
# (quickshell/services/TerminalColorFade.qml, obsidianFade). The later call from
# apply-wallpaper.sh gives the same file and then leaves it untouched (no second reload).
PALETTE=""
if [ "${1:-}" = "--palette" ]; then
    PALETTE=$2
    shift 2
fi
if [ -n "$1" ]; then
    VAULTS=("$1")
else
    mapfile -t VAULTS < <(python3 -c '
import json, os
p = os.path.expanduser("~/.config/obsidian/obsidian.json")
try:
    for v in json.load(open(p)).get("vaults", {}).values():
        print(v["path"])
except Exception:
    pass
')
fi
if [ ${#VAULTS[@]} -eq 0 ]; then
    echo "No Obsidian vault found" >&2
    exit 1
fi

for VAULT in "${VAULTS[@]}"; do
# Only real vaults (with .obsidian) - otherwise a typo would create an empty folder
if [ ! -d "$VAULT/.obsidian" ]; then
    echo "Not a vault: $VAULT" >&2
    continue
fi
SNIPPET_DIR="$VAULT/.obsidian/snippets"
SNIPPET="$SNIPPET_DIR/wal-colors.css"
mkdir -p "$SNIPPET_DIR"

python3 -I - "$SNIPPET" "$PALETTE" << 'PYEOF'
import colorsys, io, json, os, re, sys

snippet_path = sys.argv[1]

if len(sys.argv) > 2 and sys.argv[2]:
    pal = json.loads(sys.argv[2])
    if not (isinstance(pal, list) and len(pal) == 16
            and all(isinstance(x, str) and re.fullmatch(r'#[0-9a-fA-F]{6}', x) for x in pal)):
        sys.exit('Invalid palette')
    c = {f'color{i}': x.lower() for i, x in enumerate(pal)}
    s = {'background': c['color0'], 'foreground': c['color15']}
else:
    with open(os.path.expanduser('~/.cache/wal/colors.json')) as f:
        wal = json.load(f)
    c = wal['colors']
    s = wal['special']

# ---------- Color helpers (everything as (r, g, b) with 0-255) ----------
def h2t(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb(t):
    return f"{t[0]}, {t[1]}, {t[2]}"

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def darker(a, f):
    return tuple(round(x * f) for x in a)

def lum(t):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(x) for x in t)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

def ensure(col, bg, minc):
    """Farbe so lange Richtung Weiss (dunkles Theme) bzw. Schwarz aufhellen/abdunkeln,
    bis sie auf bg mindestens minc:1 Kontrast hat. Farbton bleibt weitgehend erhalten."""
    target = (255, 255, 255) if lum(bg) < 0.5 else (0, 0, 0)
    for i in range(101):
        out = lerp(col, target, i / 100)
        if contrast(out, bg) >= minc:
            return out
    return target

def over(col, alpha, bg):
    return lerp(bg, col, alpha)

def best_alpha(col, bg, text, minc, lo, hi):
    """Highest opacity for a background tone (highlight, selection)
    at which the text on it still has minc:1 contrast."""
    a = hi
    while a > lo and contrast(text, over(col, a, bg)) < minc:
        a = round(a - 0.01, 2)
    return a

def chroma(t):
    return max(t) - min(t)

bg = h2t(s['background'])
fg = h2t(s['foreground'])
dark = lum(bg) < 0.5

# ---------- Neutral tones – interpolated between fg and bg ----------
# Everything that carries text gets a minimum contrast to the background.
fg = ensure(fg, bg, 9.0)
neutrals = {
    'text':      fg,
    'subtext1':  ensure(lerp(fg, bg, 0.15), bg, 7.0),
    'subtext0':  ensure(lerp(fg, bg, 0.30), bg, 5.5),   # --text-muted
    'overlay2':  ensure(lerp(fg, bg, 0.45), bg, 4.5),   # --text-faint
    'overlay1':  ensure(lerp(fg, bg, 0.55), bg, 3.0),   # placeholder, icons
    'overlay0':  ensure(lerp(fg, bg, 0.65), bg, 2.2),   # Hilfslinien
    'surface2':  lerp(fg, bg, 0.78),
    'surface1':  lerp(fg, bg, 0.88),
    'surface0':  lerp(fg, bg, 0.94),
    'base':      bg,
    'mantle':    darker(bg, 0.85) if dark else lerp(bg, fg, 0.04),
    'crust':     darker(bg, 0.70) if dark else lerp(bg, fg, 0.08),
}

# ---------- Accent colors – here you decide which wal slot becomes what ----------
slots = {
    'rosewater': 'color7',
    'flamingo':  'color15',
    'pink':      'color13',
    'mauve':     'color5',
    'red':       'color1',
    'maroon':    'color9',
    'peach':     'color3',
    'yellow':    'color11',
    'green':     'color2',
    'teal':      'color6',
    'sky':       'color14',
    'sapphire':  'color12',
    'blue':      'color4',
    'lavender':  'color13',
}
# Accents are used as text (links, tags, heading markers) -> min. 4.5:1
# against the lightest surface tone they can stand on.
text_bg = neutrals['surface0'] if dark else neutrals['base']
accents = {name: ensure(h2t(c[slot]), text_bg, 4.5) for name, slot in slots.items()}

# Main accent: selectable with OBSIDIAN_ACCENT=colorN, otherwise the strongest slot 1-6
pick = os.environ.get('OBSIDIAN_ACCENT')
if pick not in c:
    pick = max((f'color{i}' for i in range(1, 7)), key=lambda k: chroma(h2t(c[k])))
accent = ensure(h2t(c[pick]), text_bg, 4.5)
on_accent = max((neutrals['base'], neutrals['text']), key=lambda t: contrast(t, accent))

# Obsidian sets its own accent color (Settings > Appearance) inline on the body -
# it is overridden here with !important.
hh, ll, ss = colorsys.rgb_to_hls(*(x / 255 for x in accent))

# Highlight (==text==) and selection: choose the opacity so text on it stays readable
hl = accents['yellow']
hl_a = best_alpha(hl, bg, fg, 7.0, 0.15, 0.40)
hl_a_active = best_alpha(hl, bg, fg, 5.5, hl_a, 0.55)
sel_a = best_alpha(accent, bg, fg, 7.0, 0.15, 0.35)

# Graph color groups (for the plugin .obsidian/plugins/wal-graph-colors): 7 tones from the
# color family of the accent - small hue shifts (toward turquoise/violet) plus
# different lightness/saturation. This way it stays with the theme (no rainbow) and is still
# distinguishable. Which folder gets which number is in the plugin.
#        (hue offset in degrees, saturation, lightness in the dark theme)
graph_spec = [(-18, .55, .68),   # 1 light, toward sky/turquoise
              (22, .42, .72),    # 2 toward violet
              (45, .30, .80),    # 3 very light, slightly violet
              (-38, .38, .60),   # 4 medium, clearly toward turquoise
              (0, .12, .84),     # 5 almost white, cool
              (0, .55, .52),     # 6 strong accent tone
              (0, .06, .58)]     # 7 neutral gray
graph_cols = []
for dh, gs, gl in graph_spec:
    if not dark:
        gl = max(0.28, gl - 0.30)
    col = tuple(round(x * 255) for x in colorsys.hls_to_rgb((hh + dh / 360) % 1.0, gl, gs))
    graph_cols.append(ensure(col, bg, 3.0))

# Build in memory first: unchanged -> do not touch the file (Obsidian reloads otherwise), otherwise in
# ONE write into the same file (Obsidian watches it; no half snippet in between)
with io.StringIO() as out:
    out.write("/* Auto-generated from pywal – do not edit by hand */\n")
    out.write("/* Regenerate: ~/.config/wal/gen-obsidian-wal.sh /path/to/vault */\n\n")

    out.write(".theme-dark, .theme-light {\n")
    for name, t in accents.items():
        out.write(f"  --ctp-{name}: {rgb(t)} !important;\n")
    for name, t in neutrals.items():
        out.write(f"  --ctp-{name}: {rgb(t)} !important;\n")
    out.write(f"  --ctp-accent: {rgb(accent)} !important;\n")
    for i, t in enumerate(graph_cols, 1):
        out.write(f"  --wal-graph-{i}: {rgb(t)} !important;\n")
    out.write("}\n\n")

    # AnuPpuccin hangs its whole color mapping on the class .anuppuccin-accent-toggle,
    # which only the plugin "Style Settings" sets. Without the plugin backgrounds, text,
    # accent and highlights stay at the Obsidian default - that is why the mapping is directly on the body here.
    out.write(f"""body.theme-dark, body.theme-light {{
  --accent-h: {round(hh * 360)} !important;
  --accent-s: {round(ss * 100)}% !important;
  --accent-l: {round(ll * 100)}% !important;

  --color-base-00: rgb(var(--ctp-crust));
  --color-base-05: rgb(var(--ctp-crust));
  --color-base-10: rgb(var(--ctp-mantle));
  --color-base-20: rgb(var(--ctp-base));
  --color-base-25: rgb(var(--ctp-surface0));
  --color-base-30: rgb(var(--ctp-surface1));
  --color-base-35: rgb(var(--ctp-surface2));
  --color-base-40: rgb(var(--ctp-overlay0));
  --color-base-50: rgb(var(--ctp-overlay1));
  --color-base-60: rgb(var(--ctp-overlay2));
  --color-base-70: rgb(var(--ctp-subtext0));
  --color-base-100: rgb(var(--ctp-text));

  --color-red-rgb: var(--ctp-red);
  --color-red: rgb(var(--ctp-red));
  --color-orange-rgb: var(--ctp-peach);
  --color-orange: rgb(var(--ctp-peach));
  --color-yellow-rgb: var(--ctp-yellow);
  --color-yellow: rgb(var(--ctp-yellow));
  --color-green-rgb: var(--ctp-green);
  --color-green: rgb(var(--ctp-green));
  --color-cyan-rgb: var(--ctp-sky);
  --color-cyan: rgb(var(--ctp-sky));
  --color-blue-rgb: var(--ctp-blue);
  --color-blue: rgb(var(--ctp-blue));
  --color-purple-rgb: var(--ctp-lavender);
  --color-purple: rgb(var(--ctp-lavender));
  --color-pink-rgb: var(--ctp-pink);
  --color-pink: rgb(var(--ctp-pink));

  --color-accent: rgb(var(--ctp-accent));
  --color-accent-1: rgb(var(--ctp-accent));
  --color-accent-2: rgba(var(--ctp-accent), 0.9);
  --interactive-accent: rgb(var(--ctp-accent));
  --interactive-accent-rgb: var(--ctp-accent);
  --interactive-accent-hover: rgba(var(--ctp-accent), 0.9);
  --text-accent: rgb(var(--ctp-accent));
  --text-accent-hover: rgb(var(--ctp-accent));
  --text-on-accent: rgb({rgb(on_accent)});
  --text-on-accent-inverted: rgb({rgb(on_accent)});
  --blockquote-border-color: rgb(var(--ctp-accent));
  --heading-formatting: rgb(var(--ctp-accent));
  --icon-color-focused: rgb(var(--ctp-accent));
  --nav-item-color-active: rgb(var(--ctp-text));

  /* Graph view: base colors from wal (color groups per folder are fixed in .obsidian/graph.json) */
  --graph-line: rgba(var(--ctp-overlay0), 0.55);
  --graph-node: rgb(var(--ctp-overlay2));
  --graph-node-unresolved: rgba(var(--ctp-overlay0), 0.6);
  --graph-node-focused: rgb(var(--ctp-accent));
  --graph-node-tag: rgb(var(--ctp-yellow));
  --graph-node-attachment: rgb(var(--ctp-teal));
  --graph-text: rgb(var(--ctp-subtext1));
  --nav-item-background-active: rgba(var(--ctp-accent), 0.15);
  --nav-item-background-selected: rgba(var(--ctp-accent), 0.2);
  --background-modifier-active: rgba(var(--ctp-accent), 0.1);
  --background-modifier-active-hover: rgba(var(--ctp-accent), 0.15);
  --link-unresolved-decoration-color: rgba(var(--ctp-accent), 0.3);
  --tag-color: rgb(var(--ctp-accent));
  --tag-background: rgba(var(--ctp-accent), 0.1);
  --tag-background-hover: rgba(var(--ctp-accent), 0.2);
  --tag-border-color: rgba(var(--ctp-accent), 0.15);
  --tag-border-color-hover: rgba(var(--ctp-accent), 0.15);

  --text-highlight-bg: rgba(var(--ctp-yellow), {hl_a});
  --text-highlight-bg-active: rgba(var(--ctp-yellow), {hl_a_active});
  --text-highlight-bg-rgb: var(--ctp-yellow);
  --text-selection: rgba(var(--ctp-accent), {sel_a});

  --background-primary: rgb(var(--ctp-base));
  --background-primary-alt: rgb(var(--ctp-mantle));
  --background-secondary: rgb(var(--ctp-mantle));
  --background-secondary-alt: rgb(var(--ctp-crust));
  --background-modifier-hover: rgba(var(--ctp-text), 0.075);
  --background-modifier-form-field: rgba(var(--ctp-crust), 0.3);
  --background-modifier-success: rgb(var(--ctp-green));
  --background-modifier-success-rgb: var(--ctp-green);
  --background-modifier-error: rgb(var(--ctp-red));
  --background-modifier-error-rgb: var(--ctp-red);
  --background-modifier-message: rgba(var(--ctp-crust), 0.9);
  --modal-border-color: rgb(var(--ctp-surface0));

  --text-normal: rgb(var(--ctp-text));
  --text-muted: rgb(var(--ctp-subtext0));
  --text-muted-rgb: var(--ctp-subtext0);
  --text-faint: rgb(var(--ctp-overlay2));
  --text-error: rgb(var(--ctp-red));
  --text-success: rgb(var(--ctp-green));
  --interactive-normal: rgb(var(--ctp-surface0));
  --interactive-hover: rgb(var(--ctp-surface1));
  --interactive-success: rgb(var(--ctp-green));
  --code-normal: rgb(var(--ctp-text));
}}

/* Selected text always keeps the normal text color */
.markdown-rendered mark, .cm-s-obsidian span.cm-highlight {{
  color: var(--text-normal);
}}
""")
    css = out.getvalue()

try:
    with open(snippet_path) as f:
        unchanged = f.read() == css
except OSError:
    unchanged = False
if unchanged:
    print(f"Snippet unchanged: {snippet_path}")
    sys.exit(0)
with open(snippet_path, 'w') as f:
    f.write(css)

print(f"Snippet written: {snippet_path}  (accent: {pick} -> #{''.join(f'{x:02x}' for x in accent)}, "
      f"Highlight {hl_a}, selection {sel_a})")
PYEOF
done
