#!/bin/bash
# After a wallpaper change: bring apps to the new wal colors that do not do it themselves.
# Called by apply-wallpaper.sh AFTER it has already done awww, wal, GTK (theme Wal),
# nvim and Obsidian - so not again here.
# Vesktop needs nothing: Quickshell blends the colors over via QuickCSS
# (services/TerminalColorFade.qml + scripts/vesktop_colors.py, Template: ~/.config/wal/templates/colors-discord.css).

# ---------- rmpc ----------
# Fallback cover (song without a cover) in the new wal colors; rmpc reloads the theme itself.
# Before Zen, because the Zen part ends with exit.
~/.config/wal/gen-rmpc-cover.sh

# ---------- Telegram ----------
# walogram builds ~/.cache/walogram/wal.tdesktop-theme from the wal colors (wallpaper blurred
# as the chat background), the script fills its gaps and restarts a running Telegram
# (it reads the theme only at start). Select it once in Telegram: Settings >
# Chat Settings > "Choose from file".
~/.config/wal/telegram/gen-telegram-theme.sh

# ---------- Steam ----------
# The Millennium plugin "pywal live" loads the colors themselves from Quick CSS. Here only switch the
# fixed colors in the theme "Minimal Dark" to the wal variables - only does something after a
# theme update, Steam loads the patched theme on its next start.
steam_patch=$(python3 ~/.config/wal/steam/patch-theme.py 2>&1)
[ -n "$steam_patch" ] && pgrep -x steamwebhelper >/dev/null &&
    notify-send -a Steam "Steam theme switched to wal colors" "$steam_patch"

# ---------- Qt (qt6ct) ----------
# Quickshell already wrote it at the start of the wave (TerminalColorFade.qml); here the final state from
# colors.json (unchanged -> no second reload) and the case without Quickshell
~/.config/wal/qt/gen-qt6ct-colors.sh

# ---------- OBS Studio ----------
# Yami variant "Wal" (~/.config/obs-studio/themes/Wal.ovt). Quickshell already writes it at the
# start of the wave and blends over with a still image (TerminalColorFade.qml); here only the final state,
# in case Quickshell is not running. Select it once: Settings > Appearance > theme Yami, style Wal.
~/.config/wal/obs/gen-obs-theme.sh

# ---------- hyprtoolkit (screen picker when streaming) ----------
# hyprland-share-picker is no longer Qt since xdph 1.5.0 -> own color file, applies from the next opening
~/.config/wal/hyprtoolkit/gen-hyprtoolkit-colors.sh

# ---------- Fcitx5 ----------
# Own theme instead of GTK: theme.conf from the wal colors, a running Fcitx5 reloads it
~/.config/wal/fcitx5/gen-fcitx5-theme.sh

# ---------- Cursor ----------
# Cursor (Kitty / Bongo Cat) in the wal accent color. If Quickshell is running, it already fades the cursor
# in sync with the wave (services/CursorColorFade.qml -> ~/.config/wal/cursor/cursor-fade.py); gen-cursor.sh
# would interfere (Adwaita in between) -> only as a fallback without Quickshell
pgrep -f 'wal/cursor/cursor-fade.py' >/dev/null || ~/.config/wal/cursor/gen-cursor.sh

# ---------- Helium ----------
# Base colors follow the GTK theme "Wal" live (theme "GTK" in Helium). Here only the
# accent color - takes effect on the next Helium start (details in the script)
~/.config/wal/helium/apply-helium-color.sh

# ---------- Zen: more websites in wal colors ----------
# GitHub, Reddit ... (site data in ~/.config/wal/zen/sites.json); Quickshell already builds this at the start
# of the wave, this is for the case without Quickshell. zen-live loads ~/.cache/wal/zen-sites.css live.
python3 -I -B ~/.config/wal/zen/zen-sites.py build

# ---------- Zen: synced settings (fonts, userContent.css) into the profile ----------
# Before the Zen color part, because that one ends with exit
~/.config/wal/zen/install-zen-prefs.sh

# ---------- Zen ----------
# With zen-live (~/.config/wal/zen-live/install.sh) Zen watches the wal color file itself
# and changes colors without a restart -> nothing to do.
[ -f /opt/zen-browser-bin/zen-live.cfg ] && exit 0

# Without zen-live: write the color into user.js and restart Zen. Zen reads user.js on
# every start but never writes it itself (prefs.js would be overwritten on exit).
# The profile folder has a different name on every machine -> the active one from Zen's installs.ini
ZEN_PROFILE=$(~/.config/wal/zen/zen-profiles.sh | head -n1)
[ -n "$ZEN_PROFILE" ] || exit 0
ZEN_USERJS="${ZEN_PROFILE}user.js"
PREF="mod.sameerasw.zen_transparency_color"

touch "$ZEN_USERJS"
sed -i "/$PREF/d" "$ZEN_USERJS"
echo "user_pref(\"$PREF\", \"$(cat ~/.cache/wal/colors-zen.txt)\");" >> "$ZEN_USERJS"

if pgrep -f zen-bin >/dev/null; then
    pkill -f zen-bin
    # Wait until Zen is really closed (profile lock released), at most 15 s
    for _ in $(seq 75); do pgrep -f zen-bin >/dev/null || break; sleep 0.2; done
    setsid /opt/zen-browser-bin/zen-bin </dev/null >/dev/null 2>&1 &
fi
