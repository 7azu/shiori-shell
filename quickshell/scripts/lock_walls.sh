#!/bin/bash
# Plain wallpaper per monitor for the lock screen: $XDG_RUNTIME_DIR/quickshell-lock-wall-<monitor>
#   - monitor with a video: the paused video frame (AnimatedWallpaper stores wallpaper-frame-<mon>.bmp)
#   - otherwise, if the current wallpaper is animated (scene, video, GIF): its still image from the cache
#     of wallpaper_still.sh. Do NOT ask awww: under video/scene awww still holds the previous wallpaper
#     on the bar monitor (scenes write no video frame -> the lock screen showed the old image)
#   - otherwise the image awww shows there, converted to monitor size as PPM (decoding a big PNG
#     took ~0.7 s in the lock screen, the intro stood still that long)
# Used by hypr/scripts/lock.sh and the power menu (there the lock screen slides in as a surface).
#   lock_walls.sh "<monitors with video>" [monitor ...]     (without monitors: all)
run="${XDG_RUNTIME_DIR:-/tmp}"
video_mons="$1"
shift
want=" $* "

# Video frames appear ~60 ms after pausing -> wait a moment for them
for mon in $video_mons; do
    for _ in $(seq 25); do [ -s "$run/wallpaper-frame-$mon.bmp" ] && break; sleep 0.02; done
done

# Current wallpaper (WallpaperPickerState writes it) and, if animated, its still image
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
cur=$(cat "$cache/current-wallpaper" 2>/dev/null)
case "${cur,,}" in
    */project.json) still_kind=scene-v2 ;;
    *.mp4 | *.webm | *.mkv | *.mov | *.m4v | *.gif) still_kind=still ;;
    *) still_kind= ;;
esac
key=$(printf '%s' "$cur" | sha256sum | cut -d ' ' -f 1)
# Still image with the same aspect ratio as <WxH> (the cache has only one size per format)
anim_still() {
    local f s r
    for f in "$cache/wallpaper-stills/$key.$still_kind-"*.jpg; do
        [ -s "$f" ] || continue
        s=${f##*-}
        s=${s%.jpg}
        # Aspect ratio still image / monitor in percent (2560x1440 also fits 1920x1080)
        r=$((${s%x*} * ${1#*x} * 100 / (${s#*x} * ${1%x*})))
        [ "$r" -ge 99 ] && [ "$r" -le 101 ] && { echo "$f"; return 0; }
    done
    # Video/GIF without cache: the first frame is quick to make (rendering a scene took seconds)
    [ "$still_kind" = still ] &&
        "$(dirname -- "$(realpath -- "$0")")/wallpaper_still.sh" "$cur" "$1" 2>/dev/null | cut -d ' ' -f 2-
}

pids=()
while IFS= read -r line; do
    mon=$(sed -n 's/^[: ]*\([^:]*\):.*/\1/p' <<<"$line")
    size=$(sed -n 's/^[: ]*[^:]*: \([0-9]*x[0-9]*\),.*/\1/p' <<<"$line")
    img=$(sed -n 's/.*currently displaying: image: //p' <<<"$line")
    [ -n "$mon" ] || continue
    [ "$want" = "  " ] || [[ "$want" == *" $mon "* ]] || continue
    out="$run/quickshell-lock-wall-$mon"
    if [ -s "$run/wallpaper-frame-$mon.bmp" ]; then
        cp -f "$run/wallpaper-frame-$mon.bmp" "$out.tmp" && mv -f "$out.tmp" "$out"
        continue
    fi
    if [ -n "$still_kind" ] && [ -n "$size" ]; then
        still=$(anim_still "$size")
        [ -n "$still" ] && img=$still
    fi
    if [ -n "$img" ] && [ -f "$img" ] && [ -n "$size" ]; then
        (ffmpeg -v error -y -i "$img" \
            -vf "scale=${size%x*}:${size#*x}:force_original_aspect_ratio=increase,crop=${size%x*}:${size#*x}" \
            -f image2 -c:v ppm "$out.tmp" </dev/null && mv -f "$out.tmp" "$out") ||
            ln -sf "$img" "$out" &
        pids+=($!)
    fi
done < <(awww query 2>/dev/null)
for p in "${pids[@]}"; do wait "$p"; done
exit 0
