#!/bin/bash
# Tint the active cursor theme (Kitty / Bongo Cat) with the current pywal accent color.
# Called by hypr/scripts/wallpaper-apps.sh after every wallpaper change.
#
# The original Windows cursors live in <theme>/src/ (default.* + pointer.*) next to the theme in
# ~/.local/share/icons - on purpose outside the dotfiles (license: personal use, no redistribution).
# Without that folder (e.g. a machine where the pack isn't installed) this script does nothing.

# theme/size from gsettings: env vars of long-running processes (Quickshell) can be outdated
theme_name=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null)
theme_name=${theme_name:-BongoCat}
size=${size:-32}
theme="$HOME/.local/share/icons/$theme_name"
src="$theme/src"
[ -d "$src" ] || exit 0

ls "$src"/default.* >/dev/null 2>&1 || exit 0

# optional per-theme settings in <theme>/gen-cursor.conf (key=value); defaults = Bongo Cat
#   tint=blue|grey       which pixels get the accent (bluish shading / grey fur, e.g. Kuro Kitty)
#   text_cursor=yes|no   generate the cat-ear I-beam below (no = the pack brings its own text.*)
#   saturation=F         factor for the tint saturation (0.5 = paler), default 1
#   chroma=F             tint=grey: max. color strength (OKLab chroma), default 0.045 (see ani2xcursor.py)
#   size=N               also write a downscaled size (e.g. 28 for a 32 px pack); set XCURSOR_SIZE to match
conf() { sed -n "s/^$1=//p" "$theme/gen-cursor.conf" 2>/dev/null | tail -n1; }
tint_mode=$(conf tint); tint_mode=${tint_mode:-blue}
text_cursor=$(conf text_cursor); text_cursor=${text_cursor:-yes}
saturation=$(conf saturation); saturation=${saturation:-1}
extra_size=$(conf size); extra_size=${extra_size:-0}
chroma=$(conf chroma)
chroma_arg=()
[ -n "$chroma" ] && chroma_arg=(--chroma "$chroma")

# own text cursor (I-beam with cat ears, text-cursor.py) - the Bongo Cat pack has none, Adwaita's
# plain "I" didn't fit. Generated into src/ so it gets the same tint as the cat.
if [ "$text_cursor" = yes ]; then
    python3 "$HOME/.config/wal/cursor/text-cursor.py" "$src/text.ani" || exit 1
fi

# every file in src/ is one shape: <shape>.ani / <shape>.cur
shapes=()
for f in "$src"/*.ani "$src"/*.cur; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    shapes+=("${name%.*}=$f")
done

# accent = most saturated of color1..6 with a lightness close to 0.6
# (same rule as WalColors.vividAccent in Quickshell -> cat, tablet icon and Claude logo match)
accent=$(python3 - <<'EOF'
import colorsys, json, os
c = json.load(open(os.path.expanduser("~/.cache/wal/colors.json")))["colors"]
def score(h):
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
    _, l, s = colorsys.rgb_to_hls(r, g, b)
    return s * (1 - abs(l - 0.6))
print(max((c[f"color{i}"] for i in range(1, 7)), key=score))
EOF
)
[ -n "$accent" ] || exit 0

python3 "$HOME/.config/hypr/scripts/ani2xcursor.py" --tint "$accent" --tint-mode "$tint_mode" \
    --saturation "$saturation" "${chroma_arg[@]}" --size "$extra_size" "$theme" "${shapes[@]}" >/dev/null || exit 1

# Hyprland caches the loaded cursor images and ignores setcursor with the same theme + size
# -> switch to another theme for a moment so it really reloads the files
hyprctl setcursor Adwaita "$size" >/dev/null 2>&1
hyprctl setcursor "$theme_name" "$size" >/dev/null 2>&1
