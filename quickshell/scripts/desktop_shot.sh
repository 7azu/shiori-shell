#!/bin/bash
# Screenshot of single monitors as <prefix>-<monitor>.ppm (without cursor; PPM = raw data, writes and
# loads much faster than PNG -> the lock screen appears sooner).
# Without monitor arguments: all. Used by the lock screen (hypr/scripts/lock.sh) and the
# power menu (desktop image without the menu, which the lock screen thaws to when unlocking).
#   desktop_shot.sh <prefix> [monitor ...]
prefix="$1"
shift
[ -n "$prefix" ] || exit 1
outs=("$@")
[ ${#outs[@]} -gt 0 ] || mapfile -t outs < <(hyprctl monitors -j | jq -r '.[].name')
for out in "${outs[@]}"; do
    grim -t ppm -o "$out" "$prefix-$out.ppm" &
done
wait
