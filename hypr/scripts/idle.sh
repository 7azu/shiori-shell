#!/usr/bin/env bash
# Starts hypridle with the steps from the settings (darker, lock, monitors off, standby).
#   idle.sh            at login (modules/autostart.lua)
#   idle.sh restart    after a change in the settings (Quickshell services/IdleState.qml)
# The configuration is written by quickshell/scripts/idle_config.py; if that fails, hypridle falls
# back to ~/.config/hypr/hypridle.conf.

if [ "${1:-}" = "restart" ]; then
    pkill -x hypridle
    for _ in $(seq 20); do pgrep -x hypridle >/dev/null || break; sleep 0.1; done
fi

if conf=$(python3 "$HOME/.config/quickshell/scripts/idle_config.py" 2>/dev/null) && [ -s "$conf" ]; then
    exec hypridle -c "$conf"
fi
exec hypridle
