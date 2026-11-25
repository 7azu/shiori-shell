import "../common"
import "../services"
import "./parts"
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Task manager in the look of the clipboard picker (same size, intro, scroll physics,
// search, segmented control, card strip + list, keyboard nav).
//
//  • Search       : filters by app name, window title and class
//  • Segmented    : sorting  Recent (last used) · CPU (usage descending) · RAM (memory descending)
//  • Cards        : one card per workspace (number, window count, app icons)
//                   Click/Enter = filter the list to this workspace (again = clear)
//                   Right-click/Shift+Enter = jump to that workspace
//  • List         : Click/Shift+Enter = focus the window · Enter/middle click/Ctrl+D = close
//                   Ctrl+Shift+D or Shift+click on ✕ = kill the process hard (kill -9)
//  • Recent       : only windows that are really open (mapped)
//  • CPU / RAM    : window apps (incl. child processes) AND all background processes,
//                   grouped by program, updated every 2.5 s (from /proc/*/stat).
//                   CPU = share of the whole CPU (all cores = 100 %) since the last measurement
//  • Close        : the window is closed cleanly. If the app keeps running invisibly afterwards
//                   (tray, e.g. Discord), its whole process tree is ended.
//  • Hyprland     : dispatches go through Lua (hyprctl dispatch 'hl.dsp...')
Item {
    id: root

    // ───────────────────────── Layout constants (same as the clipboard) ─────────────────────────
    readonly property real pad: 16
    readonly property real bleed: 8
    readonly property real cardSize: 120
    readonly property real cardGap: 12
    readonly property real cardStride: cardSize + cardGap
    readonly property real rowH: 52
    readonly property real rowGap: 4
    readonly property real rowStride: rowH + rowGap
    readonly property real listMaxH: 6 * rowStride - rowGap
    readonly property real panelWidth: Math.min(680, width - 48)
    readonly property real innerWidth: panelWidth - 2 * pad
    readonly property string mono: Theme.font
    // ───────────────────────── State ─────────────────────────
    readonly property int noWs: -9999
    property string sortMode: "recent"
    readonly property bool procMode: sortMode === "memory" || sortMode === "cpu"
    property string zone: "list"
    property int listIndex: 0
    property int stripIndex: 0
    property string selId: ""
    property int wsFilter: noWs
    property string dyingId: ""
    property var dyingApp: null
    property bool dyingHard: false
    property bool intro: true
    property real shown: 0
    property real lastMouseX: -1
    property real lastMouseY: -1
    // Memory/CPU: memMap (kB) and cpuMap (%) = current values per key (pid or "g:<name>"),
    // sortSnap = snapshot of the values of the active mode that is sorted by (so the list does not
    // jump on every tick)
    property var memMap: ({})
    property var cpuMap: ({})
    property var sortSnap: ({})
    // CPU time (ticks) per pid from the last measurement; CPU values only exist from the second measurement on
    property var prevTicks: ({})
    property real prevTime: 0
    property bool cpuReady: false
    // Total usage (summary above the list in the CPU/RAM tab): CPU from /proc/stat (line "cpu"),
    // RAM from /proc/meminfo (used = MemTotal - MemAvailable, like free/btop)
    property real sysCpu: 0
    property real prevCpuBusy: 0
    property real prevCpuAll: 0
    property int cores: 1
    property real sysMemUsedKb: 0
    property real sysMemTotalKb: 0
    // All process groups of the last measurement (mem, cpu, pids); applyGroups picks from them per mode
    property var allGroups: []
    // Background processes (CPU/RAM mode only): entries are only rebuilt when the selection changes
    property var ramGroups: []
    property string ramKey: ""
    property var groupInfo: ({})
    // Chosen process groups. Their entries are only built in CPU/RAM mode (buildRamGroups);
    // before, an icon was looked up for every background process on every opening: the first time
    // Qt searches the whole icon theme for it (10-30 ms per process) -> ~0.5 s hang in the intro
    property var rawGroups: []
    // Name + icon per program, filled piece by piece by the lookupTimer
    property var groupLookups: ({})
    property var lookupQueue: []
    readonly property real minGroupKb: 10240
    // CPU: a group appears from 0.1 % and stays while it is above 0.02 % (otherwise the list flickers)
    readonly property real minGroupCpu: 0.1
    readonly property real keepGroupCpu: 0.02
    readonly property int maxGroups: 80
    // These programs cannot be ended from the list
    readonly property var protectedComms: ["systemd", "Hyprland", "hyprland", ".Hyprland-wrapp", "quickshell", "dbus-daemon", "dbus-broker", "dbus-broker-lau"]
    // ───────────────────────── Data ─────────────────────────
    readonly property string needle: PickerManager.searchText.toLowerCase()
    readonly property var ignored: ["ueberzug", "xwaylandvideobridge"]
    readonly property int focusedWsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    readonly property var baseApps: {
        const v = Hyprland.toplevels.values;
        const out = [];
        for (let i = 0; i < v.length; i++) {
            const t = v[i];
            if (!isApp(t))
                continue;

            const o = t.lastIpcObject ?? ({});
            const cls = appClass(t);
            const entry = cls !== "" ? DesktopEntries.heuristicLookup(cls) : null;
            const title = t.title ?? "";
            const name = entry?.name ?? (cls !== "" ? cls : title);
            const pid = o["pid"] ?? 0;
            out.push({
                "id": t.address,
                "t": t,
                "isWindow": true,
                "name": name,
                "title": title,
                "cls": cls,
                "icon": iconFor(entry, cls),
                "pid": pid,
                "memKey": pid,
                "ws": t.workspace ? t.workspace.id : 0,
                "wsName": t.workspace ? t.workspace.name : "",
                "floating": o["floating"] === true,
                "focusRank": o["focusHistoryID"] ?? 999,
                "hay": (name + " " + title + " " + cls).toLowerCase()
            });
        }
        return out;
    }
    readonly property var searchedApps: {
        if (needle === "")
            return baseApps;

        return baseApps.filter((a) => {
            return a.hay.indexOf(needle) !== -1;
        });
    }
    readonly property var wsCards: {
        const m = {};
        const ids = [];
        for (let i = 0; i < searchedApps.length; i++) {
            const a = searchedApps[i];
            if (!m[a.ws]) {
                m[a.ws] = {
                    "id": a.ws,
                    "name": a.wsName,
                    "label": a.ws > 0 ? String(a.ws) : (a.ws === 0 ? "?" : "S"),
                    "apps": []
                };
                ids.push(a.ws);
            }
            m[a.ws].apps.push(a);
        }
        const rank = (x) => {
            return x > 0 ? x : 1e+06 - x;
        };
        ids.sort((x, y) => {
            return rank(x) - rank(y);
        });
        return ids.map((k) => {
            return m[k];
        });
    }
    readonly property bool wsFilterValid: wsFilter !== noWs && wsCards.some((c) => {
        return c.id === wsFilter;
    })
    readonly property int effWs: wsFilterValid ? wsFilter : noWs
    readonly property var listApps: {
        const ws = effWs;
        let arr = ws === noWs ? searchedApps.slice() : searchedApps.filter((a) => {
            return a.ws === ws;
        });
        if (procMode) {
            const mm = sortSnap;
            // Several windows of the same app share one process: show it only once
            const seen = {};
            arr = arr.filter((a) => {
                if (a.pid <= 0)
                    return true;

                if (seen[a.pid])
                    return false;

                seen[a.pid] = true;
                return true;
            });
            // Plus the background processes that use CPU or RAM (not with a workspace filter)
            if (ws === noWs) {
                const groups = ramGroups;
                for (let i = 0; i < groups.length; i++) {
                    if (needle === "" || groups[i].hay.indexOf(needle) !== -1)
                        arr.push(groups[i]);

                }
            }
            arr.sort((a, b) => {
                return memOf(b.memKey, mm) - memOf(a.memKey, mm);
            });
        } else {
            arr.sort((a, b) => {
                return a.focusRank - b.focusRank;
            });
        }
        return arr;
    }
    readonly property bool showStrip: wsCards.length > 1
    readonly property bool showList: listApps.length > 0
    readonly property bool isEmpty: !showList
    readonly property real listTotal: Math.max(0, listApps.length * rowStride - rowGap)
    readonly property real maxMem: {
        let m = 1;
        for (let i = 0; i < listApps.length; i++)
            m = Math.max(m, memOf(listApps[i].memKey, memMap));
        return m;
    }
    // At least 10 %: with an almost idle machine the smallest value would otherwise already be a full bar
    readonly property real maxCpu: {
        let m = 10;
        for (let i = 0; i < listApps.length; i++)
            m = Math.max(m, memOf(listApps[i].memKey, cpuMap));
        return m;
    }
    readonly property var sortModel: [{
        "key": "recent",
        "label": "Recent"
    }, {
        "key": "cpu",
        "label": "CPU"
    }, {
        "key": "memory",
        "label": "RAM"
    }]
    // ───────────────────────── Shell scripts ─────────────────────────
    // Ends a process with all its child processes. $1 = TERM|KILL, then the PIDs.
    // TERM: ask nicely, after 2 s kill whatever is left hard.
    readonly property string terminateScript: [`tree() { for c in $(pgrep -P "$1" 2>/dev/null); do tree "$c"; done; echo "$1"; }`, `sig="$1"; shift`, `all=""`, `for p in "$@"; do all="$all $(tree "$p")"; done`, `if [ "$sig" = KILL ]; then kill -KILL $all 2>/dev/null; exit 0; fi`, `kill -TERM $all 2>/dev/null`, `sleep 2`, `kill -KILL $all 2>/dev/null`, `exit 0`].join("\n")
    // After the close request: if the window is gone but the app is still alive (tray mode,
    // e.g. Discord), the whole process tree is ended. If the window is still there (e.g. a
    // "Save?" dialog), nothing happens. $1 = PID.
    readonly property string closeScript: [`tree() { for c in $(pgrep -P "$1" 2>/dev/null); do tree "$c"; done; echo "$1"; }`, `pid="$1"`, `gone=0`, `i=0`, `while [ "$i" -lt 20 ]; do`, `  kill -0 "$pid" 2>/dev/null || exit 0`, `  out=$(hyprctl clients -j 2>/dev/null) || exit 0`, `  if ! printf "%s" "$out" | grep -Eq '"pid": *'"$pid,"; then gone=1; break; fi`, `  sleep 0.5`, `  i=$((i+1))`, `done`, `[ "$gone" = 1 ] || exit 0`, `sleep 0.8`, `kill -0 "$pid" 2>/dev/null || exit 0`, `pids=$(tree "$pid")`, `kill -TERM $pids 2>/dev/null`, `sleep 2`, `kill -KILL $pids 2>/dev/null`, `exit 0`].join("\n")

    // ───────────────────────── Helpers ─────────────────────────
    function focusSearch() {
        searchInput.forceActiveFocus();
    }

    function appClass(t) {
        const o = t.lastIpcObject;
        const fromWayland = t.wayland ? t.wayland.appId : "";
        return fromWayland || (o ? (o["class"] ?? "") : "");
    }

    // Only windows that are really open (mapped) right now
    function isApp(t) {
        if (t.address === "")
            return false;

        const o = t.lastIpcObject;
        // Without fresh IPC data it is unclear whether the window is really open
        if (!o || o["mapped"] !== true)
            return false;

        if (!(o["pid"] > 0))
            return false;

        if (!t.workspace)
            return false;

        const cls = appClass(t).toLowerCase();
        const title = (t.title ?? "").toLowerCase();
        if (cls === "" && title === "")
            return false;

        for (let i = 0; i < ignored.length; i++) {
            if (cls.indexOf(ignored[i]) >= 0 || title.indexOf(ignored[i]) >= 0)
                return false;

        }
        const sz = o["size"];
        if (sz && sz.length >= 2 && sz[0] > 0 && sz[1] > 0 && sz[0] < 40 && sz[1] < 40)
            return false;

        return true;
    }

    function iconFor(entry, cls) {
        if (entry && entry.icon) {
            const p = Quickshell.iconPath(entry.icon, true);
            if (p)
                return p;

        }
        if (cls !== "") {
            const p2 = Quickshell.iconPath(cls.toLowerCase(), true);
            if (p2)
                return p2;

        }
        return "";
    }

    function addr(t) {
        return t.address.startsWith("0x") ? t.address : "0x" + t.address;
    }

    // ───────────────────────── Hyprland (Lua) ─────────────────────────
    // Since Hyprland 0.55 `hyprctl dispatch` expects a Lua expression (hl.dsp.*),
    // the old form "focuswindow address:..." no longer exists.
    function luaStr(s) {
        return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    function hyprDispatch(expr) {
        Quickshell.execDetached(["hyprctl", "dispatch", expr]);
    }

    function focusWindow(t) {
        if (t.wayland)
            t.wayland.activate();
        else
            hyprDispatch("hl.dsp.focus({ window = " + luaStr("address:" + addr(t)) + " })");
    }

    function closeWindow(t) {
        if (t.wayland)
            t.wayland.close();
        else
            hyprDispatch("hl.dsp.window.close({ window = " + luaStr("address:" + addr(t)) + " })");
    }

    function goToWorkspace(card) {
        if (card.id > 0)
            hyprDispatch("hl.dsp.focus({ workspace = " + luaStr(String(card.id)) + " })");
        else if (card.name !== "")
            hyprDispatch("hl.dsp.workspace.toggle_special(" + luaStr(card.name.replace("special:", "")) + ")");
        PickerManager.close();
    }

    // ───────────────────────── Ending processes ─────────────────────────
    function isProtected(a) {
        return !a.isWindow && protectedComms.indexOf(a.comm) !== -1;
    }

    function groupPids(a) {
        const g = groupInfo[a.id];
        return g ? g.pids : [];
    }

    function groupLabel(a) {
        const g = groupInfo[a.id];
        if (!g)
            return "";

        return g.count + (g.count === 1 ? " process" : " processes");
    }

    function terminate(sig, pids) {
        if (!pids || pids.length === 0)
            return ;

        Quickshell.execDetached(["sh", "-c", terminateScript, "sh", sig].concat(pids.map((p) => {
            return String(p);
        })));
    }

    // How many open windows belong to this process? (Firefox, Chrome ... share one)
    function windowCount(pid) {
        const v = Hyprland.toplevels.values;
        let n = 0;
        for (let i = 0; i < v.length; i++) {
            const o = v[i].lastIpcObject;
            if (o && o["pid"] === pid && o["mapped"] === true)
                n++;

        }
        return n;
    }

    // Steam: the window belongs to the steamwebhelper, which the Steam main process restarts right away.
    // So end Steam itself instead of only the window's process tree. Not games (steam_app_*).
    function isSteam(a) {
        return a.isWindow && a.cls.toLowerCase() === "steam";
    }

    // Hard: the process tree right away with SIGKILL
    function killApp(a) {
        if (isSteam(a))
            Quickshell.execDetached(["sh", "-c", `exec sh -c "$1" sh KILL $(pgrep -x steam)`, "sh", terminateScript]);
        else if (!a.isWindow)
            terminate("KILL", groupPids(a));
        else if (a.pid > 0)
            terminate("KILL", [a.pid]);
        else
            closeWindow(a.t);
    }

    // Normal: close the window cleanly; if the app stays alive invisibly, it is ended completely.
    // If the app has more windows, only this one is closed.
    function closeApp(a) {
        if (!a.isWindow) {
            terminate("TERM", groupPids(a));
            return ;
        }
        if (isSteam(a)) {
            Quickshell.execDetached(["steam", "-shutdown"]);
            return ;
        }
        closeWindow(a.t);
        if (a.pid > 0 && windowCount(a.pid) <= 1)
            Quickshell.execDetached(["sh", "-c", closeScript, "sh", String(a.pid)]);
    }

    // ───────────────────────── Memory (ps) ─────────────────────────
    function memOf(key, map) {
        return (map && key && map[key]) ? map[key] : 0;
    }

    function fmtMem(kb) {
        if (kb >= 1.048576e+06)
            return (kb / 1.048576e+06).toFixed(1) + " GB";

        return Math.round(kb / 1024) + " MB";
    }

    function fmtCpu(p) {
        if (p >= 10)
            return Math.round(p) + " %";

        if (p >= 0.1)
            return p.toFixed(1) + " %";

        return p > 0 ? "<0.1 %" : "0 %";
    }

    function cpuColor(p) {
        if (p > 50)
            return WalColors.color1;

        if (p > 20)
            return WalColors.color3;

        return WalColors.withAlpha(WalColors.color7, 0.5);
    }

    function cpuBarColor(p) {
        if (p > 50)
            return WalColors.withAlpha(WalColors.color1, 0.7);

        if (p > 20)
            return WalColors.withAlpha(WalColors.color3, 0.7);

        return WalColors.withAlpha(WalColors.color4, 0.55);
    }

    function memColor(kb) {
        if (kb > 3 * 1.048576e+06)
            return WalColors.color1;

        if (kb > 1.5 * 1.048576e+06)
            return WalColors.color3;

        return WalColors.withAlpha(WalColors.color7, 0.5);
    }

    function memBarColor(kb) {
        if (kb > 3 * 1.048576e+06)
            return WalColors.withAlpha(WalColors.color1, 0.7);

        if (kb > 1.5 * 1.048576e+06)
            return WalColors.withAlpha(WalColors.color3, 0.7);

        return WalColors.withAlpha(WalColors.color4, 0.55);
    }

    // Until the lookupTimer has looked up a program: process name and letter icon
    function groupEntry(g) {
        const l = groupLookups[g.comm];
        const name = l ? l.name : g.comm;
        return {
            "id": "g:" + g.comm,
            "t": null,
            "isWindow": false,
            "comm": g.comm,
            "name": name,
            "title": "",
            "cls": g.comm,
            "icon": l ? l.icon : "",
            "pid": 0,
            "memKey": "g:" + g.comm,
            "ws": 0,
            "wsName": "",
            "floating": false,
            "focusRank": 1e+06,
            "hay": (name + " " + g.comm).toLowerCase()
        };
    }

    // One measurement from /proc/*/stat (first line: page size, ticks per second, cores).
    // Memory = rss, CPU = CPU time used since the last measurement.
    function parseProcs(text) {
        const lines = text.split("\n");
        const head = (lines[0] || "").trim().split(/\s+/);
        const pageKb = (parseInt(head[0]) || 4096) / 1024;
        const hz = parseInt(head[1]) || 100;
        const cores = Math.max(1, parseInt(head[2]) || 1);
        root.cores = cores;
        const now = Date.now();
        const dt = prevTime > 0 ? (now - prevTime) / 1000 : 0;
        const rss = {};
        const cpu = {};
        const comm = {};
        const parent = {};
        const kids = {};
        const ticks = {};
        const pids = [];
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i];
            if (line.startsWith("cpu ")) {
                // user nice system idle iowait irq softirq steal: idle + iowait = not busy
                const v = line.trim().split(/\s+/).slice(1, 9).map((x) => {
                    return parseInt(x) || 0;
                });
                const all = v.reduce((a, b) => {
                    return a + b;
                }, 0);
                const busy = all - v[3] - v[4];
                if (prevCpuAll > 0 && all > prevCpuAll)
                    sysCpu = Math.max(0, Math.min(100, (busy - prevCpuBusy) / (all - prevCpuAll) * 100));

                prevCpuBusy = busy;
                prevCpuAll = all;
                continue;
            }
            if (line.startsWith("MemTotal:")) {
                sysMemTotalKb = parseInt(line.slice(9)) || 0;
                continue;
            }
            if (line.startsWith("MemAvailable:")) {
                sysMemUsedKb = Math.max(0, sysMemTotalKb - (parseInt(line.slice(13)) || 0));
                continue;
            }
            // Format: pid (comm) state ppid ... ; comm may contain spaces and parentheses
            const open = line.indexOf(" (");
            const close = line.lastIndexOf(")");
            if (open < 0 || close < open)
                continue;

            const pid = parseInt(line.slice(0, open));
            const f = line.slice(close + 2).split(" ");
            if (isNaN(pid) || f.length < 22)
                continue;

            const ppid = parseInt(f[1]);
            // utime + stime (fields 14 and 15)
            const t = parseInt(f[11]) + parseInt(f[12]);
            const prev = prevTicks[pid];
            ticks[pid] = t;
            cpu[pid] = dt > 0 && prev !== undefined && t >= prev ? (t - prev) / hz / dt * 100 / cores : 0;
            rss[pid] = (parseInt(f[21]) || 0) * pageKb;
            comm[pid] = line.slice(open + 2, close);
            parent[pid] = ppid;
            pids.push(pid);
            if (!kids[ppid])
                kids[ppid] = [];

            kids[ppid].push(pid);
        }
        prevTicks = ticks;
        prevTime = now;
        if (dt > 0)
            cpuReady = true;

        // Sum per process tree (for window apps: browsers, Electron ...)
        const treeSums = (vals) => {
            const totals = {};
            const calc = (pid, depth) => {
                if (totals[pid] !== undefined)
                    return totals[pid];

                totals[pid] = vals[pid] || 0;
                let s = vals[pid] || 0;
                const k = kids[pid];
                if (k && depth < 14) {
                    for (let j = 0; j < k.length; j++)
                        s += calc(k[j], depth + 1);

                }
                totals[pid] = s;
                return s;
            };
            for (let i = 0; i < pids.length; i++)
                calc(pids[i], 0);

            return totals;
        };
        const memAll = treeSums(rss);
        const cpuAll = treeSums(cpu);
        // Everything that does not belong to an open window is grouped by program name
        const owned = {};
        const mark = (pid, depth) => {
            if (owned[pid] || depth > 14)
                return ;

            owned[pid] = true;
            const k = kids[pid];
            if (k) {
                for (let j = 0; j < k.length; j++)
                    mark(k[j], depth + 1);

            }
        };
        const apps = baseApps;
        for (let i = 0; i < apps.length; i++) {
            if (apps[i].pid > 0)
                mark(apps[i].pid, 0);

        }
        const gm = {};
        for (let i = 0; i < pids.length; i++) {
            const pid = pids[i];
            // Kernel threads (kthreadd = pid 2 and its children) cannot be ended: do not show them
            if (owned[pid] || pid === 2 || parent[pid] === 2)
                continue;

            if (!(rss[pid] > 0) && !(cpu[pid] > 0))
                continue;

            const key = "g:" + comm[pid];
            if (!gm[key])
                gm[key] = {
                    "comm": comm[pid],
                    "mem": 0,
                    "cpu": 0,
                    "pids": []
                };

            gm[key].mem += rss[pid];
            gm[key].cpu += cpu[pid];
            gm[key].pids.push(pid);
        }
        const groups = Object.keys(gm).map((k) => {
            return gm[k];
        });
        const info = {};
        for (let i = 0; i < groups.length; i++) {
            const id = "g:" + groups[i].comm;
            memAll[id] = groups[i].mem;
            cpuAll[id] = groups[i].cpu;
            info[id] = {
                "count": groups[i].pids.length,
                "pids": groups[i].pids
            };
        }
        memMap = memAll;
        cpuMap = cpuAll;
        groupInfo = info;
        allGroups = groups;
        applyGroups(false);
    }

    // Picks the background groups for the active mode and updates the sorting.
    // force: always re-sort after a mode change
    function applyGroups(force) {
        const cpuMode = sortMode === "cpu";
        let groups;
        if (cpuMode) {
            const shown = {};
            for (let i = 0; i < rawGroups.length; i++)
                shown[rawGroups[i].comm] = true;

            groups = allGroups.filter((g) => {
                return g.cpu >= (shown[g.comm] ? keepGroupCpu : minGroupCpu);
            }).sort((a, b) => {
                return b.cpu - a.cpu;
            });
        } else {
            groups = allGroups.filter((g) => {
                return g.mem >= minGroupKb;
            }).sort((a, b) => {
                return b.mem - a.mem;
            });
        }
        groups = groups.slice(0, maxGroups);
        const values = cpuMode ? cpuMap : memMap;
        // Only rebuild entries when the set of background apps changes
        const key = (cpuMode ? "cpu\n" : "mem\n") + groups.map((g) => {
            return g.comm;
        }).sort().join("\n");
        let changed = force;
        if (key !== ramKey) {
            ramKey = key;
            rawGroups = groups;
            buildRamGroups();
            changed = true;
        }
        // Only rebuild the sorting when the order really changes
        if (procMode && !changed) {
            const cur = listApps.map((a) => {
                return a.id;
            }).join(",");
            const next = listApps.slice().sort((a, b) => {
                return memOf(b.memKey, values) - memOf(a.memKey, values);
            }).map((a) => {
                return a.id;
            }).join(",");
            if (cur !== next)
                sortSnap = values;

        } else {
            sortSnap = values;
        }
    }

    // ───────────────────────── Selection ─────────────────────────
    function selectList(i) {
        listIndex = i;
        selId = (i >= 0 && i < listApps.length) ? listApps[i].id : "";
    }

    function normalizeZone() {
        if (zone === "strip" && !showStrip)
            zone = "list";
        else if (zone === "list" && !showList && showStrip)
            zone = "strip";
    }

    function clampSelection() {
        const fi = selId !== "" ? listApps.findIndex((a) => {
            return a.id === selId;
        }) : -1;
        if (fi >= 0)
            listIndex = fi;

        listIndex = Math.max(0, Math.min(listIndex, listApps.length - 1));
        stripIndex = Math.max(0, Math.min(stripIndex, wsCards.length - 1));
        selId = listApps.length > 0 ? listApps[listIndex].id : "";
        normalizeZone();
    }

    function resetList() {
        listScroll.stop();
        list.positionViewAtBeginning();
        // Recent: the first app is the current window -> the selection starts on the second (Alt-Tab feel)
        const startIdx = (sortMode === "recent" && listApps.length > 1 && listApps[0].focusRank === 0) ? 1 : 0;
        selectList(startIdx);
    }

    function resetSelection() {
        stripScroll.stop();
        strip.contentX = -strip.leftMargin;
        resetList();
        const fi = wsCards.findIndex((c) => {
            return c.id === focusedWsId;
        });
        stripIndex = fi >= 0 ? fi : 0;
        zone = "list";
        normalizeZone();
        scrollStripTo(stripIndex);
    }

    function buildRamGroups() {
        if (!procMode)
            return ;

        const queued = lookupQueue.slice();
        for (let i = 0; i < rawGroups.length; i++) {
            const c = rawGroups[i].comm;
            if (groupLookups[c] === undefined && queued.indexOf(c) === -1)
                queued.push(c);

        }
        if (queued.length > 0) {
            lookupQueue = queued;
            lookupTimer.start();
        }
        ramGroups = rawGroups.map(groupEntry);
    }

    function setSort(m) {
        if (sortMode === m)
            return ;

        sortMode = m;
        // CPU and RAM show different background groups
        applyGroups(true);
        buildRamGroups();
        Qt.callLater(resetList);
    }

    function cycleSort(dir) {
        const keys = ["recent", "cpu", "memory"];
        const i = keys.indexOf(sortMode);
        setSort(keys[(i + dir + keys.length) % keys.length]);
    }

    function hoverSelect(target, mouse, zoneName, idx) {
        const p = target.mapToItem(null, mouse.x, mouse.y);
        if (Math.abs(p.x - lastMouseX) < 3 && Math.abs(p.y - lastMouseY) < 3)
            return ;

        lastMouseX = p.x;
        lastMouseY = p.y;
        zone = zoneName;
        if (zoneName === "list")
            selectList(idx);
        else
            stripIndex = idx;
    }

    // ───────────────────────── Scrolling (animated) ─────────────────────────
    function animateListTo(y) {
        const minY = list.originY;
        const maxY = minY + Math.max(0, listTotal - list.height);
        listScroll.stop();
        const to = Math.max(minY, Math.min(y, maxY));
        if (Math.abs(to - list.contentY) < 0.5)
            return ;

        listScroll.to = to;
        listScroll.start();
    }

    function animateStripTo(x) {
        const minX = -strip.leftMargin;
        const maxX = Math.max(minX, wsCards.length * cardStride - cardGap + strip.rightMargin - strip.width);
        const to = Math.max(minX, Math.min(x, maxX));
        const running = stripScroll.running;
        stripScroll.stop();
        if (!running && Math.abs(to - strip.contentX) < 0.5)
            return ;

        stripScroll.to = to;
        stripScroll.start();
    }

    function scrollListTo(i) {
        const top = list.originY + i * rowStride;
        const bottom = top + rowH;
        let to = list.contentY;
        if (top < to)
            to = top;
        else if (bottom > to + list.height)
            to = bottom - list.height;
        animateListTo(to);
    }

    function scrollStripTo(i) {
        const left = i * cardStride;
        const right = left + cardSize;
        let to = strip.contentX;
        if (left - 10 < to)
            to = left - 10;
        else if (right + 10 > to + strip.width)
            to = right + 10 - strip.width;
        animateStripTo(to);
    }

    // ───────────────────────── Navigation ─────────────────────────
    function moveVertical(dir) {
        if (dir > 0) {
            if (zone === "strip") {
                if (showList) {
                    zone = "list";
                    scrollListTo(listIndex);
                }
            } else if (listIndex < listApps.length - 1) {
                selectList(listIndex + 1);
                scrollListTo(listIndex);
            }
        } else if (zone === "list") {
            if (listIndex > 0) {
                selectList(listIndex - 1);
                scrollListTo(listIndex);
            } else if (showStrip) {
                zone = "strip";
                scrollStripTo(stripIndex);
            }
        }
    }

    function moveHorizontal(dir) {
        const n = stripIndex + dir;
        if (n >= 0 && n < wsCards.length) {
            stripIndex = n;
            scrollStripTo(n);
        }
    }

    // ───────────────────────── Actions ─────────────────────────
    function currentApp() {
        if (zone === "list" && showList)
            return listApps[listIndex];

        return undefined;
    }

    function currentCard() {
        if (zone === "strip" && showStrip)
            return wsCards[stripIndex];

        return undefined;
    }

    function toggleWs(card) {
        wsFilter = (effWs === card.id) ? noWs : card.id;
        Qt.callLater(resetList);
    }

    function activateCurrent(alt) {
        if (zone === "strip") {
            const c = currentCard();
            if (!c)
                return ;

            if (alt)
                goToWorkspace(c);
            else
                toggleWs(c);
            return ;
        }
        const a = currentApp();
        if (!a)
            return ;

        // Enter ends (like Ctrl+D, with the closing animation), Shift+Enter focuses. Deliberately this
        // way round: in the task manager ending is the main action, focusing also works with a click
        if (!alt) {
            requestClose(a, false);
        } else if (a.isWindow) {
            focusWindow(a.t);
            PickerManager.close();
        }
    }

    function closeCurrent(hard) {
        const a = currentApp();
        if (a)
            requestClose(a, hard);

    }

    function commitDying() {
        if (dyingId === "")
            return ;

        const a = dyingApp;
        const hard = dyingHard;
        dyingId = "";
        dyingApp = null;
        if (!a)
            return ;

        if (hard)
            killApp(a);
        else
            closeApp(a);
    }

    function requestClose(a, hard) {
        if (isProtected(a))
            return ;

        if (dyingId !== "")
            commitDying();

        dyingId = a.id;
        dyingApp = a;
        dyingHard = hard;
        deleteTimer.restart();
    }

    // Closing: reverse of the intro (panel glides down, shrinks, fades out).
    // Called by PickerWindow, the window stays visible briefly for it.
    function playOutro() {
        introAnim.stop();
        outroAnim.restart();
    }

    function playIntro() {
        outroAnim.stop();
        intro = true;
        // Measure the CPU again: otherwise the first measurement would count all the time the picker was closed
        prevTicks = {};
        prevTime = 0;
        prevCpuAll = 0;
        cpuReady = false;
        introTimer.restart();
        introAnim.restart();
        // Get fresh window data, so only really open windows appear
        Hyprland.refreshToplevels();
        resetSelection();
    }

    Component.onCompleted: playIntro()
    onVisibleChanged: {
        if (visible)
            playIntro();

    }
    onListAppsChanged: clampSelection()
    onWsCardsChanged: clampSelection()
    onBaseAppsChanged: {
        if (intro)
            Qt.callLater(resetSelection);

    }

    // ───────────────────────── Timers & animations ─────────────────────────
    Timer {
        id: introTimer

        interval: 700
        running: true
        onTriggered: root.intro = false
    }

    Timer {
        id: deleteTimer

        interval: 230
        onTriggered: root.commitDying()
    }

    // Looks up names + icons of the background processes, per tick only as many as fit in ~8 ms
    // (unknown icons cost 10-30 ms the first time, then Qt has them cached)
    Timer {
        id: lookupTimer

        interval: 16
        repeat: true
        onTriggered: {
            const t0 = Date.now();
            const q = root.lookupQueue.slice();
            const l = Object.assign({}, root.groupLookups);
            while (q.length > 0 && (Date.now() - t0 < 8 || q.length === root.lookupQueue.length)) {
                const comm = q.shift();
                const entry = DesktopEntries.heuristicLookup(comm);
                l[comm] = {
                    "name": entry?.name ?? comm,
                    "icon": root.iconFor(entry, comm)
                };
            }
            root.lookupQueue = q;
            root.groupLookups = l;
            // Only rebuild the list when everything is there (a rebuild resets the list)
            if (q.length === 0) {
                stop();
                if (root.procMode)
                    root.ramGroups = root.rawGroups.map(root.groupEntry);

            }
        }
    }

    // Memory and CPU time of all processes, only while the picker is visible. One read instead of ps:
    // ps only knows the average CPU since the process started, not the current usage.
    Process {
        id: psProc

        command: ["sh", "-c", "echo \"$(getconf PAGESIZE) $(getconf CLK_TCK) $(nproc)\"; head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /proc/[0-9]*/stat 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: root.parseProcs(text)
        }

    }

    // The second measurement already after 0.8 s: only from then on there are CPU values
    Timer {
        interval: root.cpuReady ? 2500 : 800
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: {
            if (!psProc.running)
                psProc.running = true;

        }
    }

    NumberAnimation {
        id: introAnim

        target: root
        property: "shown"
        from: 0
        to: 1
        duration: 520
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    // Faster than the intro and accelerating (ease-in) -> feels snappy instead of sluggish
    NumberAnimation {
        id: outroAnim

        target: root
        property: "shown"
        to: 0
        duration: 200
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.accelerate
    }

    NumberAnimation {
        id: listScroll

        target: list
        property: "contentY"
        duration: Appearance.anim.durations.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    NumberAnimation {
        id: stripScroll

        target: strip
        property: "contentX"
        duration: 340
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    Connections {
        function onSearchTextChanged() {
            Qt.callLater(root.resetSelection);
        }

        target: PickerManager
    }

    // Click outside the panel closes the picker.
    MouseArea {
        anchors.fill: parent
        onClicked: PickerManager.close()
    }

    // ═════════════════════════ Panel ═════════════════════════
    Item {
        id: panel

        width: root.panelWidth
        height: column.implicitHeight + 2 * root.pad
        x: (root.width - width) / 2
        y: Math.max(40, root.height * 0.12) + (1 - root.shown) * 24
        opacity: Math.min(1, root.shown * 1.6)
        scale: 0.95 + 0.05 * root.shown
        transformOrigin: Item.Top

        SoftShadow {
            panel: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: WalColors.withAlpha(WalColors.color0, 0.97)
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.09)
        }

        // Swallows clicks on the panel so the backdrop doesn't close it.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column

            x: root.pad
            y: root.pad
            width: root.innerWidth
            spacing: 0

            // ───────────── Header: search + sort ─────────────
            Item {
                id: header

                width: parent.width
                height: 44

                SearchField {
                    id: searchInput

                    anchors.left: parent.left
                    anchors.right: segmented.left
                    anchors.rightMargin: 12
                    height: parent.height
                    placeholder: "Search apps…"
                    text: PickerManager.searchText
                    onTextChanged: PickerManager.searchText = text
                    onKeyPressed: (event) => {
                        // Ctrl+J/K = arrow down/up, the same in all pickers (PickerManager.navKey)
                        const key = PickerManager.navKey(event);
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0 && key === event.key;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        switch (key) {
                        case Qt.Key_Escape:
                            if (text !== "")
                                text = "";
                            else
                                PickerManager.close();
                            event.accepted = true;
                            break;
                        case Qt.Key_Tab:
                        case Qt.Key_Backtab:
                            // Standalone picker (not in the tab bundle): Tab switches its own
                            // tabs Recent/CPU/RAM, like Ctrl+Left/Right
                            root.cycleSort(shift || key === Qt.Key_Backtab ? -1 : 1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Down:
                            root.moveVertical(1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Up:
                            root.moveVertical(-1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Left:
                            if (ctrl) {
                                root.cycleSort(-1);
                                event.accepted = true;
                            } else if (root.zone === "strip" && root.showStrip) {
                                root.moveHorizontal(-1);
                                event.accepted = true;
                            }
                            break;
                        case Qt.Key_Right:
                            if (ctrl) {
                                root.cycleSort(1);
                                event.accepted = true;
                            } else if (root.zone === "strip" && root.showStrip) {
                                root.moveHorizontal(1);
                                event.accepted = true;
                            }
                            break;
                        // Ctrl+H/L = left/right in the workspace strip (as in the clipboard image strip).
                        // Local instead of in navKey: other pickers may use Ctrl+H/L differently
                        case Qt.Key_H:
                        case Qt.Key_L:
                            if (ctrl) {
                                if (root.zone === "strip" && root.showStrip)
                                    root.moveHorizontal(key === Qt.Key_L ? 1 : -1);

                                event.accepted = true;
                            }
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.activateCurrent(shift);
                            event.accepted = true;
                            break;
                        case Qt.Key_D:
                            if (ctrl) {
                                root.closeCurrent(shift);
                                event.accepted = true;
                            }
                            break;
                        }
                    }
                }

                // iOS-style segmented control with springy pill (sorting)
                PillSegmented {
                    id: segmented

                    anchors.right: parent.right
                    height: parent.height
                    segW: 66
                    current: root.sortMode
                    options: root.sortModel
                    onPicked: (key) => {
                        root.setSort(key);
                        searchInput.forceActiveFocus();
                    }
                }

            }

            // ───────────── Workspace cards ─────────────
            Item {
                id: stripSection

                x: -root.bleed
                width: parent.width + 2 * root.bleed
                height: root.showStrip ? 14 + root.cardSize + 12 : 0
                opacity: root.showStrip ? 1 : 0
                visible: height > 0.5
                clip: true

                ListView {
                    id: strip

                    y: 14
                    width: parent.width
                    height: root.cardSize + 12
                    orientation: ListView.Horizontal
                    leftMargin: root.bleed
                    rightMargin: root.bleed
                    spacing: root.cardGap
                    clip: true
                    model: root.wsCards
                    // The hover selection must not move the card row.
                    currentIndex: -1
                    cacheBuffer: 400
                    boundsBehavior: Flickable.StopAtBounds
                    onMovementStarted: stripScroll.stop()

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: (event) => {
                            const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                            const base = stripScroll.running ? stripScroll.to : strip.contentX;
                            root.animateStripTo(base - d / 120 * root.cardStride);
                        }
                    }

                    delegate: Item {
                        id: card

                        required property var modelData
                        required property int index
                        readonly property var ws: modelData
                        readonly property bool selected: root.zone === "strip" && root.stripIndex === index
                        readonly property bool filtered: root.effWs === ws.id
                        readonly property bool here: root.focusedWsId === ws.id
                        property real enter: 1

                        width: root.cardSize
                        height: strip.height
                        opacity: enter
                        Component.onCompleted: {
                            if (root.intro) {
                                enter = 0;
                                enterAnim.start();
                            }
                        }

                        SequentialAnimation {
                            id: enterAnim

                            PauseAnimation {
                                duration: Math.min(Math.max(0, card.index), 8) * 35 + 60
                            }

                            NumberAnimation {
                                target: card
                                property: "enter"
                                to: 1
                                duration: 480
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.anim.curves.outQuint
                            }

                        }

                        Item {
                            id: cardBody

                            anchors.verticalCenter: parent.verticalCenter
                            width: root.cardSize
                            height: root.cardSize
                            scale: (card.selected ? 1.05 : 1) * (cardMouse.pressed ? 0.96 : 1)

                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: card.filtered ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.07)
                                border.width: card.filtered ? 1.5 : 0
                                border.color: WalColors.withAlpha(WalColors.color4, 0.6)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 180
                                    }

                                }

                            }

                            Text {
                                x: 15
                                y: 11
                                text: "WORKSPACE"
                                font.family: root.mono
                                font.pixelSize: 8
                                font.letterSpacing: 1.2
                                color: WalColors.withAlpha(WalColors.color7, 0.38)
                            }

                            Text {
                                x: 14
                                y: 22
                                text: card.ws.label
                                font.family: root.mono
                                font.pixelSize: 32
                                font.bold: true
                                color: (card.filtered || card.here) ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.85)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 180
                                    }

                                }

                            }

                            Text {
                                x: 15
                                y: 62
                                text: card.ws.apps.length + (card.ws.apps.length === 1 ? " app" : " apps")
                                font.family: root.mono
                                font.pixelSize: 10
                                color: WalColors.withAlpha(WalColors.color7, 0.45)
                            }

                            // App icons of this workspace
                            Row {
                                x: 14
                                y: parent.height - 14 - 26
                                spacing: 6

                                Repeater {
                                    model: card.ws.apps.length > 3 ? 2 : Math.min(3, card.ws.apps.length)

                                    delegate: Item {
                                        required property int index
                                        readonly property string src: card.ws.apps[index] ? card.ws.apps[index].icon : ""
                                        readonly property string nm: card.ws.apps[index] ? card.ws.apps[index].name : "?"

                                        width: 26
                                        height: 26

                                        Image {
                                            anchors.fill: parent
                                            visible: parent.src !== ""
                                            source: parent.src
                                            sourceSize.width: 52
                                            sourceSize.height: 52
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: parent.src === ""
                                            radius: 8
                                            color: WalColors.withAlpha(WalColors.color7, 0.1)

                                            Text {
                                                anchors.centerIn: parent
                                                text: parent.parent.nm.length > 0 ? parent.parent.nm.charAt(0).toUpperCase() : "?"
                                                font.family: root.mono
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: WalColors.withAlpha(WalColors.color7, 0.6)
                                            }

                                        }

                                    }

                                }

                                Rectangle {
                                    visible: card.ws.apps.length > 3
                                    width: 26
                                    height: 26
                                    radius: 8
                                    color: WalColors.withAlpha(WalColors.color7, 0.1)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "+" + (card.ws.apps.length - 2)
                                        font.family: root.mono
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: WalColors.withAlpha(WalColors.color7, 0.65)
                                    }

                                }

                            }

                            // Marker: you are on this workspace right now
                            Rectangle {
                                x: parent.width - 8 - 14
                                y: 14
                                width: 8
                                height: 8
                                radius: height / 2
                                color: WalColors.color4
                                visible: card.here

                                SequentialAnimation on opacity {
                                    running: card.here
                                    loops: Animation.Infinite

                                    NumberAnimation {
                                        to: 0.35
                                        duration: 1100
                                        easing.type: Easing.InOutSine
                                    }

                                    NumberAnimation {
                                        to: 1
                                        duration: 1100
                                        easing.type: Easing.InOutSine
                                    }

                                }

                            }

                            // Selection ring
                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: "transparent"
                                border.width: 2
                                border.color: WalColors.color4
                                opacity: card.selected ? 1 : 0

                                Behavior on opacity {
                                    Smooth {
                                        duration: 180
                                    }

                                }

                            }

                            MouseArea {
                                id: cardMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPositionChanged: (mouse) => {
                                    return root.hoverSelect(cardMouse, mouse, "strip", card.index);
                                }
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton)
                                        root.goToWorkspace(card.ws);
                                    else
                                        root.toggleWs(card.ws);
                                }
                            }

                            Behavior on scale {
                                Springy {
                                }

                            }

                        }

                    }

                }

                Behavior on height {
                    Smooth {
                    }

                }

                Behavior on opacity {
                    Smooth {
                        duration: 220
                    }

                }

            }

            // ───────────── Total usage (CPU/RAM tab only) ─────────────
            // Plain without a card: value on the left, extra on the right, below it a fine line for the usage
            Item {
                id: totalSection

                readonly property bool cpuView: root.sortMode === "cpu"
                readonly property real fraction: cpuView ? root.sysCpu / 100 : (root.sysMemTotalKb > 0 ? root.sysMemUsedKb / root.sysMemTotalKb : 0)
                readonly property bool ready: cpuView ? root.cpuReady : root.sysMemTotalKb > 0
                readonly property color tone: cpuView ? root.cpuColor(root.sysCpu) : (fraction > 0.85 ? WalColors.color1 : (fraction > 0.7 ? WalColors.color3 : WalColors.withAlpha(WalColors.color7, 0.5)))

                width: parent.width
                height: root.procMode ? 14 + 36 : 0
                opacity: root.procMode ? 1 : 0
                visible: height > 0.5
                clip: true

                Text {
                    id: totalLabel

                    x: 12
                    y: 14 + 4
                    text: totalSection.cpuView ? "CPU" : "RAM"
                    font.family: root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1.2
                    color: WalColors.withAlpha(WalColors.color7, 0.45)
                }

                Text {
                    anchors.left: totalLabel.right
                    anchors.leftMargin: 10
                    anchors.baseline: totalLabel.baseline
                    text: !totalSection.ready ? "–" : (totalSection.cpuView ? root.fmtCpu(root.sysCpu) : root.fmtMem(root.sysMemUsedKb) + " of " + root.fmtMem(root.sysMemTotalKb))
                    font.family: root.mono
                    font.pixelSize: 13
                    color: WalColors.color7
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.baseline: totalLabel.baseline
                    text: totalSection.cpuView ? root.cores + (root.cores === 1 ? " core" : " cores") : (totalSection.ready ? Math.round(totalSection.fraction * 100) + " %" : "")
                    font.family: root.mono
                    font.pixelSize: 10
                    color: totalSection.cpuView ? WalColors.withAlpha(WalColors.color7, 0.45) : totalSection.tone
                }

                // Track + fill
                Rectangle {
                    id: totalTrack

                    x: 12
                    y: 14 + 26
                    width: parent.width - 24
                    height: 2
                    radius: 1
                    color: WalColors.withAlpha(WalColors.color7, 0.08)

                    Rectangle {
                        width: Math.max(2, parent.width * Math.min(1, totalSection.fraction))
                        height: parent.height
                        radius: 1
                        visible: totalSection.ready
                        color: totalSection.cpuView ? root.cpuBarColor(root.sysCpu) : (totalSection.fraction > 0.7 ? WalColors.withAlpha(totalSection.tone, 0.7) : WalColors.withAlpha(WalColors.color4, 0.55))

                        Behavior on width {
                            Smooth {
                                duration: Appearance.anim.durations.slow
                            }

                        }

                    }

                }

                Behavior on height {
                    Smooth {
                    }

                }

                Behavior on opacity {
                    Smooth {
                        duration: 220
                    }

                }

            }

            // ───────────── App list ─────────────
            Item {
                id: listSection

                width: parent.width
                height: root.showList ? 14 + Math.min(root.listTotal, root.listMaxH) : 0
                opacity: root.showList ? 1 : 0
                visible: height > 0.5
                clip: true

                ListView {
                    id: list

                    y: 14
                    width: parent.width
                    height: Math.max(0, listSection.height - 14)
                    spacing: root.rowGap
                    clip: true
                    snapMode: ListView.SnapToItem
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.listApps
                    currentIndex: root.listIndex
                    cacheBuffer: 400
                    highlightFollowsCurrentItem: false
                    onMovementStarted: listScroll.stop()

                    WheelHandler {
                        id: rowWheel

                        property int pendingDelta: 0

                        acceptedDevices: PointerDevice.Mouse
                        onWheel: (event) => {
                            rowWheel.pendingDelta += event.angleDelta.y;
                            const steps = Math.trunc(rowWheel.pendingDelta / 120);
                            if (steps === 0)
                                return;

                            rowWheel.pendingDelta -= steps * 120;
                            const base = listScroll.running ? listScroll.to : list.contentY;
                            const firstRow = Math.round((base - list.originY) / root.rowStride);
                            root.animateListTo(list.originY + (firstRow - steps) * root.rowStride);
                        }
                    }

                    // Single selection pill that slides to current row via spring.
                    highlight: Rectangle {
                        y: list.originY + root.listIndex * root.rowStride
                        width: list.width
                        height: root.rowH
                        radius: 16
                        color: WalColors.withAlpha(WalColors.color4, 0.13)
                        opacity: root.zone === "list" ? 1 : 0

                        Behavior on y {
                            Springy {
                            }

                        }

                        Behavior on opacity {
                            Smooth {
                                duration: 160
                            }

                        }

                    }

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property var app: modelData
                        readonly property bool selected: root.zone === "list" && root.listIndex === index
                        readonly property bool dying: root.dyingId === app.id
                        readonly property bool isActive: app.t ? app.t.activated : false
                        readonly property bool canClose: !root.isProtected(app)
                        readonly property real mem: root.memOf(app.memKey, root.memMap)
                        readonly property real memRatio: Math.min(1, mem / root.maxMem)
                        readonly property bool cpuView: root.sortMode === "cpu"
                        readonly property real cpu: root.memOf(app.memKey, root.cpuMap)
                        readonly property real barRatio: cpuView ? Math.min(1, cpu / root.maxCpu) : memRatio
                        property real enter: 1

                        width: list.width
                        height: dying ? 0 : root.rowH
                        opacity: enter
                        clip: dying
                        Component.onCompleted: {
                            if (root.intro) {
                                enter = 0;
                                rowEnter.start();
                            }
                        }

                        SequentialAnimation {
                            id: rowEnter

                            PauseAnimation {
                                duration: Math.min(Math.max(0, row.index), 9) * 30 + 60
                            }

                            NumberAnimation {
                                target: row
                                property: "enter"
                                to: 1
                                duration: 460
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.anim.curves.outQuint
                            }

                        }

                        Item {
                            id: rowBody

                            width: parent.width
                            height: root.rowH
                            opacity: row.dying ? 0 : 1
                            scale: rowMouse.pressed ? 0.985 : 1

                            // App badge with icon + "active window" dot
                            Rectangle {
                                id: badge

                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 34
                                radius: 11
                                color: row.selected ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.07)

                                Image {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    visible: row.app.icon !== ""
                                    source: row.app.icon
                                    sourceSize.width: 48
                                    sourceSize.height: 48
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: row.app.icon === ""
                                    text: row.app.name.length > 0 ? row.app.name.charAt(0).toUpperCase() : "?"
                                    font.family: root.mono
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: row.selected ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.55)
                                }

                                Rectangle {
                                    x: parent.width - width + 2
                                    y: parent.height - height + 2
                                    width: 10
                                    height: 10
                                    radius: height / 2
                                    color: WalColors.color4
                                    border.width: 2
                                    border.color: WalColors.color0
                                    visible: row.isActive
                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                            }

                            // Name + window title (for background processes: number of processes)
                            Column {
                                anchors.left: badge.right
                                anchors.leftMargin: 12
                                anchors.right: rightArea.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: row.app.name
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: root.mono
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: (row.selected || row.isActive) ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.72)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.anim.durations.fast
                                        }

                                    }

                                }

                                Text {
                                    width: parent.width
                                    text: row.app.isWindow ? row.app.title : root.groupLabel(row.app)
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: root.mono
                                    font.pixelSize: 10
                                    color: WalColors.withAlpha(WalColors.color7, 0.45)
                                }

                            }

                            // CPU/RAM bars (RAM relative to the biggest app in the list, CPU at least 10 %)
                            Rectangle {
                                x: 12 + 34 + 12
                                y: root.rowH - 7
                                width: Math.max(2, (rowBody.width - 12 - 34 - 12 - 12) * row.barRatio)
                                height: 2
                                radius: 1
                                color: row.cpuView ? root.cpuBarColor(row.cpu) : root.memBarColor(row.mem)
                                visible: row.cpuView ? row.cpu >= 0.05 : row.mem > 0

                                Behavior on width {
                                    Smooth {
                                        duration: Appearance.anim.durations.slow
                                    }

                                }

                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onPositionChanged: (mouse) => {
                                    return root.hoverSelect(rowMouse, mouse, "list", row.index);
                                }
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.MiddleButton) {
                                        root.requestClose(row.app, false);
                                    } else if (row.app.isWindow) {
                                        root.focusWindow(row.app.t);
                                        PickerManager.close();
                                    }
                                }
                            }

                            Row {
                                id: rightArea

                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                // Workspace chip (background processes: "background")
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 18
                                    width: wsChipText.implicitWidth + 14
                                    radius: height / 2
                                    color: WalColors.withAlpha(WalColors.color7, 0.07)

                                    Text {
                                        id: wsChipText

                                        anchors.centerIn: parent
                                        text: !row.app.isWindow ? "background" : ((row.app.ws > 0 ? "WS " + row.app.ws : (row.app.ws === 0 ? "WS ?" : "special")) + (row.app.floating ? " · float" : ""))
                                        font.family: root.mono
                                        font.pixelSize: 9
                                        color: WalColors.withAlpha(WalColors.color7, 0.55)
                                    }

                                }

                                // CPU (in the CPU tab) or memory; before the second measurement there are no CPU values yet
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 58
                                    horizontalAlignment: Text.AlignRight
                                    text: row.cpuView ? (root.cpuReady ? root.fmtCpu(row.cpu) : "–") : (row.mem > 0 ? root.fmtMem(row.mem) : "–")
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    color: row.cpuView ? root.cpuColor(row.cpu) : root.memColor(row.mem)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 200
                                        }

                                    }

                                }

                                IconButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 20
                                    glyph: "✕"
                                    danger: true
                                    opacity: (row.selected && row.canClose) ? 1 : 0
                                    visible: opacity > 0.01
                                    onClicked: root.requestClose(row.app, shiftHeld)

                                    Behavior on opacity {
                                        Smooth {
                                            duration: 160
                                        }

                                    }

                                }

                            }

                            transform: Translate {
                                y: (1 - row.enter) * 12
                            }

                            Behavior on scale {
                                Springy {
                                }

                            }

                            Behavior on opacity {
                                Smooth {
                                    duration: 180
                                }

                            }

                        }

                        Behavior on height {
                            Smooth {
                                duration: 220
                            }

                        }

                    }

                }

                Behavior on height {
                    Smooth {
                    }

                }

                Behavior on opacity {
                    Smooth {
                        duration: 220
                    }

                }

            }

            // ───────────── Empty state ─────────────
            Item {
                id: emptyState

                width: parent.width
                height: root.isEmpty ? 150 : 0
                opacity: root.isEmpty ? 1 : 0
                visible: height > 0.5
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "◌"
                        font.pixelSize: 36
                        color: WalColors.withAlpha(WalColors.color7, 0.2)
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: PickerManager.searchText === "" ? "Nothing running" : "Nothing found"
                        font.family: root.mono
                        font.pixelSize: 12
                        color: WalColors.withAlpha(WalColors.color7, 0.38)
                    }

                }

                Behavior on height {
                    Smooth {
                    }

                }

                Behavior on opacity {
                    Smooth {
                        duration: 220
                    }

                }

            }

        }

    }

    component IconButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool danger: false
        property real size: 20
        property bool shiftHeld: false

        signal clicked()

        width: size
        height: size
        radius: size / 2
        color: btnArea.containsMouse ? WalColors.withAlpha(danger ? WalColors.color1 : WalColors.color4, 0.9) : WalColors.withAlpha(WalColors.color0, 0.4)
        scale: btnArea.pressed ? 0.9 : 1

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: root.mono
            font.pixelSize: btn.size * 0.42
            color: btnArea.containsMouse ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.55)
        }

        MouseArea {
            id: btnArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                btn.shiftHeld = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                btn.clicked();
            }
        }

        Behavior on scale {
            Springy {
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 120
            }

        }

    }

}
