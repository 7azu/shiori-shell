#!/usr/bin/env bash
# Moves a window silently (without changing focus) to a workspace.
#   Usage: hypr_move_window.sh <window-address> <workspace-nr>
#
# Hyprland with the Lua config: the old syntax
#   hyprctl dispatch movetoworkspacesilent 3,address:0x...
# is read as Lua code and fails. So the window is looked up in Lua
# by its address and moved with hl.dsp.window.move.
# If that fails (e.g. still an old hyprlang config), the old syntax is used.

addr="${1#0x}"
addr="${addr,,}"
ws="$2"

# Allow only a hex address and digits (the values end up in Lua code)
case "$addr" in '' | *[!0-9a-f]*) exit 1 ;; esac
case "$ws" in '' | *[!0-9]*) exit 1 ;; esac

lua="local w for _, x in ipairs(hl.get_windows()) do if tostring(x.address):lower():gsub(\"^0x\", \"\") == \"$addr\" then w = x end end if not w then return end hl.dispatch(hl.dsp.window.move({ workspace = \"$ws\", follow = false, window = w }))"

out=$(hyprctl eval "$lua" 2>&1)
if printf '%s' "$out" | grep -qiE 'error|invalid|unknown|expected'; then
    hyprctl dispatch "movetoworkspacesilent $ws,address:0x$addr" > /dev/null 2>&1
fi
