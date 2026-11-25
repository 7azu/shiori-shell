#!/bin/bash
# Stores a new clipboard entry in cliphist and shows a short notification.
# Called by (Hyprland, modules/autostart.lua):
#   wl-paste --type text  --watch ~/.config/quickshell/scripts/clip_store.sh text
#   wl-paste --type image --watch ~/.config/quickshell/scripts/clip_store.sh image
# Passwords (CLIPBOARD_STATE=sensitive, e.g. KeePassXC) are not shown.
# Screenshots create $XDG_RUNTIME_DIR/qs-clip-quiet first -> no double notification.
# Copies from the clipboard picker create $XDG_RUNTIME_DIR/qs-clip-from-picker -> neither stored nor shown.

kind="$1"
run="${XDG_RUNTIME_DIR:-/tmp}"

# Copy from the clipboard picker (ClipboardState.copyEntry creates the file): already in cliphist, do not
# store it again (otherwise a new id -> the entry jumps to the top) and do not notify (the picker confirms itself).
# Do not delete: for images both the text and the image watcher can fire; the file counts for 2 s.
from_picker="$run/qs-clip-from-picker"
if [ -e "$from_picker" ] && [ $(( $(date +%s) - $(stat -c %Y "$from_picker") )) -lt 2 ]; then
    cat > /dev/null
    exit 0
fi
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"

# As before: cliphist decides itself what is stored
cliphist store < "$tmp"

[ "${CLIPBOARD_STATE:-data}" = "data" ] || exit 0
[ -s "$tmp" ] || exit 0

quiet="$run/qs-clip-quiet"
if [ -e "$quiet" ] && [ $(( $(date +%s) - $(stat -c %Y "$quiet") )) -lt 5 ]; then
    rm -f "$quiet"
    exit 0
fi

if [ "$kind" = "image" ]; then
    img="$run/qs-clip-last.png"
    cp "$tmp" "$img"
    notify-send -a "Clipboard" -e -t 2500 -h "string:x-qs-success:1" -h "string:image-path:$img" -- "Image copied" "Saved to clipboard history"
else
    # First line, shortened; only whitespace = no notification
    preview=$(head -c 400 "$tmp" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ $//' | cut -c1-90)
    [ -n "$preview" ] || exit 0
    chars=$(wc -m < "$tmp")
    notify-send -a "Clipboard" -e -t 2500 -h "string:x-qs-success:1" -- "Copied · $chars chars" "$preview"
fi
