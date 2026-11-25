#!/bin/bash
# Downloads the round flags (circle-flags, MIT) for all WireGuard connections
# into ~/.config/quickshell/resources/flags
# Without arguments: codes from the NetworkManager connections "proton-xx"
# With codes:        ./fetch-flags.sh de us nl
set -u
dest="$HOME/.config/quickshell/resources/flags"
mkdir -p "$dest"

if [ $# -gt 0 ]; then
    codes="$*"
else
    codes=$(nmcli -t -f NAME,TYPE connection show \
        | grep ':wireguard$' \
        | sed -nE 's/^proton-([a-zA-Z]{2})([-_.].*)?:wireguard$/\1/p' \
        | tr 'A-Z' 'a-z' | sort -u)
fi

[ -n "$codes" ] || { echo "No country codes found (import VPN files via the Quickshell VPN picker first)"; exit 1; }

for c in $codes; do
    url="https://raw.githubusercontent.com/HatScripts/circle-flags/gh-pages/flags/$c.svg"
    if curl -fsS -o "$dest/$c.svg" "$url"; then
        echo "ok: $c"
    else
        rm -f "$dest/$c.svg"
        echo "not found: $c" >&2
    fi
done
echo "Flaggen in $dest"
