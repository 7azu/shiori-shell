#!/bin/bash
# The queued songs sit directly behind the playing song.
# In MPD's random mode, descending priorities keep the same order.
set -euo pipefail

set_queue_priorities() {
    local start=$1 count=$2 i position priority existing
    local -a priorities reset=()
    if ((count == 0)); then
        return
    fi

    existing=$(mpc -f 'p%prio%' playlist)
    mapfile -t priorities <<< "$existing"
    for ((i=0; i<count; i++)); do
        position=$((start + i))
        priority=$((i < 255 ? 255 - i : 0))
        if [[ ${priorities[position - 1]:-p0} == "p$priority" ]]; then
            continue
        fi
        if ((priority > 0)); then
            mpc -q prio "$priority" "$position"
        else
            reset+=("$position")
        fi
    done
    if ((${#reset[@]} > 0)); then
        mpc -q prio 0 "${reset[@]}"
    fi
}

# mpc insert appends in random mode and sets priority 1. The physical position
# has to be right in both modes, so the same queue can be edited.
add_at_position() {
    local song=$1 target=$2 last
    mpc -q add -- "$song"
    last=$(mpc -f '%position%' playlist | tail -n 1)
    if ((last != target)); then
        mpc -q move "$last" "$target"
    fi
}

cmd=$1
shift

if [[ "$cmd" == start ]]; then
    song=$1
    shift
    mpc -q clear
    mpc listall | mpc -q add
    location=$(mpc -f '%file%' playlist | grep -nxF -- "$song")
    position=${location%%:*}

    mpc -q play "$position"
    mpc -q seek 0
    target=$((position + 1))
    for queued_song in "$@"; do
        add_at_position "$queued_song" "$target"
        ((++target))
    done
    set_queue_priorities "$((position + 1))" "$#"
    exit
fi

cur=$(mpc -f '%position%' current)

if [[ "$cmd" == snapshot ]]; then
    if [[ -z "$cur" ]]; then
        # MPD reports no current song when stopped.
        mpc --with-prio -f '%file%' playlist
        exit
    fi

    # A failed job can make the UI list differ from the real block in MPD.
    playlist=$(mpc -f '%prio% %file%' playlist)
    position=0
    queued=0
    previous=("$@")
    while IFS= read -r entry; do
        if ((++position <= cur)); then
            continue
        fi
        priority=${entry%% *}
        song=${entry#* }
        if [[ "$priority" =~ ^[1-9][0-9]*$ ]] ||
            { ((queued >= 255 && queued < ${#previous[@]})) && [[ "${previous[queued]}" == "$song" ]]; }; then
            printf '%s\n' "$song"
            ((++queued))
        else
            break
        fi
    done <<< "$playlist"
    exit
fi

[[ -n "$cur" ]] || exit 1
base=$((cur + 1))

# Indices are 0-based within the queue.
case "$cmd" in
    add)
        song=$1 count=$2
        add_at_position "$song" "$((base + count))"
        set_queue_priorities "$base" "$((count + 1))"
        ;;
    del)
        index=$1 count=$2
        mpc -q del "$((base + index))"
        if ((count >= 255)); then
            set_queue_priorities "$base" "$count"
        fi
        ;;
    next)
        mpc -q move "$((base + $1))" "$base"
        set_queue_priorities "$base" "$2"
        ;;
    play)
        index=$1
        if ((index > 0)); then
            # On a jump the skipped titles drop out of Up next.
            skipped=()
            for ((i=0; i<index; i++)); do
                skipped+=("$((base + i))")
            done
            mpc -q prio 0 "${skipped[@]}"
        fi
        mpc -q play "$((base + index))"
        ;;
    clear)
        for ((i=0; i<$1; i++)); do
            mpc -q del "$base"
        done
        ;;
    priorities)
        set_queue_priorities "$base" "$1"
        ;;
    *)
        exit 2
        ;;
esac
