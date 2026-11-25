#!/bin/bash
# Installs the VPN killswitch from ../system to /etc (the original lives in the Quickshell folder,
# so it comes with the repo; but root services should not read from the home folder):
#   /etc/vpn-killswitch.nft                     rules (loaded by the VPN dropdown and the boot service)
#   /usr/local/bin/vpn-killswitch               on|off|status for the terminal
#   /etc/systemd/system/vpn-killswitch.service  killswitch already at boot
#   /etc/sudoers.d/quickshell-nft               nft without a password (VPN dropdown)
# Run with: sudo ./install-killswitch.sh   (after changes in system/ simply again)
set -eu
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi
user="${SUDO_USER:-}"
if [ -z "$user" ] || [ "$user" = root ]; then
    echo "Please start as your normal user via sudo (the sudo rule needs the username)" >&2
    exit 1
fi
if ! command -v nft >/dev/null; then
    echo "nft missing: sudo pacman -S nftables" >&2
    exit 1
fi
src="$(dirname "$(readlink -f "$0")")/../system"

install -Dm644 "$src/vpn-killswitch.nft" /etc/vpn-killswitch.nft
install -Dm755 "$src/vpn-killswitch" /usr/local/bin/vpn-killswitch
install -Dm644 "$src/vpn-killswitch.service" /etc/systemd/system/vpn-killswitch.service
echo "Files installed"

# Check the sudo rule first, then install it (a broken sudoers file locks sudo out completely)
# Allow exactly the nft calls Quickshell needs:
# a free "nft" could be abused as root (e.g. "nft -f <any file>" reads other files)
tmp=$(mktemp)
nft="$(command -v nft)"
echo "$user ALL=(root) NOPASSWD: $nft list tables, $nft list table inet killswitch, $nft delete table inet killswitch, $nft -f /etc/vpn-killswitch.nft" > "$tmp"
if visudo -cqf "$tmp"; then
    install -Dm440 "$tmp" /etc/sudoers.d/quickshell-nft
    # An older variant stored the free rule under this name
    rm -f /etc/sudoers.d/vpn-killswitch
    echo "sudo rule for nft installed"
else
    echo "sudo rule invalid, not installed" >&2
fi
rm -f "$tmp"

systemctl daemon-reload
if systemctl is-enabled -q vpn-killswitch.service; then
    echo "Killswitch at boot is already active"
else
    # install.sh asks this itself and passes the answer; run by hand, the question comes here
    case "${1:-}" in
        --boot) answer=y ;;
        --no-boot) answer=n ;;
        *) read -rp "Enable the killswitch at boot? Without VPN there is no internet then. [y/N] " answer ;;
    esac
    if [[ "$answer" == [jJyY]* ]]; then
        systemctl enable vpn-killswitch.service
    fi
fi
echo "Done. Toggle it in the VPN dropdown or with: vpn-killswitch on|off|status"
