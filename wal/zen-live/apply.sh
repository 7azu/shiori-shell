#!/bin/bash
# Puts the live colors into the Zen installation. Called by the pacman hook after every
# Zen update (an update overwrites /opt/zen-browser-bin).
set -eu
share=/usr/local/share/zen-live
zen=/opt/zen-browser-bin
[ -d "$zen" ] || exit 0
install -Dm644 "$share/autoconfig.js" "$zen/defaults/pref/autoconfig.js"
install -Dm644 "$share/zen-live.cfg" "$zen/zen-live.cfg"
