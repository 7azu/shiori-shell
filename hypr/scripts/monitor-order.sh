#!/bin/bash
# Move the fastest monitor to the front for Qt programs (autostart, BEFORE Quickshell).
#
# Why: Qt (and so Quickshell) drives all animations with a timer at the rate of its "primary screen",
# and under Wayland that is simply the first monitor Hyprland reports. With a 75 Hz monitor first,
# all animations ran at ~77 frames/s even on a 240 Hz monitor.
# A monitor that is turned off and on again is at the end of the list afterwards. So turn all except
# the fastest off once and back on with their current values.
#
# Generic: with one monitor, or all equally fast, it does nothing.
# Note: without "disabled = false" the monitors stay off; the refresh rate is taken from the current state
# (a mode in monitors.lua may ask for more than the monitor really runs at - forcing it would be wrong).

monitors=$(hyprctl monitors -j) || exit 0

# Rows: name width height refresh x y scale transform; fastest first
mapfile -t rows < <(jq -r 'sort_by(-.refreshRate) | .[]
    | "\(.name) \(.width) \(.height) \(.refreshRate) \(.x) \(.y) \(.scale) \(.transform)"' <<<"$monitors")
[ "${#rows[@]}" -lt 2 ] && exit 0

fastest=$(cut -d' ' -f4 <<<"${rows[0]}")
slowest=$(cut -d' ' -f4 <<<"${rows[-1]}")
awk -v a="$fastest" -v b="$slowest" 'BEGIN { exit !(a - b < 1) }' && exit 0

others=("${rows[@]:1}")
for row in "${others[@]}"; do
    read -r name _ <<<"$row"
    hyprctl eval "hl.monitor({ output = \"$name\", disabled = true })" >/dev/null
done
sleep 0.5
for row in "${others[@]}"; do
    read -r name w h hz x y scale transform <<<"$row"
    mode=$(printf '%sx%s@%.2f' "$w" "$h" "$hz")
    hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"${x}x${y}\", scale = $scale, transform = $transform, disabled = false })" >/dev/null
done
