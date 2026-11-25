#!/bin/bash

kitty --title="tmux_nvim" -o background_opacity=1 -o dynamic_background_opacity=yes tmux new-session -A -s Nvim nvim
