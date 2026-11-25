#!/bin/bash
# Imports the given WireGuard .conf files (from any provider; chosen in the VPN picker) as NetworkManager
# connections "vpn-<country>[-N]", or "vpn-<file name>" when the file name names no country.
# Usage: import_vpn_file.sh <file.conf>...  - runs without sudo (nmcli import as a normal user).
#
# The country is the first two-letter part of the file name that is a country code ("wg" is skipped):
#   NL#12.conf, wg-NL-FREE-12.conf, se-got-wg-001.conf  ->  vpn-nl, vpn-nl-2, vpn-se
#   home.conf, Office Berlin.conf                       ->  vpn-home, vpn-office-berl
# NetworkManager names the interface after the connection, so a name has at most 15 characters.
# Older imports are called "proton-<country>"; the shell reads both (services/VpnPickerState.codeOf).
set -u

# ISO 3166-1 alpha-2 plus "xk" (Kosovo) and "uk" (stored as "gb"); the same list as VpnPickerState.isoCodes
ISO=" ad ae af ag ai al am ao aq ar as at au aw ax az ba bb bd be bf bg bh bi bj bl bm bn bo bq br bs bt bv bw by bz
 ca cc cd cf cg ch ci ck cl cm cn co cr cu cv cw cx cy cz de dj dk dm do dz ec ee eg eh er es et fi fj fk fm fo
 fr ga gb gd ge gf gg gh gi gl gm gn gp gq gr gs gt gu gw gy hk hm hn hr ht hu id ie il im in io iq ir is it je
 jm jo jp ke kg kh ki km kn kp kr kw ky kz la lb lc li lk lr ls lt lu lv ly ma mc md me mf mg mh mk ml mm mn mo
 mp mq mr ms mt mu mv mw mx my mz na nc ne nf ng ni nl no np nr nu nz om pa pe pf pg ph pk pl pm pn pr ps pt pw
 py qa re ro rs ru rw sa sb sc sd se sg sh si sj sk sl sm sn so sr ss st sv sx sy sz tc td tf tg th tj tk tl tm
 tn to tr tt tv tw tz ua ug uk um us uy uz va vc ve vg vi vn vu wf ws xk ye yt za zm zw "
# One line, so that every code stands between two spaces
ISO=" $(tr -s ' \n' ' ' <<<"$ISO") "
# Longest name of a network interface
MAX=15
# The tunnel's own packets carry this mark, so the killswitch (system/vpn-killswitch.nft) lets them through
# whatever port the server uses. 51820 is the value wg-quick uses too.
FWMARK=51820
# Installed killswitch rules (only read, to warn about an old version)
RULES="${VPN_KILLSWITCH_RULES:-/etc/vpn-killswitch.nft}"

notify() { # $1 = title, $2 = text, $3 = "ok" -> success (Quickshell fires a sparkle)
    command -v notify-send >/dev/null 2>&1 && notify-send -a "VPN" ${3:+-h "string:x-qs-success:1"} "$1" "${2:-}"
    return 0
}

# File name in lowercase without ".conf"
stem() {
    local base
    base=$(basename "$1")
    echo "${base%.[cC][oO][nN][fF]}" | tr 'A-Z' 'a-z'
}

# Country code from the file name: the first two-letter part that is a country; empty if there is none
country_code() {
    local tok
    for tok in $(stem "$1" | tr -c 'a-z' ' '); do
        [ "${#tok}" -eq 2 ] && [ "$tok" != "wg" ] || continue
        case "$ISO" in
            *" $tok "*)
                [ "$tok" = "uk" ] && tok="gb"
                echo "$tok"
                return
                ;;
        esac
    done
}

# File name as part of a connection name: letters and digits, everything else becomes one dash
slug() {
    local s
    s=$(stem "$1" | tr -c 'a-z0-9\n' '-' | tr -s '-')
    s="${s#-}"
    s="${s%-}"
    s="${s#wg-}"
    echo "${s:-new}"
}

# "<base><suffix>", the base cut so that the whole name fits an interface name
fit() {
    local base="$1" suffix="$2"
    base="${base:0:$((MAX - ${#suffix}))}"
    echo "${base%-}$suffix"
}

[ "$#" -gt 0 ] || exit 0
files=$(printf '%s\n' "$@")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

existing=$(nmcli -g NAME connection show)
ok=0
fail=0
last_err=""

while IFS= read -r f; do
    [ -n "$f" ] || continue

    cc=$(country_code "$f")
    if [ -n "$cc" ]; then
        base="vpn-$cc"
    else
        base="vpn-$(slug "$f")"
    fi
    name=$(fit "$base" "")
    n=2
    while grep -qxF "$name" <<<"$existing"; do
        name=$(fit "$base" "-$n")
        n=$((n + 1))
    done

    # NetworkManager names the connection + interface after the file name
    cp -- "$f" "$tmp/$name.conf"
    if err=$(nmcli connection import type wireguard file "$tmp/$name.conf" 2>&1); then
        nmcli connection modify "$name" connection.autoconnect no >/dev/null 2>&1
        # A mark from the file itself (FwMark = ...) stays
        mark=$(nmcli -g wireguard.fwmark connection show "$name" 2>/dev/null)
        case "$mark" in
            "" | 0 | 0x0) nmcli connection modify "$name" wireguard.fwmark "$FWMARK" >/dev/null 2>&1 ;;
        esac
        existing+=$'\n'"$name"
        ok=$((ok + 1))
    else
        fail=$((fail + 1))
        last_err="$(basename "$f"): $err"
    fi
    rm -f "$tmp/$name.conf"
done <<<"$files"

if [ "$fail" -gt 0 ]; then
    notify "VPN import: $ok ok, $fail failed" "$last_err"
elif [ "$ok" -gt 0 ]; then
    notify "VPN import" "$ok connection(s) imported" ok
fi
# Killswitch rules from before 2026-11-25 only let interfaces called "proton*" through
if [ "$ok" -gt 0 ] && [ -r "$RULES" ] && ! grep -q 'oifkind' "$RULES"; then
    notify "VPN killswitch is outdated" "With the killswitch on, the new connections stay blocked. Update it: sudo $(dirname "$(readlink -f "$0")")/install-killswitch.sh"
fi
exit 0
