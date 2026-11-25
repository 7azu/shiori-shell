#!/bin/bash
# Full-size still image of a wallpaper for the ink transition (services/WallpaperTransition.qml)
# and the picker preview (wallpaper_thumbs.sh). Permanent cache, only missing/outdated ones are created.
#
#   wallpaper_still.sh <path> <WxH> [<WxH> ...]
#
# stdout: one line per size "<WxH> <file>".
#   image -> scaled down to monitor size (aspect ratio stays, the transition crops like awww
#            does); decoding a 7K PNG otherwise delayed the start noticeably
#   video -> first frame, scaled down the same way (the video then starts exactly there -> no jump)
#   scene -> render by linux-wallpaperengine in exactly this size (portrait/landscape crop
#            scenes differently, so one per monitor format)
# Exit 1 if no still image was possible.
path=$1
shift
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallpaper-stills"
mkdir -p "$cache" || exit 1
key=$(printf '%s' "$path" | sha256sum | cut -d ' ' -f 1)
ok=0

case "${path,,}" in
    */project.json)
        folder=$(dirname -- "$path")
        # Only one render at a time (also with wallpaper_thumbs.sh): one GPU window each
        lock="${XDG_RUNTIME_DIR:-/tmp}/quickshell-scene-render.lock"
        # The same color corrections as at the live start (wallpaperengine_run.py: "1 1 1" is almost
        # black otherwise), otherwise the still image does not match the running scene
        # One line per argument; without corrections none at all (an empty line would be an empty argument,
        # on which linux-wallpaperengine fails right away)
        mapfile -t colorfix < <(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import wallpaperengine_run as w; sys.stdout.write("".join(a + "\n" for a in w.color_fixes(sys.argv[2])))' \
            "$(dirname -- "$(realpath -- "$0")")" "$folder" 2>/dev/null)
        for size in "$@"; do
            # "v2": do not reuse still images without color correction from the old cache
            out="$cache/$key.scene-v2-$size.jpg"
            if [ ! -s "$out" ] || [ "$path" -nt "$out" ] || [ "$folder/scene.pkg" -nt "$out" ]; then
                tmp="$cache/.$key.$size.$$.png"
                (
                    flock 9
                    # hypr/modules/windows.lua makes the window invisible (title "wallpaperengine")
                    nice -n 5 linux-wallpaperengine --silent --disable-mouse --fps 30 "${colorfix[@]}" \
                        --window "0x0x$size" --screenshot "$tmp" --screenshot-delay 45 "$folder" >/dev/null 2>&1 &
                    pid=$! last=-1
                    # Does not quit by itself after the screenshot -> wait until the file is fully
                    # written (size stable), then quit; after 20 s at the latest
                    for _ in $(seq 200); do
                        kill -0 "$pid" 2>/dev/null || break
                        if [ -s "$tmp" ]; then
                            cur=$(stat -c %s -- "$tmp")
                            [ "$cur" = "$last" ] && break
                            last=$cur
                        fi
                        sleep 0.1
                    done
                    kill "$pid" 2>/dev/null
                    wait "$pid" 2>/dev/null
                ) 9>"$lock"
                if [ -s "$tmp" ]; then
                    magick "$tmp" -quality 92 "$out" 2>/dev/null
                fi
                rm -f -- "$tmp"
            fi
            [ -s "$out" ] && { echo "$size $out"; ok=1; }
        done
        ;;
    *)
        # Image or video (first frame): scaled down per monitor format so that it just fills the
        # monitor - exactly as awww or PreserveAspectCrop crop it afterwards
        [ -f "$path" ] || exit 1
        for size in "$@"; do
            out="$cache/$key.still-$size.jpg"
            if [ ! -s "$out" ] || [ "$path" -nt "$out" ]; then
                tmp="$cache/.$key.$size.$$.jpg"
                nice -n 5 ffmpeg -nostdin -v error -threads 2 -i "$path" -frames:v 1 \
                    -vf "scale=${size%x*}:${size#*x}:force_original_aspect_ratio=increase:flags=lanczos" \
                    -q:v 2 -y "$tmp" && [ -s "$tmp" ] && mv -f -- "$tmp" "$out"
                rm -f -- "$tmp"
            fi
            [ -s "$out" ] && { echo "$size $out"; ok=1; }
        done
        ;;
esac
[ "$ok" = 1 ]
