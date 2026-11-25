pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// State of the sync icon in the bar (bar/SyncToggle.qml) and its dropdown (dropdowns/SyncContent.qml).
// The entries come from "sync" in the settings (services/Settings, ~/.config/shiori-shell/settings.json);
// scripts/shiori_sync.py knows the types (git, rclone, command), checks and syncs them. A sync runs as
// its own systemd unit (shiori-sync-<id>), so it keeps going while Quickshell reloads. Progress and the
// last result come from $XDG_RUNTIME_DIR/sync-progress/<id>.json (services/SyncProgress). That folder is gone
// after a reboot, so the script also keeps the last successful sync in the state folder (check: "synced").
// A run that was killed is closed by the next check (shiori_sync.py, sync_progress.stale).
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/shiori_sync.py").toString().replace("file://", "")
    readonly property string unlockScript: Quickshell.env("HOME") + "/.config/hypr/scripts/ssh-unlock.sh"
    // [{id, name, icon, kind, subtitle, rcSocket, prompt, hasCheck, hasInput}]
    property var entries: []
    readonly property bool hasEntries: entries.length > 0
    // Result of the last check per id: {pending, changed, unpushed, subtitle, files, state, message, prompt, time, synced}
    property var checks: ({})
    // Started by a click, the unit has not reported yet: id -> ms
    property var requested: ({})
    // id -> error text of the last input (wrong code ...); inputBusy = id that is being checked
    property var inputErrors: ({})
    property string inputBusy: ""
    property bool keyLocked: false
    property double now: Date.now()

    readonly property bool running: entries.some((e) => {
        return isRunning(e.id);
    })
    readonly property int pending: entries.reduce((sum, e) => {
        return sum + ((checks[e.id] || {}).pending || 0);
    }, 0)
    readonly property var pendingFiles: entries.reduce((all, e) => {
        return all.concat((checks[e.id] || {}).files || []);
    }, [])
    readonly property int changedCount: entries.reduce((sum, e) => {
        const c = checks[e.id] || {};
        return sum + (c.changed !== undefined ? c.changed : (c.files || []).length);
    }, 0)
    // First entry with this last state ("error", "offline", "locked", "input"), or null
    readonly property var failedEntry: firstWith("error")
    readonly property var offlineEntry: firstWith("offline")
    readonly property var inputEntry: firstWith("input")
    readonly property bool locked: keyLocked || firstWith("locked") !== null
    // Newest successful sync (Unix seconds); failed runs do not count
    readonly property double lastTime: entries.reduce((t, e) => {
        return Math.max(t, syncedAt(e.id));
    }, 0)

    // A run of an entry ended without error (bar icon: star)
    signal finished(string id)

    function entry(id) {
        return entries.find((e) => {
            return e.id === id;
        }) || null;
    }

    function progressFile(id) {
        return SyncProgress.files[id] || null;
    }

    function isRunning(id) {
        const f = progressFile(id);
        return requested[id] !== undefined || (f !== null && f.state === "running" && Date.now() / 1000 - f.time < 7200) || (checks[id] || {}).state === "running";
    }

    // Last known state of an entry: the newer of progress file and check
    function lastState(id) {
        const f = progressFile(id);
        const c = checks[id] || {};
        if (f && f.state !== "running" && (!c.time || f.time >= c.time))
            return f.state === "2fa" ? "input" : f.state;

        return c.state || (f && f.state !== "running" ? f.state : "");
    }

    function lastMessage(id) {
        const f = progressFile(id);
        const c = checks[id] || {};
        return (f && f.state !== "running" && f.summary) ? f.summary : (c.message || "");
    }

    function finishedAt(id) {
        const f = progressFile(id);
        const c = checks[id] || {};
        return Math.max(f && f.state !== "running" ? f.time : 0, c.time || 0);
    }

    // Last successful sync of an entry: this session's progress file, a check that knows its own runs
    // (state + time) or "synced", which shiori_sync.py keeps across reboots
    function syncedAt(id) {
        const f = progressFile(id);
        const c = checks[id] || {};
        return Math.max(f && f.state === "ok" ? f.time : 0, c.synced || 0, c.time && (!c.state || c.state === "ok") ? c.time : 0);
    }

    function firstWith(state) {
        for (const e of entries) {
            if (!isRunning(e.id) && lastState(e.id) === state)
                return e;

        }
        return null;
    }

    // "x min ago" for Unix seconds ("" = unknown)
    function agoOf(t) {
        if (t <= 0)
            return "";

        const min = Math.floor((now / 1000 - t) / 60);
        if (min < 1)
            return "just now";

        if (min < 60)
            return min + " min ago";

        const h = Math.floor(min / 60);
        return h < 24 ? h + " h ago" : Math.floor(h / 24) + " d ago";
    }

    // Everything (bar icon, "Sync now")
    function sync() {
        const ids = entries.filter((e) => {
            return lastState(e.id) !== "unavailable" && !isRunning(e.id);
        }).map((e) => {
            return e.id;
        });
        // Everything is running already (second click): nothing to start
        if (ids.length === 0)
            return ;

        SyncProgress.begin(ids);
        for (const id of ids) start(id)
    }

    // Button of one row
    function syncEntry(id) {
        if (isRunning(id))
            return ;

        SyncProgress.begin([id]);
        start(id);
    }

    function start(id) {
        const r = Object.assign({}, requested);
        r[id] = Date.now();
        requested = r;
        Quickshell.execDetached(["systemd-run", "--user", "--quiet", "--no-block", "--collect", "--unit=shiori-sync-" + id, "python3", script, "run", id]);
        pollTimer.restart();
    }

    function submitInput(id, value) {
        if (inputBusy !== "" || value === "")
            return ;

        const errs = Object.assign({}, inputErrors);
        delete errs[id];
        inputErrors = errs;
        inputBusy = id;
        inputProc.value = value;
        inputProc.command = ["python3", script, "input", id];
        inputProc.running = true;
    }

    function check() {
        if (!checkProc.running && hasEntries) {
            checkProc.command = ["sh", "-c", "s=\"$1\"; shift; for id; do printf '\\036%s\\n' \"$id\"; python3 \"$s\" check \"$id\"; done", "sync-check", script].concat(entries.map((e) => {
                return e.id;
            }));
            checkProc.running = true;
        }
        if (entries.some((e) => {
            return e.sshKey;
        }) && !keyCheckProc.running)
            keyCheckProc.running = true;

    }

    function onChecks(text) {
        const out = {};
        for (const chunk of text.split("\u001e")) {
            const nl = chunk.indexOf("\n");
            if (nl <= 0)
                continue;

            try {
                out[chunk.slice(0, nl)] = JSON.parse(chunk.slice(nl + 1));
            } catch (e) {
            }
        }
        checks = out;
    }

    // Requests are done once the unit has written a progress file for this run (or after 20 s)
    function settleRequests() {
        let changed = false;
        const r = Object.assign({}, requested);
        for (const id in r) {
            const f = progressFile(id);
            if ((f && f.run * 1000 >= r[id] - 2000) || Date.now() - r[id] > 20000) {
                delete r[id];
                changed = true;
            }
        }
        if (changed)
            requested = r;

    }

    Component.onCompleted: listProc.running = true
    onRunningChanged: {
        if (!running)
            check();

    }

    // Settings changed (entries edited): list again
    Connections {
        function onDataChanged() {
            listProc.running = true;
        }

        target: Settings
    }

    Connections {
        function onFilesChanged() {
            const before = root.lastStates;
            const now = {};
            for (const e of root.entries) {
                const f = root.progressFile(e.id);
                now[e.id] = f ? f.state + ":" + f.run : "";
                if (before[e.id] !== undefined && before[e.id] !== now[e.id] && f && f.state === "ok")
                    root.finished(e.id);

            }
            root.lastStates = now;
            root.settleRequests();
        }

        target: SyncProgress
    }

    property var lastStates: ({})

    Process {
        id: listProc

        command: ["python3", root.script, "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.entries = JSON.parse(text);
                } catch (e) {
                    root.entries = [];
                }
                root.check();
            }
        }

    }

    Process {
        id: checkProc

        stdout: StdioCollector {
            onStreamFinished: root.onChecks(text)
        }

    }

    Process {
        id: keyCheckProc

        // A sync entry with "sshKey": "<path>" brings its own key (ssh-unlock.sh reads SSH_UNLOCK_KEY), otherwise
        // the agent's usual keys are checked
        readonly property string syncKey: {
            for (const e of root.entries) {
                if (typeof e.sshKey === "string" && e.sshKey !== "")
                    return e.sshKey;

            }
            return "";
        }

        command: [root.unlockScript, "--check"]
        environment: syncKey !== "" ? ({
            "SSH_UNLOCK_KEY": syncKey
        }) : ({
        })
        onExited: (code) => {
            root.keyLocked = code !== 0;
        }
    }

    Process {
        id: inputProc

        property string value: ""

        stdinEnabled: true
        // The pipe stays open after the write, so the script reads exactly one line (not until the end of the input)
        onStarted: {
            write(value + "\n");
            value = "";
        }
        onExited: (code) => {
            const id = root.inputBusy;
            root.inputBusy = "";
            if (code === 0) {
                root.start(id);
            } else {
                const errs = Object.assign({}, root.inputErrors);
                errs[id] = code === 75 ? "Try again shortly" : "Try a fresh code";
                root.inputErrors = errs;
            }
        }
    }

    // While syncing check every second for the unit, otherwise every 30 s ("x min ago")
    Timer {
        id: pollTimer

        interval: root.running ? 1000 : 30000
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now();
            root.settleRequests();
        }
    }

    // Count local changes every 5 min (fast, no network); not while the icon is hidden (edit mode)
    Timer {
        interval: 5 * 60 * 1000
        running: root.hasEntries && BarIcons.shown("sync")
        repeat: true
        onTriggered: root.check()
    }

}
