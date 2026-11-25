#!/bin/bash
# rmpc on the home stage (started by start.sh in the kitty window kitty-stage-music).
# Starts rmpc again in the same window when ~/.config/wal/gen-rmpc-cover.sh asks for it: rmpc reads its
# fallback cover (shown when no song is loaded) only at start, neither "set theme" nor a changed theme
# file reloads it. rmpc keeps no state of its own (queue and playback live in MPD), so a restart is safe.
# Quitting rmpc by hand (q) still closes the window.

flag="${XDG_RUNTIME_DIR:-/tmp}/rmpc-stage-restart"
rm -f "$flag"
while true; do
    rmpc
    [ -e "$flag" ] || break
    rm -f "$flag"
done
