#!/usr/bin/env bash
# shiori-shell installer (Arch Linux)
#
#   ./install.sh            install everything, link the configs into ~/.config, set up the lock screen
#   ./install.sh --check    only report what is missing, change nothing
#   ./install.sh --uninstall  undo what the installer set up (asks before removing any data)
#
# Options:
#   --check          report missing programs, links and files, then exit
#   --uninstall      remove the links, restore the old configs, remove the lock screen file
#                    (and the killswitch); caches, your settings and packages only on request
#   --no-packages    skip all package installation (only link configs and set up files)
#   --dry-run        print what would be done without doing it
#   -y, --yes        accept the default answer for every question
#   -v, --verbose    show the full output of pacman, the AUR helper and git instead of a spinner
#   -h, --help       show this help
#
# Everything the shell uses is installed without asking (parts you do not use can be switched off in
# the shell: settings window, page "Bar & Features"). Only asked: Zen Browser and the VPN killswitch.
# Packages are installed together with a full system update (pacman -Syu), as Arch expects.
# Safe to run again: packages use --needed, links that already point here are kept,
# and anything that has to be replaced in ~/.config is moved to a backup folder first.

set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
BACKUP="$HOME/.config-backup-shiori-$(date +%Y-%m-%d-%H%M%S)"

MIN_HYPRLAND="0.57.1"
MIN_QUICKSHELL="0.3.2"

CHECK=0 NO_PACKAGES=0 DRY_RUN=0 YES=0 UNINSTALL=0 VERBOSE=0

# ─────────────────────────────── output ───────────────────────────────

# Colors are the terminal's own palette (with pywal they already match the wallpaper)
TTY=0
[ -t 1 ] && TTY=1
if [ "$TTY" = 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    bold=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m'
    blue=$'\e[34m' magenta=$'\e[35m' cyan=$'\e[36m' reset=$'\e[0m'
else
    bold='' dim='' red='' green='' yellow='' blue='' magenta='' cyan='' reset=''
fi

COLS=80
if [ "$TTY" = 1 ]; then COLS="$(tput cols 2>/dev/null || echo 80)"; fi
[[ "$COLS" =~ ^[0-9]+$ ]] || COLS=80
if [ "$COLS" -gt 80 ]; then COLS=80; fi
if [ "$COLS" -lt 40 ]; then COLS=40; fi

# Symbols in three levels: a terminal emulator with a full font, the bare Linux console (where a fresh
# install usually runs; its font only has the old PC characters), and plain ASCII without UTF-8
if [[ "$(locale charmap 2>/dev/null)" != UTF-8 ]]; then
    G_OK='+' G_ERR='x' G_STEP='*' G_BAR='|' G_RULE='-' G_ARROW='>' G_DOT='-' G_ELL='..'
    SPIN=('|' '/' '-' '\') ART=0
elif [ "${TERM:-}" = linux ]; then
    G_OK='√' G_ERR='x' G_STEP='■' G_BAR='│' G_RULE='─' G_ARROW='»' G_DOT='·' G_ELL='..'
    SPIN=('|' '/' '-' '\') ART=1
else
    G_OK='✓' G_ERR='✗' G_STEP='◆' G_BAR='│' G_RULE='─' G_ARROW='→' G_DOT='·' G_ELL='…'
    SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') ART=1
fi

LOG=/dev/null        # full output of the long steps (set in main)
WARNINGS=()          # repeated in the summary, where they do not scroll away
STEP_N=0 STEP_TOTAL=0
SPIN_PID='' KEEPALIVE_PID='' SUDO_READY=0

# step "Title" ["text on the right"]: without the text, the step counter stands there
step() {
    STEP_N=$((STEP_N + 1))
    local title="$1" right="${2:-}" n rule
    if [ -z "$right" ] && [ "$STEP_TOTAL" -gt 0 ]; then right="$STEP_N/$STEP_TOTAL"; fi
    n=$((COLS - 6 - ${#title} - ${#right}))
    if [ "$n" -lt 3 ]; then n=3; fi
    printf -v rule '%*s' "$n" ''
    rule="${rule// /$G_RULE}"
    printf '\n  %s%s%s %s%s%s %s%s %s%s\n' "$magenta" "$G_STEP" "$reset" "$bold" "$title" "$reset" \
        "$dim" "$rule" "$right" "$reset"
}
line() { printf '  %s%s%s %s\n' "$dim" "$G_BAR" "$reset" "$1"; }
info() { line "$1"; }
note() { line "${dim}$1${reset}"; }
ok()   { line "${green}${G_OK}${reset} $1"; }
bad()  { line "${red}${G_ERR}${reset} $1"; }
warn() { line "${yellow}!${reset} $1"; WARNINGS+=("$1"); }
fail() { spin_stop; printf '\n  %s%s error:%s %s\n' "$red" "$G_ERR" "$reset" "$1" >&2; exit 1; }

# Long text (package lists) folded to the width, dimmed
wrap() {
    local l
    while IFS= read -r l; do note "$l"; done < <(printf '%s\n' "$1" | fold -s -w "$((COLS - 6))")
}

# grid MARK item...: short items in columns instead of one line each
grid() {
    local mark="$1"; shift
    [ $# -gt 0 ] || return 0
    local it w=0 per i=0 row='' cell
    for it in "$@"; do if [ "${#it}" -gt "$w" ]; then w=${#it}; fi; done
    per=$(((COLS - 4) / (w + 4)))
    if [ "$per" -lt 1 ]; then per=1; fi
    for it in "$@"; do
        printf -v cell '%s %-*s  ' "$mark" "$w" "$it"
        row+="$cell"
        i=$((i + 1))
        if [ $((i % per)) = 0 ]; then line "$row"; row=''; fi
    done
    if [ -n "$row" ]; then line "$row"; fi
}

tilde() {
    case "$1" in
        "$HOME"*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

duration() {
    if [ "$1" -ge 60 ]; then printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi
}

# Spinner on one line: label, time, and the newest line of the log so a long pacman run shows life
spin_start() {
    local label="$1"
    # a label longer than the line would wrap and break the redraw
    if [ "${#label}" -gt $((COLS - 16)) ]; then label="${label:0:$((COLS - 18))}$G_ELL"; fi
    printf '\e[?25l'
    (
        set +eE
        trap - ERR
        trap 'exit 0' TERM INT
        # only what this step wrote: the log also holds the output of the steps before
        i=0 start=$SECONDS last='' from=$(($(stat -c %s "$LOG" 2>/dev/null || echo 0) + 1))
        while :; do
            if [ $((i % 5)) = 0 ]; then
                last="$(tail -c "+$from" "$LOG" 2>/dev/null | tail -c 600 | tr '\r' '\n' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' |
                    tr -cd '[:print:]\n' | grep -v -e '^[[:space:]]*$' -e '^\$ ' | tail -n 1)"
                last="${last#"${last%%[![:space:]]*}"}"
            fi
            t=$((SECONDS - start))
            printf -v el '%d:%02d' $((t / 60)) $((t % 60))
            room=$((COLS - 12 - ${#label} - ${#el}))
            shown="$last"
            if [ "$room" -lt 10 ]; then
                shown=''
            elif [ "${#shown}" -gt "$room" ]; then
                shown="${shown:0:$((room - 2))}$G_ELL"
            fi
            printf '\r\e[K  %s%s%s %s%s%s %s  %s%s  %s%s' "$dim" "$G_BAR" "$reset" \
                "$magenta" "${SPIN[$((i % ${#SPIN[@]}))]}" "$reset" "$label" "$dim" "$el" "$shown" "$reset"
            i=$((i + 1))
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
}
spin_stop() {
    [ -n "$SPIN_PID" ] || return 0
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true
    SPIN_PID=''
    printf '\r\e[K\e[?25h'
}

# What --dry-run prints instead of running a command, with short paths (./ = this repo)
dry() {
    local c="$*"
    c="${c//"$REPO"\//./}"
    c="${c//"$HOME"\//\~/}"
    wrap "[dry-run] $c"
}

# Run a short command, or only print it with --dry-run
run() {
    if [ "$DRY_RUN" = 1 ]; then
        dry "$@"
    else
        "$@"
    fi
}

# Like run, but the command's output goes to the log instead of the screen
quiet() {
    if [ "$DRY_RUN" = 1 ]; then
        dry "$@"
        return 0
    fi
    printf '\n$ %s\n' "$*" >>"$LOG"
    "$@" >>"$LOG" 2>&1
}

# task "Doing it" "Done text" command...: a long step. With a terminal it runs behind a spinner and its
# output goes to the log (the last lines are shown when it fails); with --verbose or without a
# terminal the output is printed as it comes. Returns the command's exit status, never ends the script.
task() {
    local label="$1" done_label="$2"; shift 2
    if [ "$DRY_RUN" = 1 ]; then
        dry "$@"
        return 0
    fi
    local start=$SECONDS rc=0 took t='' l from
    printf '\n$ %s\n' "$*" >>"$LOG"
    from=$(($(stat -c %s "$LOG" 2>/dev/null || echo 0) + 1))
    if [ "$TTY" = 1 ] && [ "$VERBOSE" = 0 ]; then
        # ask for the sudo password (if it is needed again) before the spinner covers the prompt
        if [ "$1" = sudo ]; then sudo -v -p "$SUDO_PROMPT" || true; fi
        spin_start "$label"
        "$@" >>"$LOG" 2>&1 || rc=$?
        spin_stop
    else
        info "$label"
        "$@" 2>&1 | tee -a "$LOG" || rc=$?
    fi
    took=$((SECONDS - start))
    if [ "$took" -ge 5 ]; then t="  ${dim}$(duration "$took")${reset}"; fi
    if [ "$rc" = 0 ]; then
        ok "$done_label$t"
        return 0
    fi
    bad "$label: failed (exit $rc)$t"
    if [ "$TTY" = 1 ] && [ "$VERBOSE" = 0 ]; then
        while IFS= read -r l; do note "  ${l:0:$((COLS - 8))}"; done < <(tail -c "+$from" "$LOG" | tail -n 40 | tr '\r' '\n' |
            sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -v -e '^[[:space:]]*$' -e '^\$ ' | tail -n 8)
        note "  full output: $LOG"
    fi
    return "$rc"
}

# ask "Question" y|n  ->  returns 0 for yes. With --yes the default is taken.
ask() {
    local prompt="$1" default="$2" hint reply
    [ "$default" = y ] && hint="[Y/n]" || hint="[y/N]"
    printf '  %s%s%s %s?%s %s %s%s%s ' "$dim" "$G_BAR" "$reset" "$cyan" "$reset" "$prompt" "$dim" "$hint" "$reset"
    if [ "$YES" = 1 ] || [ ! -t 0 ]; then
        reply="$default"
        printf '%s\n' "$reply"
    else
        read -r reply || reply=""
        reply="${reply:-$default}"
    fi
    [[ "$reply" =~ ^[Yy] ]]
}

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

banner() {
    local rev
    rev="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)"
    echo
    if [ "$ART" = 1 ]; then
        printf '%s' "$magenta"; echo '    ███████╗██╗  ██╗██╗ ██████╗ ██████╗ ██╗'
        printf '%s' "$magenta"; echo '    ██╔════╝██║  ██║██║██╔═══██╗██╔══██╗██║'
        printf '%s' "$blue";    echo '    ███████╗███████║██║██║   ██║██████╔╝██║'
        printf '%s' "$blue";    echo '    ╚════██║██╔══██║██║██║   ██║██╔══██╗██║'
        printf '%s' "$cyan";    echo '    ███████║██║  ██║██║╚██████╔╝██║  ██║██║'
        printf '%s' "$cyan";    echo '    ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝'
        printf '%s\n' "$reset"
    else
        printf '    %sshiori-shell%s\n\n' "$bold" "$reset"
    fi
    printf '    %sshell %s %s%s%s\n' "$bold" "$G_DOT" "$1" "$reset" "${rev:+  ${dim}$rev${reset}}"
    printf '    %s%s%s\n' "$dim" "$(tilde "$REPO")" "$reset"
}

# One sudo password for the whole run: refresh the timestamp in the background until the script ends
sudo_keepalive() {
    if [ "$DRY_RUN" = 1 ] || [ "$SUDO_READY" = 1 ]; then return 0; fi
    note "Some steps need sudo (packages, lock screen, services). Your password, once:"
    sudo -v -p "$SUDO_PROMPT" || fail "sudo is needed"
    SUDO_READY=1
    (
        set +eE
        trap - ERR
        while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done
    ) >/dev/null 2>&1 &
    KEEPALIVE_PID=$!
}
SUDO_PROMPT="  $G_BAR password for %u: "

# The script never ends silently: an unexpected failing command is named with its line
on_error() {
    local rc="$1"
    [ "$BASHPID" = "$$" ] || exit "$rc"
    spin_stop
    printf '\n  %s%s error:%s line %s: %s (exit %s)\n' "$red" "$G_ERR" "$reset" "$2" "$3" "$rc" >&2
    if [ -f "$LOG" ]; then printf '  %sfull output: %s%s\n' "$dim" "$LOG" "$reset" >&2; fi
    exit "$rc"
}
cleanup() {
    spin_stop
    if [ -n "$KEEPALIVE_PID" ]; then kill "$KEEPALIVE_PID" 2>/dev/null || true; fi
    return 0
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'spin_stop; printf "\n  %s\n" "aborted"; exit 130' INT TERM

# ─────────────────────────────── what gets installed ───────────────────────────────

# Configs in this repo that are linked to ~/.config/<name>
CONFIGS=(
    hypr quickshell wal kitty
    nvim tmux yazi fastfetch starship.toml
    mpd rmpc swayimg
    xdg-desktop-portal xdg-desktop-portal-termfilechooser
)

# Everything the shell uses, installed without asking. Parts you do not use can be switched off in the shell.
PACKAGES=(
    # compositor, shell, colors, screenshots, clipboard, fonts
    hyprland hypridle hyprpolkitagent hyprsunset
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    quickshell qt6-multimedia qt6-multimedia-ffmpeg qt6-imageformats qt6-svg qt6-5compat qt6ct
    pipewire pipewire-pulse wireplumber
    python awww jq
    networkmanager wl-clipboard cliphist grim slurp satty swayimg
    ffmpeg imagemagick libnotify playerctl
    kitty git curl xdg-user-dirs xdg-utils
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji
    # terminal tools: Neovim (+ build tools for treesitter), tmux, yazi (also the file picker), fastfetch,
    # the starship prompt
    neovim tmux yazi fd ripgrep fzf unzip make gcc tree-sitter-cli ffmpegthumbnailer chafa fastfetch starship
    # music: MPD, rmpc, the cava visualizer, mpd-mpris (MPD in the audio dropdown)
    mpd mpc mpd-mpris rmpc cava
    # input method (Japanese, Chinese, Korean ...)
    fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt
    # video tools and language tool: playback, downloads, HandBrake (compress), uv (its Python packages)
    mpv yt-dlp handbrake-cli uv
    # bluetooth, laptop battery, sync and encrypted folders
    bluez bluez-utils upower rclone gocryptfs
)

# From the AUR (paru is set up when there is no AUR helper):
# pywal16 = pywal, which was dropped from the official repos (an installed python-pywal counts as well);
# termfilechooser = file picker in yazi instead of the GTK dialog
AUR_PACKAGES=(python-pywal16 xdg-desktop-portal-termfilechooser)


# For --check: command|what it is for|required (1) or optional (0)
PROGRAMS=(
    "Hyprland|compositor|1" "qs|Quickshell|1" "wal|colors from the wallpaper|1" "awww|wallpaper|1"
    "starship|prompt|0" "jq|scripts|1" "python3|scripts|1" "nmcli|network icon|1" "wl-paste|clipboard|1" "cliphist|clipboard|1"
    "grim|screenshots|1" "slurp|screenshots|1" "ffmpeg|thumbnails, video editor|1" "magick|images|1"
    "notify-send|notifications from scripts|1" "kitty|terminal|1" "hypridle|automatic lock|1"
    "nvim|editor|0" "tmux|terminal multiplexer|0" "yazi|file manager|0"
    "mpd|music|0" "mpc|music|0" "rmpc|music player|0" "cava|audio visualizer|0"
    "fcitx5|input method|0" "mpv|video playback|0" "yt-dlp|downloads|0" "HandBrakeCLI|video compression|0"
    "uv|language tool Python packages|0" "bluetoothctl|bluetooth|0" "upower|battery|0"
    "rclone|sync|0" "gocryptfs|encrypted vault|0" "nft|VPN killswitch|0"
    "linux-wallpaperengine|Wallpaper Engine backgrounds|0" "claude|Claude usage icon|0"
    "codex|Codex usage icon|0" "openrgb|RGB colors from the wallpaper|0" "hyprsunset|night light|0"
)

# ─────────────────────────────── helpers ───────────────────────────────

has() { command -v "$1" >/dev/null 2>&1; }

# Both helpers print "" when nothing is found but still succeed: with set -e a failing
# $(...) assignment ended the whole script silently (fresh Arch without paru/yay)
aur_helper() {
    local h
    for h in paru yay; do has "$h" && { echo "$h"; return 0; }; done
    return 0
}

# Installed version of the first package that exists (e.g. quickshell or quickshell-git)
pkg_version() {
    local p
    for p in "$@"; do
        if pacman -Q "$p" >/dev/null 2>&1; then
            pacman -Q "$p" | awk '{print $2}'
            return 0
        fi
    done
    return 0
}

# Packages that are not satisfied yet. pacman -T also counts "provides", so quickshell-git
# counts as quickshell and is not replaced.
missing_packages() {
    pacman -T "$@" 2>/dev/null || true
}

# ─────────────────────────────── steps ───────────────────────────────

check_system() {
    step "System"
    if [ ! -f /etc/arch-release ] && ! grep -qs '^ID_LIKE=.*arch' /etc/os-release; then
        fail "this installer supports Arch Linux only for now. Use --no-packages to only link the configs."
    fi
    has pacman || fail "pacman not found"
    ok "Arch Linux"
}

# paru from the AUR (prebuilt paru-bin), the usual way by hand: clone, makepkg, pacman -U.
# The AUR is sometimes briefly unreachable ("fatal: unable to access"): a few tries
fetch_paru() {
    local try
    for try in 1 2 3; do
        git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$1" && return 0
        rm -rf "$1"
        if [ "$try" != 3 ]; then echo "the AUR did not answer, trying again in 5 s"; sleep 5; fi
    done
    return 1
}
# Not "makepkg -i": makepkg installs with "sudo -k", which throws away the password entered at the
# start and asks again (behind the spinner nobody sees that). So build only and install the result here.
build_paru() {
    (
        cd "$1" || exit 1
        makepkg --noconfirm || exit 1
        files=()
        while IFS= read -r f; do
            if [ -f "$f" ]; then files+=("$f"); fi
        done < <(makepkg --packagelist)
        [ "${#files[@]}" -gt 0 ] || exit 1
        sudo pacman -U --needed --noconfirm "${files[@]}"
    )
}

setup_paru() {
    local tmp
    tmp="$(mktemp -d)"
    if ! task "Fetching paru from the AUR" "paru fetched" fetch_paru "$tmp/paru-bin"; then
        warn "the AUR could not be reached, paru skipped (run ./install.sh again later)"
    else
        task "Building paru" "paru installed" build_paru "$tmp/paru-bin" || warn "paru could not be built"
    fi
    rm -rf "$tmp"
}

# AUR packages without questions: the defaults (provider, clean build), no PKGBUILD review pager
aur_cmd() {
    local helper="$1"; shift
    local try args=(-S --needed --noconfirm)
    if [ "$helper" = paru ]; then args+=(--skipreview); else args+=(--answerdiff None --answerclean None); fi
    for try in 1 2; do
        "$helper" "${args[@]}" "$@" && return 0
        if [ "$try" = 1 ]; then echo "AUR install failed, trying once more"; sleep 5; fi
    done
    return 1
}

# AUR failures (server briefly down, a package that does not build) must not end the whole installer
aur_install() {
    local helper="$1"; shift
    task "Building from the AUR: $*" "$* (AUR)" aur_cmd "$helper" "$@" && return 0
    warn "could not install from the AUR: $*  (run ./install.sh again later)"
    return 1
}

install_packages() {
    step "Packages"
    wrap "Hyprland, Quickshell, pywal, terminal tools, music, input method, video and language tools, bluetooth, battery and sync. Parts you do not use can be switched off in the shell."
    sudo_keepalive

    local helper wanted=("${PACKAGES[@]}") aur_wanted=() p
    helper="$(aur_helper)"
    # paru is built with makepkg, which needs base-devel
    if [ -z "$helper" ]; then wanted+=(base-devel); fi

    local -a todo
    mapfile -t todo < <(missing_packages "${wanted[@]}" | sort -u)
    if [ "${#todo[@]}" -eq 0 ]; then
        ok "all packages from the repos are installed"
    else
        info "To install (${#todo[@]}):"
        wrap "${todo[*]}"
        # -Syu: new packages on an old package database fail to download or do not fit the installed
        # libraries (Quickshell is built against one Qt version), so the system is updated with them.
        # --noconfirm: the default for every pacman question (e.g. which provider)
        task "Updating the system and installing ${#todo[@]} packages" "${#todo[@]} packages installed" \
            sudo pacman -Syu --needed --noconfirm "${todo[@]}" ||
            fail "pacman could not install the packages. Fix what it reports, then run ./install.sh again."
    fi

    if [ -z "$helper" ]; then
        note "No AUR helper found: setting up paru (pywal and the yazi file picker are only in the AUR)."
        setup_paru
        helper="$(aur_helper)"
    fi
    if [ -z "$helper" ] && [ "$DRY_RUN" = 0 ]; then
        warn "paru could not be set up: skipping pywal and the file picker in yazi."
        if [ -n "$(missing_packages python-pywal)" ]; then
            warn "Without pywal there are no colors from the wallpaper (the default palette stays)."
        fi
        return 0
    fi

    for p in "${AUR_PACKAGES[@]}"; do
        # an installed python-pywal (from before) already covers pywal16
        if [ "$p" = python-pywal16 ] && [ -z "$(missing_packages python-pywal)" ]; then continue; fi
        aur_wanted+=("$p")
    done
    todo=()
    if [ "${#aur_wanted[@]}" -gt 0 ]; then
        mapfile -t todo < <(missing_packages "${aur_wanted[@]}" | sort -u)
    fi
    if [ "${#todo[@]}" -gt 0 ]; then
        aur_install "${helper:-paru}" "${todo[@]}" || true
    else
        ok "all packages from the AUR are installed"
    fi
}

check_versions() {
    step "Versions"
    local v
    v="$(pkg_version hyprland hyprland-git)"
    if [ -z "$v" ]; then
        warn "Hyprland is not installed"
    elif [ "$(vercmp "$v" "$MIN_HYPRLAND")" -lt 0 ]; then
        warn "Hyprland $v is older than $MIN_HYPRLAND (the Lua config needs at least that)"
    else
        ok "Hyprland $v"
    fi
    v="$(pkg_version quickshell quickshell-git)"
    if [ -z "$v" ]; then
        warn "Quickshell is not installed"
    elif [ "$(vercmp "$v" "$MIN_QUICKSHELL")" -lt 0 ]; then
        warn "Quickshell $v is older than $MIN_QUICKSHELL"
    else
        ok "Quickshell $v"
    fi
}

link_configs() {
    step "Configs"
    local name target src replace=() linked=() kept=()
    for name in "${CONFIGS[@]}"; do
        src="$REPO/$name" target="$CONFIG/$name"
        [ -e "$src" ] || continue
        if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$src" ]; then
            continue
        fi
        if [ -e "$target" ] || [ -L "$target" ]; then replace+=("$name"); fi
    done

    if [ "${#replace[@]}" -gt 0 ]; then
        info "These already exist and are moved to $(tilde "$BACKUP"):"
        grid "${yellow}${G_ARROW}${reset}" "${replace[@]}"
        run mkdir -p "$BACKUP"
    fi

    run mkdir -p "$CONFIG"
    for name in "${CONFIGS[@]}"; do
        src="$REPO/$name" target="$CONFIG/$name"
        [ -e "$src" ] || continue
        if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$src" ]; then
            kept+=("$name")
            continue
        fi
        if [ -e "$target" ] || [ -L "$target" ]; then
            run mv "$target" "$BACKUP/$name"
        fi
        run ln -s "$src" "$target"
        linked+=("$name")
    done
    if [ "${#linked[@]}" -gt 0 ]; then
        info "Linked into $(tilde "$CONFIG"):"
        grid "${green}${G_OK}${reset}" "${linked[@]}"
    fi
    if [ "${#kept[@]}" -gt 0 ]; then
        info "Already linked:"
        grid "${dim}${G_OK}${reset}" "${kept[@]}"
    fi
}

# Files that pywal writes to ~/.cache/wal on every wallpaper change; the configs read them through
# links. Absolute targets, because relative ones break when ~/.config/<name> is itself a link.
link_generated() {
    step "Generated colors"
    local pair link dest made=0
    run mkdir -p "$CACHE/wal"
    for pair in \
        "hypr/hyprtoolkit.conf:hyprtoolkit.conf" \
        "yazi/theme.toml:theme.toml" \
        "yazi/nvim/theme.toml:theme.toml"; do
        link="$REPO/${pair%%:*}" dest="$CACHE/wal/${pair##*:}"
        [ -d "$(dirname "$link")" ] || continue
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$dest" ]; then
            continue
        fi
        if [ -e "$link" ] && [ ! -L "$link" ]; then
            warn "${pair%%:*} is a real file, left as it is"
            continue
        fi
        run ln -sfn "$dest" "$link"
        ok "${pair%%:*}"
        made=1
    done
    if [ "$made" = 0 ]; then ok "links to $(tilde "$CACHE/wal") are in place"; fi
}

setup_folders() {
    step "Folders"
    if has xdg-user-dirs-update; then
        run xdg-user-dirs-update
    fi
    local pictures
    pictures="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
    run mkdir -p "$pictures/Wallpaper" "$pictures/Screenshots" "$CONFIG/shiori-shell"
    ok "$(tilde "$pictures/Wallpaper")  ${dim}put your wallpapers here${reset}"
    # Default wallpaper (see THIRD_PARTY.md): the first start takes it and makes the colors from it
    # (hypr/scripts/start.sh). Never overwrites a file of the same name.
    if [ -f "$REPO/wallpapers/default.jpg" ] && [ ! -e "$pictures/Wallpaper/shiori-default.jpg" ]; then
        run cp "$REPO/wallpapers/default.jpg" "$pictures/Wallpaper/shiori-default.jpg"
        ok "$(tilde "$pictures/Wallpaper/shiori-default.jpg")  ${dim}default wallpaper${reset}"
    fi
    ok "$(tilde "$CONFIG/shiori-shell")  ${dim}your own settings, see quickshell/defaults/settings.json${reset}"
}

setup_lock() {
    step "Lock screen"
    local pam=/etc/pam.d/quickshell-lock
    if [ -f "$pam" ]; then
        ok "$pam exists"
        return 0
    fi
    # The lock screen checks the password through PAM (same rules as the login prompt)
    if [ "$DRY_RUN" = 1 ]; then
        run sudo tee "$pam"
    else
        sudo_keepalive
        printf '%s\n' \
            "# PAM configuration for the shiori-shell lock screen (Quickshell)" \
            "# Same rules as the login prompt (see /etc/pam.d/login)" \
            "" \
            "auth        include     login" | sudo tee "$pam" >/dev/null
    fi
    ok "$pam"
}

# Prompt and greeting in every new terminal, as on the author's machine: starship as the prompt, fastfetch
# at the top (only in interactive shells, not in tmux and not on the bare TTY). Each line only once per
# rc file. The comment lines starting with "# shiori-shell:" are what --uninstall looks for.
setup_prompt() {
    step "Prompt"
    if ! has starship && ! has fastfetch; then
        note "starship and fastfetch are not installed, skipped"
        return 0
    fi
    local sh rc
    for sh in bash zsh; do
        rc="$HOME/.${sh}rc"
        # zsh only when it is used (its rc exists or it is the login shell)
        if [ "$sh" = zsh ] && [ ! -f "$rc" ] && [ "$(basename "${SHELL:-}")" != zsh ]; then continue; fi
        if has starship && ! grep -qs 'starship init' "$rc"; then
            if [ "$DRY_RUN" = 1 ]; then
                note "[dry-run] add the starship init line to $rc"
            else
                printf '\n# shiori-shell: starship prompt (config: ~/.config/starship.toml)\ncommand -v starship >/dev/null && eval "$(starship init %s)"\n' "$sh" >>"$rc"
            fi
        fi
        if has fastfetch && ! grep -qs 'fastfetch' "$rc"; then
            if [ "$DRY_RUN" = 1 ]; then
                note "[dry-run] add fastfetch to $rc"
            else
                # $- has an i only in interactive shells: bash also reads ~/.bashrc for scp, rsync and
                # git over ssh, where any output breaks the transfer
                printf '%s\n' '' \
                    '# shiori-shell: system info at the top of new terminals (config: ~/.config/fastfetch)' \
                    'if [[ $- == *i* ]] && command -v fastfetch >/dev/null && [ -z "$TMUX" ] && [ "$TERM" != linux ]; then' \
                    '    fastfetch' \
                    'fi' >>"$rc"
            fi
        fi
        ok "$(tilde "$rc")"
    done
}

# Without a display manager (login screen) Hyprland starts after logging in on tty1, as in most minimal
# Arch setups: a few lines in the login shell's profile (not when one of them already starts Hyprland)
setup_autostart() {
    step "Autostart"
    if systemctl is-enabled --quiet display-manager 2>/dev/null; then
        ok "login screen found: choose Hyprland there"
        return 0
    fi
    if grep -qsE 'start-hyprland|exec Hyprland' "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.zprofile" "$HOME/.profile"; then
        ok "Hyprland already starts from your login shell"
        return 0
    fi
    # bash reads only the first of ~/.bash_profile, ~/.bash_login, ~/.profile: take the one in use, so
    # a new ~/.bash_profile does not switch off an existing ~/.profile
    local prof="$HOME/.bash_profile" f
    if [ "$(basename "${SHELL:-}")" = zsh ]; then
        prof="$HOME/.zprofile"
    else
        for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
            if [ -f "$f" ]; then prof="$f"; break; fi
        done
    fi
    if [ "$DRY_RUN" = 1 ]; then
        note "[dry-run] add the Hyprland autostart to $prof"
    else
        # a ~/.bash_profile made here still has to load ~/.bashrc, as the one from /etc/skel does
        if [ ! -e "$prof" ] && [ "$prof" = "$HOME/.bash_profile" ]; then
            printf '%s\n' '[[ -f ~/.bashrc ]] && . ~/.bashrc' >"$prof"
        fi
        printf '%s\n' "" \
            "# shiori-shell: start Hyprland after logging in on tty1 (no login screen installed)" \
            'if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = /dev/tty1 ] && command -v start-hyprland >/dev/null; then' \
            "    exec start-hyprland >/dev/null 2>&1" \
            "fi" >>"$prof"
    fi
    ok "$(tilde "$prof")  ${dim}Hyprland starts after logging in on tty1${reset}"
}

setup_tmux() {
    step "tmux plugins"
    if ! has tmux; then
        note "tmux is not installed, skipped"
        return 0
    fi
    local tpm="$REPO/tmux/plugins/tpm"
    if [ ! -d "$tpm" ]; then
        if ! task "Fetching tpm" "tpm fetched" git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm"; then
            warn "the tmux plugin manager could not be fetched (run ./install.sh again later)"
            return 0
        fi
    fi
    task "Installing the tmux plugins" "tpm, tmux-sensible, vim-tmux-navigator" "$tpm/bin/install_plugins" ||
        warn "the tmux plugins could not be installed (run ./install.sh again later)"
}

setup_services() {
    step "Services"
    if has nmcli && ! systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
        warn "NetworkManager is not enabled. The network icon needs it:"
        info "  sudo systemctl enable --now NetworkManager"
        note "  (turn off other network managers such as iwd or systemd-networkd first)"
    fi
    # mpd-mpris (MPD in the audio dropdown) is not enabled: at login it would start before MPD, fail and
    # be blocked by systemd. start.sh starts it right after MPD. Undo the enable of older versions
    if has mpd-mpris && systemctl --user is-enabled --quiet mpd-mpris 2>/dev/null; then
        quiet systemctl --user disable mpd-mpris.service || true
    fi
    if has bluetoothctl; then
        if systemctl is-enabled --quiet bluetooth 2>/dev/null; then
            ok "bluetooth"
        elif quiet sudo systemctl enable --now bluetooth; then
            ok "bluetooth enabled"
        else
            warn "the bluetooth service could not be enabled"
        fi
    fi
    if has nmcli; then
        wrap "VPN killswitch: blocks all traffic outside the VPN. It installs a sudo rule for four nft commands, firewall rules and a boot service. Only for the VPN picker, not needed otherwise."
        if ask "Install the killswitch?" n; then
            local boot=--no-boot
            if ! systemctl is-enabled --quiet vpn-killswitch.service 2>/dev/null &&
                ask "Also switch it on at every boot? Without a VPN there is no internet then." n; then
                boot=--boot
            fi
            if [ -n "$(missing_packages nftables)" ]; then
                task "Installing nftables" "nftables installed" sudo pacman -S --needed --noconfirm nftables || true
            fi
            task "Installing the killswitch" "killswitch installed" \
                sudo "$REPO/quickshell/scripts/install-killswitch.sh" "$boot" ||
                warn "the killswitch could not be installed"
        else
            note "skipped"
        fi
    fi
}

# Headless Zen never ends by itself: after 20 s the profile exists, the timeout (exit 124) is the plan
zen_first_start() {
    local rc=0
    timeout 20 "$1" --headless about:blank || rc=$?
    if [ "$rc" = 124 ]; then return 0; fi
    return "$rc"
}

# Zen Browser with the wallpaper colors: zen-live (colors change live), the mod Transparent Zen from Zen's
# mod store, and the repo's Zen settings (wal/zen). A Zen installed before only gets the setup.
setup_zen() {
    step "Zen Browser"
    local zen=/opt/zen-browser-bin/zen-bin helper
    if [ ! -x "$zen" ]; then
        ask "Install Zen Browser, set up in the wallpaper colors (AUR)?" y || { note "skipped"; return 0; }
        helper="$(aur_helper)"
        if [ -z "$helper" ] && [ "$DRY_RUN" = 0 ]; then warn "no AUR helper, Zen skipped"; return 0; fi
        aur_install "${helper:-paru}" zen-browser-bin || return 0
        if [ "$DRY_RUN" = 1 ]; then return 0; fi
    fi
    [ -x "$zen" ] || return 0
    if [ -f /opt/zen-browser-bin/zen-live.cfg ]; then
        ok "zen-live  ${dim}colors follow the wallpaper without a restart${reset}"
    else
        task "Installing zen-live" "zen-live  ${dim}colors follow the wallpaper without a restart${reset}" \
            sudo "$REPO/wal/zen-live/install.sh" || warn "zen-live could not be installed"
    fi
    # Zen creates its profile on the first start: once headless, so the mod and settings have a place
    if [ -z "$("$REPO/wal/zen/zen-profiles.sh")" ] && [ "$DRY_RUN" = 0 ]; then
        task "Creating the Zen profile (20 s)" "Zen profile created" zen_first_start "$zen" || true
    fi
    local -a profiles
    mapfile -t profiles < <("$REPO/wal/zen/zen-profiles.sh")
    if [ "${#profiles[@]}" -eq 0 ]; then
        warn "no Zen profile yet: start Zen once, then run ./install.sh again for the mod"
        return 0
    fi
    task "Fetching the mod Transparent Zen" "Transparent Zen" \
        python3 -I "$REPO/wal/zen/install-zen-mod.py" "${profiles[@]}" ||
        warn "Transparent Zen could not be downloaded"
    if quiet "$REPO/wal/zen/install-zen-prefs.sh"; then
        ok "the shell's Zen settings"
    else
        warn "the Zen settings could not be written"
    fi
}

finish() {
    local w
    step "Finished" "$(duration "$SECONDS")"
    if [ "$DRY_RUN" = 1 ]; then
        ok "dry run: nothing was changed"
    elif [ "${#WARNINGS[@]}" -eq 0 ]; then
        ok "shiori-shell is set up"
    else
        ok "shiori-shell is set up, with ${#WARNINGS[@]} warning(s):"
        for w in "${WARNINGS[@]}"; do line "  ${yellow}!${reset} $w"; done
    fi
    line ""
    info "${bold}Next${reset}"
    # pacman -Syu may have replaced the running kernel: its modules are gone until the reboot
    # (bluetooth, VPN, encrypted folders would fail to load theirs)
    if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
        line "${yellow}${G_ARROW}${reset} The kernel was updated: ${bold}reboot${reset} before starting Hyprland."
    fi
    line "${magenta}${G_ARROW}${reset} Start Hyprland: log in again on tty1, choose it at your login screen,"
    line "  or run ${bold}cd && start-hyprland${reset}"
    line "${magenta}${G_ARROW}${reset} Put wallpapers into the Wallpaper folder and pick one with ${bold}Super+W${reset}"
    line "${magenta}${G_ARROW}${reset} Fixed monitor layout: copy hypr/modules/monitors.example.lua to monitors.lua"
    line "${magenta}${G_ARROW}${reset} See what is still missing at any time: ${bold}./install.sh --check${reset}"
    if [ -f "$LOG" ]; then
        line ""
        note "Full output of this run: $LOG"
    fi
    echo
}

# ─────────────────────────────── uninstall ───────────────────────────────

uninstall() {
    banner "uninstaller"
    if [ "$DRY_RUN" = 1 ]; then echo; note "Dry run: nothing is changed."; fi
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        echo
        warn "Hyprland is running with these configs. Better log out and run this from a TTY."
        ask "Continue anyway?" n || exit 0
    fi

    step "Links in $(tilde "$CONFIG")"
    local name target removed=()
    for name in "${CONFIGS[@]}"; do
        target="$CONFIG/$name"
        if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$REPO/$name")" ]; then
            run rm "$target"
            removed+=("$name")
        fi
    done
    if [ "${#removed[@]}" -gt 0 ]; then
        info "Removed:"
        grid "${green}${G_OK}${reset}" "${removed[@]}"
    else
        note "no links to this repo found"
    fi

    # The newest backup made by install.sh: move back what is not in the way
    local backup
    backup="$(find "$HOME" -maxdepth 1 -type d -name '.config-backup-shiori-*' 2>/dev/null | sort | tail -n 1)"
    if [ -n "$backup" ]; then
        step "Old configs"
        if ask "Move the configs from $(tilde "$backup") back?" y; then
            local item
            for item in "$backup"/* "$backup"/.[!.]*; do
                [ -e "$item" ] || [ -L "$item" ] || continue
                target="$CONFIG/$(basename "$item")"
                if [ -e "$target" ] || [ -L "$target" ]; then
                    warn "$(basename "$item"): $(tilde "$target") exists, left in the backup"
                else
                    run mv "$item" "$target"
                    ok "$(basename "$item")"
                fi
            done
            run rmdir "$backup" 2>/dev/null || true
        fi
    fi

    # The lines setup_prompt and setup_autostart added (each block starts with "# shiori-shell:")
    local f rcs=()
    for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.zprofile" "$HOME/.profile"; do
        if grep -qs '^# shiori-shell: ' "$f"; then rcs+=("$f"); fi
    done
    if [ "${#rcs[@]}" -gt 0 ]; then
        step "Shell startup files"
        info "The installer added the prompt, fastfetch and the Hyprland autostart to:"
        for f in "${rcs[@]}"; do info "  $(tilde "$f")"; done
        if ask "Remove these lines again?" y; then
            for f in "${rcs[@]}"; do
                run sed -i --follow-symlinks \
                    -e '/^# shiori-shell: starship prompt/,+1d' \
                    -e '/^# shiori-shell: system info/,/^fi$/d' \
                    -e '/^# shiori-shell: start Hyprland/,/^fi$/d' "$f"
            done
            ok "removed"
        fi
    fi

    step "System files"
    local any=0
    if [ -f /etc/pam.d/quickshell-lock ]; then
        any=1
        if ask "Remove /etc/pam.d/quickshell-lock (needs sudo)?" y; then
            run sudo rm /etc/pam.d/quickshell-lock
            ok "lock screen file removed"
        fi
    fi
    if [ -f /etc/vpn-killswitch.nft ] || [ -f /etc/systemd/system/vpn-killswitch.service ]; then
        any=1
        if ask "Remove the VPN killswitch (rules, boot service, sudo rule)?" y; then
            quiet sudo systemctl disable --now vpn-killswitch.service || true
            quiet sudo nft delete table inet killswitch || true
            run sudo rm -f /etc/vpn-killswitch.nft /usr/local/bin/vpn-killswitch \
                /etc/systemd/system/vpn-killswitch.service /etc/sudoers.d/quickshell-nft
            run sudo systemctl daemon-reload
            ok "killswitch removed"
        fi
    fi
    # zen-live: the pacman hook would put the live colors back after every Zen update
    if [ -d /usr/local/share/zen-live ] || [ -f /etc/pacman.d/hooks/zen-live.hook ]; then
        any=1
        if ask "Remove zen-live (live colors in Zen Browser, pacman hook)?" y; then
            run sudo rm -rf /usr/local/share/zen-live
            run sudo rm -f /etc/pacman.d/hooks/zen-live.hook /opt/zen-browser-bin/zen-live.cfg \
                /opt/zen-browser-bin/defaults/pref/autoconfig.js
            ok "zen-live removed"
        fi
    fi
    if [ "$any" = 0 ]; then note "nothing installed"; fi

    step "Data"
    local data=("$CACHE/quickshell" "${XDG_DATA_HOME:-$HOME/.local/share}/quickshell"
        "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell" "$CONFIG/quickshell-local" "$CACHE/cliphist")
    local existing=() d
    for d in "${data[@]}"; do if [ -e "$d" ]; then existing+=("$d"); fi; done
    if [ "${#existing[@]}" -gt 0 ]; then
        wrap "Caches and data of the shell (thumbnails, progress, imported books of the language tool, machine settings in quickshell-local, the clipboard history):"
        for d in "${existing[@]}"; do info "  $(tilde "$d")"; done
        if ask "Delete them?" n; then
            run rm -rf "${existing[@]}"
            ok "deleted"
        fi
    fi
    if [ -d "$CACHE/wal" ] && ask "Delete the generated colors in $(tilde "$CACHE/wal")? A new install then starts from the default wallpaper." n; then
        run rm -rf "$CACHE/wal"
        ok "deleted"
    fi
    if [ -d "$CONFIG/shiori-shell" ] && ask "Delete your own settings in $(tilde "$CONFIG/shiori-shell")?" n; then
        run rm -rf "$CONFIG/shiori-shell"
        ok "deleted"
    fi

    step "Finished"
    info "Packages stay installed (you may need some elsewhere). To remove them, for example:"
    info "  sudo pacman -Rns quickshell hyprland python-pywal16"
    info "Your wallpapers are left as they are."
    info "The repo itself is still here: $(tilde "$REPO")"
    echo
}

# ─────────────────────────────── --check ───────────────────────────────

check_only() {
    local entry cmd what required missing_req=0 missing_opt=() present=()
    banner "check"
    step "Programs"
    for entry in "${PROGRAMS[@]}"; do
        IFS='|' read -r cmd what required <<<"$entry"
        if has "$cmd"; then
            present+=("$cmd")
        elif [ "$required" = 1 ]; then
            bad "$cmd  ${dim}$what${reset}"
            missing_req=$((missing_req + 1))
        else
            missing_opt+=("$cmd|$what")
        fi
    done
    grid "${green}${G_OK}${reset}" "${present[@]}"
    if [ "${#missing_opt[@]}" -gt 0 ]; then
        line ""
        note "Optional, not installed:"
        for entry in "${missing_opt[@]}"; do note "$G_DOT ${entry%%|*}  ${entry#*|}"; done
    fi

    if has pacman; then check_versions; fi

    step "Configs"
    local name linked=()
    for name in "${CONFIGS[@]}"; do
        if [ -L "$CONFIG/$name" ] && [ "$(readlink -f "$CONFIG/$name")" = "$REPO/$name" ]; then
            linked+=("$name")
        else
            warn "$name is not linked to this repo"
        fi
    done
    grid "${green}${G_OK}${reset}" "${linked[@]}"

    step "Files"
    if [ -f /etc/pam.d/quickshell-lock ]; then ok "/etc/pam.d/quickshell-lock"
    else warn "/etc/pam.d/quickshell-lock missing: the lock screen cannot unlock"; fi
    if has tmux; then
        if [ -d "$REPO/tmux/plugins/tpm" ]; then ok "tmux plugins"
        else warn "tmux plugins missing (run ./install.sh)"; fi
    fi

    echo
    if [ "$missing_req" -gt 0 ]; then
        printf '  %s%s %d required program(s) missing.%s\n\n' "$red" "$G_ERR" "$missing_req" "$reset"
        return 1
    fi
    printf '  %s%s Everything required is there.%s\n\n' "$green" "$G_OK" "$reset"
}

# ─────────────────────────────── main ───────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --no-packages) NO_PACKAGES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -y|--yes) YES=1 ;;
        -v|--verbose) VERBOSE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; fail "unknown option: $1" ;;
    esac
    shift
done

if [ "$CHECK" = 1 ]; then
    if check_only; then exit 0; else exit 1; fi
fi

# With sudo, $HOME is root's: the links and files would land there
[ "$(id -u)" -ne 0 ] || fail "run as your normal user, not with sudo (the script asks for sudo when needed)"

if [ "$UNINSTALL" = 1 ]; then
    uninstall
    exit 0
fi

banner "installer"
if [ "$DRY_RUN" = 1 ]; then
    echo
    note "Dry run: nothing is changed."
else
    LOG="$(mktemp -t shiori-install.XXXXXX.log)"
fi

STEPS=()
if [ "$NO_PACKAGES" = 0 ]; then STEPS+=(check_system install_packages check_versions); fi
STEPS+=(link_configs link_generated setup_folders setup_lock setup_prompt setup_autostart setup_tmux)
if [ "$NO_PACKAGES" = 0 ]; then STEPS+=(setup_services setup_zen); fi
STEP_TOTAL=${#STEPS[@]}
for s in "${STEPS[@]}"; do "$s"; done

STEP_TOTAL=0
finish
