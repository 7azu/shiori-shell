#!/bin/bash
# Autostart (from autostart.lua): wallpaper + colors, terminal layout on workspace 1,
# input method and music queue.

# Send a Lua dispatcher to Hyprland (since the Lua config, hyprctl dispatch expects hl.dsp.*)
dispatch() { hyprctl dispatch "$1" >/dev/null; }

# Optional programs are skipped when they are not installed (see install.sh)
has() { command -v "$1" >/dev/null 2>&1; }

# Waits up to 2 s until a window with exactly this class exists (class instead of title: programs
# in the terminal - zsh, Claude Code - change the title, sometimes even before the window appears)
wait_for_window() {
    for _ in $(seq 20); do
        hyprctl clients -j | jq -e --arg c "$1" 'any(.[]; .class == $c)' >/dev/null && return 0
        sleep 0.1
    done
    echo "Window '$1' not found" >&2
    return 1
}

# ---------- Wallpaper + pywal colors ----------
awww-daemon &
for _ in $(seq 50); do awww query >/dev/null 2>&1 && break; sleep 0.1; done
# Vesktop colors come from Quickshell (scripts/vesktop_colors.py -> QuickCSS, with a fade).
# wal must NOT write into the themes folder anymore: every change there makes Vencord reload all
# themes via @import -> ~170 ms of unthemed Discord. Remove the old link from before
# (only the link; pywal.css stays as a static fallback).
mkdir -p ~/.cache/wal
[ -L ~/.cache/wal/colors-discord.css ] && rm ~/.cache/wal/colors-discord.css
# Steam (Millennium, theme "Minimal Dark"): wal writes directly into Quick CSS
[ -d ~/.config/millennium ] && ln -sfn ~/.config/millennium/quick.css ~/.cache/wal/steam-colors.css
# Restore the last colors. On a fresh install there is nothing to restore yet: then take the default
# wallpaper that install.sh copied (colors made from it), without it the default palette
# (wal/colorschemes/dark/shiori.json). Either way all color files are written for the first time.
wal_bin=/usr/bin/wal
[ -x "$wal_bin" ] || wal_bin=wal
wall_state="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/current-wallpaper"
default_wall="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpaper/shiori-default.jpg"
if [ -f ~/.cache/wal/colors.json ]; then
    "$wal_bin" -R -n -e
elif [ -f "$default_wall" ] && "$wal_bin" -i "$default_wall" -n -e; then
    mkdir -p "$(dirname "$wall_state")"
    printf '%s\n' "$default_wall" > "$wall_state"
    # Hyprland read its config before these colors existed (fallback palette in looks.lua): reload,
    # otherwise the borders keep the default palette until the next wallpaper change
    hyprctl reload >/dev/null 2>&1
    # The apps get their colors the same way as on a wallpaper change (GTK theme, Zen settings and
    # website colors, Qt, OBS, fcitx5, rmpc cover ...); before, they waited for the first change
    bash "$HOME/.config/wal/gtk/install-gtk-theme.sh" >/dev/null 2>&1
    nohup "$HOME/.config/hypr/scripts/wallpaper-apps.sh" "$default_wall" >/dev/null 2>&1 &
else
    "$wal_bin" --theme shiori -n -e
fi
wallpaper_path=$(cat "$wall_state" 2>/dev/null)
[ -f "$wallpaper_path" ] || wallpaper_path=$(cat ~/.cache/wal/wal 2>/dev/null)
case "${wallpaper_path,,}" in
    *.gif|*.mp4|*.webm|*.mkv|*.mov|*.m4v|*/project.json) ;; # Quickshell plays animated backgrounds.
    *) [ -f "$wallpaper_path" ] && awww img "$wallpaper_path" --filter Bilinear & ;; # none yet on a fresh install
esac

# ---------- Environment for systemd/D-Bus ----------
# hl.env only applies to Hyprland's own children; apps started via D-Bus/systemd (portals,
# polkit agent, fcitx5 settings ...) need the Qt theme and input method separately
dbus-update-activation-environment --systemd QT_QPA_PLATFORMTHEME QT_IM_MODULE XMODIFIERS SDL_IM_MODULE GLFW_IM_MODULE

# Polkit agent (graphical password prompt for pkexec & co.), only after the import above,
# so the Qt dialog gets the wal colors from qt6ct
systemctl --user cat hyprpolkitagent.service >/dev/null 2>&1 && systemctl --user start hyprpolkitagent.service

# ---------- Input method ----------
has fcitx5 && fcitx5 -d

# ---------- Terminal stage on workspace 1 ----------
# Workspace, position, size, transparency and fly-in animation come from modules/home.lua
# (window rules by class). Started slightly apart, so the two fly in one after the other.
# The audio visualizer below is not a window but Quickshell (windows/DesktopVisualizer.qml).
# Wait for the Quickshell bar first (max. 5 s): home.lua computes the places relative to the area without
# the bar. Without waiting the bar was not there yet at boot -> rmpc ended up 40 px too high and too big.
for _ in $(seq 50); do
    hyprctl monitors -j | jq -e 'any(.[]; .reserved | add > 0)' >/dev/null && break
    sleep 0.1
done
# fastfetch at the top of the shell terminal, unless the own shell config already runs it
# (then it would show twice); kitty then hands over to the normal shell
stage_cmd=()
if has fastfetch && ! grep -qs fastfetch ~/.zshrc ~/.bashrc ~/.config/fish/config.fish; then
    stage_cmd=(sh -c 'fastfetch; exec "${SHELL:-/bin/bash}"')
fi
kitty --class kitty-stage-shell "${stage_cmd[@]}" &
wait_for_window kitty-stage-shell
sleep 0.15
# music player only with rmpc; without it the shell terminal stands alone
if has rmpc; then
    # in a small loop, so the fallback cover can be refreshed by a restart (see rmpc-stage.sh)
    kitty --class kitty-stage-music -e "$HOME/.config/hypr/scripts/rmpc-stage.sh" &
    wait_for_window kitty-stage-music
fi

dispatch 'hl.dsp.focus({ window = "class:^kitty-stage-shell$" })'
read -r x y < <(hyprctl clients -j | jq -r 'first(.[] | select(.class == "kitty-stage-shell"))
    | [.at[0] + .size[0] / 2, .at[1] + .size[1] / 2] | map(floor) | @tsv')
dispatch "hl.dsp.cursor.move({ x = $x, y = $y })"

# Neovim in tmux on workspace 3, but "silent": otherwise the window rule (windows.lua) brings workspace 3
# to the front and the main monitor jumps away from the stage (workspace 1) at boot.
# As a Hyprland exec, because only its start rule takes precedence over the title rule.
if has tmux && has nvim; then
    dispatch 'hl.dsp.exec_cmd("kitty --title=tmux_nvim -o background_opacity=1 -o dynamic_background_opacity=yes tmux new-session -A -s Nvim nvim", { workspace = "3 silent" })'
fi

# ---------- Music ----------
# MPD runs as a user service; only fill an empty queue with the whole library,
# otherwise every login appends the library again
if has mpd && has mpc; then
    systemctl --user start mpd.service
    for _ in $(seq 30); do mpc status >/dev/null 2>&1 && break; sleep 1; done
    if [ "$(mpc playlist | wc -l)" -eq 0 ]; then
        mpc listall | mpc add
    fi
    # mpd-mpris (MPD in the audio dropdown) needs a running MPD, so it is started here and not enabled.
    # An older install.sh enabled it: then it failed at login before MPD and systemd blocked further
    # starts (start-limit-hit) -> clear that first
    if has mpd-mpris; then
        systemctl --user reset-failed mpd-mpris.service 2>/dev/null
        systemctl --user start mpd-mpris.service
    fi
fi
