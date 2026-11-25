#!/bin/bash
# Telegram theme from the wal colors: walogram builds ~/.cache/walogram/wal.tdesktop-theme (with the
# wallpaper blurred as the chat background), then its gaps are filled and a
# running Telegram is restarted.
#
# Select it once in Telegram: Settings > Chat Settings > "Choose from file" >
# ~/.cache/walogram/wal.tdesktop-theme. Telegram remembers the path and reads the file again on every
# start (tested) - it cannot reload live, hence the restart.
#
# Gaps: walogram (1.3.0) creates no color6 and no *_ff variants, but its template refers
# to them (historyPeer6*, callBg). Telegram skips such values -> default colors.
# Every reference the file does not resolve is added here with walogram's own formulas.
#
#   gen-telegram-theme.sh [--no-restart]
set -u
export MAGICK_MEMORY_LIMIT=256MiB MAGICK_MAP_LIMIT=256MiB
export MAGICK_DISK_LIMIT=512MiB MAGICK_THREAD_LIMIT=2 MAGICK_TIME_LIMIT=60

THEME="$HOME/.cache/walogram/wal.tdesktop-theme"
command -v walogram >/dev/null || exit 0
# Older wal caches may still point to a GIF. Only use its first frame.
telegram_wall=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/wal/wal" 2>/dev/null || true)
case "${telegram_wall,,}" in
    *.gif)
        still_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallpaper-stills"
        mkdir -p "$still_dir"
        still_key=$(printf '%s' "$telegram_wall" | sha256sum | cut -d ' ' -f 1)
        still="$still_dir/$still_key.small.png"
        if [ ! -s "$still" ] || [ "$telegram_wall" -nt "$still" ]; then
            ffmpeg -nostdin -v error -filter_threads 2 -threads 2 -i "$telegram_wall" \
                -vf "scale=640:640:force_original_aspect_ratio=decrease" -frames:v 1 -threads 2 -update 1 -y "$still" || exit 1
        fi
        telegram_wall="$still"
        ;;
esac
walogram -B -i "$telegram_wall" >/dev/null 2>&1 || { echo "walogram failed" >&2; exit 1; }
[ -f "$THEME" ] || exit 1

python3 -I - "$THEME" "$HOME/.cache/wal/colors.json" <<'EOF'
import json, re, sys, zipfile, os
theme, colors = sys.argv[1], json.load(open(sys.argv[2]))
wal = colors["colors"]
NAME = "colors.tdesktop-theme"

files = None
if zipfile.is_zipfile(theme):
    with zipfile.ZipFile(theme) as z:
        files = {n: z.read(n) for n in z.namelist()}
if files and NAME in files:
    text = files[NAME].decode()
else:  # without the zip command walogram writes the colors directly, without an archive
    files, text = None, open(theme).read()

body = re.sub(r"//.*", "", text)
defs = dict(re.findall(r"^\s*([A-Za-z0-9_]+)\s*:\s*([^;]+);", body, re.M))

def rgb(h): return [int(h[i:i + 2], 16) for i in (1, 3, 5)]
def hexc(t): return "#" + "".join(f"{max(0, min(255, x)):02x}" for x in t)
def resolve(key):
    """Value for a missing walogram name, formulas as in /usr/bin/walogram."""
    m = re.fullmatch(r"color(\d+)", key)
    if m:
        return wal.get(f"color{m.group(1)}")
    m = re.fullmatch(r"colorAlpha(\d+)_([0-9a-f]{2})", key)
    if m and f"color{m.group(1)}" in wal:
        return wal[f"color{m.group(1)}"] + m.group(2)
    m = re.fullmatch(r"color(Lighter|Darker)(\d+)_(\d+)", key)
    if m and f"color{m.group(2)}" in wal:
        d, c = int(m.group(3)), rgb(wal[f"color{m.group(2)}"])
        sign = 1 if m.group(1) == "Lighter" else -1
        return hexc([x + sign * (x * (d // 10) // 10) for x in c])
    return None

missing = sorted({v.strip() for v in defs.values()
                  if not v.strip().startswith("#") and v.strip() not in defs})
add = {k: resolve(k) for k in missing}
add = {k: v for k, v in add.items() if v}
if not add:
    sys.exit(0)
# Definitions to the front: Telegram only resolves references to names already defined
head = "// added by ~/.config/wal/telegram/gen-telegram-theme.sh (missing in walogram)\n"
head += "".join(f"{k}: {v};\n" for k, v in add.items()) + "\n"
text = head + text
if files is None:
    open(theme, "w").write(text)
else:
    files[NAME] = text.encode()
    tmp = theme + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for n, data in files.items():
            z.writestr(n, data)
    os.replace(tmp, theme)
EOF

# Restart a running Telegram, on its previous workspace and without jumping there
[ "${1:-}" = "--no-restart" ] && exit 0
pgrep -x Telegram >/dev/null || exit 0
ws=$(hyprctl clients -j 2>/dev/null | jq -r '[.[] | select(.class == "org.telegram.desktop")][0].workspace.name // empty')
pkill -x Telegram
for _ in $(seq 50); do pgrep -x Telegram >/dev/null || break; sleep 0.2; done
if [ -n "$ws" ]; then
    hyprctl dispatch "hl.dsp.exec_cmd('Telegram', { workspace = '$ws silent' })" >/dev/null
else
    setsid -f Telegram >/dev/null 2>&1
fi
exit 0
