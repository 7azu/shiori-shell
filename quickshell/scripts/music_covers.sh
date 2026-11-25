#!/bin/bash
# Small cover previews for the music picker (permanent cache, only missing ones are created).
# Usage: music_covers.sh <musicDir> <coverDir> <size> <md5> <songpath> [<md5> <songpath> ...]
#        (songpath relative to musicDir, order = priority)
# stdout: one line per song "<md5> jpg" (cover there) or "<md5> none" (song has no cover)
music="$1"
dir="$2"
size="${3:-216}"
shift 3
mkdir -p "$dir"

make_one() {
    local md5="$1" path="$2" tmp="$dir/.$md5.$$.jpg"
    # Crop to a square as in the picker (PreserveAspectCrop), small and quick to decode
    if ffmpeg -nostdin -v error -i "$music$path" -an -frames:v 1 \
        -vf "scale=$size:$size:force_original_aspect_ratio=increase,crop=$size:$size" \
        -q:v 3 -y "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv -f "$tmp" "$dir/$md5.jpg"
        rm -f "$dir/$md5.none"
        echo "$md5 jpg"
    else
        rm -f "$tmp" "$dir/$md5.jpg"
        : > "$dir/$md5.none"
        echo "$md5 none"
    fi
}
export -f make_one
export music dir size

# Report current ones right away, then create missing or outdated ones in parallel (low priority).
# Outdated = song file newer than the entry (e.g. song deleted and downloaded again with a cover),
# otherwise a "no cover" remembered once would stick forever
todo=()
while [ $# -ge 2 ]; do
    md5="$1" path="$2"
    shift 2
    if [ -e "$dir/$md5.jpg" ] && ! [ "$music$path" -nt "$dir/$md5.jpg" ]; then
        echo "$md5 jpg"
    elif [ -e "$dir/$md5.none" ] && ! [ "$music$path" -nt "$dir/$md5.none" ]; then
        echo "$md5 none"
    else
        todo+=("$md5" "$path")
    fi
done
[ ${#todo[@]} -eq 0 ] && exit 0
printf '%s\0' "${todo[@]}" | nice -n 10 xargs -0 -n 2 -P "$(nproc)" bash -c 'make_one "$1" "$2"' _
