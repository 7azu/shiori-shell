#!/bin/bash
# Prints the cookie source for yt-dlp: "firefox:<active Zen profile>" (Zen = Firefox based).
# Usage:  yt-dlp --cookies-from-browser "$(zen_cookies.sh)" ...
# yt-dlp reads the cookies fresh from the profile on every call -> no cookie file
# that goes stale or gets synced by accident. No profile found = empty output, exit 1.

zen="$HOME/.config/zen"
ini="$zen/profiles.ini"
[ -f "$ini" ] || exit 1

# The profile actually in use is in the [Install...] section, otherwise the one with Default=1
profile=$(awk -F= '
    /^\[/ { install = ($0 ~ /^\[Install/) }
    install && $1 == "Default" { print $2; exit }
' "$ini")
if [ -z "$profile" ]; then
    profile=$(awk -F= '
        /^\[/ { path = "" }
        $1 == "Path" { path = $2 }
        $1 == "Default" && $2 == "1" && path != "" { print path; exit }
    ' "$ini")
fi

[ -n "$profile" ] && [ -f "$zen/$profile/cookies.sqlite" ] || exit 1
printf 'firefox:%s\n' "$zen/$profile"
