#!/usr/bin/env bash
# Claude Code status line (set as statusLine in ~/.claude/settings.json).
# 1) Stores the plan limits (rate_limits) for the Quickshell bar:
#    ~/.cache/quickshell/claude-limits.json  -> { "updated": <epoch>, "rate_limits": {...} }
# 2) Prints a short line for the status line in Claude Code.

input=$(cat)
dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
file="$dir/claude-limits.json"

if printf '%s' "$input" | jq -e '.rate_limits | type == "object"' >/dev/null 2>&1; then
    mkdir -p "$dir"
    printf '%s' "$input" | jq -c --argjson now "$(date +%s)" '{updated: $now, rate_limits: .rate_limits}' >"$file.tmp" \
        && mv "$file.tmp" "$file"
fi

printf '%s' "$input" | jq -r '
    def pct(w): (w.used_percentage // w.utilization) as $u
        | if $u == null then empty else ($u | floor | tostring) + "%" end;
    [ (.model.display_name // empty),
      (if .rate_limits.five_hour then "5h " + pct(.rate_limits.five_hour) else empty end),
      (if .rate_limits.seven_day then "7d " + pct(.rate_limits.seven_day) else empty end)
    ] | map(select(. != "" and . != "5h " and . != "7d ")) | join(" · ")
' 2>/dev/null
