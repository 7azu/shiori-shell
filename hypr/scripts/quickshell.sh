#!/bin/bash
# Start Quickshell (autostart and SUPER+SHIFT+Q in keybindings.lua). Arguments go to qs.
#
# MALLOC_CONF: Quickshell uses jemalloc, which by default creates 4 memory arenas per CPU core
# (64 on a 16-core CPU) and keeps freed memory in each. With the big buffers of the video wallpaper
# Quickshell got to ~900 MB. With 2 arenas (measured): video player ~127 instead of ~223 MB, the empty
# shell 29 instead of 59 MB, CPU load unchanged. Applies only to Quickshell, not to other programs.
export MALLOC_CONF="narenas:2,dirty_decay_ms:1000,muzzy_decay_ms:0,background_thread:true"
exec qs "$@"
