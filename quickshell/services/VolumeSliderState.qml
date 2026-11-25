import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
pragma Singleton

QtObject {
    id: root

    property bool open: false
    // The mouse was moved over the popup. If it only happens to sit where the popup opens, that does not count:
    // otherwise it would stay open after turning the knob until you move the mouse away
    property bool hovered: false
    property bool draggingSystem: false
    property bool expanded: false
    // How long the popup stays open depending on the intent: a key press only wants to see the value, whoever
    // opens it by hand wants to adjust something, and whoever moves the mouse away is done
    readonly property int keyLinger: 1200
    readonly property int manualLinger: 3500
    readonly property int doneLinger: 800
    readonly property int mixerLinger: 2500
    readonly property bool busy: hovered || draggingSystem || draggingGroupKey !== ""
    // ==== System-Volume (0..1) ====
    property real systemVolume: 0
    property bool systemMuted: false
    // ==== Active audio streams (grouped by app) ====
    // Each: { key, name, subtitle, icon, volume, muted, ids: [int] }
    property var streams: []
    // Key of the group being dragged right now (the poll must not overwrite it)
    property string draggingGroupKey: ""
    property var _pendingStreamVol: null
    property var _pendingSystemVol: null
    // Pending key steps (volume knob) while stepProc is still running
    property real _pendingStep: 0
    // Time of the last local change (dragging the slider): shortly after, PipeWire sometimes still
    // reports the old value, the orb/slider then jumped back and forth again
    property double _lastLocalSet: 0
    // Volume and mute come directly from PipeWire (changes are reported). Before,
    // `wpctl get-volume` ran every second, five times per second with the popup open.
    // Setting still goes through wpctl (-l 1.0 hard-limits the key steps to 100 %).
    readonly property PwNode sink: Pipewire.defaultAudioSink
    property PwObjectTracker sinkTracker
    property Connections sinkWatch
    property Timer settleTimer
    // ==== Steam detection (same logic as in Workspaces.qml) ====
    property var steamNames: ({
    })
    // appid -> Titel
    property var steamCompactMap: ({
    })
    // Title without spaces/special characters -> appid
    property var steamIconMap: ({
    })
    // appid -> file://-URL
    property var pidAppIds: ({
    })
    // pid -> appid ("" = none found)
    property var _pidQueue: []
    property var _pidPending: ({
    })
    property var _rescanned: ({
    })
    property var _tmpNames: ({
    })
    property var _tmpCompact: ({
    })
    property var _tmpIcons: ({
    })
    property double lastScan: Date.now()
    // Group key -> resolved icon: once found, it stays (no theme/desktop search every
    // 800 ms and no change of source that would reload the image). Not for Steam groups, their
    // icon may still change from the Steam logo to the game icon after the Steam scan
    property var _iconCache: ({
    })
    readonly property string scanScript: Qt.resolvedUrl("../scripts/steam_scan.sh").toString().replace("file://", "")
    property Timer autoCloseTimer
    property Timer streamsRefreshTimer
    property Process setProc
    property Process muteProc
    property Process stepProc
    property Process getStreamsProc
    property Process setStreamVolProc
    property Process muteStreamProc
    property Process steamScan
    property Process pidProc

    // ==== Steam-Hilfsfunktionen ====
    function compactTitle(t) {
        return String(t || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
    }

    // Theme icon only if it really exists (otherwise "")
    function themeIconUrl(name) {
        if (!name)
            return "";

        try {
            if (Quickshell.iconPath(name, true) !== "")
                return "image://icon/" + name;

        } catch (e) {
        }
        return "";
    }

    function requestRescan() {
        if (steamScan.running || Date.now() - lastScan < 15000)
            return ;

        lastScan = Date.now();
        _tmpNames = ({
        });
        _tmpCompact = ({
        });
        _tmpIcons = ({
        });
        steamScan.running = true;
    }

    // Steam sets SteamGameId/SteamAppId in the environment of the started command.
    // We read them asynchronously from /proc/<pid>/environ. The first call returns "",
    // the next stream poll sees the cached result.
    function steamIdFromPid(pid) {
        const p = parseInt(pid);
        if (!p || p <= 0)
            return "";

        const key = String(p);
        if (pidAppIds[key] !== undefined)
            return pidAppIds[key];

        if (!_pidPending[key]) {
            _pidPending[key] = true;
            _pidQueue.push(key);
            processPidQueue();
        }
        return "";
    }

    function processPidQueue() {
        if (pidProc.running || _pidQueue.length === 0)
            return ;

        const pid = _pidQueue.shift();
        pidProc.command = ["bash", "-c", "echo \"$1|$(tr '\\0' '\\n' < /proc/$1/environ 2>/dev/null | grep -m1 -E '^(SteamGameId|SteamAppId)=[0-9]+')\"", "_", pid];
        pidProc.running = true;
    }

    // Fuzzy comparison: the Steam name is contained in the (exe) name
    function steamIdByFuzzy(ct) {
        if (ct === "")
            return "";

        let best = "";
        let bestLen = 0;
        for (const k in steamCompactMap) {
            if (k.length >= 4 && k.length > bestLen && ct.indexOf(k) !== -1) {
                best = steamCompactMap[k];
                bestLen = k.length;
            }
        }
        return best;
    }

    // Steam appid for a sink input: 1) steam_icon_<id>, 2) process environment
    // (also with gamescope/Proton), 3) name == Steam title, 4) Wine exe name
    function steamIdFor(props) {
        const iconName = String(props["application.icon_name"] || "");
        const m = iconName.match(/^steam_icon_(\d+)$/);
        if (m)
            return m[1];

        const byPid = steamIdFromPid(props["application.process.id"]);
        if (byPid)
            return byPid;

        const names = [props["application.name"], props["media.name"]];
        for (const n of names) {
            const ct = compactTitle(n);
            if (ct !== "" && steamCompactMap[ct])
                return steamCompactMap[ct];

        }
        const bin = String(props["application.process.binary"] || "") + " " + String(props["application.name"] || "");
        if (/\.exe|win64|win32/i.test(bin))
            return steamIdByFuzzy(compactTitle(bin.replace(/-win(64|32)-shipping|\.exe/gi, "")));

        return "";
    }

    // Order: theme icon steam_icon_<id> -> cached image -> Steam logo
    function steamIconFor(id) {
        const t = themeIconUrl("steam_icon_" + id);
        if (t)
            return t;

        if (steamIconMap[id])
            return steamIconMap[id];

        if (!_rescanned[id]) {
            _rescanned[id] = true;
            requestRescan();
        }
        return themeIconUrl("steam");
    }

    // ==== Icon resolution ====
    // Always returns a string: the ListModel in the popup fixes the type of the role "icon" at the first entry.
    // If a url (Qt.resolvedUrl) came later instead of a string, it rejected every update
    // ("Can't assign to existing role 'icon' of different type") and the icon got stuck
    function resolveIcon(props, steamId) {
        // Steam game (also behind gamescope)
        if (steamId) {
            const si = steamIconFor(steamId);
            if (si)
                return si;

        }
        const cands = [];
        const push = (s) => {
            if (s === undefined || s === null)
                return ;

            const t = String(s).trim();
            if (t === "")
                return ;

            cands.push(t);
            const stripped = t.replace(/(-bin|-wrapped|-stable)$/i, "");
            if (stripped !== t)
                cands.push(stripped);

        };
        push(props["application.icon_name"]);
        push(props["application.process.binary"]);
        push(props["application.id"]);
        push(props["application.name"]);
        push(props["node.name"]);
        // Discord (also Vesktop & co.) -> the normal Discord icon
        for (const c of cands) {
            if (/vesktop|discord|webcord|armcord|legcord|equibop/i.test(c) && Settings.icon("discord") !== "")
                return Settings.icon("discord");

        }
        try {
            for (const c of cands) {
                const variants = [c, c.toLowerCase(), c.toLowerCase().replace(/\s+/g, "-")];
                for (const v of variants) {
                    if (Quickshell.iconPath(v, true) !== "")
                        return "image://icon/" + v;

                }
            }
            for (const c of cands) {
                const e = DesktopEntries.heuristicLookup(c);
                if (e && e.icon) {
                    if (e.icon.startsWith("/"))
                        return "file://" + e.icon;

                    if (Quickshell.iconPath(e.icon, true) !== "")
                        return "image://icon/" + e.icon;

                }
            }
        } catch (err) {
            console.warn("[VolumeSliderState] icon lookup failed:", err);
        }
        // Own icons from the settings, matched as part of the name (e.g. "youtube" in a browser stream)
        for (const c of cands) {
            const l = c.toLowerCase();
            for (const key of Settings.iconKeys()) {
                if (l.indexOf(key) !== -1)
                    return Settings.icon(key);

            }
        }
        return "";
    }

    function cachedIcon(key, props, steamId) {
        if (steamId)
            return resolveIcon(props, steamId);

        const hit = _iconCache[key];
        if (hit)
            return hit;

        const icon = resolveIcon(props, steamId);
        if (icon)
            _iconCache[key] = icon;

        return icon;
    }

    // ==== Group key for a sink input ====
    // All streams of the same app land in one group.
    function groupKeyFor(props) {
        const name = (props["application.name"] || "").toLowerCase().trim();
        if (name !== "")
            return "app:" + name;

        const bin = (props["application.process.binary"] || "").toLowerCase().trim();
        if (bin !== "")
            return "bin:" + bin;

        const node = (props["node.name"] || "").toLowerCase().trim();
        if (node !== "")
            return "node:" + node;

        return "unknown";
    }

    // ==== Open/close the popup ====
    function toggle() {
        if (open)
            close();
        else
            openPopup();
    }

    function openPopup() {
        _show(expanded ? mixerLinger : manualLinger);
    }

    function _show(linger) {
        open = true;
        _closeIn(linger);
        syncFromSink();
        // Fetch the streams already when opening (not only when expanding): then the list and
        // icons are ready before the mixer opens, instead of showing letters first and then the icons
        if (!getStreamsProc.running)
            getStreamsProc.running = true;

    }

    function close() {
        open = false;
        hovered = false;
        expanded = false;
        draggingGroupKey = "";
        autoCloseTimer.stop();
    }

    function _closeIn(ms) {
        autoCloseTimer.interval = ms;
        autoCloseTimer.restart();
    }

    // After every interaction in the popup
    function restartAutoClose() {
        _closeIn(expanded ? mixerLinger : doneLinger);
    }

    function toggleExpanded() {
        expanded = !expanded;
        restartAutoClose();
        if (expanded)
            getStreamsProc.running = true;

    }

    // ==== System volume ====
    // Take the value from PipeWire. During knob steps and while dragging, do not jump back with an
    // old value: then the local value counts, settleTimer syncs once afterwards.
    function syncFromSink() {
        const a = sink ? sink.audio : null;
        if (!a)
            return ;

        const settling = setProc.running || _pendingSystemVol !== null || Date.now() - _lastLocalSet < 600;
        if (!stepProc.running && _pendingStep === 0 && !settling && Number.isFinite(a.volume))
            systemVolume = Math.max(0, Math.min(1, a.volume));

        systemMuted = a.muted;
    }

    function _runSystemVol(v) {
        setProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(3)];
        setProc.running = true;
    }

    function setSystemVolume(val) {
        const safeVal = Math.max(0, Math.min(val, 1));
        root.systemVolume = safeVal;
        _lastLocalSet = Date.now();
        settleTimer.restart();
        if (setProc.running)
            _pendingSystemVol = safeVal;
        else
            _runSystemVol(safeVal);
    }

    // Volume keys / volume knob: show the popup and change relatively.
    // wpctl -l 1.0 hard-limits to 100 %, even if the local value is outdated.
    function _runStep(delta) {
        const pct = Math.round(Math.abs(delta) * 100) + "%" + (delta > 0 ? "+" : "-");
        stepProc.command = ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", pct];
        stepProc.running = true;
    }

    function stepSystemVolume(delta) {
        // Do not shorten with the mixer open: you are looking at something there right now
        if (open)
            _closeIn(expanded ? mixerLinger : keyLinger);
        else
            _show(keyLinger);
        root.systemVolume = Math.max(0, Math.min(1, root.systemVolume + delta));
        if (stepProc.running)
            _pendingStep += delta;
        else
            _runStep(delta);
    }

    function toggleSystemMute() {
        root.systemMuted = !root.systemMuted;
        muteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", root.systemMuted ? "1" : "0"];
        muteProc.running = true;
    }

    // ==== Stream actions (work on groups) ====
    function _findGroup(key) {
        for (let i = 0; i < streams.length; i++) {
            if (streams[i].key === key)
                return streams[i];

        }
        return null;
    }

    function _patchStream(key, patch) {
        const arr = streams.slice();
        for (let i = 0; i < arr.length; i++) {
            if (arr[i].key === key) {
                arr[i] = Object.assign({
                }, arr[i], patch);
                break;
            }
        }
        streams = arr;
    }

    // Sets the volume for all streams of a group at once.
    function _runStreamVol(ids, val) {
        const pct = Math.round(val * 100) + "%";
        // pactl only knows one sink input per call -> bash loop.
        const cmds = ids.map((id) => {
            return "pactl set-sink-input-volume " + id + " " + pct;
        }).join("; ");
        setStreamVolProc.command = ["bash", "-c", cmds];
        setStreamVolProc.running = true;
    }

    function setStreamVolume(key, val) {
        const safeVal = Math.max(0, Math.min(val, 1));
        const group = _findGroup(key);
        if (!group)
            return ;

        if (setStreamVolProc.running)
            _pendingStreamVol = {
            "key": key,
            "val": safeVal
        };
        else
            _runStreamVol(group.ids, safeVal);
        _patchStream(key, {
            "volume": safeVal
        });
    }

    // Toggles mute for all streams of a group.
    function _runStreamMute(ids, muteOn) {
        const arg = muteOn ? "1" : "0";
        const cmds = ids.map((id) => {
            return "pactl set-sink-input-mute " + id + " " + arg;
        }).join("; ");
        muteStreamProc.command = ["bash", "-c", cmds];
        muteStreamProc.running = true;
    }

    function toggleStreamMute(key) {
        const group = _findGroup(key);
        if (!group)
            return ;

        const newMuted = !group.muted;
        _runStreamMute(group.ids, newMuted);
        _patchStream(key, {
            "muted": newMuted
        });
    }

    onSinkChanged: syncFromSink()

    // Without a tracker PipeWire gives no volume for the node
    sinkTracker: PwObjectTracker {
        objects: [root.sink]
    }

    sinkWatch: Connections {
        function onVolumeChanged() {
            root.syncFromSink();
        }

        function onMutedChanged() {
            root.syncFromSink();
        }

        target: root.sink ? root.sink.audio : null
    }

    // After the last drag sync once with the real value (notifications in the meantime
    // are dropped, see syncFromSink)
    settleTimer: Timer {
        interval: 700
        onTriggered: root.syncFromSink()
    }

    setProc: Process {
        onRunningChanged: {
            if (!running && root._pendingSystemVol !== null) {
                const v = root._pendingSystemVol;
                root._pendingSystemVol = null;
                root._runSystemVol(v);
            }
        }
    }

    muteProc: Process {
    }

    stepProc: Process {
        onRunningChanged: {
            if (running)
                return ;

            if (root._pendingStep !== 0) {
                const d = root._pendingStep;
                root._pendingStep = 0;
                root._runStep(d);
            } else {
                // The PipeWire notification can arrive just after the process ends
                root.syncFromSink();
                root.settleTimer.restart();
            }
        }
    }

    // Steam titles and icons (scripts/steam_scan.sh), once at start
    steamScan: Process {
        command: ["bash", root.scanScript]
        running: true
        onExited: (exitCode, exitStatus) => {
            root.steamNames = root._tmpNames;
            root.steamCompactMap = root._tmpCompact;
            root.steamIconMap = root._tmpIcons;
            if (!root.getStreamsProc.running && root.open && root.expanded)
                root.getStreamsProc.running = true;

        }

        stdout: SplitParser {
            onRead: (data) => {
                const parts = data.split("|");
                if (parts.length < 3)
                    return ;

                const kind = parts[0];
                const appId = parts[1].trim();
                const rest = parts.slice(2).join("|").trim();
                if (!appId || !rest)
                    return ;

                if (kind === "T") {
                    root._tmpNames[appId] = rest;
                    const c = root.compactTitle(rest);
                    if (c !== "")
                        root._tmpCompact[c] = appId;

                } else if (kind === "I") {
                    root._tmpIcons[appId] = "file://" + rest;
                }
            }
        }

    }

    // Reads SteamGameId/SteamAppId from /proc/<pid>/environ (one process after another)
    pidProc: Process {
        onRunningChanged: {
            if (!running)
                root.processPidQueue();

        }

        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim();
                const idx = line.indexOf("|");
                if (idx === -1)
                    return ;

                const pid = line.substring(0, idx);
                const m = line.substring(idx + 1).match(/=(\d+)/);
                const copy = Object.assign({
                }, root.pidAppIds);
                copy[pid] = (m && m[1] !== "0") ? m[1] : "";
                root.pidAppIds = copy;
                delete root._pidPending[pid];
                // Read again right away, so the Steam icon appears without delay
                if (copy[pid] !== "" && !root.getStreamsProc.running)
                    root.getStreamsProc.running = true;

            }
        }

    }

    getStreamsProc: Process {
        command: ["pactl", "-f", "json", "list", "sink-inputs"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const groups = {
                    };
                    for (const item of data) {
                        const props = item.properties || {
                        };
                        // Steam game? Then group by appid and show the Steam title.
                        const sid = root.steamIdFor(props);
                        const key = sid !== "" ? "steam:" + sid : root.groupKeyFor(props);
                        const steamName = sid !== "" ? (root.steamNames[sid] || "") : "";
                        const appName = steamName || props["application.name"] || props["media.name"] || "Unknown";
                        const mediaName = sid !== "" ? "" : (props["media.name"] || "");
                        let vol = 0.5;
                        if (item.volume) {
                            const ch = Object.keys(item.volume)[0];
                            if (ch && item.volume[ch] && item.volume[ch].value_percent)
                                vol = parseFloat(item.volume[ch].value_percent) / 100;

                        }
                        if (!groups[key])
                            groups[key] = {
                            "key": key,
                            "name": appName,
                            "subtitle": mediaName !== appName ? mediaName : "",
                            "icon": root.cachedIcon(key, props, sid),
                            "ids": [],
                            "vols": [],
                            "mutedCount": 0,
                            "total": 0
                        };

                        const g = groups[key];
                        g.ids.push(item.index);
                        g.vols.push(vol);
                        g.total += 1;
                        if (item.mute)
                            g.mutedCount += 1;

                    }
                    const arr = [];
                    for (const k in groups) {
                        const g = groups[k];
                        // Average volume, but if the group is being
                        // dragged right now, keep the local value.
                        let avg = 0;
                        if (g.vols.length > 0) {
                            for (const v of g.vols) avg += v
                            avg = avg / g.vols.length;
                        }
                        if (k === root.draggingGroupKey) {
                            const existing = root._findGroup(k);
                            if (existing)
                                avg = existing.volume;

                        }
                        // Only counts as "muted" if ALL streams are muted.
                        const allMuted = g.mutedCount === g.total;
                        // Subtitle: with several streams show "N streams".
                        let subtitle = g.subtitle;
                        if (g.total > 1)
                            subtitle = g.total + " streams";

                        arr.push({
                            "key": g.key,
                            "name": g.name,
                            "subtitle": subtitle,
                            "icon": g.icon,
                            "volume": avg,
                            "muted": allMuted,
                            "ids": g.ids
                        });
                    }
                    arr.sort((a, b) => {
                        if (a.ids.length === 0 || b.ids.length === 0)
                            return 0;

                        return a.ids[0] - b.ids[0];
                    });
                    root.streams = arr;
                } catch (e) {
                    console.error("[VolumeSliderState] Failed to parse pactl output:", e);
                    root.streams = [];
                }
            }
        }

    }

    setStreamVolProc: Process {
        onRunningChanged: {
            if (!running && root._pendingStreamVol !== null) {
                const p = root._pendingStreamVol;
                root._pendingStreamVol = null;
                const group = root._findGroup(p.key);
                if (group)
                    root._runStreamVol(group.ids, p.val);

            }
        }
    }

    muteStreamProc: Process {
    }

    // While busy holds, the timer does not go on waiting: the end of busy restarts it
    onBusyChanged: {
        if (busy)
            autoCloseTimer.stop();
        else if (open)
            restartAutoClose();
    }

    // ==== Timer ====
    autoCloseTimer: Timer {
        interval: root.manualLinger
        onTriggered: {
            if (!root.busy)
                root.close();

        }
    }

    streamsRefreshTimer: Timer {
        // Paused during a drag, so the slider does not jump.
        interval: 800
        running: root.expanded && root.open && root.draggingGroupKey === ""
        repeat: true
        onTriggered: {
            if (!getStreamsProc.running)
                getStreamsProc.running = true;

        }
    }

}
