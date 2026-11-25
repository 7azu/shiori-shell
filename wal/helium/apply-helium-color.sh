#!/bin/bash
# Helium (Chromium based): accent color from the wal colors.
#
# The base colors (bar, tabs, text) come live from the GTK theme "Wal" - Helium is set to
# theme "GTK" (helium://settings/appearance), apply-wallpaper.sh reloads the GTK theme.
# But Chromium does not take the accents (focus ring of the URL bar, hover of "+", profile icon, ...)
# from GTK, but from its own base color (pref browser.theme.user_color2,
# default Google blue). That only exists as a pref -> takes effect on the next Helium start.
#
# If Helium is running, the script waits in the background until it is closed: Helium writes its prefs
# itself on exit and would overwrite a file changed before.
#
# Base color = color5 (like Hyprland's active border), variant "Neutral" (2), so Chromium
# does not turn it into a strong orange.

PROFILE_ROOT="$HOME/.config/net.imput.helium"
[ -d "$PROFILE_ROOT" ] || exit 0

write_prefs() {
    . "$HOME/.cache/wal/colors.sh"   # only read now: the newest wallpaper wins
    python3 - "$PROFILE_ROOT" "$color5" <<'EOF'
import glob, json, os, sys
root, hexcolor = sys.argv[1], sys.argv[2].lstrip("#")
argb = 0xFF000000 | int(hexcolor, 16)
signed = argb - (1 << 32)            # Chromium stores SkColor as int32
for path in glob.glob(os.path.join(root, "*", "Preferences")):
    with open(path) as f:
        prefs = json.load(f)
    theme = prefs.setdefault("browser", {}).setdefault("theme", {})
    theme["user_color2"] = signed
    theme["color_variant2"] = 2      # Neutral
    tmp = path + ".wal-tmp"
    with open(tmp, "w") as f:
        json.dump(prefs, f, separators=(",", ":"))
    os.replace(tmp, path)
EOF
}

if ! pgrep -x helium >/dev/null; then
    write_prefs
    exit 0
fi

# Helium is running: one single waiter in the background (further wallpaper changes need no
# second one - it only reads the colors when writing)
LOCK="${XDG_RUNTIME_DIR:-/tmp}/helium-wal-accent.lock"
(
    flock -n 9 || exit 0
    while pgrep -x helium >/dev/null; do sleep 3; done
    sleep 1   # Helium is gone, the prefs are written
    write_prefs
) 9>"$LOCK" </dev/null >/dev/null 2>&1 &
disown
exit 0
