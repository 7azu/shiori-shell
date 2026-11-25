#!/bin/bash
# Remembers the last used VPN connection and restores it.
# Usage:
#   vpn-state.sh save <name>   – stores <name> as the last connection
#   vpn-state.sh restore       – connects to the stored connection

STATE_FILE="$HOME/.cache/vpn-last"

case "$1" in
    save)
        if [ -z "$2" ]; then
            echo "Usage: $0 save <name>"
            exit 1
        fi
        echo "$2" > "$STATE_FILE"
        ;;
    restore)
        [ -f "$STATE_FILE" ] || exit 0
        NAME=$(cat "$STATE_FILE")
        [ -n "$NAME" ] || exit 0

        # Wait briefly until NetworkManager is ready (after login)
        for i in $(seq 1 10); do
            if nmcli -t -f RUNNING general 2>/dev/null | grep -q "running"; then
                break
            fi
            sleep 1
        done

        # Only connect if it is not active already
        if ! nmcli -t -f NAME connection show --active | grep -qxF "$NAME"; then
            nmcli connection up "$NAME"
        fi
        ;;
    *)
        echo "Usage: $0 {save <name>|restore}"
        exit 1
        ;;
esac
