#!/bin/bash
# Put the bar monitor first for Qt programs (called by quickshell.sh before every Quickshell start).
#
# Why: Qt (and so Quickshell) times all animations by the refresh rate of its "primary screen", and under
# Wayland that is simply the first output the compositor announced. With a 75 Hz monitor first, all
# animations ran at ~77 frames/s even on the 240 Hz monitor (measured 13 ms per frame in the bar morph).
# Qt has no setting for it. An output that is turned off and on again is announced anew, so it comes
# last. Hyprland's own list (hyprctl monitors) does NOT show this order.
#
# Target: the bar monitor of the shell (quickshell-local/screens.json "barScreen"), otherwise the fastest.
# A small Qt probe (screen-order.qml) asks which monitor is first; only if it is not the target, all
# other monitors are turned off (waiting until Hyprland really has them off: half a second was not
# enough, nothing changed) and back on with their current values. So it only flickers when needed.
# Note: the refresh rate is taken from the current state (a mode in monitors.lua may ask for more than
# the monitor really runs at - forcing it would be wrong).

here=$(dirname "$(readlink -f "$0")")
monitors=$(hyprctl monitors -j) || exit 0
[ "$(jq length <<<"$monitors")" -lt 2 ] && exit 0

conf=${XDG_CONFIG_HOME:-$HOME/.config}/quickshell-local/screens.json
target=$(jq -r '.barScreen // empty' "$conf" 2>/dev/null)
if [ -z "$target" ] || ! jq -e --arg n "$target" 'any(.[]; .name == $n)' <<<"$monitors" >/dev/null; then
    target=$(jq -r 'max_by(.refreshRate).name' <<<"$monitors")
fi

first() {
    XDG_STATE_HOME=${XDG_RUNTIME_DIR:-/tmp}/qs-screen-probe timeout 10 qs -p "$here/screen-order.qml" --no-color 2>&1 \
        | sed -n 's/.*FIRST_SCREEN \([^ ]*\).*/\1/p' | head -1
}

now=$(first)
[ -z "$now" ] || [ "$now" = "$target" ] && exit 0
echo "monitor-order: Qt sees $now first, moving $target to the front"

# Rows of the other monitors: name width height refresh x y scale transform
mapfile -t others < <(jq -r --arg t "$target" '.[] | select(.name != $t)
    | "\(.name) \(.width) \(.height) \(.refreshRate) \(.x) \(.y) \(.scale) \(.transform)"' <<<"$monitors")

enabled() { hyprctl monitors -j | jq -r '.[].name'; }

for row in "${others[@]}"; do
    read -r name _ <<<"$row"
    hyprctl eval "hl.monitor({ output = \"$name\", disabled = true })" >/dev/null
done
for _ in $(seq 30); do
    still=0
    for row in "${others[@]}"; do
        read -r name _ <<<"$row"
        enabled | grep -qx "$name" && still=1
    done
    [ "$still" = 0 ] && break
    sleep 0.1
done
sleep 0.3
for row in "${others[@]}"; do
    read -r name w h hz x y scale transform <<<"$row"
    mode=$(printf '%sx%s@%.2f' "$w" "$h" "$hz")
    hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"${x}x${y}\", scale = $scale, transform = $transform, disabled = false })" >/dev/null
done
# Wait until they are back, so Quickshell starts with all monitors
for _ in $(seq 30); do
    [ "$(enabled | wc -l)" -ge "$(( ${#others[@]} + 1 ))" ] && break
    sleep 0.1
done
