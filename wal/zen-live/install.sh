#!/bin/bash
# Live colors for Zen: AutoConfig script into the Zen installation + a pacman hook that puts it
# back after Zen updates. Run with: sudo ~/.config/wal/zen-live/install.sh
# (after changes to the files here simply run it again)
set -eu
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi
src="$(dirname "$(readlink -f "$0")")"
if [ ! -x /opt/zen-browser-bin/zen-bin ]; then
    echo "Zen not found at /opt/zen-browser-bin" >&2
    exit 1
fi
# Root-owned copy: the hook runs as root and runs nothing from the home folder
share=/usr/local/share/zen-live
install -Dm644 "$src/autoconfig.js" "$share/autoconfig.js"
install -Dm644 "$src/zen-live.cfg" "$share/zen-live.cfg"
install -Dm755 "$src/apply.sh" "$share/apply.sh"
install -Dm644 "$src/zen-live.hook" /etc/pacman.d/hooks/zen-live.hook
"$share/apply.sh"
echo "Done. Restart Zen once, then the color follows the wallpaper live."
