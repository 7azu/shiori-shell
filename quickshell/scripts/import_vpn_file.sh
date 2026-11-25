#!/bin/bash
# Imports the given WireGuard .conf files (e.g. from Proton; chosen in the VPN picker) as NetworkManager connections "proton-<country>[-N]".
# Usage: import_vpn_file.sh <file.conf>...  - runs without sudo (nmcli import as a normal user).
#
# The country code is read from the file name, e.g.:
#   NL#12.conf, wg-NL-FREE-12.conf, proton-nl.conf  ->  proton-nl, proton-nl-2, ...
set -u

notify() { # $1 = title, $2 = text, $3 = "ok" -> success (Quickshell fires a sparkle)
    command -v notify-send >/dev/null 2>&1 && notify-send -a "VPN" ${3:+-h "string:x-qs-success:1"} "$1" "${2:-}"
    return 0
}

# Reads the country code from the file name (first 2-letter token, "wg" is skipped)
country_code() {
    local base lower tok
    base=$(basename "$1")
    base="${base%.conf}"
    lower=$(echo "$base" | tr 'A-Z' 'a-z')
    for tok in $(echo "$lower" | tr -c 'a-z' ' '); do
        if [ "${#tok}" -eq 2 ] && [ "$tok" != "wg" ]; then
            echo "$tok"
            return
        fi
    done
    echo "xx"
}

[ "$#" -gt 0 ] || exit 0
files=$(printf '%s\n' "$@")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

existing=$(nmcli -g NAME connection show)
ok=0
fail=0
last_err=""

while IFS= read -r f; do
    [ -n "$f" ] || continue

    cc=$(country_code "$f")
    name="proton-$cc"
    n=2
    while grep -qxF "$name" <<<"$existing"; do
        name="proton-$cc-$n"
        n=$((n + 1))
    done

    # NetworkManager names the connection + interface after the file name
    cp -- "$f" "$tmp/$name.conf"
    if err=$(nmcli connection import type wireguard file "$tmp/$name.conf" 2>&1); then
        nmcli connection modify "$name" connection.autoconnect no >/dev/null 2>&1
        existing+=$'\n'"$name"
        ok=$((ok + 1))
    else
        fail=$((fail + 1))
        last_err="$(basename "$f"): $err"
    fi
    rm -f "$tmp/$name.conf"
done <<<"$files"

if [ "$fail" -gt 0 ]; then
    notify "VPN import: $ok ok, $fail failed" "$last_err"
elif [ "$ok" -gt 0 ]; then
    notify "VPN import" "$ok connection(s) imported" ok
fi
exit 0
