#!/bin/bash
# Opens a video in the shell's editor (opener in yazi.toml).
# "qs ipc" reports success even without a match, so check first whether the shell is running at all.
file=$(realpath -- "$1") || exit 1
if pgrep -x qs >/dev/null; then
    exec qs ipc call videoEditor open "$file" >/dev/null 2>&1
fi
exec mpv -- "$file"
