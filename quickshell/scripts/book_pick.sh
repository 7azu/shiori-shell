#!/bin/bash
# Yazi file picker for the Read tab of the language tool ("Add a book" card).
#   book_pick.sh <books folder>
# Opens yazi in a floating kitty (same window class as Super+E) in Downloads and copies the chosen
# EPUB/TXT/PDF/MD files into the books folder (setting "books"). The import itself is the normal scan of
# that folder (scripts/jp_library.py scan), which the picker starts when it opens again.
# Never overwrites: an identical file is skipped, a different one with the same name gets " (2)".
set -euo pipefail

notify() {
    notify-send -a "Language tool" "Add a book" "$1" 2>/dev/null || true
}

books=${1:-}
if [[ -z "$books" ]]; then
    notify "No books folder set (setting folders.books)"
    exit 1
fi

for tool in kitty yazi; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        notify "$tool is not installed"
        exit 1
    fi
done

mkdir -p -- "$books"
books=$(cd -- "$books" && pwd -P)

start=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
[[ -d "$start" ]] || start="$HOME/Downloads"
[[ -d "$start" ]] || start="$books"

selection=$(mktemp)
trap 'rm -f -- "$selection"' EXIT

# Without --detach: read the selection only after yazi is closed
if ! kitty --class fzfwindows --name fzfwindows yazi --chooser-file="$selection" "$start"; then
    exit 0
fi

skipped=0
while IFS= read -r file || [[ -n "$file" ]]; do
    [[ -n "$file" && -f "$file" ]] || continue
    case "${file,,}" in
        *.epub | *.txt | *.pdf | *.md) ;;
        *) skipped=$((skipped + 1)); continue ;;
    esac
    real=$(cd -- "$(dirname -- "$file")" && pwd -P)/$(basename -- "$file")
    # Already in the books folder: the scan finds it anyway
    if [[ "$real" == "$books"/* ]]; then
        continue
    fi
    name=$(basename -- "$file")
    dest="$books/$name"
    if [[ -e "$dest" ]] && cmp -s -- "$file" "$dest"; then
        continue
    fi
    stem=${name%.*}
    ext=${name##*.}
    n=2
    while [[ -e "$dest" ]]; do
        dest="$books/$stem ($n).$ext"
        n=$((n + 1))
    done
    cp -n -- "$file" "$dest"
done < "$selection"

if ((skipped > 0)); then
    notify "Skipped $skipped file(s): only EPUB, TXT, PDF and MD can be imported"
fi
