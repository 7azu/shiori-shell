#!/bin/bash
# Puts the Zen settings from the repo into the profile (the profile folder has a different name on every machine):
#   - user-prefs.js  -> marked block in <profile>/user.js (the rest of the file stays, e.g. the
#                       transparency color from wallpaper-apps.sh); the same prefs outside it are removed
#   - userContent.css -> symlink, or with the website colors directly in the profile
#     if the installed zen-live version loads no website CSS
# Runs on every wallpaper change (wallpaper-apps.sh).
# Zen reads both only at start.
set -u

SRC="$HOME/.config/wal/zen"
WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
live_site_css=0
if grep -qs 'zen-sites\.css' /opt/zen-browser-bin/zen-live.cfg; then
    live_site_css=1
fi
mapfile -t profiles < <("$SRC/zen-profiles.sh")
[ ${#profiles[@]} -gt 0 ] || exit 0

for p in "${profiles[@]}"; do
    mkdir -p "$p/chrome"
    css="$p/chrome/userContent.css"
    if [ "$live_site_css" = 1 ]; then
        ln -sfn "$SRC/userContent.css" "$css" || exit 1
    else
        pending=$(mktemp "$p/chrome/.userContent.XXXXXXXX") || exit 1
        if (
            cat "$SRC/userContent.css" || exit 1
            for site_css in "$WAL_CACHE/zen-youtube.css" "$WAL_CACHE/zen-sites.css"; do
                [ -f "$site_css" ] || continue
                printf '\n' && cat "$site_css" || exit 1
            done
        ) >"$pending" && mv -fT "$pending" "$css"; then
            :
        else
            rm -f "$pending"
            exit 1
        fi
    fi

    python3 -I - "$SRC/user-prefs.js" "$p/user.js" <<'EOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
BEGIN = "// >>> shiori-shell: ~/.config/wal/zen/user-prefs.js (do not edit here)"
END = "// <<< shiori-shell"
# Markers of older versions, still recognized so an existing block is replaced instead of duplicated
OLD_BEGIN = ("// >>> dotfiles: ~/.config/wal/zen/user-prefs.js (nicht hier bearbeiten)",)
OLD_END = ("// <<< dotfiles",)
block = open(src).read().strip()
keys = set(re.findall(r'user_pref\("([^"]+)"', block))
try:
    lines = open(dst).read().splitlines()
except FileNotFoundError:
    lines = []
out, inside = [], False
for line in lines:
    if line == BEGIN or line in OLD_BEGIN:
        inside = True
        continue
    if line == END or line in OLD_END:
        inside = False
        continue
    m = re.match(r'\s*user_pref\("([^"]+)"', line)
    if inside or (m and m.group(1) in keys):
        continue
    out.append(line)
text = re.sub(r"\n{3,}", "\n\n", "\n".join(out).strip())
new = (text + "\n\n" if text else "") + BEGIN + "\n" + block + "\n" + END + "\n"
if new != ("\n".join(lines) + "\n"):
    open(dst, "w").write(new)
EOF
done
exit 0
