#!/bin/bash
# Image from which pywal computes the colors of a wallpaper (prints the path).
# Shared by apply-wallpaper.sh (wal) and Quickshell (scripts/wal_preview.py), so the
# palette computed in advance for the transition matches exactly the one wal sets later.
#
#   wallpaper-theme-image.sh <wallpaper>
#
#   image -> the image itself
#   video -> first frame as PNG (cached, a single frame is enough for the colors)
#   scene -> the preview image of the Wallpaper Engine project
# Errors (in English, they are shown) on stderr, exit 1.
path=$1
[ -f "$path" ] || { echo "Wallpaper not found: $path" >&2; exit 1; }

case "${path,,}" in
    */project.json)
        # Accept only scene projects with a preview image.
        python3 - "$path" <<'SCENE' || exit 1
import json,sys
from pathlib import Path
p=Path(sys.argv[1]).resolve();data=json.loads(p.read_text())
if str(data.get('type','')).lower() != 'scene':
    raise SystemExit('Unsupported Wallpaper Engine project type')
preview=(p.parent/str(data.get('preview','preview.jpg'))).resolve()
if not preview.is_relative_to(p.parent) or not preview.is_file():
    raise SystemExit('Scene preview image not found')
print(preview)
SCENE
        ;;
    *.gif|*.mp4|*.webm|*.mkv|*.mov|*.m4v)
        export MAGICK_MEMORY_LIMIT=256MiB MAGICK_MAP_LIMIT=256MiB
        still_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallpaper-stills"
        mkdir -p "$still_dir" || exit 1
        still_key=$(printf '%s' "$path" | sha256sum | cut -d ' ' -f 1)
        theme_path="$still_dir/$still_key.theme-v2.png"
        if [ ! -s "$theme_path" ] || [ "$path" -nt "$theme_path" ]; then
            tmp="$still_dir/.$still_key.$$.png"
            trap 'rm -f -- "$tmp"' EXIT
            nice -n 10 ffmpeg -nostdin -v error -filter_threads 2 -threads 2 -i "$path" \
                -vf "scale=1280:1280:force_original_aspect_ratio=decrease" \
                -frames:v 1 -threads 2 -update 1 -y "$tmp" || exit 1
            mv -f -- "$tmp" "$theme_path" || exit 1
        fi
        echo "$theme_path"
        ;;
    *)
        echo "$path"
        ;;
esac
