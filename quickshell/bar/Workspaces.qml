import "../services"
import "../common/WorkspaceNumbers.js" as WorkspaceNumbers
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: workspaceWidget

    // ------------------------------------------------------------------
    // Steam data (delivered by scripts/steam_scan.sh)
    // ------------------------------------------------------------------
    property var steamTitleMap: ({})       // exakter Titel -> appid
    property var steamNormalizedMap: ({})  // normalisierter Titel -> appid
    property var steamIconMap: ({})        // appid -> file://-URL
    // Increased on every finished scan -> bindings re-evaluate
    property int mapsVersion: 0
    property var _tmpTitles: ({})
    property var _tmpNormalized: ({})
    property var _tmpIcons: ({})
    property var _rescanned: ({})
    property double lastScan: Date.now()
    // appid cache for gamescope windows (key: pid|address)
    property var pidAppIds: ({})
    property var _pidPending: ({})
    property var _pidQueue: []
    property int pidVersion: 0
    readonly property string scanScript: Qt.resolvedUrl("../scripts/steam_scan.sh").toString().replace("file://", "")
    // Folder with the own icons (relative to this file, no home path hardcoded)
    readonly property int tabletWorkspaceId: 11
    // Colors of the generated icons (tray, media) as a fixed palette { fg, bg, accent }: pen/stroke or
    // play triangle in the strongest pywal color (rule see WalColors.vividAccent).
    // NOT bound live to WalColors: on a wallpaper change WalColors fades in ~22 steps/s, every
    // step gave a new SVG that had to reload the image (the fallback symbol flashed meanwhile), and the
    // "strongest" color jumped back and forth between mixed colors -> the icon trembled. Instead
    // the icon is created once per change for the target palette and crossfaded by opacity, as long
    // as WalColors' color change (iconPalA = shown, iconPalB = target, iconMix).
    property var iconPalA: null
    property var iconPalB: null
    property real iconMix: 0

    function iconPalOf(c) {
        return {
            "fg": c.color7,
            "bg": c.color0,
            "accent": WalColors.vividOf([c.color1, c.color2, c.color3, c.color4, c.color5, c.color6])
        };
    }

    // WalColors has started a color change (fadeTo sets the target and starts the animation right
    // after -> only read the duration afterwards)
    function beginIconFade() {
        const t = WalColors.fadeTarget;
        if (!t || !t.color1)
            return ;

        const next = iconPalOf(t);
        if (iconMixAnim.running) {
            iconMixAnim.stop();
            if (iconMix >= 0.5)
                iconPalA = iconPalB;

        }
        const anim = WalColors.fadeAnim;
        const ms = anim.running ? Math.max(1, anim.duration * (1 - WalColors.fadeT)) : 0;
        iconPalB = next;
        iconMix = 0;
        if (ms <= 1) {
            iconPalA = next;
            return ;
        }
        iconMixAnim.duration = ms;
        iconMixAnim.start();
    }

    // The tray icon is generated with the pywal colors instead of a fixed SVG: a fixed dark icon
    // got lost on the dark bar. The light pad (text color) always stands out, pen/stroke in accent colors.
    function tabletSvg(p) {
        if (!p)
            return "";

        const fg = p.fg, bg = p.bg, pen = p.accent, ink = p.accent;
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
            // Pad with express keys on the left and a dark drawing area
            + '<rect x="2" y="13" width="44" height="28" rx="5" fill="' + fg + '"/>'
            + '<rect x="5.5" y="18" width="4" height="4" rx="1.2" fill="' + bg + '"/>'
            + '<rect x="5.5" y="25" width="4" height="4" rx="1.2" fill="' + bg + '"/>'
            + '<rect x="5.5" y="32" width="4" height="4" rx="1.2" fill="' + bg + '"/>'
            + '<rect x="13" y="17" width="29" height="20" rx="2" fill="' + bg + '"/>'
            // The stroke starts exactly at the pen tip -> "drawing happens here"
            + '<path d="M16.5 32.5c1.8-5 5.6-5.6 5.6-2.6s-4.4 4.4-2.4 5.1c2.2.8 5-4 6.6-5.4" fill="none" stroke="' + ink + '" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'
            // Pen: outline in the background color, so it separates from the light pad frame
            + '<g transform="translate(27.6 29) rotate(40)" stroke="' + bg + '" stroke-width="1.2" stroke-linejoin="round">'
            + '<path d="M0 0l-2.8-6.5h5.6z" fill="' + fg + '"/>'
            + '<rect x="-3.1" y="-24" width="6.2" height="18" rx="3.1" fill="' + pen + '"/>'
            + '<rect x="-3.1" y="-11" width="6.2" height="2.6" fill="' + bg + '"/>'
            + '</g></svg>';
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
    }

    // Media workspace (everything the media picker plays, see PickerManager.playerWorkspace): a fixed
    // icon instead of the mpv window. Like the tablet from pywal colors: light screen frame, dark
    // surface, play triangle in the accent color. Is already there while loading (workspace still empty).
    function mediaSvg(p) {
        if (!p)
            return "";

        const fg = p.fg, bg = p.bg, accent = p.accent;
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
            + '<rect x="3" y="7" width="42" height="30" rx="6" fill="' + fg + '"/>'
            + '<rect x="6.5" y="10.5" width="35" height="23" rx="3" fill="' + bg + '"/>'
            + '<path d="M20.5 16.5L29.5 22L20.5 27.5Z" fill="' + accent + '" stroke="' + accent + '" stroke-width="2.4" stroke-linejoin="round"/>'
            + '<rect x="16" y="40" width="16" height="3.2" rx="1.6" fill="' + fg + '"/>'
            + '</svg>';
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
    }

    readonly property string tabletIconPath: tabletSvg(iconPalA)
    readonly property string tabletIconPathNext: tabletSvg(iconPalB)
    readonly property int mediaWorkspaceId: PickerManager.playerWorkspace
    // The media icon is in the candidate list of the app icons (one source): changes once to the target
    readonly property string mediaIconPath: mediaSvg(iconPalB)
    readonly property bool tabletWorkspaceFocused: Hyprland.focusedMonitor?.activeWorkspace?.id === tabletWorkspaceId
    // Edit mode of the bar (right-click the logo), set by MainBar
    property bool editMode: false
    // Tablet including the separator can be hidden in edit mode (BarIcons ID "tablet"). If you are
    // on the tablet workspace right now, it stays visible: otherwise the active workspace would have no tile
    readonly property bool tabletShown: editMode || BarIcons.shown("tablet") || tabletWorkspaceFocused
    // 0..1 soft: tablet + separator grow/shrink like an appearing workspace (appearK)
    property real tabletK: tabletShown ? 1 : 0

    Behavior on tabletK {
        NumberAnimation {
            duration: 450
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.inOutSoft
            // Meanwhile MainBar centers without rounding, otherwise the growing strip stutters
            onRunningChanged: workspaceWidget.appearing += running ? 1 : -1
        }

    }
    // ---- Dock magnification (like the macOS dock), only while the mouse is over the workspaces ----
    // Icons grow depending on the distance to the mouse pointer (bell curve), neighbors move aside a bit.
    // Only scale/offset: the width of the bar stays, shape and shadow of the bar are not recomputed.
    // The tile itself does not grow (the bar is only 40 px high), but the icon or number in it.
    readonly property real magMax: 0.22 // extra size right under the mouse pointer
    readonly property real magSigma: 18 // reach of the curve in px (icons stand 35 px apart)
    readonly property real magSpread: 3 // this far the outer tiles move aside
    // Raw mouse position and target strength; magXs/magTs follow them smoothed at the frame rate
    // (see magFollow), so the magnification feels fluid even with irregular mouse events
    property real magX: 0
    readonly property real magTarget: dockHover.hovered ? 1 : 0
    property real magXs: 0
    property real magTs: 0
    // Shared light tile: glides to the workspace under the mouse, otherwise to the active one
    property Item hoverItem: null
    property Item focusedItem: null
    readonly property Item pillItem: dockHover.hovered && hoverItem ? hoverItem : focusedItem
    // The active workspace normally has 20 px of extra room. On hover all icons stand
    // equally far apart; the 20 px move half each to the ends of the row,
    // so the width stays the same and nothing jumps.
    // Directly from Hyprland (not via focusedItem): this way there is no intermediate state
    // without an active workspace on a workspace change, which would briefly switch the spacing
    readonly property bool focusedHere: (Hyprland.focusedMonitor?.activeWorkspace?.id ?? 0) > 0
    readonly property bool evenSpacing: dockHover.hovered && focusedHere && !clickedWhileHovered
    // Click on a workspace: it gets its extra room right away (neighbors move away),
    // until the mouse leaves the workspaces
    property bool clickedWhileHovered: false
    // This much bigger is the icon of the active workspace (before via margins/font size)
    readonly property real focusBoost: 0.2
    // Spacing without a layout change: all tiles are always 35 px wide, the row has a fixed 10 px margin
    // left and right. The extra spacing around the active workspace is made only by offsets:
    // tiles to the left of it move gapShift to the left, to the right of it to the right, it itself
    // stays. Before, tile width and margin animated separately and were supposed to cancel out - the
    // row layout did not apply both in the same tick, the active icon trembled (measured ~0.5 px).
    readonly property int focusedId: Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1
    property real evenK: evenSpacing ? 1 : 0
    readonly property real gapShift: focusedHere ? 10 * (1 - evenK) : 0

    Behavior on evenK {
        NumberAnimation {
            duration: 510
            easing.type: Easing.BezierSpline
            // soft start and end (middle way between Material "standard" and easeInOutSine)
            easing.bezierCurve: Appearance.anim.curves.inOutSoft
        }

    }

    onTabletWorkspaceFocusedChanged: {
        if (tabletWorkspaceFocused)
            focusedItem = tabletItem;

    }

    // Smooths the mouse position and the strength of the magnification (exponentially, independent of the
    // frame rate). Only runs while something is still moving
    FrameAnimation {
        id: magFollow

        running: Math.abs(workspaceWidget.magX - workspaceWidget.magXs) > 0.05 || Math.abs(workspaceWidget.magTarget - workspaceWidget.magTs) > 0.002
        onTriggered: {
            const w = workspaceWidget;
            const kx = 1 - Math.exp(-frameTime * 22);
            const kt = 1 - Math.exp(-frameTime * 12);
            const dx = w.magX - w.magXs;
            const dt = w.magTarget - w.magTs;
            w.magXs = Math.abs(dx) < 0.05 ? w.magX : w.magXs + dx * kx;
            w.magTs = Math.abs(dt) < 0.002 ? w.magTarget : w.magTs + dt * kt;
        }
    }

    // ------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------
    // Magnification of a tile with center cx (coordinates of mainRow)
    function magScale(cx) {
        if (magTs <= 0)
            return 1;

        const d = cx - magXs;
        return 1 + magTs * magMax * Math.exp(-(d * d) / (2 * magSigma * magSigma));
    }

    // Moving aside: 0 right at the mouse pointer, up to magSpread toward the outside
    function magShift(cx) {
        if (magTs <= 0)
            return 0;

        const d = cx - magXs;
        const g = Math.exp(-(d * d) / (2 * magSigma * magSigma));
        return magTs * magSpread * (d < 0 ? -1 : 1) * (1 - g);
    }

    function normalizeTitle(title) {
        return String(title || "").toLowerCase().replace(/[™®©]/g, "").replace(/[^a-z0-9]+/g, "");
    }

    // Icon theme lookup. Returns a usable image source or "" if
    // the icon does not exist (prevents the purple-black placeholder icon).
    function themeIcon(name) {
        if (!name)
            return "";

        let p = "";
        try {
            p = Quickshell.iconPath(name, true);
        } catch (e) {
            p = "";
        }
        if (!p)
            return "";

        return p.startsWith("/") ? "file://" + p : p;
    }

    // Absolute path OR theme name -> image source
    function iconUrl(ref) {
        if (!ref)
            return "";

        if (ref.startsWith("file://") || ref.startsWith("image://"))
            return ref;

        if (ref.startsWith("/"))
            return "file://" + ref;

        return themeIcon(ref);
    }

    // Hyprland with the Lua config no longer understands `hyprctl dispatch workspace N`
    // (the old syntax is read as Lua code -> syntax error). New:
    //   hyprctl dispatch 'hl.dsp.focus({ workspace = "N" })'
    // If Hyprland does not answer "ok" (e.g. still an old hyprlang config),
    // the old syntax is tried automatically.
    function focusWorkspace(id) {
        const n = String(parseInt(id));
        if (n === "NaN")
            return ;

        Quickshell.execDetached(["bash", "-c", "out=$(hyprctl dispatch \"hl.dsp.focus({ workspace = \\\"$1\\\" })\" 2>&1); " + "[ \"$out\" = ok ] || hyprctl dispatch workspace \"$1\"", "_", n]);
    }

    // Right-click on a workspace opens the overview
    function openOverview() {
        Quickshell.execDetached(["qs", "ipc", "call", "workspaceoverview", "toggle"]);
    }

    function requestRescan() {
        if (steamScan.running)
            return ;

        if (Date.now() - lastScan < 15000)
            return ;

        lastScan = Date.now();
        _tmpTitles = ({});
        _tmpNormalized = ({});
        _tmpIcons = ({});
        steamScan.running = true;
    }

    // Fuzzy title comparison on compact strings ("stellarblade").
    // Steam name in the window title OR window title in the Steam name.
    function findAppIdByTitleSubstring(title) {
        const t = normalizeTitle(title);
        if (t === "" || t === "gamescope")
            return "";

        let bestId = "";
        let bestScore = 0;
        for (const n in steamNormalizedMap) {
            let score = 0;
            if (n === t)
                score = 1000;
            else if (n.length >= 4 && t.includes(n))
                score = n.length;
            else if (t.length >= 5 && n.includes(t))
                score = t.length - 1;
            if (score > bestScore) {
                bestScore = score;
                bestId = steamNormalizedMap[n];
            }
        }
        return bestId;
    }

    // Reads SteamGameId/SteamAppId from the environment of the window's process
    // (gamescope inherits them from Steam). Asynchronous: the first call returns "",
    // then pidVersion increases and the bindings re-evaluate.
    function appIdForWindow(win) {
        if (!win || !win.pid)
            return "";

        const key = String(win.pid) + "|" + (win.address || "");
        if (pidAppIds[key] !== undefined)
            return pidAppIds[key];

        if (!_pidPending[key]) {
            _pidPending[key] = true;
            _pidQueue.push({
                "key": key,
                "pid": String(win.pid)
            });
            Qt.callLater(processPidQueue);
        }
        return "";
    }

    function processPidQueue() {
        if (pidProc.running || _pidQueue.length === 0)
            return ;

        const next = _pidQueue.shift();
        pidProc.key = next.key;
        pidProc.pid = next.pid;
        pidProc.running = true;
    }

    // Steam appid for a window:
    // 1) Proton class steam_app_<id>
    // 2) gamescope: SteamGameId from the process (reliable)
    // 3) window title (fuzzy) as a fallback
    function steamAppIdFor(win) {
        const cls = win.class || "";
        if (cls.indexOf("steam_app_") === 0) {
            const id = cls.substring(10);
            if (/^[0-9]+$/.test(id) && id !== "0")
                return id;

        }
        if (!(cls === "gamescope" || cls.indexOf("steam_app_") === 0))
            return "";

        const pidId = appIdForWindow(win);
        if (pidId)
            return pidId;

        const norm = normalizeTitle(win.title);
        if (norm === "" || norm === "gamescope")
            return "";

        if (steamNormalizedMap[norm])
            return steamNormalizedMap[norm];

        return findAppIdByTitleSubstring(win.title);
    }

    // Order: theme icon "steam_icon_<id>" -> cached image -> Steam logo
    function steamCandidates(appId) {
        const out = [];
        const t = themeIcon("steam_icon_" + appId);
        if (t)
            out.push(t);

        const cached = steamIconMap[appId];
        if (cached) {
            out.push(cached);
        } else if (!_rescanned[appId]) {
            // Newly installed game? Rescan once per appid.
            _rescanned[appId] = true;
            Qt.callLater(requestRescan);
        }
        const g = themeIcon("steam");
        if (g)
            out.push(g);

        return out;
    }

    // Returns a CHAIN of icon sources. The first one that can be loaded
    // is shown (see candIdx in the delegate).
    function iconCandidatesFor(win, _mapsVersion, _pidVersion) {
        const list = [];
        if (!win)
            return list;

        const cls = win.class || "";
        const title = win.title || "";
        const lc = cls.toLowerCase();
        const add = (u) => {
            if (u && list.indexOf(u) === -1)
                list.push(u);

        };
        // ---- 1) Own icons from the settings ("icons": "title:<title>", class) ----
        add(Settings.icon("title:" + title));
        add(Settings.icon(lc));
        // Minecraft class changes with the version ("Minecraft* 26.2")
        if (/^minecraft/i.test(cls) || (lc.indexOf("java") !== -1 && /minecraft/i.test(title)))
            add(Settings.icon("minecraft"));

        // ---- 2) Discord (Vesktop & co. also show the normal Discord icon) ----
        if (["vesktop", "discord", "webcord", "armcord", "legcord", "equibop"].indexOf(lc) !== -1) {
            add(Settings.icon("discord"));
            add(themeIcon("discord"));
            add(themeIcon("com.discordapp.Discord"));
        }
        // ---- 3) Steam games ----
        const appId = steamAppIdFor(win);
        if (appId) {
            for (const c of steamCandidates(appId)) add(c)
        } else if (cls === "gamescope") {
            add(themeIcon("steam"));
        }
        // ---- 4) Known classes -> theme icon ----
        const classMap = {
            "code-oss": "code-oss",
            "com.obsproject.studio": "com.obsproject.Studio",
            "obs-studio": "com.obsproject.Studio",
            "zen-alpha": "zen-browser",
            "zen": "zen-browser",
            "openrgb": "openrgb",
            "yazi": "yazi",
            "fzfwindows": "yazi",
            // Terminal stage on workspace 1 (hypr/modules/home.lua): kitty with its own class
            "kitty-stage-shell": "kitty",
            "kitty-stage-music": "kitty"
        };
        if (classMap[lc])
            add(themeIcon(classMap[lc]));

        // ---- 5) Heuristic via desktop entries + class name ----
        if (cls) {
            try {
                const entry = DesktopEntries.heuristicLookup(cls);
                if (entry && entry.icon)
                    add(iconUrl(entry.icon));

            } catch (e) {
            }
            add(themeIcon(cls));
            add(themeIcon(lc));
            add(themeIcon(lc.replace(/\.exe$/, "")));
        }
        return list;
    }

    // Own copy of Hyprland.workspaces (sorted by id): new workspaces grow in,
    // vanished ones stay with leaving=true until they are faded out (dropWorkspace)
    function syncWorkspaces() {
        const ids = Hyprland.workspaces.values.map((w) => w.id);
        const live = {};
        for (const id of ids) live[id] = true;
        const known = {};
        for (let i = 0; i < wsModel.count; i++) {
            const e = wsModel.get(i);
            known[e.wsId] = true;
            if (e.leaving === !!live[e.wsId])
                wsModel.setProperty(i, "leaving", !live[e.wsId]);

        }
        for (const id of ids) {
            if (known[id])
                continue;

            let j = 0;
            while (j < wsModel.count && wsModel.get(j).wsId < id)
                j++;
            wsModel.insert(j, {
                "wsId": id,
                "leaving": false
            });
        }
    }

    function dropWorkspace(id) {
        for (let i = 0; i < wsModel.count; i++) {
            const e = wsModel.get(i);
            if (e.wsId === id && e.leaving) {
                wsModel.remove(i);
                return ;
            }
        }
    }

    NumberAnimation {
        id: iconMixAnim

        target: workspaceWidget
        property: "iconMix"
        from: 0
        to: 1
        // like WalColors.fadeAnim
        easing.type: Easing.InOutQuad
        onFinished: {
            workspaceWidget.iconPalA = workspaceWidget.iconPalB;
            workspaceWidget.iconMix = 0;
        }
    }

    Connections {
        function onFadeTargetChanged() {
            Qt.callLater(workspaceWidget.beginIconFade);
        }

        target: WalColors
    }

    implicitWidth: bg.implicitWidth
    implicitHeight: 40
    Component.onCompleted: {
        iconPalA = iconPalOf(WalColors);
        iconPalB = iconPalA;
        syncWorkspaces();
        if (tabletWorkspaceFocused)
            focusedItem = tabletItem;

        pill.prevItem = pillItem;
    }

    ListModel {
        id: wsModel
    }

    Connections {
        function onValuesChanged() {
            workspaceWidget.syncWorkspaces();
        }

        target: Hyprland.workspaces
    }

    // Do not animate at start (otherwise all workspaces would grow in at the same time)
    property bool wsAnimReady: false
    // Number of workspaces fading in/out right now: meanwhile the module grows/shrinks,
    // the bar then centers it without pixel rounding (see MainBar)
    property int appearing: 0

    Timer {
        interval: 1500
        running: true
        onTriggered: workspaceWidget.wsAnimReady = true
    }

    Process {
        id: pidProc

        property string key: ""
        property string pid: ""

        command: ["bash", "-c", "tr '\\0' '\\n' < /proc/" + pid + "/environ 2>/dev/null | grep -m1 -E '^(SteamGameId|SteamAppId)=[0-9]+' || true"]
        onRunningChanged: {
            if (!running)
                Qt.callLater(workspaceWidget.processPidQueue);

        }

        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/=([0-9]+)/);
                workspaceWidget.pidAppIds[pidProc.key] = (m && m[1] !== "0") ? m[1] : "";
                workspaceWidget.pidVersion++;
            }
        }

    }

    Process {
        id: steamScan

        command: ["bash", workspaceWidget.scanScript]
        running: true
        onExited: (exitCode, exitStatus) => {
            // Only now take it over in one go (clean change signal)
            workspaceWidget.steamTitleMap = workspaceWidget._tmpTitles;
            workspaceWidget.steamNormalizedMap = workspaceWidget._tmpNormalized;
            workspaceWidget.steamIconMap = workspaceWidget._tmpIcons;
            workspaceWidget.mapsVersion++;
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
                    workspaceWidget._tmpTitles[rest] = appId;
                    const n = workspaceWidget.normalizeTitle(rest);
                    if (n !== "")
                        workspaceWidget._tmpNormalized[n] = appId;

                } else if (kind === "I") {
                    workspaceWidget._tmpIcons[appId] = "file://" + rest;
                }
            }
        }

    }

    Rectangle {
        id: bg

        anchors.centerIn: parent
        implicitWidth: mainRow.implicitWidth + 16
        height: 40
        radius: 13
        color: WalColors.withAlpha(WalColors.color2, 0.2)
        border.color: WalColors.withAlpha(WalColors.color2, 0.4)
        border.width: 2

        // The light tile (before fixed to the active workspace): sits behind the workspace under
        // the mouse or behind the active one.
        // - If it stays at the same workspace, it sticks exactly to its position (if the
        //   tile moves through spacing animations, box and icon run congruently, nothing wobbles).
        // - If it changes to another one, it glides over: the offset to the old position is
        //   reduced exponentially at the frame rate (independent of the frame rate, no restart on changes).
        Rectangle {
            id: pill

            property Item prevItem: null
            // Offset to the target position, reduces after a change
            property real offset: 0

            function xFor(it) {
                return it ? mainRow.x + it.cx + workspaceWidget.magShift(it.cx) - width / 2 : 0;
            }

            x: xFor(workspaceWidget.pillItem) + offset
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 11
            color: "#33ffffff"
            visible: workspaceWidget.pillItem !== null

            Connections {
                // On a change continue at the old place and glide over from there
                function onPillItemChanged() {
                    const next = workspaceWidget.pillItem;
                    if (pill.prevItem && next && pill.prevItem !== next)
                        pill.offset = pill.xFor(pill.prevItem) + pill.offset - pill.xFor(next);
                    else
                        pill.offset = 0;
                    pill.prevItem = next;
                }

                target: workspaceWidget
            }

            // Only runs while there is still an offset to reduce
            FrameAnimation {
                running: Math.abs(pill.offset) > 0.05
                onTriggered: {
                    const o = pill.offset * Math.exp(-frameTime * 16);
                    pill.offset = Math.abs(o) < 0.05 ? 0 : o;
                }
            }

        }

        Row {
            id: mainRow

            anchors.centerIn: parent
            spacing: 0
            // Fixed margin for the tiles pushed outward (see gapShift)
            leftPadding: 10
            rightPadding: 10

            // Mouse position for the dock magnification; on leaving it stays,
            // so the effect fades out in place
            HoverHandler {
                id: dockHover

                onHoveredChanged: {
                    if (!hovered)
                        workspaceWidget.clickedWhileHovered = false;

                }

                onPointChanged: {
                    if (!hovered)
                        return ;

                    workspaceWidget.magX = point.position.x;
                    // Freshly moved in: start at the mouse position instead of gliding over from the old one
                    if (workspaceWidget.magTs < 0.01)
                        workspaceWidget.magXs = point.position.x;

                }
            }

            Row {
                id: row

                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Repeater {
                    model: wsModel

                    delegate: Item {
                        id: wsDelegate

                        required property int wsId
                        required property bool leaving
                        readonly property bool isTabletWs: wsId === workspaceWidget.tabletWorkspaceId
                        readonly property bool isFocused: wsId === Hyprland.focusedMonitor?.activeWorkspace?.id
                        readonly property var biggestWindow: HyprlandData.biggestWindowForWorkspace(wsId)
                        // 0..1: fading in/out when the workspace appears or disappears
                        // (the width grows along, the neighbors move aside softly)
                        property real appearK: 1

                        function animateAppear(k) {
                            appearAnim.stop();
                            appearAnim.from = appearK;
                            appearAnim.to = k;
                            appearAnim.start();
                        }
                        // Chain of possible icon sources; candIdx points to the one tried right now.
                        // Important: source ALWAYS stays bound (before, the binding was overwritten on a
                        // load error, afterwards the icon never updated again).
                        readonly property var iconCandidates: wsId === workspaceWidget.mediaWorkspaceId ? [workspaceWidget.mediaIconPath] : workspaceWidget.iconCandidatesFor(biggestWindow, workspaceWidget.mapsVersion, workspaceWidget.pidVersion)
                        readonly property string iconKey: iconCandidates.join("|")
                        property int candIdx: 0
                        readonly property string iconSource: candIdx < iconCandidates.length ? iconCandidates[candIdx] : ""
                        readonly property bool iconReady: dynamicIcon.status === Image.Ready
                        readonly property bool iconExhausted: !!biggestWindow && iconSource === ""
                        // Side relative to the active workspace: -1 left, 0 itself, 1 right (soft on a change)
                        property real side: workspaceWidget.tabletWorkspaceFocused ? -1 : Math.sign(wsId - workspaceWidget.focusedId)
                        readonly property real shift: side * workspaceWidget.gapShift
                        // Visible center in mainRow coordinates (dock magnification, box)
                        readonly property real cx: row.x + x + width / 2 + shift
                        readonly property real mag: workspaceWidget.magScale(cx)
                        readonly property bool isHovered: dockHover.hovered && workspaceWidget.hoverItem === wsDelegate
                        readonly property bool lit: isFocused || isHovered
                        // 0..1, soft: how much the icon is enlarged as the active workspace
                        property real focusK: isFocused ? 1 : 0
                        readonly property real iconScale: mag * (1 + workspaceWidget.focusBoost * focusK)

                        Behavior on focusK {
                            NumberAnimation {
                                duration: Appearance.anim.durations.normal
                                easing.type: Easing.OutCubic
                            }

                        }

                        Behavior on side {
                            NumberAnimation {
                                duration: 510
                                easing.type: Easing.BezierSpline
                                // soft start and end (middle way between Material "standard" and easeInOutSine)
                                easing.bezierCurve: Appearance.anim.curves.inOutSoft
                            }

                        }

                        NumberAnimation {
                            id: appearAnim

                            target: wsDelegate
                            property: "appearK"
                            duration: 450
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.anim.curves.inOutSoft
                            onRunningChanged: workspaceWidget.appearing += running ? 1 : -1
                            onFinished: {
                                if (wsDelegate.leaving && wsDelegate.appearK === 0)
                                    Qt.callLater(workspaceWidget.dropWorkspace, wsDelegate.wsId);

                            }
                        }

                        visible: !isTabletWs
                        width: isTabletWs ? 0 : 35 * appearK
                        height: isTabletWs ? 0 : 40
                        // Move the whole tile (also the click area)
                        transform: Translate {
                            x: wsDelegate.shift
                        }
                        onIconKeyChanged: candIdx = 0
                        onLeavingChanged: animateAppear(leaving ? 0 : 1)
                        onIsFocusedChanged: {
                            if (isFocused)
                                workspaceWidget.focusedItem = wsDelegate;

                        }
                        Component.onCompleted: {
                            if (isFocused)
                                workspaceWidget.focusedItem = wsDelegate;

                            if (workspaceWidget.wsAnimReady) {
                                appearK = 0;
                                animateAppear(1);
                            }
                        }
                        Component.onDestruction: {
                            if (appearAnim.running)
                                workspaceWidget.appearing--;

                        }

                        Rectangle {
                            id: iconBg

                            opacity: wsDelegate.appearK
                            scale: 0.5 + 0.5 * wsDelegate.appearK

                            // Fixed size: the active workspace only gets bigger by scaling
                            // (iconScale), so no geometry changes on a switch.
                            // Do not round to whole pixels: the tile's width animates (growing in),
                            // rounded the icon/kanji jumps pixel by pixel ("trembles"). At rest it lies on whole pixels anyway.
                            // That is why x/y by hand instead of anchors.centerIn: that still snaps to half pixels even with
                            // alignWhenCentered: false (measured) - visible at 60 Hz and an odd scaling on a laptop
                            x: (parent.width - width) / 2
                            y: (parent.height - height) / 2
                            width: 35
                            height: 35
                            radius: 11
                            color: "transparent"

                            transform: Translate {
                                x: workspaceWidget.magShift(wsDelegate.cx)
                            }

                            // Workspace number: when empty OR no icon was found
                            Text {
                                anchors.centerIn: parent
                                scale: wsDelegate.mag * (1 + 0.08 * wsDelegate.focusK)
                                font.family: Theme.font
                                font.pixelSize: 13
                                color: wsDelegate.lit ? "white" : WalColors.withAlpha(WalColors.color2, 0.6)
                                text: WorkspaceNumbers.kanjiNumber(wsDelegate.wsId)
                                visible: !wsDelegate.iconReady && (!wsDelegate.biggestWindow || wsDelegate.iconExhausted)
                            }

                            Item {
                                anchors.fill: parent
                                visible: wsDelegate.iconReady
                                anchors.margins: 6
                                scale: wsDelegate.iconScale

                                // Drawn once onto a high-resolution, mipmapped layer (72 px),
                                // on which MultiEffect desaturates inactive icons a bit. Before, a
                                // desaturate copy at 23 px resolution lay above it: blurry when scaling and
                                // "trembling" against the icon below
                                Image {
                                    id: dynamicIcon

                                    property real sat: wsDelegate.lit ? 0 : -0.35

                                    anchors.fill: parent
                                    source: wsDelegate.iconSource
                                    sourceSize: Qt.size(72, 72)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                    layer.enabled: true
                                    layer.textureSize: Qt.size(72, 72)
                                    layer.smooth: true
                                    layer.mipmap: true
                                    // Loading failed -> next candidate
                                    onStatusChanged: {
                                        if (status === Image.Error)
                                            wsDelegate.candIdx++;

                                    }

                                    layer.effect: MultiEffect {
                                        saturation: dynamicIcon.sat
                                    }

                                    Behavior on sat {
                                        NumberAnimation {
                                            duration: 160
                                        }

                                    }

                                }

                            }

                        }

                        // Click handler with a high z-index, so nothing
                        // lying above catches the click.
                        MouseArea {
                            anchors.fill: parent
                            z: 100
                            // Disappearing workspace: no longer clickable
                            enabled: !wsDelegate.leaving
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: {
                                if (containsMouse)
                                    workspaceWidget.hoverItem = wsDelegate;

                            }
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.LeftButton) {
                                    workspaceWidget.clickedWhileHovered = true;
                                    workspaceWidget.focusWorkspace(wsDelegate.wsId);
                                    mouse.accepted = true;
                                } else if (mouse.button === Qt.RightButton) {
                                    workspaceWidget.openOverview();
                                    mouse.accepted = true;
                                }
                            }
                        }

                    }

                }

            }

            Item {
                id: tabletSeparator

                property real side: workspaceWidget.tabletWorkspaceFocused ? -1 : 1

                visible: workspaceWidget.tabletK > 0.001
                width: 13 * workspaceWidget.tabletK
                height: 40

                transform: Translate {
                    x: tabletSeparator.side * workspaceWidget.gapShift
                }

                Behavior on side {
                    NumberAnimation {
                        duration: 510
                        easing.type: Easing.BezierSpline
                        // soft start and end (middle way between Material "standard" and easeInOutSine)
                        easing.bezierCurve: Appearance.anim.curves.inOutSoft
                    }

                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 20 * (0.5 + 0.5 * workspaceWidget.tabletK)
                    opacity: workspaceWidget.tabletK
                    color: WalColors.withAlpha(WalColors.color2, 0.35)
                }

            }

            Item {
                id: tabletItem

                property real side: workspaceWidget.tabletWorkspaceFocused ? 0 : 1

                visible: workspaceWidget.tabletK > 0.001
                readonly property real shift: side * workspaceWidget.gapShift
                readonly property real cx: x + width / 2 + shift
                readonly property real mag: workspaceWidget.magScale(cx)
                readonly property bool lit: workspaceWidget.tabletWorkspaceFocused || (dockHover.hovered && workspaceWidget.hoverItem === tabletItem)
                property real focusK: workspaceWidget.tabletWorkspaceFocused ? 1 : 0

                Behavior on focusK {
                    NumberAnimation {
                        duration: Appearance.anim.durations.normal
                        easing.type: Easing.OutCubic
                    }

                }

                width: 35 * workspaceWidget.tabletK
                height: 40

                transform: Translate {
                    x: tabletItem.shift
                }

                Behavior on side {
                    NumberAnimation {
                        duration: 510
                        easing.type: Easing.BezierSpline
                        // soft start and end (middle way between Material "standard" and easeInOutSine)
                        easing.bezierCurve: Appearance.anim.curves.inOutSoft
                    }

                }

                Rectangle {
                    id: tabletBg

                    anchors.centerIn: parent
                    anchors.alignWhenCentered: false
                    width: 35
                    height: 35
                    radius: 11
                    color: "transparent"
                    // A colored tile like the app icons: only dim slightly, otherwise it looks washed out.
                    // Own property instead of a Behavior on opacity: the opacity of the icons also depends
                    // on iconMix, which changes every frame (a Behavior would chase it).
                    property real iconDim: tabletItem.lit ? 1 : 0.85

                    Behavior on iconDim {
                        NumberAnimation {
                            duration: 200
                        }

                    }

                    // Fading in/out like the workspace icons
                    opacity: workspaceWidget.tabletK
                    scale: 0.5 + 0.5 * workspaceWidget.tabletK

                    transform: Translate {
                        x: workspaceWidget.magShift(tabletItem.cx)
                    }

                    Image {
                        id: tabletIcon

                        scale: tabletItem.mag * (1 + workspaceWidget.focusBoost * tabletItem.focusK)
                        anchors.fill: parent
                        anchors.margins: 6
                        source: workspaceWidget.tabletIconPath
                        sourceSize: Qt.size(72, 72)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        // synchronous: a small SVG is drawn right away; asynchronously every change of the
                        // source briefly showed the fallback symbol below
                        asynchronous: false
                        // Lower image of the crossfade (see tabletIconNext): chosen so that
                        // both layers together are exactly iconDim opaque
                        opacity: {
                            const m = workspaceWidget.iconMix, d = tabletBg.iconDim;
                            if (m <= 0)
                                return d;

                            if (d * m >= 0.999)
                                return 0;

                            return d * (1 - m) / (1 - d * m);
                        }
                    }

                    // The new icon (target palette) fades in above on a wallpaper change. Sibling instead of
                    // child of tabletIcon: as a child it inherited its 0.85, two semi-transparent layers
                    // on top of each other looked brighter than one, and on the switch at the end the light pad
                    // got darker abruptly. With d*m on top and d*(1-m)/(1-d*m) below, opaque pixels get
                    // exactly d*(m*new + (1-m)*old) + (1-d)*background, without a jump.
                    Image {
                        id: tabletIconNext

                        anchors.fill: tabletIcon
                        scale: tabletIcon.scale
                        visible: workspaceWidget.iconMix > 0
                        source: visible ? workspaceWidget.tabletIconPathNext : ""
                        sourceSize: Qt.size(72, 72)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: false
                        opacity: tabletBg.iconDim * workspaceWidget.iconMix
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: tabletIcon.status !== Image.Ready
                        scale: tabletItem.mag * (1 + 0.08 * tabletItem.focusK)
                        text: "󰓹"
                        font.family: Theme.font
                        font.pixelSize: 16
                        color: tabletItem.lit ? "white" : WalColors.withAlpha(WalColors.color2, 0.6)
                    }


                }

                // Click handler for the tablet icon
                MouseArea {
                    anchors.fill: parent
                    z: 100
                    hoverEnabled: true
                    onContainsMouseChanged: {
                        if (containsMouse)
                            workspaceWidget.hoverItem = tabletItem;

                    }
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            workspaceWidget.clickedWhileHovered = true;
                            workspaceWidget.focusWorkspace(workspaceWidget.tabletWorkspaceId);
                            mouse.accepted = true;
                        } else if (mouse.button === Qt.RightButton) {
                            workspaceWidget.openOverview();
                            mouse.accepted = true;
                        }
                    }
                }

                // Edit mode: click = tablet on/off. Same look as the EditBadge of the other
                // bar icons (MainBar), which cannot be used here: it depends on the reordering there
                // and would replace the tablet's own offset (transform)
                MouseArea {
                    id: tabletEdit

                    readonly property bool on: BarIcons.shown("tablet")
                    // Own soft values for on/off and press: directly on opacity/scale the
                    // Behaviors would restart on every frame of growing (tabletK) and lag behind
                    property real dimK: on ? 0 : 1
                    property real pressK: pressed ? 0.8 : 1

                    Behavior on dimK {
                        NumberAnimation {
                            duration: 160
                        }

                    }

                    Behavior on pressK {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutBack
                        }

                    }

                    anchors.fill: parent
                    z: 200
                    visible: workspaceWidget.editMode
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BarIcons.toggle("tablet")

                    // Grows with the tablet (tabletK), otherwise it stuck out over the separator while fading in
                    Rectangle {
                        anchors.centerIn: parent
                        width: 34
                        height: 32
                        radius: height / 2
                        color: WalColors.withAlpha(WalColors.color0, 0.7)
                        opacity: tabletEdit.dimK * workspaceWidget.tabletK
                        scale: 0.5 + 0.5 * workspaceWidget.tabletK

                    }

                    Rectangle {
                        x: parent.width - width
                        y: Math.max(0, (parent.height - 32) / 2)
                        width: 13
                        height: 13
                        radius: height / 2
                        color: tabletEdit.on ? WalColors.color4 : WalColors.color0
                        border.width: 1.2
                        border.color: tabletEdit.on ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.5)
                        opacity: workspaceWidget.tabletK
                        scale: tabletEdit.pressK * workspaceWidget.tabletK

                        Text {
                            anchors.centerIn: parent
                            text: tabletEdit.on ? "󰄬" : "󰅖"
                            color: tabletEdit.on ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.8)
                            font.family: Theme.font
                            font.pixelSize: 9
                            font.bold: true
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                            }

                        }

                    }

                }

            }

        }

    }

}
