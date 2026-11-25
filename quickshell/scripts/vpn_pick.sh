#!/bin/bash
# Yazi file picker for the existing WireGuard import.
set -euo pipefail

notify() {
    notify-send -a VPN "VPN import" "$1" 2>/dev/null || true
}

for tool in kitty yazi; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        notify "$tool is not installed"
        exit 1
    fi
done

selection=$(mktemp)
trap 'rm -f -- "$selection"' EXIT
start=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
[[ -d "$start" ]] || start="$HOME/Downloads"
if [[ ! -d "$start" ]]; then
    notify "Downloads folder not found"
    exit 1
fi

# Without --detach: read the selection only after Yazi is closed.
if ! kitty --class fzfwindows --name fzfwindows yazi --chooser-file="$selection" "$start"; then
    exit 0
fi

files=()
while IFS= read -r file || [[ -n "$file" ]]; do
    [[ -n "$file" ]] || continue
    if [[ -f "$file" && "${file,,}" == *.conf ]]; then
        files+=("$file")
    else
        notify "Please select WireGuard .conf files only"
        exit 1
    fi
done < "$selection"

((${#files[@]})) || exit 0
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$script_dir/import_vpn_file.sh" "${files[@]}"
