#!/bin/bash
# Small preview images for the wallpaper picker (permanent cache, only missing/outdated ones are created).
# Usage: wallpaper_thumbs.sh <wallpaperDir> <thumbDir> <width> <height> <md5> <file name> [<md5> <file name> ...]
# stdout: one line per wallpaper "<md5> ok" (preview there) or "<md5> fail" (use the original)
# WALLPAPER_STILL_SIZES (e.g. "2560x1440 1080x1920"): monitor formats; for scenes this also creates
# the big still images of the ink transition (wallpaper_still.sh), so it starts right away.
src="$1"
dir="$2"
w="$3"
h="$4"
shift 4
mkdir -p "$dir"
still_script="$(dirname -- "$(realpath -- "$0")")/wallpaper_still.sh"
sizes=${WALLPAPER_STILL_SIZES:-1920x1080}

# Render a Wallpaper Engine scene (project.json) as a real image: the bundled preview is
# square and often tiny. For the tile the first landscape format. If that fails, the
# bundled preview stays.
scene_still() {
    local project="$1" folder preview line
    folder=$(dirname -- "$project")
    if command -v linux-wallpaperengine >/dev/null; then
        # shellcheck disable=SC2086 # sizes deliberately as separate arguments
        line=$(bash "$still_script" "$project" $sizes | awk '{ split($1, s, "x"); if (s[1] >= s[2]) { print $2; exit } }')
        [ -s "$line" ] && { echo "$line"; return; }
    fi
    preview=$(jq -r '.preview // "preview.jpg"' "$project" 2>/dev/null)
    [ -f "$folder/$preview" ] && echo "$folder/$preview"
}

make_one() {
    local md5="$1" name="$2" tmp="$dir/.$md5.$$.jpg"
    local input="$name"
    [[ "$input" = /* ]] || input="$src$name"
    if [[ "$input" = */project.json ]]; then
        input=$(scene_still "$input")
    fi
    # Only scale down (aspect ratio stays), the picker still chooses the crop
    if ffmpeg -nostdin -v error -threads 1 -filter_threads 1 -i "$input" -frames:v 1 \
        -vf "scale=$w:$h:force_original_aspect_ratio=increase" \
        -threads 1 -q:v 3 -y "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv -f "$tmp" "$dir/$md5.jpg"
        echo "$md5 ok"
    else
        rm -f "$tmp"
        echo "$md5 fail"
    fi
}
export -f make_one scene_still
export src dir w h still_script sizes

# Report current ones right away, then create missing or outdated ones (original newer) in parallel
todo=()
stills=()
while [ $# -ge 2 ]; do
    md5="$1" name="$2"
    shift 2
    input="$name"
    [[ "$input" = /* ]] || input="$src$name"
    stills+=("$input")
    if [ -e "$dir/$md5.jpg" ] && ! [ "$input" -nt "$dir/$md5.jpg" ]; then
        echo "$md5 ok"
    else
        todo+=("$md5" "$name")
    fi
done
if [ ${#todo[@]} -gt 0 ]; then
    printf '%s\0' "${todo[@]}" | nice -n 10 xargs -0 -n 2 -P 2 bash -c 'make_one "$1" "$2"' _
fi
# Keep transition still images of all wallpapers ready (existing ones cost nothing): otherwise
# the transition would first have to shrink a 7K PNG or decode a 4K video and would start noticeably late
if [ ${#stills[@]} -gt 0 ]; then
    # shellcheck disable=SC2016,SC2086
    printf '%s\0' "${stills[@]}" | nice -n 10 xargs -0 -n 1 -P 2 bash -c 'bash "$still_script" "$1" $sizes >/dev/null' _
fi
# Keep videos in monitor size ready (wallpaper_video_variant.sh): a 4K video cost ~225 MB of RAM
# per monitor. One after another (GPU encoder), existing ones cost nothing.
variant_script="$(dirname -- "$(realpath -- "$0")")/wallpaper_video_variant.sh"
for input in "${stills[@]}"; do
    case "${input,,}" in
        *.mp4|*.webm|*.mkv|*.mov|*.m4v)
            # shellcheck disable=SC2086
            bash "$variant_script" --make "$input" $sizes >/dev/null ;;
    esac
done
exit 0
