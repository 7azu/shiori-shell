#!/bin/bash
# Video wallpaper in monitor size (for windows/AnimatedWallpaper.qml).
# Why: every monitor has its own player; a 4K video costs ~225 MB of RAM and a lot of
# CPU per player (measured), ~700 MB with three monitors - although no monitor shows more than 1440p. A copy
# made once and cropped to the monitor needs only a fraction.
#
#   wallpaper_video_variant.sh [--make] <video> <WxH> [<WxH> ...]
#
# stdout: per size "<WxH> <file>" - the copy if there is one, otherwise the original.
#   without --make: only look (fast; missing copies are made in the background)
#   with    --make: make missing copies now (wallpaper_thumbs.sh, one after another with flock)
# No gain (GIF, video hardly bigger than the monitor): always the original.
make=0
[ "$1" = "--make" ] && { make=1; shift; }
path=$1
shift
[ -f "$path" ] || exit 1
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallpaper-video"
mkdir -p "$cache" || exit 1
key=$(printf '%s' "$path" | sha256sum | cut -d ' ' -f 1)
IFS=, read -r sw sh < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$path" 2>/dev/null)

missing=()
for size in "$@"; do
    w=${size%x*} h=${size#*x}
    out="$cache/$key.$size.mp4"
    # GIFs are small; only worth it if the video has clearly more pixels than the monitor
    if [[ "${path,,}" = *.gif ]] || [ -z "$sw" ] || [ $((sw * sh)) -le $((w * h * 3 / 2)) ]; then
        echo "$size $path"
    elif [ -s "$out" ] && ! [ "$path" -nt "$out" ]; then
        echo "$size $out"
    else
        echo "$size $path"
        missing+=("$size")
    fi
done

[ ${#missing[@]} -eq 0 ] && exit 0
if [ "$make" = 0 ]; then
    # Make it in the background; next time the copy is used
    setsid nohup bash "$0" --make "$path" "${missing[@]}" >/dev/null 2>&1 &
    exit 0
fi

lock="${XDG_RUNTIME_DIR:-/tmp}/quickshell-video-variant.lock"
exec 9>"$lock"
flock 9
for size in "${missing[@]}"; do
    w=${size%x*} h=${size#*x}
    out="$cache/$key.$size.mp4"
    [ -s "$out" ] && ! [ "$path" -nt "$out" ] && continue
    tmp="$cache/.$key.$size.$$.mp4"
    # Like PreserveAspectCrop: scale to fill, crop centered. GPU (VAAPI), otherwise CPU.
    vf="scale=$w:$h:force_original_aspect_ratio=increase:flags=lanczos,crop=$w:$h"
    nice -n 10 ffmpeg -nostdin -v error -y -vaapi_device /dev/dri/renderD128 -i "$path" -an \
        -vf "$vf,format=nv12,hwupload" -c:v h264_vaapi -qp 18 "$tmp" 2>/dev/null \
    || nice -n 10 ffmpeg -nostdin -v error -y -i "$path" -an -vf "$vf" \
        -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -threads 2 "$tmp" \
    || { rm -f -- "$tmp"; continue; }
    mv -f -- "$tmp" "$out"
done
