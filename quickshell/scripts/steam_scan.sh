#!/usr/bin/env bash
# Lists installed Steam games and their icons, one line per entry:
#   T|<appid>|<name>     title from the appmanifest_*.acf
#   I|<appid>|<path>     best available image from the librarycache
# Considers ALL Steam libraries (libraryfolders.vdf), not just the
# default library, as well as Flatpak Steam.

roots=()
for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  [ -d "$r/steamapps" ] && roots+=("$(readlink -f "$r")")
done
[ ${#roots[@]} -eq 0 ] && exit 0
mapfile -t roots < <(printf '%s\n' "${roots[@]}" | sort -u)

libs=()
for r in "${roots[@]}"; do
  libs+=("$r/steamapps")
  vdf="$r/steamapps/libraryfolders.vdf"
  if [ -f "$vdf" ]; then
    while IFS= read -r p; do
      [ -d "$p/steamapps" ] && libs+=("$(readlink -f "$p")/steamapps")
    done < <(awk -F'"' '/"path"/{print $4}' "$vdf")
  fi
done
mapfile -t libs < <(printf '%s\n' "${libs[@]}" | sort -u)

# ---- Titel ----
for l in "${libs[@]}"; do
  for f in "$l"/appmanifest_*.acf; do
    [ -f "$f" ] || continue
    awk -F'"' '/^\t"appid"/{a=$4} /^\t"name"/{n=$4} END{ if (a != "" && n != "") print "T|" a "|" n }' "$f"
  done
done

# ---- Icons ----
for r in "${roots[@]}"; do
  cache="$r/appcache/librarycache"
  [ -d "$cache" ] || continue
  for d in "$cache"/*/; do
    id=$(basename "$d")
    case "$id" in '' | *[!0-9]*) continue ;; esac
    # 1) small client icon (hash file name .jpg)
    icon=$(find "$d" -maxdepth 2 -type f -name '*.jpg' \
      ! -name 'header*' ! -name 'library_*' ! -name 'logo*' ! -name 'icon*' 2>/dev/null | head -1)
    # 2) portrait cover
    [ -z "$icon" ] && icon=$(find "$d" -maxdepth 2 -type f -name 'library_600x900*.jpg' 2>/dev/null | head -1)
    # 3) header image
    [ -z "$icon" ] && icon=$(find "$d" -maxdepth 2 -type f -name 'header*.jpg' 2>/dev/null | head -1)
    [ -n "$icon" ] && echo "I|$id|$icon"
  done
done
