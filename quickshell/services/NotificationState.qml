// Notification daemon of the shell (replaces swaync) + state for the notification center
// (the bar morphs into the center, toasts at the top right: windows/NotificationToasts.qml).
// - All notifications go into the history (server.trackedNotifications)
// - The history survives a restart of the shell: what is in the center is written to
//   <stateDir>/notification-history.json and comes back as `past` (plain objects with the same fields
//   as a notification, without actions). `items` = live ones and past ones, newest first.
// - New ones also appear briefly as a toast (popups), except in do-not-disturb mode
// - Session info for the header: user, host, since when Hyprland is running

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../common/Format.js" as Fmt
pragma Singleton

Singleton {
    id: root

    property bool centerOpen: false
    // true while yazi is open for a new profile picture
    readonly property bool avatarPicking: avatarProcess.running
    readonly property string avatarScript: Qt.resolvedUrl("../scripts/avatar_pick.sh").toString().replace("file://", "")
    // Toasts, newest first
    property var popups: []
    readonly property bool dnd: persist.dnd
    readonly property var list: server.trackedNotifications.values
    // From earlier runs of the shell (see the top); they stay until dismissed
    property var past: []
    // Everything in the center, newest first: live notifications and the past ones
    readonly property var items: {
        const live = list.slice().reverse();
        return live.concat(past);
    }
    readonly property int count: list.length + past.length
    readonly property string historyFile: Quickshell.stateDir + "/notification-history.json"
    // How many entries the file keeps at most
    readonly property int historyMax: 80

    // ---- Session ----
    readonly property string user: Quickshell.env("USER") || ""
    property string host: ""
    property real sessionStartMs: 0
    // Profile picture: ~/.face if there is one; empty = the panel draws common/DefaultAvatar (pywal colors)
    property string avatar: ""
    property real nowMs: Date.now()

    function toggle() {
        centerOpen ? close() : open();
    }

    function open() {
        nowMs = Date.now();
        // What is in the center needs no toast anymore
        popups = [];
        centerOpen = true;
    }

    function close() {
        centerOpen = false;
    }

    // Pick a profile picture with yazi. The center stays open: while avatarPicking holds,
    // MainBar suspends the focus grab (otherwise the focus change to yazi closes the center), and the
    // script puts yazi centered below the center (top = bottom edge of the center on the monitor).
    function changeAvatar(screenName, top) {
        if (avatarPicking)
            return ;

        avatarProcess.command = ["bash", avatarScript, screenName, String(Math.round(top))];
        avatarProcess.running = true;
    }

    // The shell's own notification (picker, clipboard ...), goes via notify-send
    // through our own server. opts: icon (theme name/path), image (path or http URL,
    // then cached locally), timeout (ms), keep (true = stays in the history),
    // success (true = success: hint x-qs-success, the card fires a sparkle), critical (true = urgent:
    // the toast stays until clicked away)
    function send(app, summary, body, opts) {
        const o = opts || {
        };
        const script = 'app="$1"; sum="$2"; body="$3"; icon="$4"; img="$5"; t="$6"; keep="$7"; ok="$8"; crit="$9"; ' + 'case "$img" in http*) f="${XDG_RUNTIME_DIR:-/tmp}/qs-notify-$(printf %s "$img" | md5sum | cut -c1-16)"; ' + '[ -s "$f" ] || curl -sfL --max-time 4 "$img" -o "$f" || rm -f "$f"; img="$f"; [ -s "$img" ] || img="";; esac; ' + 'set -- -a "$app" -t "$t"; [ "$keep" = 1 ] || set -- "$@" -e; ' + '[ -n "$icon" ] && set -- "$@" -i "$icon"; [ -n "$img" ] && set -- "$@" -h "string:image-path:$img"; ' + '[ "$ok" = 1 ] && set -- "$@" -h "string:x-qs-success:1"; ' + '[ "$crit" = 1 ] && set -- "$@" -u critical; ' + 'notify-send "$@" -- "$sum" "$body"';
        Quickshell.execDetached(["sh", "-c", script, "qs-notify", app, summary, body || "", o.icon || "", o.image || "", String(o.timeout || 4000), o.keep ? "1" : "0", o.success ? "1" : "0", o.critical ? "1" : "0"]);
    }

    function setDnd(on) {
        persist.dnd = on;
        if (on)
            popups = [];

    }

    function hidePopup(n) {
        popups = popups.filter((p) => {
            return p !== n;
        });
        // Transient notifications do not belong in the history. Only while still tracked: one that already
        // closed itself (timeout) gave "Cannot close destroyed notification" in the log
        if (n && n.transient && n.tracked)
            n.expire();

    }

    function dismiss(n) {
        if (n && n.past) {
            past = past.filter((p) => {
                return p !== n;
            });
            saveSoon.restart();
            return ;
        }
        hidePopup(n);
        if (n && n.tracked)
            n.dismiss();
    }

    // All of one app at once (a group in the center)
    function dismissApp(app) {
        const of = (n) => {
            return (n.appName || "Notification") === app;
        };
        past = past.filter((p) => {
            return !of(p);
        });
        const live = list.filter(of);
        for (let i = 0; i < live.length; i++) dismiss(live[i])
        saveSoon.restart();
    }

    function clearAll() {
        popups = [];
        past = [];
        const all = list.slice();
        for (let i = 0; i < all.length; i++) all[i].dismiss()
        saveSoon.restart();
    }

    // A live notification as a plain object for the file. Embedded pictures (image://...) only live
    // in this process, so only file paths and theme icons are kept.
    function snapshot(n) {
        const img = String(n.image || "");
        const keepImg = img.startsWith("/") || img.startsWith("file://") || img.startsWith("image://icon/");
        return {
            "past": true,
            "session": persist.session,
            "appName": n.appName || "",
            "summary": n.summary || "",
            "body": n.body || "",
            "image": keepImg ? img : "",
            "appIcon": n.appIcon || "",
            "desktopEntry": n.desktopEntry || "",
            "urgency": n.urgency,
            "hints": n.hints && n.hints["x-qs-success"] ? {
                "x-qs-success": 1
            } : {
            },
            "actions": [],
            "resident": false,
            "time": timeOf(n) || Date.now()
        };
    }

    function save() {
        const all = list.map(snapshot).concat(past.map((p) => {
            return Object.assign({
            }, p);
        }));
        all.sort((a, b) => {
            return b.time - a.time;
        });
        historyView.setText(JSON.stringify(all.slice(0, historyMax)));
    }

    // Run the default action (click on the card); true if there was one
    function activate(n) {
        if (!n || n.past)
            return false;

        const acts = n.actions;
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].identifier === "default") {
                acts[i].invoke();
                return true;
            }
        }
        return false;
    }

    // Time of arrival (survives reloads)
    function timeOf(n) {
        if (n && n.past)
            return n.time || 0;

        return persist.times[n.id] || 0;
    }

    function ago(ms) {
        if (!ms)
            return "";

        return Fmt.ago(Math.max(0, Math.round((nowMs - ms) / 1000)));
    }

    function duration(ms) {
        const m = Math.max(0, Math.floor(ms / 60000));
        const h = Math.floor(m / 60);
        if (h >= 24)
            return Math.floor(h / 24) + "d " + (h % 24) + "h";

        return h > 0 ? h + "h " + (m % 60) + "m" : m + "m";
    }

    // Toast duration in ms (expireTimeout comes in ms, <= 0 = default)
    function popupDuration(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 0; // stays until you click it away

        return n.expireTimeout > 0 ? Math.max(2000, n.expireTimeout) : 6000;
    }

    // Icon: embedded image > path > icon name from the theme ("" = symbol/letter as a fallback)
    function iconOf(n) {
        // Quickshell also stores plain theme icons as image://icon/<name> -> check first,
        // otherwise a missing icon shows the checkerboard instead of the fallback
        if (n.image && !n.image.startsWith("image://icon/"))
            return n.image;

        if (n.image) {
            const themed = Quickshell.iconPath(n.image.slice(13), true);
            if (themed)
                return themed;

        }

        const ic = n.appIcon || n.desktopEntry || "";
        if (ic.startsWith("/"))
            return "file://" + ic;

        if (ic.startsWith("file://") || ic.startsWith("image://"))
            return ic;

        return ic ? Quickshell.iconPath(ic, true) : "";
    }

    // Fallback symbol (Nerd Font) for the shell's own messages when there is no image
    function glyphOf(app) {
        const g = {
            "Clipboard": "󰅍",
            "Music": "󰎆",
            "Wallpaper": "󰸉",
            "Launcher": "󰀻",
            "Anime": "󰎁",
            "Manga": "󰂺",
            "Screenshot": "󰹑",
            "Battery": "󰂃"
        };
        return g[app] || "";
    }

    PersistentProperties {
        id: persist

        property bool dnd: false
        property var times: ({
        })
        // Marks the entries this run of the shell wrote: after a reload those notifications are still
        // live (keepOnReload), so they must not come back a second time as past ones
        property string session: ""

        reloadableId: "notificationState"
    }

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: (n) => {
            n.tracked = true;
            if (!persist.times[n.id]) {
                const t = Object.assign({
                }, persist.times);
                t[n.id] = Date.now();
                persist.times = t;
            }
            root.nowMs = Date.now();
            n.closed.connect(() => {
                root.popups = root.popups.filter((p) => {
                    return p !== n;
                });
                const left = Object.assign({
                }, persist.times);
                delete left[n.id];
                persist.times = left;
                saveSoon.restart();
            });
            saveSoon.restart();
            // After a reload Quickshell reports the old ones again: no toast, no sound
            if (root.centerOpen || n.lastGeneration)
                return ;

            if (!persist.dnd)
                root.popups = [n].concat(root.popups.filter((p) => {
                return p !== n;
            })).slice(0, 4);

        }
    }

    // The history file: read once at the start, written a moment after every change
    FileView {
        id: historyView

        path: root.historyFile
        printErrors: false
        onLoaded: {
            let all = [];
            try {
                all = JSON.parse(text()) || [];
            } catch (e) {
                all = [];
            }
            // Entries of this very run are still live (a reload, not a restart)
            root.past = all.filter((e) => {
                return e && e.session !== persist.session;
            }).map((e) => {
                return Object.assign(e, {
                    "past": true,
                    "actions": []
                });
            });
            // What is in the center right now goes into the file as well
            saveSoon.restart();
        }
        // No file yet (first start)
        onLoadFailed: saveSoon.restart()
    }

    Timer {
        id: saveSoon

        interval: 800
        onTriggered: root.save()
    }

    Component.onCompleted: {
        if (persist.session === "")
            persist.session = String(Date.now()) + "-" + Math.floor(Math.random() * 1e6);

    }

    // Open yazi, crop the image and save it as ~/.face (scripts/avatar_pick.sh)
    Process {
        id: avatarProcess

        stdout: StdioCollector {
            onStreamFinished: {
                // The timestamp forces a reload, otherwise Image shows the cached old picture
                if (text.trim() === "ok")
                    root.avatar = "file://" + Quickshell.env("HOME") + "/.face?" + Date.now();

            }
        }

    }

    // Uptime of the Hyprland session
    Process {
        running: true
        command: ["sh", "-c", "uname -n; ps -o etimes= -p \"$(pgrep -xo Hyprland)\"; [ -f \"$HOME/.face\" ] && echo face"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.host = (lines[0] || "").trim();
                const secs = parseInt(lines[1] || "", 10);
                root.sessionStartMs = isNaN(secs) ? 0 : Date.now() - secs * 1000;
                if ((lines[2] || "").trim() === "face")
                    root.avatar = "file://" + Quickshell.env("HOME") + "/.face";

            }
        }

    }

    Timer {
        interval: root.centerOpen ? 1000 : 30000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    IpcHandler {
        function toggle() {
            root.toggle();
        }

        function clear() {
            root.clearAll();
        }

        function toggleDnd() {
            root.setDnd(!root.dnd);
        }

        target: "notifications"
    }

}
