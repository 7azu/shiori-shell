#!/bin/bash
# Yazi as a floating window (size/position: window rule "fzfwindows" in windows.lua)

# yazi starts in the working directory: home, not the folder Hyprland was started from
cd "$HOME" || exit 1
exec kitty --class fzfwindows --name fzfwindows yazi
