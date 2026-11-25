#!/bin/bash
# Move a wallpaper from the picker to the trash (restorable via the trash picker).
# Usage: wallpaper_trash.sh <wallpaperDir> <path>
#   - local file directly in <wallpaperDir>        -> only this file
#   - file in steamapps/workshop/content/431960/<id>/ -> the whole workshop folder
# stdout: "local" or "workshop <id>"; errors (in English, they are shown) on stderr.
# Everything else is rejected, so a broken path never removes anything else.
dir=$(realpath -e -- "$1" 2>/dev/null) || { echo "Wallpaper folder not found" >&2; exit 1; }
path=$(realpath -e -- "$2" 2>/dev/null) || { echo "File not found: $2" >&2; exit 1; }

if [ "$(dirname -- "$path")" = "$dir" ] && [ -f "$path" ]; then
    gio trash -- "$path" || exit 1
    echo "local"
    exit 0
fi

# The video can be in a subfolder of the project -> go up to the project folder
folder=$(dirname -- "$path")
while [ "$folder" != / ] && [[ "$(dirname -- "$folder")" != */steamapps/workshop/content/431960 ]]; do
    folder=$(dirname -- "$folder")
done
id=$(basename -- "$folder")
if [[ "$(dirname -- "$folder")" == */steamapps/workshop/content/431960 ]] \
    && [[ "$id" =~ ^[0-9]+$ ]] && [ -f "$folder/project.json" ]; then
    gio trash -- "$folder" || exit 1
    echo "workshop $id"
    exit 0
fi

echo "Refusing to delete a file outside the wallpaper folders" >&2
exit 1
