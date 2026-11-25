#!/usr/bin/env bash
# Pick a profile picture with yazi and save it as ~/.face (notification center, NotificationState).
#   Usage: avatar_pick.sh <monitor> <top-px>
# The yazi window is placed centered BELOW the open center (top edge relative to the monitor),
# because the center is a layer above all windows and would cover a centered window.
# Prints "ok" when a new picture was set.

mon="$1"
top="$2"
case "$top" in '' | *[!0-9]*) top=0 ;; esac

out=$(mktemp)
trap 'rm -f "$out"' EXIT
start="$HOME/Pictures"
[ -d "$start" ] || start="$HOME"

kitty --class avatarchooser yazi --chooser-file="$out" "$start" &
kpid=$!

# Find and place the window of exactly this kitty (only by address: without a target
# the dispatchers would move the active window)
place() {
    local info addr x y w h
    info=$(hyprctl clients -j | python3 -I -c '
import json, sys
pid, mon, top = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
c = next((c for c in json.load(sys.stdin) if c["pid"] == pid), None)
if not c:
    sys.exit(1)
ms = json.load(open(sys.argv[4]))
m = next((m for m in ms if m["name"] == mon), None) or next(m for m in ms if m["id"] == c["monitor"])
mw, mh = m["width"] / m["scale"], m["height"] / m["scale"]
w = int(min(1400, mw - 80))
h = int(max(360, min(880, mh - top - 40)))
print(c["address"].removeprefix("0x"), int(m["x"] + (mw - w) / 2), int(m["y"] + top), w, h)
' "$kpid" "$mon" "$top" <(hyprctl monitors -j)) || return 1
    read -r addr x y w h <<<"$info"
    case "$addr" in '' | *[!0-9a-f]*) return 1 ;; esac
    hyprctl eval "local w for _, c in ipairs(hl.get_windows()) do if tostring(c.address):lower():gsub(\"^0x\", \"\") == \"$addr\" then w = c end end if not w then return end hl.dispatch(hl.dsp.window.float({ action = \"enable\", window = w })) hl.dispatch(hl.dsp.window.resize({ window = w, x = $w, y = $h, relative = false })) hl.dispatch(hl.dsp.window.move({ window = w, x = $x, y = $y, relative = false }))" >/dev/null 2>&1
}

for _ in $(seq 30); do
    sleep 0.1
    place && break
done
wait "$kpid"

f=$(head -n1 "$out")
[ -f "$f" ] || exit 0
# Crop to a square, so it sits cleanly in the round frame (without magick: unchanged)
if command -v magick >/dev/null; then
    magick "$f[0]" -auto-orient -gravity center -thumbnail "512x512^" -extent 512x512 "png:$HOME/.face" || exit 1
else
    cp -- "$f" "$HOME/.face" || exit 1
fi
echo ok
