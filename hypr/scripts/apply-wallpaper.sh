#!/bin/bash
# Set the wallpaper and bring all programs to the new pywal colors.
# The one place for this chain: called by the wallpaper picker (Quickshell,
# pickers/WallpaperPicker.qml).
#
#   apply-wallpaper.sh <image>
#
# Order: image (awww) -> colors (wal) -> GTK (own theme "Wal"), then independently
# Hyprland, Obsidian, Neovim and the remaining apps (wallpaper-apps.sh).

# Later ImageMagick calls must not grow without limit either.
export MAGICK_MEMORY_LIMIT=256MiB MAGICK_MAP_LIMIT=256MiB
export MAGICK_DISK_LIMIT=512MiB MAGICK_THREAD_LIMIT=2 MAGICK_TIME_LIMIT=60
path=$1
theme_path="$path"
playback_path="$path"
if [ ! -f "$path" ]; then
    echo "Image not found: $path" >&2
    exit 1
fi

wall_state="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/current-wallpaper"
mkdir -p "$(dirname "$wall_state")" || exit 1
# Image for the colors (scene: preview, video: first frame); Quickshell uses the same rule
# to compute the palette for the transition in advance
theme_path=$("$HOME/.config/hypr/scripts/wallpaper-theme-image.sh" "$path") || exit 1
case "${path,,}" in
    */project.json)
        command -v linux-wallpaperengine >/dev/null || { echo "linux-wallpaperengine is not installed" >&2; exit 1; }
        ;;
    *.gif|*.mp4|*.webm|*.mkv|*.mov|*.m4v)
        # Quickshell plays the original directly
        ;;
    *)
        # WALLPAPER_AWWW_TRANSITION=none: Quickshell covers the change with the ink transition,
        # an extra crossfade underneath would only delay it
        awww img "$path" --transition-type "${WALLPAPER_AWWW_TRANSITION:-simple}" \
            --transition-duration 0.8 --transition-fps 60 || exit 1
        ;;
esac
# Publish atomically: Quickshell loads the original video, or fades it out for images.
printf '%s\n' "$path" > "$wall_state.tmp"
mv -f -- "$wall_state.tmp" "$wall_state" || exit 1
# During the Quickshell transition (WALLPAPER_AWWW_TRANSITION=none) wal does NOT color the terminals itself
# (-s): quickshell/services/TerminalColorFade.qml does that smoothly and in sync with the wave. Otherwise wal
# sent its sequences right away with the final colors - for scenes/videos even before the wave started -, then
# the fade reset the old colors and only then blended over: the terminals flickered new/old.
# Without a transition (called by hand) everything stays as before. New terminals read their colors from
# the files that wal still writes anyway (colors-kitty.conf, sequences).
# -e: no "environment reload" of wal. The shell fades the terminals itself (TerminalColorFade); pywal16 would
# otherwise try to recolor kitty over a socket that does not exist and log an error on every change
wal_flags=(-n -e -i "$theme_path")
[ "${WALLPAPER_AWWW_TRANSITION:-}" = "none" ] && wal_flags=(-s "${wal_flags[@]}")
# An old pipx launcher in ~/.local/bin may point to a Python version that no longer exists.
if [ -x /usr/bin/wal ]; then
    /usr/bin/wal "${wal_flags[@]}" || exit 1
else
    wal "${wal_flags[@]}" || exit 1
fi
# Update the RGB hardware in parallel, so the desktop does not wait for it.
bash "$HOME/.config/hypr/scripts/wallpaper-openrgb.sh" &
# wal has already written the GTK colors; reload running GTK3 apps.
bash "$HOME/.config/wal/gtk/install-gtk-theme.sh" --reload >/dev/null 2>&1
# hyprctl reload: looks.lua reads the wal colors with dofile, which Hyprland does not watch
# (unlike "source =" before) -> without a reload the window borders would stay old.
hyprctl reload >/dev/null 2>&1
# Obsidian: the script finds the vault(s) itself from Obsidian's list. If Quickshell is running, the
# snippet is already written by services/TerminalColorFade.qml (obsidianFade) under a still image that blends over;
# a call here could beat the still image -> Obsidian would switch colors hard again.
pgrep -x qs >/dev/null || "$HOME/.config/wal/gen-obsidian-wal.sh" >/dev/null 2>&1
# Fallback for Neovim, in case the live update fails.
killall -SIGUSR1 nvim 2>/dev/null

nohup "$HOME/.config/hypr/scripts/wallpaper-apps.sh" "$theme_path" >/dev/null 2>&1 &
disown
exit 0
