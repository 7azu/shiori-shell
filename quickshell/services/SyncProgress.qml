import "../common/Format.js" as Fmt
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Progress of the sync entries for the expanded sync dropdown (dropdowns/SyncContent.qml).
// The sync scripts report step, files and result via scripts/sync_progress.py to
// $XDG_RUNTIME_DIR/sync-progress/<id>.json; rclone entries also give live values over their
// remote-control socket (core/stats + core/transferred, entry field rcSocket).
// Read often while a sync runs, results still show or the dropdown is open, otherwise every 30 s.
//
// infos[id] = object for the row:
//   phase     idle (collapsed) | queued (waiting) | running | done (result, shows for a moment)
//   tone      accent | good | warn | bad
//   label     text on the left (step or result), detail = on the right (counter, speed)
//   progress  0..1, -1 = unknown (moving bar)
//   files     up to three lines {dir: up|down, name, kind (git status, D = deleted), pct (-1 = none), done}
//   more      further files besides the shown ones
QtObject {
    id: root

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property var idle: ({
        "phase": "idle"
    })
    readonly property int shownFiles: 3
    // Results stay expanded this long after the last entry finished
    readonly property int lingerMs: 10000
    property var infos: ({})
    readonly property bool anyActive: Object.values(infos).some((p) => {
        return p.phase !== "idle";
    })
    readonly property bool busy: Object.values(infos).some((p) => {
        return p.phase === "queued" || p.phase === "running";
    })
    // Start of the session (Unix seconds, 0 = none): results from then on count as fresh.
    // By a click (begin) or automatically once a run from a timer/login is seen.
    property double since: 0
    // Started by a click: entries that have not begun yet wait (queued)
    property bool clicked: false
    property var clickedIds: []
    // Last read state: progress files by id, rclone stats/transferred by id
    property var files: ({})
    property var stats: ({})
    property var transferred: ({})
    // rclone transfers of the current run per id (key source|name): done, seen, failed
    property var rcloneDone: ({})
    property var rcloneSeen: ({})
    property var rcloneFailed: ({})
    property var rcloneRun: ({})
    readonly property bool watching: SyncState.running || anyActive || DropdownState.current === "sync"
    readonly property bool liveStats: Object.keys(stats).length > 0
    property Process pollProc
    property Timer pollTimer
    property Timer lingerTimer

    function info(id) {
        return infos[id] || idle;
    }

    // From the sync button or a row button: expand the started entries as waiting right away
    function begin(ids) {
        since = Date.now() / 1000 - 2;
        clicked = true;
        clickedIds = ids;
        lingerTimer.stop();
        recompute();
        poll();
    }

    function poll() {
        if (pollProc.running || !SyncState.hasEntries)
            return ;

        const args = [];
        for (const e of SyncState.entries) args.push(e.id, e.rcSocket || "")
        pollProc.command = ["sh", "-c", "d=\"${XDG_RUNTIME_DIR:-/tmp}/sync-progress\"; " + "while [ $# -gt 1 ]; do id=$1; s=$2; shift 2; " + "printf '\\036file:%s\\n' \"$id\"; cat \"$d/$id.json\" 2>/dev/null; echo; " + "if [ -n \"$s\" ] && [ -S \"$s\" ]; then " + "printf '\\036stats:%s\\n' \"$id\"; curl -s -m 1 --unix-socket \"$s\" -X POST http://localhost/core/stats; echo; " + "printf '\\036transferred:%s\\n' \"$id\"; curl -s -m 1 --unix-socket \"$s\" -X POST http://localhost/core/transferred; echo; fi; done", "sync-poll"].concat(args);
        pollProc.running = true;
    }

    function fresh(f) {
        if (!f || !f.run)
            return false;

        const now = Date.now() / 1000;
        // Stale file (script killed): no longer counts as running after 2 h
        if (f.state === "running")
            return now - f.time < 7200;

        return since > 0 && f.time >= since;
    }

    function queued(label) {
        return {
            "phase": "queued",
            "tone": "accent",
            "label": label,
            "detail": "",
            "progress": -1,
            "files": [],
            "more": 0
        };
    }

    function countText(up, down) {
        const parts = [];
        if (up > 0)
            parts.push(up + " uploaded");

        if (down > 0)
            parts.push(down + " downloaded");

        return parts.length ? parts.join(" · ") : "Up to date";
    }

    function toneOf(state) {
        return state === "ok" ? "good" : (state === "error" ? "bad" : "warn");
    }

    function doneLabel(f, fallback) {
        if (f.state === "offline")
            return f.summary || "Unreachable";

        if (f.state === "2fa" || f.state === "input")
            return "Sign-in needed";

        if (f.state === "locked")
            return "SSH key locked";

        return fallback;
    }

    // git-like entries: steps, files per direction, result
    function gitInfo(f, waiting) {
        if (!fresh(f))
            return waiting ? queued("Starting") : idle;

        const list = (f.up || []).map((e) => {
            return {
                "dir": "up",
                "kind": e[0],
                "name": e[1],
                "pct": -1,
                "done": false
            };
        }).concat((f.down || []).map((e) => {
            return {
                "dir": "down",
                "kind": e[0],
                "name": e[1],
                "pct": -1,
                "done": false
            };
        }));
        const total = (f.upCount || 0) + (f.downCount || 0);
        const shown = list.slice(0, shownFiles);
        const info = {
            "files": shown,
            "more": Math.max(0, total - shown.length)
        };
        if (f.state === "running") {
            const inStep = f.pct >= 0 ? f.pct / 100 : 0;
            info.phase = "running";
            info.tone = "accent";
            info.label = f.label || "Starting";
            info.detail = f.detail || "";
            info.progress = f.steps > 0 ? Math.max(0, Math.min(1, (Math.max(1, f.step) - 1 + inStep) / f.steps)) : -1;
        } else {
            info.phase = "done";
            info.tone = toneOf(f.state);
            info.label = f.state === "ok" ? countText(f.upCount || 0, f.downCount || 0) : doneLabel(f, f.summary || "Failed");
            info.detail = "";
            info.progress = 1;
        }
        return info;
    }

    // rclone entries: folder from the file, files/percent/speed from rclone
    function rcloneInfo(id, f, waiting) {
        if (!fresh(f))
            return waiting ? queued(SyncState.inputBusy === id ? "Signing in" : "Starting") : idle;

        if (f.run !== rcloneRun[id]) {
            rcloneRun[id] = f.run;
            rcloneDone[id] = {};
            rcloneSeen[id] = {};
            rcloneFailed[id] = {};
        }
        const st = stats[id] || null;
        const tr = transferred[id] || [];
        // Local paths start with /, the remote is e.g. "proton{abc}:Music/"
        const isUp = (t) => {
            return String(t.srcFs || "").startsWith("/");
        };
        const keyOf = (t) => {
            return (t.srcFs || "") + "|" + t.name;
        };
        const doneMap = rcloneDone[id] || {};
        const seen = rcloneSeen[id] || {};
        const failed = rcloneFailed[id] || {};
        for (const t of tr) {
            if (t.checked || t.what === "checking" || !t.name)
                continue;

            if (t.error) {
                failed[keyOf(t)] = true;
                continue;
            }
            doneMap[keyOf(t)] = {
                "dir": isUp(t) ? "up" : "down",
                "name": t.name,
                "at": t.completed_at || ""
            };
        }
        const activeNow = st && st.transferring ? st.transferring : [];
        const activeKeys = {};
        for (const t of activeNow) {
            activeKeys[keyOf(t)] = true;
            seen[keyOf(t)] = {
                "dir": isUp(t) ? "up" : "down",
                "name": t.name
            };
        }
        // Gone without being reported as done: the folder or run is over (no socket any more or rclone
        // restarted). Not counted as success when the run failed.
        for (const key in seen) {
            if (activeKeys[key] || doneMap[key] || failed[key])
                continue;

            if (!st || !tr.some((t) => {
                return keyOf(t) === key;
            })) {
                if (f.state === "error")
                    continue;

                doneMap[key] = {
                    "dir": seen[key].dir,
                    "name": seen[key].name,
                    "at": new Date().toISOString()
                };
            }
        }
        rcloneDone[id] = doneMap;
        rcloneSeen[id] = seen;
        rcloneFailed[id] = failed;
        const finished = Object.values(doneMap).sort((a, b) => {
            return a.at < b.at ? 1 : -1;
        });
        const running = f.state === "running";
        const s = running ? st : null;
        const active = (s && s.transferring ? s.transferring : []).map((t) => {
            return {
                "dir": isUp(t) ? "up" : "down",
                "kind": "",
                "name": t.name,
                "pct": t.percentage || 0,
                "done": false
            };
        });
        const list = active.concat(finished.filter((d) => {
            return !active.some((a) => {
                return a.name === d.name;
            });
        }).map((d) => {
            return {
                "dir": d.dir,
                "kind": "",
                "name": d.name,
                "pct": -1,
                "done": true
            };
        }));
        const shown = list.slice(0, shownFiles);
        const info = {
            "files": shown,
            "more": Math.max(0, list.length - shown.length)
        };
        if (running) {
            const folder = f.label || "";
            const of = f.steps > 1 && f.step > 0 ? "  " + f.step + "/" + f.steps : "";
            info.phase = "running";
            info.tone = "accent";
            info.progress = s && s.totalBytes > 0 ? Math.min(1, s.bytes / s.totalBytes) : -1;
            if (f.step <= 0) {
                info.label = "Connecting";
                info.detail = "";
            } else if (s && (s.totalTransfers > 0 || active.length > 0)) {
                info.label = "Syncing " + folder + of;
                info.detail = s.transfers + "/" + s.totalTransfers + " files" + (s.speed > 1024 ? " · " + Fmt.bytes(s.speed) + "/s" : "");
            } else {
                info.label = "Comparing " + folder + of;
                info.detail = s && s.listed > 0 ? s.listed.toLocaleString(Qt.locale("en_US"), "f", 0) + " files" : "";
            }
        } else {
            const up = finished.filter((d) => {
                return d.dir === "up";
            }).length;
            info.phase = "done";
            info.tone = toneOf(f.state);
            info.progress = 1;
            info.detail = "";
            if (f.state === "error")
                info.label = "Sync failed" + (finished.length ? " · " + countText(up, finished.length - up) : "");
            else
                info.label = doneLabel(f, countText(up, finished.length - up));
        }
        return info;
    }

    function recompute() {
        const d = files;
        // Runs from a timer/login without a click: treat as a session from their start
        if (since === 0) {
            for (const id in d) {
                const f = d[id];
                if (f && f.state === "running" && fresh(f))
                    since = Math.min(since || f.run, f.run) - 1;

            }
        }
        const out = {};
        for (const e of SyncState.entries) {
            const waiting = clicked && clickedIds.includes(e.id) && SyncState.isRunning(e.id);
            out[e.id] = e.kind === "rclone" ? rcloneInfo(e.id, d[e.id], waiting) : gitInfo(d[e.id], waiting);
        }
        infos = out;
        if (busy)
            lingerTimer.stop();
        else if (anyActive && !lingerTimer.running)
            lingerTimer.restart();
    }

    function onPoll(text) {
        const d = {};
        const s = {};
        const t = {};
        for (const chunk of text.split("\u001e")) {
            const nl = chunk.indexOf("\n");
            if (nl <= 0)
                continue;

            const head = chunk.slice(0, nl);
            const body = chunk.slice(nl + 1).trim();
            if (body === "")
                continue;

            const colon = head.indexOf(":");
            const what = head.slice(0, colon);
            const id = head.slice(colon + 1);
            let value = null;
            try {
                value = JSON.parse(body);
            } catch (e) {
                continue;
            }
            if (what === "stats")
                s[id] = value;
            else if (what === "transferred")
                t[id] = value.transferred || [];
            else
                d[id] = value;
        }
        files = d;
        stats = s;
        transferred = t;
        recompute();
    }

    // Re-evaluate right away when a sync starts or ends
    property Connections syncConn: Connections {
        // callLater: running depends on files itself -> computing directly would be a binding loop
        function onRunningChanged() {
            Qt.callLater(root.recompute);
            root.poll();
        }

        function onEntriesChanged() {
            root.poll();
        }

        target: SyncState
    }

    pollProc: Process {
        stdout: StdioCollector {
            onStreamFinished: root.onPoll(text)
        }

    }

    // During transfers twice a second, while syncing every second, dropdown open every 2 s, else every 30 s
    pollTimer: Timer {
        interval: root.liveStats ? 500 : (root.busy || root.anyActive || SyncState.running ? 1000 : (root.watching ? 2000 : 30000))
        // With the icon hidden (edit mode) only while a sync runs or the dropdown is open
        running: SyncState.hasEntries && (BarIcons.shown("sync") || root.watching)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    lingerTimer: Timer {
        interval: root.lingerMs
        onTriggered: {
            root.since = 0;
            root.clicked = false;
            root.recompute();
        }
    }

}
