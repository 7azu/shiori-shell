#!/bin/bash
# Opens an image in the shell's editor, together with the other images of its folder (opener in yazi.toml).
# "qs ipc" reports success even without a match, so check first whether the shell is running at all.
file=$(realpath -- "$1") || exit 1
if pgrep -x qs >/dev/null; then
    exec qs ipc call imageEditor open "$file" >/dev/null 2>&1
fi
exec swayimg -- "$file"
