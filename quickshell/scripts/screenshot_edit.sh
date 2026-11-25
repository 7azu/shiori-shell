#!/bin/bash
# Helper for the screenshot editor (services/ScreenshotEditorState.qml, SUPER + SHIFT + S).
#   capture <file>  select an area with slurp and capture it (cancel with Esc -> exit 1)
#   save <file>     move the edited image to ~/Pictures/Screenshots, copy it, notify
#   save-next <file> <original>  like save, but as <name>-edited.png next to the original (never overwrites)
#   overwrite <file> <original>  replaces the original atomically and keeps its format and permissions
#   copy <file>     only put the edited image on the clipboard, notify
#   list <folder>   images in the folder, naturally sorted (only formats the editor can read)

run="${XDG_RUNTIME_DIR:-/tmp}"

to_clipboard() {
    # Suppress the clipboard notification, the screenshot reports itself
    touch "$run/qs-clip-quiet"
    wl-copy --type image/png < "$1"
}

case "$1" in
    capture)
        mkdir -p "$(dirname "$2")"
        # Leftovers of the last "copy": the notification needed the image, the folder is in RAM
        rm -f "$(dirname "$2")"/export-*.png
        # </dev/null: without a terminal slurp first reads rectangles from stdin, and the pipe from
        # Quickshell's Process never closes -> slurp would wait forever and show nothing
        geometry=$(slurp </dev/null) || exit 1
        grim -g "$geometry" "$2"
        ;;
    save)
        dir=$(python3 "$(dirname "$0")/shiori_settings.py" folder screenshots)
        [ -n "$dir" ] || dir="$HOME/Pictures/Screenshots"
        mkdir -p "$dir"
        stamp=$(date +%Y-%m-%d_%H-%M-%S)
        file="$dir/screenshot_$stamp.png"
        # Video frames also come several times per second: overwrite nothing
        n=2
        while [ -e "$file" ]; do
            file="$dir/screenshot_$stamp-$n.png"
            n=$((n + 1))
        done
        mv -- "$2" "$file" || exit 1
        to_clipboard "$file"
        action=$(notify-send -a "Screenshot" -i "$file" -h "string:image-path:$file" -h "string:x-qs-success:1" \
            -A "default=Open" \
            -- "Screenshot saved" "Copied to clipboard · click to open")
        if [ "$action" = "default" ]; then
            swayimg "$file"
        fi
        ;;
    save-next)
        dir=$(dirname -- "$3")
        name=$(basename -- "$3")
        stem="${name%.*}"
        file="$dir/$stem-edited.png"
        n=2
        while [ -e "$file" ]; do
            file="$dir/$stem-edited-$n.png"
            n=$((n + 1))
        done
        if ! mv -- "$2" "$file"; then
            notify-send -a "Screenshot" -u critical -- "Could not save image" "No write access to $dir?"
            exit 1
        fi
        to_clipboard "$file"
        # In the background: notify-send waits for a click, but the editor waits for the end of the script
        (
            action=$(notify-send -a "Screenshot" -i "$file" -h "string:image-path:$file" -h "string:x-qs-success:1" \
                -A "default=Open" \
                -- "Image saved" "$(basename -- "$file") · copied to clipboard")
            if [ "$action" = "default" ]; then
                swayimg "$file"
            fi
        ) >/dev/null 2>&1 &
        ;;
    overwrite)
        target=$(realpath -- "$3") || exit 1 # symlink: replace the real file, not the link
        dir=$(dirname -- "$target")
        name=$(basename -- "$target")
        ext="${name##*.}"
        ext="${ext,,}"
        fail() {
            [ -n "$tmp" ] && rm -f -- "$tmp"
            notify-send -a "Screenshot" -u critical -- "Could not overwrite $name" "$1. The original is unchanged."
            exit 1
        }
        # Finish writing next to it first: if something breaks off, the original stays intact
        tmp=$(mktemp -p "$dir" --suffix=".$ext" .qs-edit-XXXXXX) || fail "No write access to $dir"
        case "$ext" in
            png) cp -- "$2" "$tmp" || fail "Writing failed" ;;
            jpg|jpeg) magick "$2" -background white -alpha remove -quality 95 "$tmp" || fail "Converting failed" ;;
            webp) magick "$2" -quality 95 "$tmp" || fail "Converting failed" ;;
            *) magick "$2" "$tmp" || fail "Converting failed" ;;
        esac
        chmod --reference="$target" -- "$tmp" 2>/dev/null
        mv -f -- "$tmp" "$target" || fail "Replacing failed"
        to_clipboard "$2"
        rm -f -- "$2"
        notify-send -a "Screenshot" -i "$target" -h "string:image-path:$target" -h "string:x-qs-success:1" \
            -- "Original overwritten" "$name · copied to clipboard"
        ;;
    copy)
        to_clipboard "$2"
        notify-send -a "Screenshot" -i "$2" -h "string:image-path:$2" -h "string:x-qs-success:1" \
            -- "Image copied" "Not saved to disk"
        # The notification still shows the image briefly, then the RAM folder is freed again
        (sleep 30; rm -f -- "$2") >/dev/null 2>&1 &
        ;;
    list)
        find "$2" -maxdepth 1 -xtype f -not -name '.*' \
            \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
            -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tif' -o -iname '*.tiff' \) | sort -V
        ;;
    *)
        echo "usage: $0 capture|save|save-next|overwrite|copy|list ..." >&2
        exit 2
        ;;
esac
