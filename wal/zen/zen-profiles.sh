#!/bin/bash
# Prints the Zen profiles Zen really uses (one per line, with / at the end).
# Profile folders have different names on every machine (<random>.Default (release), sometimes also an
# unused "Default Profile") -> installs.ini decides (Default= per installation).
# Fallback without installs.ini: *.Default (release). Used by install-zen-prefs.sh and
# hypr/scripts/wallpaper-apps.sh.
shopt -s nullglob
found=0
for dir in "$HOME/.config/zen" "$HOME/.zen"; do
    [ -d "$dir" ] || continue
    while IFS= read -r p; do
        [[ "$p" == /* ]] || p="$dir/$p"
        [ -d "$p" ] && { printf '%s/\n' "${p%/}"; found=1; }
    done < <(sed -n 's/^Default=//p' "$dir/installs.ini" 2>/dev/null | sort -u)
    if [ "$found" = 0 ]; then
        for p in "$dir"/*.Default\ \(release\)/; do
            printf '%s\n' "$p"
            found=1
        done
    fi
done
exit 0
