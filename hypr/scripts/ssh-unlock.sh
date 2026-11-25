#!/bin/bash
# ~/.config/hypr/scripts/ssh-unlock.sh
#
# Unlocks the SSH key when called explicitly.
# --identity prints the sync key, if one is set and exists.
# --check checks the sync login without a passphrase window.
# The sync key comes from $SSH_UNLOCK_KEY (a sync entry's "sshKey": "<path>" in ~/.config/shiori-shell/settings.json,
# see quickshell/scripts/shiori_sync.py); without it the agent's usual keys (~/.ssh/id_ed25519) are used.
# A sync key without a passphrase needs no unlocking at all: the script then exits 0 without a window.
# A sync key with a passphrase is loaded into the agent itself (the usual keys do not help the sync).
# If the passphrase window (ssh-askpass -> pinentry-qt) does not open, try again a few times
# (this happened at login). If you cancel the window yourself, it does NOT ask again
# (ssh-askpass then writes "cancelled" to the result file) -> exit 1.
# History/errors are in $XDG_RUNTIME_DIR/ssh-unlock.log.

RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOG="$RUN/ssh-unlock.log"
export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-$RUN/ssh-agent.socket}"

log() { echo "$(date +%T) $*" >> "$LOG"; }
key_ready() { ssh-add -l >/dev/null 2>&1; }
# The sync key itself is in the agent (compared by fingerprint)
sync_key_ready() {
    local fingerprint
    fingerprint=$(ssh-keygen -lf "$sync_key" 2>/dev/null | awk '{print $2}')
    [ -n "$fingerprint" ] && ssh-add -l 2>/dev/null | grep -qF -- "$fingerprint"
}
key_without_passphrase() {
    SSH_ASKPASS_REQUIRE=never ssh-keygen -y -P "" -f "$1" </dev/null >/dev/null 2>&1
}

sync_key="${SSH_UNLOCK_KEY:-}"
sync_key="${sync_key/#\~/$HOME}"
if [ "$1" = "--identity" ]; then
    [ -z "$sync_key" ] || [ ! -f "$sync_key" ] || printf '%s\n' "$sync_key"
    exit 0
fi

if [ "$1" = "--check" ]; then
    if [ -n "$sync_key" ] && [ -f "$sync_key" ]; then
        key_without_passphrase "$sync_key" || sync_key_ready
        exit $?
    fi
    key_ready || [ ! -f "$HOME/.ssh/id_ed25519" ] || key_without_passphrase "$HOME/.ssh/id_ed25519"
    exit $?
fi

# A sync key without a passphrase is used directly, without the agent: nothing to unlock,
# so no passphrase window for the usual keys (same answer as --check).
if [ -n "$sync_key" ] && [ -f "$sync_key" ] && key_without_passphrase "$sync_key"; then
    exit 0
fi

export SSH_ASKPASS="${SSH_ASKPASS:-$HOME/.config/hypr/scripts/ssh-askpass}"
export SSH_ASKPASS_REQUIRE=force
export SSH_ASKPASS_RESULT="$RUN/ssh-askpass.result"
systemctl --user start ssh-agent.socket 2>>"$LOG"

# With a sync key (it has a passphrase, see above) exactly that key, otherwise the agent's usual keys
if [ -n "$sync_key" ] && [ -f "$sync_key" ]; then
    ready() { sync_key_ready; }
    add() { ssh-add "$sync_key"; }
else
    ready() { key_ready; }
    add() { ssh-add; }
fi

for try in 1 2 3 4 5; do
    ready && { log "key is in the agent"; exit 0; }
    rm -f "$SSH_ASKPASS_RESULT"
    log "try $try: ssh-add"
    if add </dev/null 2>>"$LOG"; then
        log "unlocked"
        exit 0
    fi
    if [ "$(cat "$SSH_ASKPASS_RESULT" 2>/dev/null)" = cancelled ]; then
        log "cancelled by user, not asking again"
        exit 1
    fi
    sleep 3
done
log "giving up"
exit 1
