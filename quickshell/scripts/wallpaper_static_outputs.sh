#!/bin/bash
# Animated wallpapers only run on the bar monitor (saves one video player or scene output
# per extra monitor). The other monitors show a still image of the wallpaper with awww.
#
#   wallpaper_static_outputs.sh <wallpaper> <monitor:WxH> [<monitor:WxH> ...]
#
# Still image per format from wallpaper_still.sh (video: first frame, scene: render, image: scaled down -
# cropped like live). Only ends when awww shows it on all named monitors (max ~3 s),
# so the transition knows when it may continue. Exit 1 if it did not work.
path=$1
shift
[ $# -gt 0 ] || exit 0
here=$(dirname -- "$(realpath -- "$0")")
declare -A want
sizes=()
for spec in "$@"; do
    sizes+=("${spec#*:}")
done
# Get the still images per format (cache, prints "<WxH> <file>")
declare -A still
while read -r size file; do
    [ -n "$file" ] && still[$size]=$file
done < <(bash "$here/wallpaper_still.sh" "$path" $(printf '%s\n' "${sizes[@]}" | sort -u))

for spec in "$@"; do
    out=${spec%%:*} size=${spec#*:}
    file=${still[$size]}
    [ -n "$file" ] || { echo "No still image for $size" >&2; exit 1; }
    want[$out]=$file
    awww img -o "$out" "$file" --transition-type none >/dev/null 2>&1 || exit 1
done

# Wait until awww really shows the images (big images take a moment)
for _ in $(seq 60); do
    ok=1
    for out in "${!want[@]}"; do
        awww query 2>/dev/null | grep -F ": $out:" | grep -q -F "image: ${want[$out]}" || ok=0
    done
    [ "$ok" = 1 ] && exit 0
    sleep 0.05
done
exit 1
