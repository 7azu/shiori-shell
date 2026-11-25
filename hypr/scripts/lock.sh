#!/bin/bash
# Lock screen: own Quickshell lock (~/.config/quickshell/lock.qml, its own qs instance).
# Emergency: if the Quickshell lock does not start or crashes, fallback() starts it again
# (Hyprland: misc.allow_session_lock_restore allows the takeover). hyprlock is not used.
#
#   lock.sh                    (hypridle, suspend)
#   lock.sh --from-powermenu   (power menu: the tiles sink away, the lock screen elements already fall in
#                               there; meanwhile the lock screen loads and then takes over the picture)
#
# Seamless through images per monitor (in $XDG_RUNTIME_DIR, readable only by us, deleted afterwards):
#   quickshell-lock-<mon>.ppm       = start image, the lock screen begins exactly with this image
#   quickshell-lock-thaw-<mon>.ppm  = target image when unlocking (power menu: desktop before the menu)
#   quickshell-lock-wall-<mon>      = plain wallpaper that the frost shows: the paused video frame
#                                     (Quickshell) or the image awww shows on the monitor
# The wallpaper animation is paused meanwhile (qs ipc call wallpaper freeze) and continues after
# unlocking from exactly this frame.

run="${XDG_RUNTIME_DIR:-/tmp}"
# Only one lock screen at a time (hypridle, power menu and suspend can trigger at the same time)
exec 9>"$run/lockscreen.flock"
flock -n 9 || exit 0

from_pm=0
[ "$1" = "--from-powermenu" ] && from_pm=1

ready="$run/quickshell-lock.ready"
loaded="$run/quickshell-lock.loaded"
handoff="$run/powermenu-handoff"
log="$run/quickshell-lock.log"
shot="$HOME/.config/quickshell/scripts/desktop_shot.sh"
rm -f "$ready" "$loaded" "$handoff"

# Timestamp for the log (milliseconds since epoch, same unit as Date.now() in lock.qml)
stamp() { echo "lock.sh time $(date +%s%3N) $*" >>"$log"; }
stamp "Start (from_pm=$from_pm)"

dismiss_menu() {
    [ "$from_pm" = 1 ] && qs ipc call powermenu dismiss >/dev/null 2>&1
}

cleanup() {
    rm -f "$ready" "$loaded" "$handoff" "$run"/quickshell-lock-*.ppm "$run"/quickshell-lock-wall-* \
        "$run"/powermenu-desktop-*.ppm "$run"/quickshell-lock-thaw-*.strip "$run"/powermenu-desktop-*.strip
    # Only after unlocking: the wallpaper continues from exactly the frame it thawed to
    qs ipc call wallpaper unfreeze >/dev/null 2>&1
    # The audio visualizer (workspace 1) fades in again only now
    qs ipc call visualizer unlock >/dev/null 2>&1
}

# Emergency: restart the Quickshell lock up to 3 times. Important above all
# when the first start never locked - otherwise the session would stay open. After a crash the
# session is still locked; allow_session_lock_restore (looks.lua) lets the new lock take over.
# If nothing works: run lock.sh again from a TTY.
fallback() {
    stamp "emergency restart ($1)"
    dismiss_menu
    local try
    for try in 1 2 3; do
        rm -f "$ready"
        qs -n -p "$HOME/.config/quickshell/lock.qml" >>"$log" 2>&1 &
        pid=$!
        if wait_for "$ready" 250; then
            wait "$pid" && { stamp "unlocked after restart $try"; return 0; }
            stamp "restart $try exited with $?"
        else
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            stamp "restart $try not ready"
        fi
    done
    stamp "emergency restart failed"
    notify-send -u critical "Lock screen" "Lock screen failed to start (see quickshell-lock.log)" 2>/dev/null
}

# Waits up to $2 x 20 ms for file $1, as long as qs is alive
wait_for() {
    for _ in $(seq "$2"); do
        [ -e "$1" ] && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.02
    done
    [ -e "$1" ]
}

# Plain wallpaper per monitor (video frame or awww image as PPM), runs in parallel to the photos
walls="$HOME/.config/quickshell/scripts/lock_walls.sh"
prepare_walls() {
    "$walls" "$video_mons" &
    walls_pid=$!
}
wait_convs() {
    wait "$walls_pid" 2>/dev/null
}

take_shots() {
    "$shot" "$run/quickshell-lock"
    local f mon pm
    for f in "$run"/quickshell-lock-*.ppm; do
        case "$f" in *-thaw-*) continue ;; esac
        mon="${f#"$run"/quickshell-lock-}"
        mon="${mon%.ppm}"
        pm="$run/powermenu-desktop-$mon.ppm"
        rm -f "$run/quickshell-lock-thaw-$mon.strip"
        if [ "$from_pm" = 1 ] && [ -s "$pm" ]; then
            mv -f "$pm" "$run/quickshell-lock-thaw-$mon.ppm"
            # The menu image still shows the audio visualizer: height of the strip that the lock screen
            # covers with the wallpaper while thawing (PowerMenu.qml / LockSurface.qml)
            [ -s "${pm%.ppm}.strip" ] && mv -f "${pm%.ppm}.strip" "$run/quickshell-lock-thaw-$mon.strip"
        else
            cp -f "$f" "$run/quickshell-lock-thaw-$mon.ppm"
        fi
    done
}

# Pause the wallpaper (with the power menu this already happened when it opened). Answer: monitors with
# a video, for which Quickshell is about to store the still frame
video_mons=$(qs ipc call wallpaper freeze 2>/dev/null)

# Audio visualizer off during the lock (DesktopVisualizer.qml, 150 ms). If it was visible, wait for the
# fade-out, so it does not end up in the start image (the lock screen begins with exactly this photo)
if [ "$(qs ipc call visualizer lock 2>/dev/null)" = "visible" ] && [ "$from_pm" = 0 ]; then
    sleep 0.17
fi

if [ "$from_pm" = 1 ]; then
    # The lock screen loads while the tiles in the menu sink away; locking happens only after the photo
    QS_LOCK_DEFER=1 qs -n -p "$HOME/.config/quickshell/lock.qml" >>"$log" 2>&1 &
    pid=$!
    prepare_walls
    # The menu reports "tiles gone, lock screen elements in place" (max 2.5 s), then capture.
    # Content = the menu's monitor: there the lock screen starts with the elements already in place
    for _ in $(seq 250); do [ -e "$handoff" ] && break; sleep 0.01; done
    menu_mon=$(cat "$handoff" 2>/dev/null)
    stamp "handover from the menu ($menu_mon)"
    take_shots
    wait_convs
    stamp "Fotos fertig"
    if wait_for "$loaded" 100; then
        qs ipc --pid "$pid" call lockscreen engage "$menu_mon" >/dev/null 2>&1
        stamp "engage gesendet"
    fi
else
    prepare_walls
    take_shots
    wait_convs
    stamp "Fotos fertig"
    qs -n -p "$HOME/.config/quickshell/lock.qml" >>"$log" 2>&1 &
    pid=$!
fi

# lock.qml creates $ready as soon as Hyprland has confirmed the lock
if ! wait_for "$ready" 250; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    fallback "Quickshell lock not ready"
    cleanup
    exit 0
fi
stamp "lock confirmed"

# Lock screen stands -> close the power menu behind it right away
dismiss_menu

wait "$pid"
rc=$?
stamp "entsperrt (rc=$rc)"
# 0 = unlocked normally; anything else (crash, killed) -> the session is still locked
[ "$rc" -ne 0 ] && fallback "Quickshell lock exited with $rc"
cleanup
exit 0
