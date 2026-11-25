import "../../common"
import "../../services"
import QtQuick
import QtQuick.Shapes
import Quickshell.Io

// Shared base of the Wi-Fi and Bluetooth pickers (pickers/WifiPicker.qml, BluetoothPicker.qml): PC in the middle,
// same look and animations. Two modes:
// - "devices": connected ones sit on the side on the inner track (wave to the PC), known ones (saved/paired)
//   orbit on the outer one.
// - "scan": the tracks fold into the PC, a radar unfolds, finds appear as blips and light up
//   when the beam brushes them.
// Click = connect/disconnect, right-click = only select.
// The pickers deliver their data, texts and actions through the interface below; nodes and connection waves
// are RadarNode/RadarLink (the delegates come from the picker, because the model lives there).
Item {
    id: root

    // ───────────────────────── Interface (set by the picker) ─────────────────────────
    // Service
    property bool on: false
    property bool available: false
    // Search running (radar beam)
    property bool scanning: false
    // Something is connected: inner track, glow and edge of the PC
    property bool anyConnected: false
    property string title: ""
    property string subtitle: ""
    property string headerGlyph: ""
    // Also with the radio off the host name (dimmed): "Off" is already in the header, the hole shows it as an extinguished disc
    readonly property string pcLabel: !available ? "No adapter" : hostFile.hostName || "This PC"
    // Message of the service (detail line)
    property string notice: ""
    property bool noticeIsError: false
    // Entries for tracks and radar (layout) and the model of the node/line Repeaters
    property var items: []
    property var nodeModel: null
    // RadarNode or RadarLink with the roles of the model (set key, item, state)
    property Component nodeDelegate: null
    property Component linkDelegate: null
    property var selectedItem: null
    property var keyOf: (item) => ""
    // "devices" (on a track) or "scan" (find in the radar)
    property var modeOf: (item) => "devices"
    // Sits on the inner track (connected or connecting right now)
    property var isInner: (item) => false
    // Order on the outer track
    property var outerLess: (a, b) => 0
    // Detail line for the selected entry
    property var glyphOf: (item) => ""
    property var nameOf: (item) => ""
    property var detailInfo: (item) => ""
    property var isConnected: (item) => false
    property var canForget: (item) => false
    // Actions
    property var activate: (item) => {}
    property var forget: (item) => {}
    property var startScan: () => {}
    property var stopScan: () => {}
    property var toggleScan: () => {}
    property var togglePower: () => {}
    property var powerOn: () => {}
    // Request of the service (Wi-Fi password, Bluetooth pairing): card at the bottom of the radar
    property var prompt: null
    // Input field of the request (gets the focus) or null
    property var promptInput: null
    property color promptAccent: WalColors.color4
    property var cancelPrompt: () => {}
    // Extra keys, checked before the shared ones: true = handled
    property var extraKey: (key, event) => false
    // Contents: request card, buttons of the detail line, options at the bottom
    property alias promptContent: promptCol.data
    property alias detailActions: actions.data
    property alias options: optionsRow.data
    // Last shown request (stays while the card fades out)
    property var promptShown: null

    FileView {
        id: hostFile

        property string hostName: ""

        path: "/etc/hostname"
        printErrors: false
        onLoaded: hostName = text().trim()
    }

    // ───────────────────────── Layout ─────────────────────────
    readonly property real pad: 16
    // Same size as the clipboard picker
    readonly property real panelWidth: Math.min(680, width - 48)
    readonly property real panelHeight: Math.min(580, height - 80)
    readonly property real innerWidth: panelWidth - 2 * pad
    readonly property real nodeR: 24
    // Outer radius of the wavy device ring (rings, end of the gas stream): as big as the old bubble
    readonly property real starR: nodeR
    readonly property real pcR: 36
    readonly property string mono: Theme.font
    // Radar geometry (coordinates within "radar")
    readonly property real cx: radar.width / 2
    readonly property real cy: radar.height / 2 - 8
    readonly property real outerRx: radar.width / 2 - 64
    readonly property real outerRy: radar.height / 2 - 52
    // Connected ones sit on the side of this track (top/bottom the distance to the PC would be too small)
    readonly property real innerRx: outerRx * 0.76
    readonly property real innerRy: outerRy * 0.66
    // ───────────────────────── State ─────────────────────────
    property bool intro: true
    property real shown: 0
    property string selectedKey: ""
    property bool confirmForget: false
    // Animation clocks (only run while the picker is visible)
    property real phase: 0
    property real sway: 0
    property real wavePhase: 0
    property real rippleT: 0
    property real busyWave: 0
    property real sweepDeg: 0
    // Rotation angle of the outer track (known entries orbit slowly around the PC)
    property real orbitAngle: 0
    // Node under the mouse pointer. The track keeps going, only this node stops (RadarNode.orbitA),
    // so you can hit it. Deliberately not on selection: a click also selects, it would stay put otherwise.
    property string hoveredKey: ""
    readonly property bool animating: visible && shown > 0.01
    // Pan: the black hole tilts with the mouse (the disc tips sideways, the view height follows the height).
    // panTX/panTY = target (-1..1: mouse relative to the middle of the hole, relative to half the panel, saturated
    // outside), panX/panY follow softly (exponentially, in the hole's FrameAnimation).
    property real panTX: 0
    property real panTY: 0
    property real panX: 0
    property real panY: 0
    // Biggest parallax offset of the nearest star layer in pixels (with the mouse at the panel edge)
    readonly property real parallaxPx: 6

    function updatePan(p) {
        const c = hole.mapToItem(root, hole.width / 2, hole.height / 2);
        panTX = Math.max(-1, Math.min(1, (p.x - c.x) / Math.max(1, panel.width / 2)));
        panTY = Math.max(-1, Math.min(1, (p.y - c.y) / Math.max(1, panel.height / 2)));
    }
    // ───────────────────────── Mode ─────────────────────────
    property string mode: "devices"
    // 0 = tracks, 1 = scan. First half: the old mode clears away, second: the new one builds up.
    property real scanT: mode === "scan" ? 1 : 0
    readonly property string shownMode: scanT >= 0.5 ? "scan" : "devices"
    readonly property real orbitK: clamp01(1 - scanT * 2)
    readonly property real radarK: clamp01(scanT * 2 - 1)
    readonly property bool sweeping: scanning && mode === "scan"
    // Finds keep their place: order of first appearance
    property var seenIndex: ({
    })
    // Key -> RadarNode. The nodes register themselves: Repeater.itemAt is still empty at first when the
    // picker loads asynchronously and does not report again afterwards -> when opening again
    // the connection lines did not find their node.
    property var nodeMap: ({
    })
    property int seenCount: 0
    readonly property var layout: computeLayout(items, mode, shownMode, seenIndex, cx, cy, innerRx, innerRy, outerRx, outerRy)
    readonly property int foundCount: items.filter((n) => {
        return modeOf(n) === "scan";
    }).length

    // When fading in (playIntro): pickers reset their own state
    signal introStarted()


    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    function easeOut(v) {
        return 1 - Math.pow(1 - v, 3);
    }


    function setMode(m) {
        if (m === mode)
            return ;

        if (m === "scan" && !available)
            return ;

        mode = m;
        select("");
        shockAnim.restart();
        pcKick.restart();
        if (m === "scan")
            startScan();
        else
            stopScan();
    }

    function registerNode(key, item) {
        const m = Object.assign({
        }, nodeMap);
        if (item)
            m[key] = item;
        else if (m[key])
            delete m[key];
        nodeMap = m;
    }

    function toggleMode() {
        setMode(mode === "scan" ? "devices" : "scan");
    }

    function registerSeen() {
        const s = Object.assign({
        }, seenIndex);
        let n = seenCount, changed = false;
        for (let i = 0; i < items.length; i++) {
            const a = keyOf(items[i]);
            if (modeOf(items[i]) === "scan" && s[a] === undefined) {
                s[a] = n++;
                changed = true;
            }
        }
        if (changed) {
            seenCount = n;
            seenIndex = s;
        }
    }


    // Scan places (normalized to the radar ellipse). Fixed places instead of an even distribution,
    // so blips do not wander around when more finds appear. Order = fill order.
    readonly property var scanSlots: [[0.5, -0.3], [-0.5, 0.3], [0, -0.92], [0, 0.92], [-0.95, -0.3], [0.95, 0.3], [-0.5, -0.3], [0.5, 0.3], [0.44, -0.9], [-0.44, 0.9], [-0.44, -0.9], [0.44, 0.9], [0.95, -0.3], [-0.95, 0.3]]

    // Per mode only its entries, and only when the transition has arrived in this mode
    // (before that the old ones fly back into the PC).
    function computeLayout(list, mode, shownMode, seen, cx, cy, irx, iry, orx, ory) {
        const pos = {
        };
        const order = [];
        if (mode !== shownMode)
            return {
                "pos": pos,
                "order": order,
                "overflow": 0
            };

        if (mode === "scan") {
            const found = list.filter((n) => {
                return modeOf(n) === "scan";
            });
            found.sort((a, b) => {
                const ia = seen[keyOf(a)] !== undefined ? seen[keyOf(a)] : 1e6;
                const ib = seen[keyOf(b)] !== undefined ? seen[keyOf(b)] : 1e6;
                return ia - ib;
            });
            const m = Math.min(found.length, scanSlots.length);
            for (let i = 0; i < m; i++) {
                const s = scanSlots[i];
                // Small fixed offset per entry -> looks less like a grid
                let h = 0;
                const a = keyOf(found[i]);
                for (let c = 0; c < a.length; c++) h = (h * 31 + a.charCodeAt(c)) % 9973
                // As angle + distance on the radar ellipse: the finds orbit like the track (all together,
                // the distances to each other stay, nothing overlaps)
                const sx = s[0] + ((h % 7) - 3) * 0.012, sy = s[1] + ((h % 5) - 2) * 0.03;
                const rho = Math.hypot(sx, sy), sa = Math.atan2(sy, sx);
                pos[a] = {
                    "x": cx + orx * sx,
                    "y": cy + ory * sy,
                    "orbit": true,
                    "a": sa,
                    "rx": orx * rho,
                    "ry": ory * rho
                };
                order.push(a);
            }
            return {
                "pos": pos,
                "order": order,
                "overflow": Math.max(0, found.length - m)
            };
        }
        const inner = [], outer = [];
        for (let i = 0; i < list.length; i++) {
            const n = list[i];
            if (modeOf(n) !== "devices")
                continue;

            if (isInner(n))
                inner.push(n);
            else
                outer.push(n);
        }
        inner.sort((a, b) => {
            return keyOf(a).localeCompare(keyOf(b));
        });
        outer.sort(outerLess);
        const maxOuter = 20;
        const n = inner.length;
        // Alternating right/left of the PC, per side in a fan around the horizontal:
        // there the ellipse is widest -> long, well visible connection waves.
        const right = Math.ceil(n / 2), left = n - right;
        for (let i = 0; i < n; i++) {
            const onRight = i % 2 === 0;
            const k = Math.floor(i / 2);
            const count = onRight ? right : left;
            const fan = Math.min(Math.PI / 4, (count - 1) * Math.PI / 9);
            const off = count > 1 ? -fan + 2 * fan * k / (count - 1) : 0;
            const a = onRight ? off : Math.PI - off;
            pos[keyOf(inner[i])] = {
                "x": cx + irx * Math.cos(a),
                "y": cy + iry * Math.sin(a)
            };
            order.push(keyOf(inner[i]));
        }
        const m = Math.min(outer.length, maxOuter);
        const step = 2 * Math.PI / Math.max(1, m);
        const stagger = m > 10;
        for (let i = 0; i < m; i++) {
            // Half a step offset from the horizontal: right/left (the place of the connected ones) stays a gap
            const a = step / 2 + i * step;
            const lane = (stagger && i % 2 === 1) ? 0.8 : 1;
            // Known but not connected: orbits slowly on the track (angle + root.orbitAngle,
            // evaluated in RadarNode, so the layout is not rebuilt every frame)
            pos[keyOf(outer[i])] = {
                "x": cx + orx * lane * Math.cos(a),
                "y": cy + ory * lane * Math.sin(a),
                "orbit": true,
                "a": a,
                "rx": orx * lane,
                "ry": ory * lane
            };
            order.push(keyOf(outer[i]));
        }
        return {
            "pos": pos,
            "order": order,
            "overflow": Math.max(0, outer.length - maxOuter)
        };
    }

    function focusSearch() {
        if (promptInput)
            promptInput.forceActiveFocus();
        else
            keys.forceActiveFocus();
    }

    // Focus back to the keyboard control (request without an input field closed)
    function focusKeys() {
        keys.forceActiveFocus();
    }

    function pingPc() {
        pcPingAnim.restart();
    }

    function select(key) {
        if (selectedKey !== key)
            confirmForget = false;

        selectedKey = key;
    }

    function moveSelection(dir) {
        const order = layout.order;
        if (order.length === 0)
            return ;

        const i = order.indexOf(selectedKey);
        if (i === -1)
            select(order[dir > 0 ? 0 : order.length - 1]);
        else
            select(order[(i + dir + order.length) % order.length]);
    }

    function forgetSelected() {
        const n = selectedItem;
        if (!n || !canForget(n))
            return ;

        if (!confirmForget) {
            confirmForget = true;
            forgetTimer.restart();
            return ;
        }
        confirmForget = false;
        selectedKey = "";
        forget(n);
    }

    function playIntro() {
        outroAnim.stop();
        intro = true;
        introTimer.restart();
        introAnim.restart();
        confirmForget = false;
        introStarted();
    }

    function playOutro() {
        introAnim.stop();
        outroAnim.restart();
    }

    Component.onCompleted: {
        playIntro();
        registerSeen();
    }
    onVisibleChanged: {
        if (visible)
            playIntro();

    }
    onItemsChanged: registerSeen()
    // No radar without radio/adapter
    onOnChanged: {
        if (!on)
            setMode("devices");

    }
    onPromptChanged: {
        if (prompt)
            promptShown = prompt;

    }

    Behavior on scanT {
        NumberAnimation {
            duration: 1100
            easing.type: Easing.InOutCubic
        }

    }

    // Shock wave that runs from the PC over the whole field on a mode change
    property real shock: 1

    NumberAnimation {
        id: shockAnim

        target: root
        property: "shock"
        from: 0
        to: 1
        duration: 1000
        easing.type: Easing.OutCubic
    }

    // The PC contracts briefly on a change and then "fires"
    property real pcBoost: 0

    SequentialAnimation {
        id: pcKick

        NumberAnimation {
            target: root
            property: "pcBoost"
            to: -0.14
            duration: 160
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: root
            property: "pcBoost"
            to: 0.1
            duration: 220
            easing.type: Easing.OutBack
        }

        NumberAnimation {
            target: root
            property: "pcBoost"
            to: 0
            duration: 420
            easing.type: Easing.OutCubic
        }

    }

    // One round in 90 s: calm enough that it does not distract
    NumberAnimation on orbitAngle {
        from: 0
        to: 2 * Math.PI
        duration: 90000
        loops: Animation.Infinite
        running: root.animating
    }

    // Clock for sparkling, nebula drift and the black hole (seconds)
    property real starTime: 0

    NumberAnimation on starTime {
        from: 0
        to: 3600
        duration: 3600000
        loops: Animation.Infinite
        running: root.animating
    }

    NumberAnimation on sweepDeg {
        from: 0
        to: 360
        duration: 3200
        loops: Animation.Infinite
        running: root.animating && root.sweeping
    }

    // ───────────────────────── Timers & animations ─────────────────────────
    Timer {
        id: introTimer

        interval: 700
        running: true
        onTriggered: root.intro = false
    }

    Timer {
        id: forgetTimer

        interval: 2600
        onTriggered: root.confirmForget = false
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

    NumberAnimation {
        id: outroAnim

        target: root
        property: "shown"
        to: 0
        duration: 200
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.accelerate
    }

    NumberAnimation on phase {
        from: 0
        to: 1
        duration: 1500
        loops: Animation.Infinite
        running: root.animating
    }

    // Phase of the connection waves (speed like the wave in the language player)
    NumberAnimation on wavePhase {
        from: 0
        to: 2 * Math.PI
        duration: 2000
        loops: Animation.Infinite
        running: root.animating
    }

    NumberAnimation on sway {
        from: 0
        to: 2 * Math.PI
        duration: 7000
        loops: Animation.Infinite
        running: root.animating
    }

    NumberAnimation on rippleT {
        from: 0
        to: 1
        duration: 2700
        loops: Animation.Infinite
        running: root.animating && root.sweeping
    }

    SequentialAnimation on busyWave {
        loops: Animation.Infinite
        running: root.animating

        NumberAnimation {
            from: 0
            to: 1
            duration: 750
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1
            to: 0
            duration: 750
            easing.type: Easing.InOutSine
        }

    }

    // Click outside the panel closes the picker.
    MouseArea {
        anchors.fill: parent
        onClicked: PickerManager.close()
    }

    // Mouse anywhere in the picker (takes no events away): target for the pan of the hole.
    // If it leaves the window, the hole slowly returns to its rest position.
    HoverHandler {
        onPointChanged: {
            if (hovered)
                root.updatePan(point.position);

        }
        onHoveredChanged: {
            if (!hovered) {
                root.panTX = 0;
                root.panTY = 0;
            }
        }
    }

    // Keyboard (the focus lies here while no input of the request is open)
    Item {
        id: keys

        focus: true
        Keys.onPressed: (event) => {
            // Ctrl+J/K = arrow down/up, the same in all pickers (PickerManager.navKey)
            const key = PickerManager.navKey(event);
            if (root.extraKey(key, event)) {
                event.accepted = true;
                return ;
            }
            switch (key) {
            case Qt.Key_Escape:
                if (root.prompt)
                    root.cancelPrompt();
                else if (root.selectedKey !== "")
                    root.select("");
                else if (root.mode === "scan")
                    root.setMode("devices");
                else
                    PickerManager.close();
                break;
            case Qt.Key_Right:
            case Qt.Key_Down:
                root.moveSelection(1);
                break;
            case Qt.Key_Left:
            case Qt.Key_Up:
                root.moveSelection(-1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (root.selectedItem)
                    root.activate(root.selectedItem);
                break;
            case Qt.Key_S:
                root.toggleMode();
                break;
            case Qt.Key_Space:
                // In scan mode: restart / stop the search
                if (root.mode === "scan")
                    root.toggleScan();
                else
                    root.setMode("scan");
                break;
            case Qt.Key_P:
                root.togglePower();
                break;
            case Qt.Key_Delete:
                root.forgetSelected();
                break;
            default:
                return ;
            }
            event.accepted = true;
        }
    }


    // ═════════════════════════ Panel ═════════════════════════
    Item {
        id: panel

        width: root.panelWidth
        height: root.panelHeight
        x: (root.width - width) / 2
        y: Math.max(40, root.height * 0.12) + (1 - root.shown) * 24
        opacity: Math.min(1, root.shown * 1.6)
        scale: 0.95 + 0.05 * root.shown
        transformOrigin: Item.Top

        SoftShadow {
            panel: true
        }

        // Plain starry sky (pickers/shaders/galaxy.frag): flat background, few stars with parallax,
        // a faint glow and a subtle dust swirl around the PC
        ShaderEffect {
            id: space

            property real time: root.starTime
            property real scan: root.radarK
            // Search beam: angle (radians, clockwise like root.sweepDeg), strength, radar ellipse
            property real sweep: root.sweepDeg * Math.PI / 180
            property real sweepOn: sweepBox.opacity
            property point scanAxes: Qt.point(root.outerRx + 30, root.outerRy + 30)
            property real power: root.on ? 1 : 0
            property real cornerR: 28
            property real alpha: 0.97
            property size size: Qt.size(width, height)
            property point center: Qt.point(radar.x + root.cx, radar.y + root.cy)
            property point orbit: Qt.point(root.outerRx, root.outerRy)
            property color bg: WalColors.color0
            property color vivid: WalColors.vividAccent
            property color starColor: WalColors.color7
            // Parallax of the nearest star layer (pixels), against the mouse: the hole tilts toward the mouse,
            // the sky behind moves away. The far layer and the swirl only get part of it in the shader.
            property point pan: Qt.point(-root.panX * root.parallaxPx, -root.panY * root.parallaxPx * 0.75)

            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("../shaders/galaxy.frag.qsb")

            Behavior on power {
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }

            }

        }

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: "transparent"
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.1)
        }

        // Sparkle stars (places as a share of the panel, outside the tracks and controls). The frontmost
        // stars: parallax a bit stronger than the nearest layer in the shader. The place is rounded to whole pixels
        // (half pixels made the fine rays flicker on redraw); the parallax shifts the star as a
        // finished image (layer, softly filtered) - so it glides smoothly instead of jumping pixel by pixel.
        Repeater {
            model: [[0.07, 0.24, 6, 0], [0.915, 0.72, 7, 4.4], [0.94, 0.27, 4, 1.7]]

            Sparkle {
                required property var modelData

                x: Math.round(panel.width * modelData[0] - width / 2)
                y: Math.round(panel.height * modelData[1] - height / 2)
                layer.enabled: true
                layer.smooth: true
                transform: Translate {
                    x: -root.panX * root.parallaxPx * 1.3
                    y: -root.panY * root.parallaxPx * 0.75 * 1.3
                }
                size: modelData[2]
                color: Qt.lighter(WalColors.color7, 1.05)
                glowColor: WalColors.vividAccent
                // Each in its own rhythm, so they do not pulse together
                twinkle: 0.5 + 0.5 * Math.sin(root.starTime * (0.5 + modelData[3] * 0.06) + modelData[3])
                opacity: root.on ? 0.8 : 0.45
            }

        }

        // Swallows clicks on the panel so the backdrop doesn't close it.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.select("");
                root.focusSearch();
            }
        }

        // ───────────── Header ─────────────
        Item {
            id: header

            x: root.pad
            y: root.pad
            width: root.innerWidth
            height: 44

            Rectangle {
                id: badge

                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: height / 2
                color: root.on ? WalColors.withAlpha(WalColors.color4, 0.16) : WalColors.withAlpha(WalColors.color7, 0.06)

                Text {
                    anchors.centerIn: parent
                    text: root.headerGlyph
                    font.family: root.mono
                    font.pixelSize: 20
                    color: root.on ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.4)
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }

                }

            }

            Column {
                anchors.left: badge.right
                anchors.leftMargin: 12
                anchors.right: headerButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: root.title
                    font.family: root.mono
                    font.pixelSize: 15
                    font.bold: true
                    color: WalColors.color7
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.subtitle
                    font.family: root.mono
                    font.pixelSize: 10
                    color: WalColors.withAlpha(WalColors.color7, 0.45)
                }

            }

            Row {
                id: headerButtons

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                // Scan mode on/off
                Rectangle {
                    id: scanBtn

                    readonly property bool active: root.mode === "scan"

                    anchors.verticalCenter: parent.verticalCenter
                    width: scanRow.implicitWidth + 28
                    height: 36
                    radius: height / 2
                    color: active ? WalColors.withAlpha(WalColors.color4, scanArea.containsMouse ? 0.3 : 0.2) : WalColors.withAlpha(WalColors.color7, scanArea.containsMouse ? 0.11 : 0.06)
                    opacity: root.on ? 1 : 0.4
                    scale: scanArea.pressed ? 0.95 : 1

                    Row {
                        id: scanRow

                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(scanBtn.active ? 0xf004d : 0xf0437)
                            font.family: root.mono
                            font.pixelSize: 15
                            color: scanBtn.active ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.7)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: scanBtn.active ? "Done" : "Scan"
                            font.family: root.mono
                            font.pixelSize: 12
                            font.bold: scanBtn.active
                            color: scanBtn.active ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.75)
                        }

                    }

                    MouseArea {
                        id: scanArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.toggleMode();
                            root.focusSearch();
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 160
                        }

                    }

                    Behavior on width {
                        Springy {
                        }

                    }

                    Behavior on scale {
                        Springy {
                        }

                    }

                }

                // On/off switch
                Rectangle {
                    id: powerSwitch

                    anchors.verticalCenter: parent.verticalCenter
                    width: 50
                    height: 28
                    radius: height / 2
                    color: root.on ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, powerArea.containsMouse ? 0.16 : 0.1)
                    opacity: root.available ? 1 : 0.4

                    Rectangle {
                        x: root.on ? parent.width - width - 4 : 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: height / 2
                        color: root.on ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.6)

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xf0425)
                            font.family: root.mono
                            font.pixelSize: 11
                            color: root.on ? WalColors.color4 : WalColors.color0
                        }

                        Behavior on x {
                            Springy {
                            }

                        }

                    }

                    MouseArea {
                        id: powerArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.togglePower();
                            root.focusSearch();
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }

                    }

                }

            }

        }

        // ───────────── Radar ─────────────
        Item {
            id: radar

            x: root.pad
            y: header.y + header.height + 4
            width: root.innerWidth
            height: panel.height - y - detail.height - footer.height - root.pad - 8

            // Tracks (device mode): two fine lines. When switching to the scan they spiral into the PC.
            Item {
                anchors.fill: parent
                opacity: (root.on ? 1 : 0.35) * root.orbitK
                visible: root.orbitK > 0.001
                transform: [
                    Rotation {
                        origin.x: root.cx
                        origin.y: root.cy
                        angle: -60 * (1 - root.orbitK)
                    },
                    Scale {
                        origin.x: root.cx
                        origin.y: root.cy
                        xScale: 0.12 + 0.88 * root.easeOut(root.orbitK)
                        yScale: xScale
                    }
                ]

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: WalColors.withAlpha(WalColors.color7, 0.06)
                        strokeWidth: 1
                        fillColor: "transparent"
                        startX: root.cx + root.outerRx
                        startY: root.cy

                        PathAngleArc {
                            centerX: root.cx
                            centerY: root.cy
                            radiusX: root.outerRx
                            radiusY: root.outerRy
                            startAngle: 0
                            sweepAngle: 360
                        }

                    }

                    ShapePath {
                        strokeColor: WalColors.withAlpha(WalColors.vividAccent, root.anyConnected ? 0.16 : 0.07)
                        strokeWidth: 1
                        fillColor: "transparent"
                        startX: root.cx + root.innerRx
                        startY: root.cy

                        PathAngleArc {
                            centerX: root.cx
                            centerY: root.cy
                            radiusX: root.innerRx
                            radiusY: root.innerRy
                            startAngle: 0
                            sweepAngle: 360
                        }

                    }

                }

            }

            // Scan mode: finely dotted rings like orbits that unfold one after another from the PC.
            // The beam itself is drawn by the background shader (it lights up the stars it brushes).
            Shape {
                id: radarGrid

                readonly property real rx: root.outerRx + 30
                readonly property real ry: root.outerRy + 30

                function ringK(i) {
                    return root.easeOut(root.clamp01(root.radarK * 1.7 - i * 0.35));
                }

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: root.radarK > 0.001

                RangeRing {
                    size: 0.36
                    k: radarGrid.ringK(0)
                }

                RangeRing {
                    size: 0.68
                    k: radarGrid.ringK(1)
                }

                RangeRing {
                    size: 1
                    k: radarGrid.ringK(2)
                    strong: true
                }

            }

            // Shock wave on a mode change
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: root.shock < 0.999

                ShapePath {
                    id: shockPath

                    readonly property real f: root.pcR / (root.outerRx + 50) + (1 - root.pcR / (root.outerRx + 50)) * root.shock

                    strokeColor: WalColors.withAlpha(Qt.lighter(WalColors.color4, 1.2), 0.75 * (1 - root.shock))
                    strokeWidth: 1 + 4 * (1 - root.shock)
                    fillColor: WalColors.withAlpha(WalColors.color4, 0.05 * (1 - root.shock))
                    startX: root.cx + (root.outerRx + 50) * f
                    startY: root.cy

                    PathAngleArc {
                        centerX: root.cx
                        centerY: root.cy
                        radiusX: (root.outerRx + 50) * shockPath.f
                        radiusY: (root.outerRy + 40) * shockPath.f
                        startAngle: 0
                        sweepAngle: 360
                    }

                }

            }

            // Search: gravitational waves running out from the black hole (squashed onto the radar ellipse).
            // The beam lies in the background shader; root.sweepDeg tells the shader and the finds where it is right now.
            Item {
                id: sweepBox

                // The beam fades out when the search is over (the radar stays)
                property real live: root.sweeping ? 1 : 0

                x: root.cx - width / 2
                y: root.cy - height / 2
                width: 2 * (root.outerRx + 30)
                height: width
                opacity: live * root.radarK
                visible: opacity > 0.01

                Behavior on live {
                    Smooth {
                        duration: Appearance.anim.durations.slow
                    }

                }

                transform: Scale {
                    origin.x: sweepBox.width / 2
                    origin.y: sweepBox.height / 2
                    yScale: (root.outerRy + 30) / (root.outerRx + 30)
                }

                Repeater {
                    model: 3

                    Rectangle {
                        required property int index
                        readonly property real t: (root.rippleT + index / 3) % 1

                        anchors.centerIn: parent
                        width: (root.pcR + t * (sweepBox.width / 2 - root.pcR)) * 2
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: WalColors.withAlpha(WalColors.vividAccent, 0.22 * (1 - t) * Math.min(1, t * 6))
                    }

                }

            }


            // Connection lines (below the nodes)
            Repeater {
                model: root.nodeModel
                delegate: root.linkDelegate
            }

            // The PC in the middle
            Item {
                id: pc

                x: root.cx - root.pcR
                y: root.cy - root.pcR
                width: 2 * root.pcR
                height: 2 * root.pcR
                // Hover is shown by the shader (orbit ring, comet); here only a touch of size
                // Only hover enlarges slightly; no press effect on click (a click no longer starts anything)
                scale: (pcArea.containsMouse ? 1.02 : 1) + root.pcBoost

                // Black hole with an accretion disk (pickers/shaders/blackhole.frag), ported from the Obsidian plugin
                // (real ray tracing). Bigger than the PC: the disc sticks out far to the sides,
                // the shadow fills the PC circle.
                ShaderEffect {
                    id: hole

                    // Own clock: runs faster on hover. Accumulated instead of time * speed, otherwise the
                    // disc jumped to a completely different angle on a speed change.
                    // Clocks for the shader quantized to 30 frames/s: the layer around it only redraws when
                    // a value changes -> the expensive ray tracing runs half as often (you do not see it)
                    property real clock: 0
                    // Also with the radio off: the extinguished disc keeps turning, only slowly
                    readonly property real starQ: Math.floor(root.starTime * 30) / 30
                    property real time: Math.floor(clock * 30) / 30
                    property real hoverK: pcArea.containsMouse ? 1 : 0
                    // Scan: the disc turns faster and wobbles around the hole (precession of the normal),
                    // meanwhile the comet circles on the orbit ring. scanK fades in and out softly.
                    property real scanK: root.sweeping ? 1 : 0
                    // Quantized to 30 frames/s like the clocks (scanQ, precess: only set in the rhythm of stepAcc)
                    property real scanQ: 0
                    property real precess: restAngle
                    property real stepAcc: 0
                    readonly property real restAngle: Math.atan2(0.03, -0.17)
                    readonly property real tumble: 0.24
                    // Shader value "hover" = orbit ring + comet + some brightness: mouse or scan
                    property real hover: Math.max(hoverK, 0.8 * scanQ)
                    // Brightness and tilt move slowly around their rest values; in the scan the tilt goes
                    // around once (seen from below the image of the disc bends over the shadow).
                    property real pulse: 0.5 + 0.5 * Math.sin(starQ * 1.05)
                    readonly property real restX: -0.17 + 0.025 * Math.sin(starQ * 0.52)
                    readonly property real restZ: 0.03 + 0.018 * Math.cos(starQ * 0.52)
                    // Pan with the mouse (root.panX/panY, taken over in the 30 fps rhythm like the clocks): sideways the
                    // disc tips (normal in x), mouse on top = steeper view from above, bottom = flatter (edge on)
                    property real panQX: 0
                    property real panQY: 0
                    property vector4d nrm: Qt.vector4d(restX + (tumble * Math.cos(precess) - restX) * scanQ + 0.16 * panQX, 1, restZ + (tumble * Math.sin(precess) - restZ) * scanQ, 0)
                    // Image section (half width in Schwarzschild radii) and view height above the disc
                    property real view: 13.2
                    property real elev: 0.16 - panQY * (panQY < 0 ? 0.11 : 0.07)
                    // Shadow radius in pixels: fills about the PC circle
                    readonly property real shadowPx: root.pcR * 0.68
                    property real power: root.on ? 1 : 0
                    // On/off animation of the disc (shader value ignite = position of the front): turning on ignites it
                    // from the inside out, turning off cools it from the outside in. Longer than power,
                    // so you see the front travel; one curve for both directions (binding the easing to the state
                    // started the animation with the old curve).
                    property real ignite: root.on ? 1 : 0
                    // Connected: calm glow. Search: the hole pulses as a transmitter in the rhythm of busyWave
                    // (not via a Behavior - that restarted on every frame and lagged behind).
                    property real connGlow: root.anyConnected ? 1 : 0
                    property real glow: Math.max(connGlow, sweepBox.opacity * (0.4 + 0.8 * root.busyWave))
                    property color accent: WalColors.vividAccent
                    property color hot: Qt.lighter(WalColors.color7, 1.08)
                    property color shade: Qt.tint("#09090c", WalColors.withAlpha(WalColors.color0, 0.08))

                    anchors.centerIn: parent
                    // Apparent shadow radius = 2.598 rs (capture impact parameter)
                    width: Math.round(2 * shadowPx * view / 2.598)
                    height: width
                    fragmentShader: Qt.resolvedUrl("../shaders/blackhole.frag.qsb")
                    // Render into a texture with EXACTLY double resolution and scale down softly: at factor 2
                    // bilinear filtering averages exactly 2x2 texels per pixel. At 1.5 it picked out single
                    // texels, the photon ring of ~1 texel became dashed; with 80 % and
                    // upscaling everything looked pixelated. Mipmaps only made it blurry. Measured
                    // (RX 9070, 60 instead of 30 frames/s): GPU load 30 % (80 %) -> 34 % (2x, 2 rays per pixel),
                    // idle 21-23 %. The layer only redraws 30 times per second.
                    layer.enabled: true
                    layer.smooth: true
                    layer.textureSize: Qt.size(Math.round(width * 2), Math.round(height * 2))

                    Behavior on power {
                        NumberAnimation {
                            duration: 700
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on ignite {
                        NumberAnimation {
                            duration: 1400
                            easing.bezierCurve: Appearance.anim.curves.inOutSoft
                        }

                    }

                    FrameAnimation {
                        running: root.animating
                        onTriggered: {
                            // extinguished (power 0) a quarter of the speed
                            hole.clock += frameTime * 1.6 * (0.25 + 0.75 * hole.power) * (1 + 1.8 * hole.hoverK + 1.4 * hole.scanK);
                            // Follow the pan softly (independent of the frame rate: 1 - e^(-t/tau), tau ~0.2 s;
                            // with 0.35 s the sky felt laggy/sluggish when moving)
                            const panK = 1 - Math.exp(-frameTime * 5);
                            root.panX += (root.panTX - root.panX) * panK;
                            root.panY += (root.panTY - root.panY) * panK;
                            hole.stepAcc += frameTime;
                            if (hole.stepAcc < 1 / 30)
                                return;

                            hole.panQX = root.panX;
                            hole.panQY = root.panY;

                            // One round in ~11 s; without a scan the angle waits at rest, so the next
                            // scan starts from the rest tilt without a jump
                            if (hole.scanK > 0)
                                hole.precess += hole.stepAcc * 0.55 * hole.scanK;
                            else
                                hole.precess = hole.restAngle;
                            hole.scanQ = hole.scanK;
                            hole.stepAcc = 0;
                        }
                    }

                    Behavior on hoverK {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on scanK {
                        NumberAnimation {
                            duration: 1600
                            easing.type: Easing.InOutSine
                        }

                    }

                    Behavior on connGlow {
                        NumberAnimation {
                            duration: 500
                        }

                    }

                }

                // Ping on connecting (triggered by LinkLine)
                Rectangle {
                    id: pcPing

                    property real t: 1

                    anchors.centerIn: parent
                    width: parent.width * (1 + 0.6 * t)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: WalColors.withAlpha(WalColors.color4, 0.6 * (1 - t))

                    NumberAnimation on t {
                        id: pcPingAnim

                        running: false
                        from: 0
                        to: 1
                        duration: 700
                        easing.type: Easing.OutCubic
                    }

                }

                Item {
                    id: pcCaption

                    readonly property var glyphs: {
                        const chars = Array.from(root.pcLabel.toUpperCase());
                        return chars.length > 28 ? chars.slice(0, 27).concat("…") : chars;
                    }
                    property real tracking: captionMetrics.font.pixelSize * (pcArea.containsMouse ? 0.5 : 0.42)
                    readonly property real advance: captionMetrics.advanceWidth + tracking
                    readonly property real arcRadius: Math.max(root.pcR * 2.35, advance * glyphs.length)
                    property color ink: pcArea.containsMouse && root.on
                        ? WalColors.withAlpha("#fffaf2", 0.95)
                        : WalColors.withAlpha("#fff4e8", root.on ? 0.66 : 0.4)

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 8
                    width: 2 * arcRadius
                    height: captionMetrics.boundingRect.height
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.pcLabel

                    TextMetrics {
                        id: captionMetrics

                        text: "M"
                        font.family: root.mono
                        font.pixelSize: Theme.sizeSmall
                        font.weight: Font.Medium
                    }

                    Behavior on ink {
                        ColorAnimation {
                            duration: 300
                        }
                    }

                    Behavior on tracking {
                        Smooth {
                            duration: 400
                        }
                    }

                    Repeater {
                        model: pcCaption.glyphs

                        Text {
                            required property int index
                            required property string modelData
                            readonly property real angle: (index - (pcCaption.glyphs.length - 1) / 2)
                                * pcCaption.advance / pcCaption.arcRadius

                            x: pcCaption.width / 2 + pcCaption.arcRadius * Math.sin(angle) - width / 2
                            y: pcCaption.arcRadius * (Math.cos(angle) - 1)
                            transformOrigin: Item.Bottom
                            rotation: -angle * 180 / Math.PI
                            text: modelData
                            font: captionMetrics.font
                            color: pcCaption.ink
                            style: Text.Outline
                            styleColor: Qt.rgba(0, 0, 0, 0.55)
                            Accessible.ignored: true
                        }
                    }
                }

                // Click on the PC: only when off = turn on. Only the scan button (or S/space) starts a scan;
                // before, a click on the hole started the scan, that was unwanted. Hover stays (the hole reacts to the mouse).
                MouseArea {
                    id: pcArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.on ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (!root.on)
                            root.powerOn();
                        root.focusSearch();
                    }
                }

            }

            // Nodes
            Repeater {
                id: nodes

                model: root.nodeModel
                delegate: root.nodeDelegate
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: "+" + root.layout.overflow + " more"
                font.family: root.mono
                font.pixelSize: 10
                color: WalColors.withAlpha(WalColors.color7, 0.38)
                visible: root.layout.overflow > 0
            }

            // Request of the service (Wi-Fi password, Bluetooth pairing). The content comes from the picker (promptContent)
            Rectangle {
                id: promptCard

                readonly property bool open: root.prompt !== null

                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - height - 6 + (open ? 0 : 16)
                width: Math.min(parent.width - 40, 440)
                height: promptCol.implicitHeight + 28
                radius: 20
                color: WalColors.withAlpha(WalColors.color0, 0.98)
                border.width: 1.5
                border.color: WalColors.withAlpha(root.promptAccent, 0.5)
                opacity: open ? 1 : 0
                visible: opacity > 0.01

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: promptCol

                    x: 18
                    y: 14
                    width: parent.width - 36
                    spacing: 10
                }

                Behavior on opacity {
                    Smooth {
                        duration: 220
                    }

                }

                Behavior on y {
                    Smooth {
                    }

                }

            }

        }

        // ───────────── Details of the selected entry ─────────────
        Rectangle {
            id: detail

            readonly property var n: root.selectedItem

            x: root.pad
            y: radar.y + radar.height + 4
            width: root.innerWidth
            height: 60
            radius: 20
            color: WalColors.withAlpha(WalColors.color7, n ? 0.06 : (root.notice !== "" ? 0.035 : 0))

            Behavior on color {
                ColorAnimation {
                    duration: 160
                }

            }

            // Nothing selected: message or hint
            Text {
                anchors.centerIn: parent
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: !detail.n
                text: root.notice
                font.family: root.mono
                font.pixelSize: 11
                color: root.notice !== "" ? (root.noticeIsError ? Theme.bad : WalColors.color4) : WalColors.withAlpha(WalColors.color7, 0.38)
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                visible: detail.n !== null

                Rectangle {
                    id: detailIcon

                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    radius: height / 2
                    color: detail.n && root.isConnected(detail.n) ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.07)

                    Text {
                        anchors.centerIn: parent
                        text: root.glyphOf(detail.n)
                        font.family: root.mono
                        font.pixelSize: 18
                        color: detail.n && root.isConnected(detail.n) ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.75)
                    }

                }

                Column {
                    anchors.left: detailIcon.right
                    anchors.leftMargin: 12
                    anchors.right: actions.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.nameOf(detail.n)
                        font.family: root.mono
                        font.pixelSize: 13
                        font.bold: true
                        color: WalColors.color7
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: {
                            const n = detail.n;
                            if (!n)
                                return "";

                            if (root.notice !== "")
                                return root.notice;

                            return root.detailInfo(n);
                        }
                        font.family: root.mono
                        font.pixelSize: 10
                        color: root.notice !== "" ? (root.noticeIsError ? Theme.bad : WalColors.color4) : WalColors.withAlpha(WalColors.color7, 0.45)
                    }

                }

                Row {
                    id: actions

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                }

            }

        }

        // ───────────── Settings ─────────────
        Item {
            id: footer

            x: root.pad
            y: panel.height - root.pad - height
            width: root.innerWidth
            height: 26

            Row {
                id: optionsRow

                // Options without pills (OptionChip): air in between replaces the borders
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
            }

        }

    }

    // Distance ring of the radar (size = share of the radar ellipse, k = build progress)
    component RangeRing: ShapePath {
        id: ring

        property real size: 1
        property real k: 1
        property bool strong: false
        readonly property real f: size * k

        strokeColor: WalColors.withAlpha(WalColors.color7, (strong ? 0.16 : 0.09) * k)
        strokeWidth: 1
        strokeStyle: ShapePath.DashLine
        dashPattern: strong ? [1, 5] : [1, 7]
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"
        startX: root.cx + radarGrid.rx * f
        startY: root.cy

        PathAngleArc {
            centerX: root.cx
            centerY: root.cy
            radiusX: radarGrid.rx * ring.f
            radiusY: radarGrid.ry * ring.f
            startAngle: 0
            sweepAngle: 360
        }

    }

}
