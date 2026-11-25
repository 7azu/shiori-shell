#!/bin/bash
set -eu

# Always take the newest palette, even with fast wallpaper changes.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/openrgb"
mkdir -p -- "$state_dir"
exec 9>"$state_dir/lighting.lock"
palette="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json"
preview=${1:-}
if [[ "$preview" == --preview ]]; then
    # Never queue a preview behind a newer change.
    flock -n 9 || exit 0
else
    flock -x 9
    [[ -r "$palette" ]] || exit 0
fi
# Largest RGB channel spread: strong and well visible pywal accents.
color=$(python3 - "$palette" "${2:-}" <<'PY'
import json
import sys

def chroma(hex_color):
    channels = bytes.fromhex(hex_color[1:])
    return max(channels) - min(channels)

if sys.argv[2]:
    colors = json.loads(sys.argv[2])
else:
    with open(sys.argv[1]) as palette:
        colors = json.load(palette)["colors"]

accents = [colors[f"color{i}"] for i in range(1, 7)]
chosen = max(accents, key=chroma)
print(chosen[1:].upper())
PY
)

# Own lighting setup (devices, zones, profiles): ~/.config/shiori-shell/openrgb.sh <RRGGBB> [--preview]
custom="$HOME/.config/shiori-shell/openrgb.sh"
if [[ -x "$custom" ]]; then
    exec "$custom" "$color" "$preview"
fi

# Default: every device in static mode, through a running OpenRGB server (openrgb --server).
# Without OpenRGB or server nothing happens.
command -v openrgb >/dev/null || exit 0
exec timeout -k 1 5 openrgb --client 127.0.0.1:6742 --mode static --color "$color" >/dev/null 2>&1
