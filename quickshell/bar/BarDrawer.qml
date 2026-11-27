import "../services"
import QtQuick
import Quickshell

// Drawer to the left of the logo button: picker slots (clipboard, trash, Bluetooth, Wi-Fi,
// apps, media, monitor) and the language group. Part of MainBar.qml (mainBar = core).
Item {
    id: drawer

    required property var mainBar
    property alias cbSlot: cbSlot
    property alias trashSlot: trashSlot
    property alias btSlot: btSlot
    property alias wifiSlot: wifiSlot
    property alias appsSlot: appsSlot
    property alias mediaSlot: mediaSlot
    property alias monitorSlot: monitorSlot
    property alias jaGroup: jaGroup

    // Stack while peeking: the first icons lie one behind the other beside the logo. It takes only the
    // room it shows (the card of the front icon starts 3 px into its slot, the last one ends 3 px early).
    readonly property int stackDepth: 3
    readonly property real stackStep: 6
    readonly property real stackW: drawerContent.leftPadding + 32 + (stackDepth - 1) * stackStep
    // The visible icons in row order, taken once when the stack starts (not on every frame)
    property var stackItems: []

    function takeStackOrder() {
        stackItems = Array.from(drawerContent.children).filter((c) => {
            return c.visible && c.width > 0;
        }).sort((a, b) => {
            return a.x - b.x;
        });
    }

    // Place of an icon in the stack (beyond it: after the last)
    function stackIndex(item) {
        const i = stackItems.indexOf(item);
        return i < 0 ? stackItems.length : i;
    }

    // Right edge of the last icon where it is drawn right now (stack place -> row place). While the stack
    // fans out, pill and drawer reach at least this far: the last icon starts far right in the stack and
    // would otherwise poke out of the pill for a few frames.
    readonly property real stackRight: {
        const last = stackItems.length ? stackItems[stackItems.length - 1] : null;
        if (!last || !mainBar.drawerFromLeft)
            return 0;

        const target = drawerContent.leftPadding + (stackItems.length - 1) * stackStep;
        return target + (last.x - target) * (1 - mainBar.stackK) + last.width;
    }

    // How far an icon is shown: the usual staggered reveal of the drawer, and while the stack is in
    // charge its place in the stack (front clear, behind fainter and smaller, beyond the stack hidden
    // until the fan-out brings it)
    function revealOf(item, id) {
        // The icons stand still and the pill's round end runs over them (opening and closing): an icon
        // shows only once the end is past its ink (ink ends ~25 px into the 32 px slot) and is fully there
        // 12 px later, which the last icon reaches exactly when the drawer is open. None stands outside the
        // pill or is cut at the drawer's edge.
        const usual = mainBar.clamp01((drawer.width - 10 - item.x - 20) / 12);
        if (!mainBar.drawerFromLeft)
            return usual;

        const i = stackIndex(item);
        const inStack = i < stackDepth ? 1 - i * 0.16 * mainBar.stackK : 1 - mainBar.stackK;
        // Closing: the stack as a whole shrinks into the logo and fades (sink), the icons only take
        // their depth in it. Not the drawer's edge: it would cut through icons that are still seen.
        if (mainBar.stackClosing)
            return Math.min(1, inStack);

        return Math.min(1, Math.max(usual, mainBar.stackShow * inStack));
    }

    // Stack mode: as wide as the icons reach (so the gap to the gear stays the same while they spring);
    // otherwise the opening value times the full width
    // Closing: shrinks with the sinking stack, so it is always exactly as wide as what is still seen
    width: mainBar.drawerFromLeft ? Math.max(mainBar.peekShown * stackW, mainBar.revealT > 0 ? sink * (stackRight + drawerContent.rightPadding) : 0) : Math.max(0, mainBar.revealT) * drawerContent.implicitWidth
    // 1, and while closing with the stack it goes to 0: icons and pill shrink toward the logo and fade
    readonly property real sink: mainBar.stackClosing ? mainBar.stackShow : 1
    height: 32
    clip: true

    Connections {
        function onDrawerFromLeftChanged() {
            if (drawer.mainBar.drawerFromLeft)
                drawer.takeStackOrder();

        }

        target: drawer.mainBar
    }

    Item {
        id: pillLayer

        x: drawerContent.x
        width: drawerContent.implicitWidth
        height: drawerContent.height
        opacity: mainBar.revealT * drawer.sink
        scale: drawer.sink
        transformOrigin: Item.Left

        Rectangle {
            id: drawerPill

            x: drawerContent.pillX
            y: (parent.height - height) / 2
            width: drawerContent.pillW
            height: 32
            radius: height / 2
            // Outlined, not filled like the tray pill beside it: the drawer is the one that comes and
            // goes, the tray stays. On hover it fills behind that icon.
            color: WalColors.withAlpha(WalColors.color4, drawerContent.focused ? 0.3 : 0.03)
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color4, drawerContent.focused ? 0 : 0.28)

            Behavior on x {
                NumberAnimation {
                    duration: 320
                    // No overshoot: the pill glides straight to its place
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on width {
                // Only for hover; while the drawer opens (and springs) the width follows it directly
                enabled: drawer.mainBar.revealT === 1

                NumberAnimation {
                    duration: 320
                    // No overshoot: the pill glides straight to its place
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    Row {
        id: drawerContent

        readonly property int hoveredIndex: {
            if (cbSlot.hovered)
                return 0;

            if (appsSlot.hovered)
                return 1;

            if (mediaSlot.hovered)
                return 2;

            if (jaBtn.hovered)
                return 3;

            if (monitorSlot.hovered)
                return 4;

            if (btSlot.hovered)
                return 5;

            if (wifiSlot.hovered)
                return 6;

            if (trashSlot.hovered)
                return 7;

            return -1;
        }
        readonly property int lockedIndex: {
            if (ClipboardState.pickerVisible && cbSlot.visible)
                return 0;

            if (TrashState.pickerVisible && trashSlot.visible)
                return 7;

            if (BluetoothState.pickerVisible && btSlot.visible)
                return 5;

            if (WifiState.pickerVisible && wifiSlot.visible)
                return 6;

            if (PickerManager.isOpen("apps") && appsSlot.visible)
                return 1;

            if (PickerManager.isOpen("media") && mediaSlot.visible)
                return 2;

            if (LanguageAudioState.isPlaying && jaGroup.visible)
                return 3;

            return -1;
        }
        readonly property int effectiveIndex: hoveredIndex >= 0 ? hoveredIndex : lockedIndex
        readonly property bool focused: effectiveIndex >= 0
        readonly property real pillWidth: Math.round(18 + 16 * BarState.density)
        // Full: the whole row. While the stack fans out the drawer is narrower than that; the pill then
        // ends (round) at the drawer's edge instead of being cut off there and running ahead of the icons
        // Ends (round) at the drawer's edge. While the stack fans out it runs exactly leftPadding behind
        // the last icon, the same distance as when open: a larger lead that shrank at the end looked like
        // the icon creeping after the pill had stopped.
        // Not capped at the full width: the pill springs a little past its end with the drawer and settles
        readonly property real pillW: focused ? pillWidth : (drawer.stackRight > 0 ? drawer.stackRight + leftPadding : drawer.width - (rightPadding - leftPadding))
        readonly property real pillX: {
            if (!focused)
                return 0;

            if (effectiveIndex === 0)
                return cbSlot.x + cbSlot.width / 2 - pillWidth / 2;

            if (effectiveIndex === 1)
                return appsSlot.x + appsSlot.width / 2 - pillWidth / 2;

            if (effectiveIndex === 2)
                return mediaSlot.x + mediaSlot.width / 2 - pillWidth / 2;

            if (effectiveIndex === 3)
                return jaGroup.x + jaBtn.x + jaBtn.width / 2 - pillWidth / 2;

            if (effectiveIndex === 4)
                return monitorSlot.x + monitorSlot.width / 2 - pillWidth / 2;

            if (effectiveIndex === 5)
                return btSlot.x + btSlot.width / 2 - pillWidth / 2;

            if (effectiveIndex === 6)
                return wifiSlot.x + wifiSlot.width / 2 - pillWidth / 2;

            if (effectiveIndex === 7)
                return trashSlot.x + trashSlot.width / 2 - pillWidth / 2;

            return 0;
        }

        // The icons stay at their places; the drawer (and its pill) grows over them from the logo and
        // shrinks back to it. Until 2026-11-27 they slid out from behind the logo: closing, the empty
        // pill then went on sliding after the icons had faded.
        x: 0
        height: parent.height
        leftPadding: 6
        rightPadding: 16
        spacing: Math.round(6 * BarState.density)
        opacity: drawer.sink
        scale: drawer.sink
        transformOrigin: Item.Left
        // Only rehang after the build: in the middle of creation (bar recreated on another monitor) icons vanish otherwise.
        // Every icon gets its shift into the stack (to its stack place, times stackK) and lies behind
        // the ones before it while stacked.
        Component.onCompleted: Qt.callLater(() => {
            mainBar.applyOrder("left");
            for (const c of drawerContent.children) {
                const item = c;
                item.transform = [stackShift.createObject(item, {
                    "x": Qt.binding(() => {
                        // Stack: to its stack place (times stackK). Otherwise, while the opening springs past
                        // its end, every icon spreads with the drawer and settles with it.
                        return mainBar.drawerFromLeft ? mainBar.stackK * (drawerContent.leftPadding + drawer.stackIndex(item) * drawer.stackStep - item.x) : Math.max(0, mainBar.revealT - 1) * (item.x + item.width + drawerContent.rightPadding);
                    })
                })];
                item.z = Qt.binding(() => {
                    return mainBar.drawerFromLeft ? 100 - drawer.stackIndex(item) : 0;
                });
                // A small opaque card per icon while stacked: line icons on top of each other would show
                // through one another; it fades while the stack fans out
                stackCard.createObject(item, {
                    "item": item
                });
            }
        })

        DrawerSlot {
            id: cbSlot

            icon: "clipboard"
            visible: mainBar.iconShown("clipboard")
            active: ClipboardState.pickerVisible
            reveal: drawer.revealOf(cbSlot, "clipboard")
            onClicked: ClipboardState.toggle()

            EditBadge {
                mainBar: drawer.mainBar
                iconId: "clipboard"
                group: "left"
            }

        }

        DrawerSlot {
            id: trashSlot

            icon: "trash"
            visible: mainBar.iconShown("trash")
            active: TrashState.pickerVisible
            reveal: drawer.revealOf(trashSlot, "trash")
            onClicked: TrashState.toggle()

            EditBadge {
                mainBar: drawer.mainBar
                iconId: "trash"
                group: "left"
            }

        }

        // Left click = Bluetooth picker, right-click = Bluetooth on/off
        DrawerSlot {
            id: btSlot

            icon: "bluetooth"
            // Like Wi-Fi: only with an adapter (shows up when a dongle is plugged in later)
            visible: mainBar.iconShown("bluetooth") && BluetoothState.available
            active: BluetoothState.pickerVisible
            linked: BluetoothState.connectedCount > 0
            dimmed: !BluetoothState.enabled
            reveal: drawer.revealOf(btSlot, "bluetooth")
            onClicked: BluetoothState.toggle()
            onRightClicked: BluetoothState.togglePower()

            EditBadge {
                mainBar: drawer.mainBar
                iconId: "bluetooth"
                group: "left"
            }

        }

        // Left click = Wi-Fi picker, nothing else (no right-click, no toggle).
        // Only on machines with a Wi-Fi adapter.
        DrawerSlot {
            id: wifiSlot

            icon: "wifi"
            visible: mainBar.iconShown("wifi") && WifiState.available
            active: WifiState.pickerVisible
            linked: WifiState.connected
            busy: WifiState.busy
            dimmed: !WifiState.enabled
            reveal: drawer.revealOf(wifiSlot, "wifi")
            onClicked: WifiState.toggle()

            EditBadge {
                mainBar: drawer.mainBar
                iconId: "wifi"
                group: "left"
            }

        }

        DrawerSlot {
            id: appsSlot

            icon: "apps"
            visible: mainBar.iconShown("apps")
            active: PickerManager.isOpen("apps")
            reveal: drawer.revealOf(appsSlot, "apps")
            onClicked: PickerManager.toggle("apps")

            EditBadge {
                mainBar: drawer.mainBar
                iconId: "apps"
                group: "left"
            }

        }

        DrawerSlot {
            id: mediaSlot

            icon: "media"
            visible: Addons.media && mainBar.iconShown("media")
            active: PickerManager.isOpen("media")
            reveal: drawer.revealOf(mediaSlot, "media")
            onClicked: PickerManager.toggle("media")

            EditBadge {
                mainBar: drawer.mainBar
                iconId: "media"
                group: "left"
            }

        }

        MonitorSwitchButton {
            id: monitorSlot

            visible: Quickshell.screens.length > 1 && mainBar.iconShown("monitor")
            reveal: drawer.revealOf(monitorSlot, "monitor")
            onClicked: mainBar.toggleMonitors()

            EditBadge {
                mainBar: drawer.mainBar
                iconId: "monitor"
                group: "left"
            }

        }

        Item {
            id: jaGroup

            readonly property bool miniActive: LanguageAudioState.currentFile !== ""
            property bool collapsed: false
            readonly property bool miniShown: miniActive && !collapsed
            readonly property bool hoverKeep: miniHover.hovered || jaBtn.hovered || capsule.dragging
            readonly property real frac: LanguageAudioState.currentDuration > 0 ? mainBar.clamp01(LanguageAudioState.currentPosition / LanguageAudioState.currentDuration) : 0
            property real shownFrac: frac
            readonly property real reveal: drawer.revealOf(jaGroup, "ja")
            readonly property real timeW: LanguageAudioState.currentDuration >= 3600 ? 44 : 30
            readonly property real miniW: 110 + 2 * timeW

            // Collapsed mini player: hover on the icon shows it again (state + seeking), 3 s after
            // leaving it collapses again (timer below)
            onHoverKeepChanged: {
                if (hoverKeep && miniActive)
                    collapsed = false;

            }
            visible: mainBar.iconShown("ja")
            height: 32
            width: capsule.x + capsule.width + 2
            opacity: reveal
            scale: 0.6 + 0.4 * reveal
            transformOrigin: Item.Left

            Rectangle {
                id: capsule

                readonly property bool dragging: trackMouse.pressed
                property real dragFrac: 0
                readonly property real dispFrac: dragging ? dragFrac : jaGroup.shownFrac
                readonly property real dispSecs: dragging ? dragFrac * LanguageAudioState.currentDuration : LanguageAudioState.currentPosition

                x: 2
                anchors.verticalCenter: parent.verticalCenter
                height: 28
                radius: height / 2
                width: 28 + (jaGroup.miniShown ? jaGroup.miniW : 0)
                color: WalColors.withAlpha(WalColors.color4, jaGroup.miniShown ? (miniHover.hovered ? 0.2 : 0.12) : 0)

                HoverHandler {
                    id: miniHover
                }

                WheelHandler {
                    enabled: jaGroup.miniShown
                    onWheel: (event) => {
                        LanguageAudioState.seekRelative(event.angleDelta.y > 0 ? 5 : -5);
                    }
                }

                Item {
                    id: miniWrap

                    x: 28
                    width: Math.max(0, capsule.width - 28)
                    height: parent.height
                    clip: true
                    opacity: jaGroup.miniShown ? 1 : 0

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        // ═══ Elapsed time ═══
                        Text {
                            id: elapsedText

                            anchors.verticalCenter: parent.verticalCenter
                            width: jaGroup.timeW
                            horizontalAlignment: Text.AlignRight
                            text: mainBar.fmtTime(capsule.dispSecs)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeBody
                            font.features: Theme.tabular
                            font.bold: true
                            color: capsule.dragging ? WalColors.color4 : (LanguageAudioState.isPlaying ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.8))

                            Behavior on color {
                                ColorAnimation {
                                    duration: Appearance.anim.durations.normal
                                }

                            }

                        }

                        // ═══ Serpentine wave (Canvas) ═══
                        Item {
                            id: waveView

                            property real phase: 0
                            property real breathe: 0
                            readonly property real progress: capsule.dispFrac
                            // Only animate when the wave is visible too (drawer open, bar visible, no panel open)
                            readonly property bool shown: jaGroup.visible && jaGroup.miniShown && jaGroup.reveal > 0.01 && BarState.barVisible && !mainBar.panelOpen
                            readonly property bool active: LanguageAudioState.isPlaying && !capsule.dragging && shown
                            readonly property real amp: 4.5 + (active ? Math.sin(breathe) * 0.6 : 0)
                            readonly property real cycles: 3.5

                            function yAt(u, h, phase, amp, cycles) {
                                return h / 2 + Math.sin(u * cycles * 2 * Math.PI + phase) * amp;
                            }

                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(40, parent.width - elapsedText.width - remainingText.width - parent.spacing * 2)
                            height: 22

                            // At the frame rate instead of a 16 ms timer (that ran beside the frame timing and stuttered slightly); same
                            // speed as before (0.05 or 0.02 rad per 16 ms)
                            FrameAnimation {
                                running: waveView.active
                                onTriggered: {
                                    waveView.phase = (waveView.phase + 3.125 * frameTime) % (2 * Math.PI);
                                    waveView.breathe = (waveView.breathe + 1.25 * frameTime) % (2 * Math.PI);
                                }
                            }

                            Canvas {
                                id: canvas

                                property real cPhase: waveView.phase
                                property real cProgress: waveView.progress
                                property real cAmp: waveView.amp
                                property real cCycles: waveView.cycles

                                anchors.fill: parent
                                onCPhaseChanged: requestPaint()
                                onCProgressChanged: requestPaint()
                                onCAmpChanged: requestPaint()
                                onCCyclesChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    var w = width;
                                    var h = height;
                                    var a = cAmp;
                                    var ph = cPhase;
                                    var cyc = cCycles;
                                    var prog = cProgress;
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";
                                    // Unplayed curve
                                    ctx.beginPath();
                                    ctx.strokeStyle = WalColors.withAlpha(WalColors.color7, 0.22);
                                    ctx.lineWidth = 2;
                                    var N = 80;
                                    for (var i = 0; i <= N; i++) {
                                        var u = i / N;
                                        var x = u * w;
                                        var y = h / 2 + Math.sin(u * cyc * 2 * Math.PI + ph) * a;
                                        if (i === 0)
                                            ctx.moveTo(x, y);
                                        else
                                            ctx.lineTo(x, y);
                                    }
                                    ctx.stroke();
                                    // Played curve
                                    if (prog > 0.001) {
                                        var N_prog = Math.max(1, Math.floor(N * prog));
                                        // Glow
                                        ctx.beginPath();
                                        ctx.strokeStyle = WalColors.withAlpha(WalColors.color4, 0.25);
                                        ctx.lineWidth = 6;
                                        for (var i = 0; i <= N_prog; i++) {
                                            var u = (i / N_prog) * prog;
                                            var x = u * w;
                                            var y = h / 2 + Math.sin(u * cyc * 2 * Math.PI + ph) * a;
                                            if (i === 0)
                                                ctx.moveTo(x, y);
                                            else
                                                ctx.lineTo(x, y);
                                        }
                                        ctx.stroke();
                                        // Core
                                        ctx.beginPath();
                                        ctx.strokeStyle = WalColors.color4;
                                        ctx.lineWidth = 2.4;
                                        for (var i = 0; i <= N_prog; i++) {
                                            var u = (i / N_prog) * prog;
                                            var x = u * w;
                                            var y = h / 2 + Math.sin(u * cyc * 2 * Math.PI + ph) * a;
                                            if (i === 0)
                                                ctx.moveTo(x, y);
                                            else
                                                ctx.lineTo(x, y);
                                        }
                                        ctx.stroke();
                                    }
                                }

                                Connections {
                                    function onColorsUpdated() {
                                        canvas.requestPaint();
                                    }

                                    target: WalColors
                                }

                            }

                            // Playhead dot
                            Rectangle {
                                x: waveView.progress * waveView.width - width / 2
                                y: waveView.yAt(waveView.progress, waveView.height, waveView.phase, waveView.amp, waveView.cycles) - height / 2
                                width: 6
                                height: 6
                                radius: height / 2
                                color: WalColors.color4
                                border.width: 1
                                border.color: WalColors.withAlpha(WalColors.color0, 0.8)
                                visible: LanguageAudioState.currentDuration > 0
                            }

                            MouseArea {
                                id: trackMouse

                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (mouse) => {
                                    capsule.dragFrac = Math.max(0, Math.min(1, mouse.x / waveView.width));
                                }
                                onPositionChanged: (mouse) => {
                                    if (pressed)
                                        capsule.dragFrac = Math.max(0, Math.min(1, mouse.x / waveView.width));

                                }
                                onReleased: {
                                    if (LanguageAudioState.currentDuration > 0)
                                        LanguageAudioState.seekToFraction(capsule.dragFrac);

                                }
                            }

                        }

                        // ═══ Remaining time ═══
                        Text {
                            id: remainingText

                            anchors.verticalCenter: parent.verticalCenter
                            width: jaGroup.timeW
                            horizontalAlignment: Text.AlignRight
                            text: LanguageAudioState.currentDuration > 0 ? ((LanguageAudioState.isPlaying || capsule.dragging) ? "−" + mainBar.fmtTime(Math.max(0, LanguageAudioState.currentDuration - capsule.dispSecs)) : mainBar.fmtTime(LanguageAudioState.currentDuration)) : "–:––"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeSmall
                            font.features: Theme.tabular
                            color: WalColors.withAlpha(WalColors.color7, 0.42)
                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 240
                        }

                    }

                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

                Behavior on width {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutCubic
                    }

                }

            }

            DrawerSlot {
                id: jaBtn

                x: 0
                icon: "language"
                // Character of the language loaded right now (otherwise the one chosen in the picker)
                mark: LanguageAudioState.markOf(jaGroup.miniActive ? LanguageAudioState.playLanguage : LanguageAudioState.language)
                // As with the other slots: highlighted while the picker is open; playback is shown by
                // the icon itself (bars instead of the character)
                active: LanguageAudioState.isOpen
                playing: LanguageAudioState.isPlaying
                // Like Bluetooth: left click = picker open/close, right-click = quick action (play/pause of the
                // loaded video; nothing without a loaded video)
                onClicked: LanguageAudioState.toggle()
                onRightClicked: {
                    if (LanguageAudioState.currentFile !== "")
                        LanguageAudioState.play(LanguageAudioState.currentFile);

                }

                // The whole group is moved (icon + mini player)
                EditBadge {
                    mainBar: drawer.mainBar
                    iconId: "ja"
                    group: "left"
                    dragItem: jaGroup
                }

            }

            Timer {
                interval: 3000
                running: jaGroup.miniActive && !jaGroup.collapsed && !LanguageAudioState.isPlaying && !jaGroup.hoverKeep
                onTriggered: jaGroup.collapsed = true
            }

            Connections {
                function onIsPlayingChanged() {
                    if (LanguageAudioState.isPlaying)
                        jaGroup.collapsed = false;

                }

                target: LanguageAudioState
            }

            Behavior on shownFrac {
                enabled: !trackMouse.pressed

                NumberAnimation {
                    duration: 950
                    easing.type: Easing.Linear
                }

            }

        }

    }

    Component {
        id: stackCard

        Rectangle {
            property Item item

            x: 3
            y: (32 - height) / 2
            // The front card lies under its icon, the ones behind cover their own: only their edges show
            z: item && drawer.stackIndex(item) === 0 ? -1 : 1
            width: 26
            height: 26
            radius: 9
            color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color4, 0.16))
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color4, 0.28)
            opacity: mainBar.drawerFromLeft ? (mainBar.stackClosing ? 1 : mainBar.stackShow) * Math.max(0, mainBar.stackK) : 0
            visible: opacity > 0.01
        }

    }

    Component {
        id: stackShift

        Translate {
        }

    }

}
