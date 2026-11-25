#!/bin/bash

dir=$(python3 "$HOME/.config/quickshell/scripts/shiori_settings.py" folder screenshots)
[ -n "$dir" ] || dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

# Selection cancelled (Esc) -> do nothing
grim -g "$(slurp)" "$file" || exit 0

# Suppress the clipboard notification, the screenshot reports itself
touch "${XDG_RUNTIME_DIR:-/tmp}/qs-clip-quiet"
wl-copy < "$file"

# Clicking the notification opens the image, "Edit" opens satty
action=$(notify-send -a "Screenshot" -i "$file" -h "string:image-path:$file" -h "string:x-qs-success:1" \
    -A "default=Open" -A "edit=Edit" \
    -- "Screenshot saved" "Copied to clipboard · click to open")
case "$action" in
    default) swayimg "$file" ;;
    edit) satty --filename "$file" --output-filename "$file" ;;
esac
