#!/usr/bin/env bash
# Hands the password prompt (polkit agent) between the shell and hyprpolkitagent.
# Called by services/PolkitState.qml; only one agent can answer in a session.
#
#   polkit_agent.sh takeover   the shell answers from now on: stop hyprpolkitagent and leave a small
#                              watcher behind that starts it again as soon as this shell process ends
#                              (crash, restart, logout), so there is never a time without a prompt
#   polkit_agent.sh release    the shell stops answering (setting turned off): hyprpolkitagent again
#
# The watcher runs as its own systemd user unit, outside the shell, so it survives the shell's exit.
# The shell process is the parent of this script ($PPID).
set -u

AGENT=hyprpolkitagent.service
WATCH=shiori-polkit-fallback.service

has_agent() {
    systemctl --user cat "$AGENT" >/dev/null 2>&1
}

case "${1:-}" in
takeover)
    shell_pid=$PPID
    # A watcher from an earlier shell process is not needed any more
    systemctl --user stop "$WATCH" 2>/dev/null
    if has_agent; then
        systemd-run --user --quiet --collect --unit="$WATCH" \
            --description="Start hyprpolkitagent once the Quickshell password prompt is gone" \
            sh -c "tail --pid=$shell_pid -f /dev/null; systemctl --user restart $AGENT"
        # Right after login graphical-session.target may still have a start job queued for the agent:
        # wait for it (up to 3 s), or the agent comes up after it was stopped and takes the place
        for _ in $(seq 30); do
            systemctl --user list-jobs --no-legend 2>/dev/null | grep -q " $AGENT " || break
            sleep 0.1
        done
        systemctl --user stop "$AGENT" 2>/dev/null
    fi
    exit 0
    ;;
release)
    systemctl --user stop "$WATCH" 2>/dev/null
    # restart, not start: an instance that came up while the shell answered could not register
    has_agent && systemctl --user restart "$AGENT"
    exit 0
    ;;
*)
    echo "usage: polkit_agent.sh takeover|release" >&2
    exit 64
    ;;
esac
