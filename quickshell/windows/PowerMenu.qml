import "../common"
import "../lock"
import "../services"
import Qt5Compat.GraphicalEffects as GE
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Session screen: blurred background (Hyprland layer rule), big clock, 4 solid tiles with a gliding underline.
// Shutdown/Reboot/Logout start a 3 s countdown (Enter/click = right away, Esc/click beside = cancel),
// Lock happens right away.
PanelWindow {
    id: powerMenu

    property bool open: false
    // Closing animation: the window stays visible briefly, then Hyprland fades out background + blur
    // (layer_rule "powermenu-blur" with animation = "fade" in ~/.config/hypr/modules/windows.lua)
    property bool closing: false
    readonly property int outroDuration: 220
    property int currentIndex: 0
    // Countdown: which action is "armed" (-1 = none) and how far the ring is (0..1)
    property int armedIndex: -1
    property real armProgress: 0
    readonly property int armSeconds: 3
    readonly property int cardW: 160
    readonly property int cardH: 200
    readonly property int cardSpacing: 28
    // Solid surfaces: background color slightly tinted toward the text (no alpha -> nothing shines through)
    readonly property color surface: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.05))
    readonly property color surfaceHi: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.1))
    readonly property string userName: Quickshell.env("USER") || ""
    readonly property var actions: [{
        "label": "Shutdown",
        "busy": "Shutting down",
        "icon": "../resources/icons/power.png",
        "confirm": true,
        "cmd": ["systemctl", "poweroff"]
    }, {
        "label": "Reboot",
        "busy": "Rebooting",
        "icon": "../resources/icons/restart.png",
        "confirm": true,
        "cmd": ["systemctl", "reboot"]
    }, {
        "label": "Lock",
        "busy": "Locking",
        "icon": "../resources/icons/lock.png",
        "confirm": false,
        "lock": true,
        "cmd": [Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh", "--from-powermenu"]
    }, {
        "label": "Logout",
        "busy": "Logging out",
        "icon": "../resources/icons/logout.png",
        "confirm": true,
        // Lua dispatcher: with the Lua config "hyprctl dispatch exit" is read as Lua and fails silently
        "cmd": ["hyprctl", "dispatch", "hl.dsp.exit()"]
    }]
    property string hoursText: ""
    property string minutesText: ""
    property string dateText: ""
    // Locking in progress: the menu stays until the lock screen covers it (lock.sh then calls
    // `qs ipc call powermenu dismiss`). This way the lock screen freezes right out of the menu.
    property bool locking: false
    // Desktop image without the menu, captured shortly before the menu appears. The lock screen thaws to it
    // when unlocking -> afterwards the menu is closed, without a jump. lock.sh picks up the file.
    readonly property string shotPrefix: Quickshell.env("XDG_RUNTIME_DIR") + "/powermenu-desktop"

    // Opening: first capture the monitor (~40 ms), then fade in
    function requestOpen() {
        if (open || shotProc.running)
            return ;

        anchor.pin();
        // Pause the wallpaper animation, otherwise the image no longer matches the video after unlocking
        frozenVideoMons = WallpaperPickerState.freezeAnimation(true);
        lockWall = "";
        const mon = anchor.screen ? anchor.screen.name : "";
        // The desktop visualizer sinks away behind the menu as in silence (only comes back after closing or
        // unlocking). But the image below still captures it -> strip height in <prefix>-<mon>.strip,
        // the lock screen covers it with the wallpaper in the thaw image (otherwise it stood there and was gone afterwards)
        const home = DesktopCavaService.homeMonitor;
        const strip = home && home.name === mon ? Math.ceil(DesktopCavaService.shownStrip) : 0;
        DesktopCavaService.menuHold = true;
        shotProc.command = ["sh", "-c", "rm -f \"$1-$2.strip\"; [ \"$3\" = 0 ] || printf %s \"$3\" > \"$1-$2.strip\"; exec \"$0\" \"$1\" \"$2\"",
            Qt.resolvedUrl("../scripts/desktop_shot.sh").toString().replace("file://", ""), shotPrefix, mon, String(strip)];
        shotProc.running = true;
        shotFailsafe.restart();
    }

    function runAction(i) {
        const a = actions[i];
        if (!a || locking)
            return ;

        console.log("PowerMenu:", a.label, a.cmd);
        disarm();
        Quickshell.execDetached(a.cmd);
        if (a.lock) {
            // Transition to the lock screen: tiles and clock sink away as when closing. At the same time
            // the lock screen elements fall in from the top (lockFg) and the background fades softly BEHIND the
            // tiles into the frozen lock screen background (lockBg). When everything stands (handoffTimer),
            // the image is identical to the lock screen: lock.sh captures it, the real lock screen
            // takes it over without a visible change. The menu only closes behind it.
            locking = true;
            lockFailsafe.restart();
            intro.stop();
            outro.restart();
            lockIn.restart();
            handoffTimer.restart();
            // At the same time on the other monitors (windows/LockTransition.qml)
            LockTransitionState.begin(anchor.screen ? anchor.screen.name : "");
            return ;
        }
        beginClose();
    }

    // Gone right away, without an outro (it already lies under the lock screen then). The wallpaper animation stays
    // paused, lock.sh resumes it after unlocking.
    function dismiss() {
        lockFailsafe.stop();
        LockTransitionState.end();
        handoffTimer.stop();
        lockIn.stop();
        lockBg.opacity = 0;
        lockFg.enter = 0;
        locking = false;
        intro.stop();
        outro.stop();
        hideTimer.stop();
        disarm();
        closing = false;
        open = false;
        // The visualizer stays off anyway: lock.sh has already locked it (locked)
        DesktopCavaService.menuHold = false;
    }

    // Outro: tiles sink away (outer ones first), the clock glides down, the underline shrinks
    function beginClose() {
        if (!open)
            return ;

        closing = true;
        open = false;
        intro.stop();
        outro.restart();
        hideTimer.restart();
        // Closed without locking -> let the wallpaper paused on opening continue
        WallpaperPickerState.freezeAnimation(false);
        DesktopCavaService.menuHold = false;
    }

    // Enter / click: actions that need confirmation are armed first, a second time = right away
    function trigger(i) {
        if (locking)
            return ;

        const a = actions[i];
        if (!a)
            return ;

        if (!a.confirm || armedIndex === i) {
            runAction(i);
            return ;
        }
        currentIndex = i;
        armedIndex = i;
        armAnim.restart();
    }

    function disarm() {
        armAnim.stop();
        armedIndex = -1;
        armProgress = 0;
    }

    function close() {
        // Do not close while locking: the menu is the starting point of the lock screen intro
        if (locking)
            return ;

        disarm();
        beginClose();
    }

    function move(step) {
        if (armedIndex >= 0)
            return ;

        currentIndex = (currentIndex + step + actions.length) % actions.length;
    }

    // Stays on the monitor + workspace where it was opened
    WindowAnchor {
        id: anchor

        open: powerMenu.open
        onClosedWhileAway: powerMenu.open = true
    }

    WlrLayershell.namespace: "quickshell:powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open && anchor.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    screen: anchor.screen
    visible: (open || closing) && anchor.here
    color: "transparent"
    onOpenChanged: {
        if (open) {
            hideTimer.stop();
            outro.stop();
            closing = false;
            disarm();
            // Reset the selection without gliding: the underline stands under tile 1 from the first frame
            selectionBar.snap = true;
            currentIndex = 0;
            selectionBar.snap = false;
            squishAnim.stop();
            selectionBar.squish = 1;
            selectionBar.grow = 0;
            intro.restart();
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    NumberAnimation {
        id: armAnim

        target: powerMenu
        property: "armProgress"
        from: 0
        to: 1
        duration: powerMenu.armSeconds * 1000
        onFinished: {
            if (powerMenu.armedIndex >= 0)
                powerMenu.runAction(powerMenu.armedIndex);

        }
    }

    Timer {
        interval: 1000
        running: powerMenu.open
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date();
            powerMenu.hoursText = Qt.formatTime(now, "HH");
            powerMenu.minutesText = Qt.formatTime(now, "mm");
            powerMenu.dateText = Qt.formatDate(now, "dddd, MMMM d");
        }
    }

    Process {
        id: shotProc

        onExited: {
            shotFailsafe.stop();
            powerMenu.open = true;
            // Afterwards (the menu is already open) prepare the wallpaper image for the lock screen surface
            if (anchor.screen) {
                // For all monitors: the others freeze along when locking (LockTransition)
                wallProc.command = [Qt.resolvedUrl("../scripts/lock_walls.sh").toString().replace("file://", ""), powerMenu.frozenVideoMons.join(" ")];
                wallProc.running = true;
            }
        }
    }

    // grim hangs -> open anyway (without an image the lock screen then thaws to the menu)
    Timer {
        id: shotFailsafe

        interval: 400
        onTriggered: {
            shotProc.running = false;
            powerMenu.open = true;
        }
    }

    // Transition to the lock screen: the background crossfades, the elements fall in from the top shortly after the start
    // of the tile outro (the tiles are still visible at the bottom then). Length until the handover.
    readonly property int lockFgDelay: 110
    readonly property int lockFgDuration: 800
    readonly property int lockBgDuration: 700

    ParallelAnimation {
        id: lockIn

        NumberAnimation {
            target: lockBg
            property: "opacity"
            from: 0
            to: 1
            duration: powerMenu.lockBgDuration
            easing.type: Easing.InOutQuad
        }

        SequentialAnimation {
            PropertyAction {
                target: lockFg
                property: "enter"
                value: 0
            }

            PauseAnimation {
                duration: powerMenu.lockFgDelay
            }

            NumberAnimation {
                target: lockFg
                property: "enter"
                to: 1
                duration: powerMenu.lockFgDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.outQuint
            }

        }

    }

    // Prepare the wallpaper image for the lock screen surface already when opening (paused video frame
    // or awww image as PPM, scripts/lock_walls.sh), so it stands right away on a click on Lock
    property string lockWall: ""
    property var frozenVideoMons: []

    Process {
        id: wallProc

        onExited: {
            if (powerMenu.open && anchor.screen)
                powerMenu.lockWall = Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-lock-wall-" + anchor.screen.name;

        }
    }

    // Everything stands -> lock.sh may capture the screen and show the lock screen. Content of the file:
    // this monitor (there the lock screen starts with the elements already in place).
    // Write .tmp first and rename, so lock.sh never reads an empty file.
    Timer {
        id: handoffTimer

        interval: Math.max(powerMenu.lockFgDelay + powerMenu.lockFgDuration, powerMenu.lockBgDuration) + 30
        onTriggered: {
            const f = Quickshell.env("XDG_RUNTIME_DIR") + "/powermenu-handoff";
            Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"", "sh", anchor.screen ? anchor.screen.name : "", f]);
        }
    }

    // The lock screen did not come (lock.sh hangs/aborted) -> do not leave the menu blocked forever
    Timer {
        id: lockFailsafe

        interval: 8000
        onTriggered: {
            LockTransitionState.end();
            powerMenu.locking = false;
            powerMenu.close();
        }
    }

    // Hyprland: hl.dsp.global("quickshell:toggle_power_menu")
    GlobalShortcut {
        name: "toggle_power_menu"
        description: "Toggle Power Menu"
        onPressed: {
            if (powerMenu.locking)
                return ;

            if (powerMenu.open)
                powerMenu.close();
            else
                powerMenu.requestOpen();
        }
    }

    IpcHandler {
        function toggle() {
            if (powerMenu.locking)
                return ;

            if (powerMenu.open)
                powerMenu.close();
            else
                powerMenu.requestOpen();
        }

        // Not "show": "qs ipc call <target> show" collides with Quickshell's own "qs ipc show"
        // and only prints the help
        function open() {
            powerMenu.requestOpen();
        }

        function hide() {
            powerMenu.close();
        }

        // From lock.sh as soon as the lock screen stands
        function dismiss() {
            powerMenu.dismiss();
        }

        target: "powermenu"
    }

    Item {
        anchors.fill: parent
        focus: powerMenu.open
        Keys.onEscapePressed: {
            if (powerMenu.armedIndex >= 0)
                powerMenu.disarm();
            else
                powerMenu.close();
        }
        Keys.onReturnPressed: powerMenu.trigger(powerMenu.currentIndex)
        Keys.onEnterPressed: powerMenu.trigger(powerMenu.currentIndex)
        Keys.onSpacePressed: powerMenu.trigger(powerMenu.currentIndex)
        Keys.onLeftPressed: powerMenu.move(-1)
        Keys.onRightPressed: powerMenu.move(1)
        Keys.onDigit1Pressed: powerMenu.trigger(0)
        Keys.onDigit2Pressed: powerMenu.trigger(1)
        Keys.onDigit3Pressed: powerMenu.trigger(2)
        Keys.onDigit4Pressed: powerMenu.trigger(3)
    }

    // ---------- Opaque background ----------
    Rectangle {
        id: backdrop

        // No more clicks during the outro
        enabled: !powerMenu.closing
        anchors.fill: parent
        // Semi-transparent: Hyprland blurs the desktop behind it (layer_rule "powermenu-blur",
        // ignore_alpha = 0.3 -> the alpha must be above that)
        color: WalColors.withAlpha(WalColors.color0, 0.5)
        opacity: 0

        // Frozen lock screen background (same component as lock.qml): fades in behind the clock and
        // tiles when locking. Without the Ken Burns breathing, the lock screen starts with exactly this image.
        LockBackdrop {
            id: lockBg

            anchors.fill: parent
            opacity: 0
            visible: powerMenu.locking && opacity > 0
            wallpaper: powerMenu.lockWall
            frost: 1
            wake: 0
            drifting: false
        }

        // A click into nothing: cancel the countdown, otherwise close
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (powerMenu.armedIndex >= 0)
                    powerMenu.disarm();
                else
                    powerMenu.close();
            }
        }

        // Soft glow in the accent color behind the dock (gets stronger during the countdown).
        // Own shader instead of RadialGradient: that showed rings on the dark background (banding),
        // windows/shaders/glow.frag runs out without a kink and with dithering.
        ShaderEffect {
            property color tint: powerMenu.armedIndex >= 0 ? WalColors.color1 : WalColors.color4
            property real strength: 0.16

            anchors.centerIn: dock
            // Same extent as the old gradient
            width: Math.max(dock.width * 2.4, 900)
            height: width * 0.75
            // Gone when locking: otherwise it would lie above the lock screen background (lockBg) and the image
            // would not be identical to the lock screen at the handover
            opacity: (0.7 + 0.3 * powerMenu.armProgress) * (1 - lockBg.opacity)
            fragmentShader: Qt.resolvedUrl("shaders/glow.frag.qsb")
        }

        // ---------- Starry sky (a recurring motif as in the Wi-Fi/Bluetooth picker) ----------
        // Particles: every star flies its own slow path and fades in and out (a sky drifting as one rigid
        // sheet looked stiff), parallax to the mouse. Gone when locking like the glow: the lock screen background
        // (lockBg) brings its own calm stars, the handover stays pixel identical.
        StarField {
            id: menuStars

            // Mouse relative to the middle (-1..1), followed softly (otherwise the stars jump with every mouse event)
            property real tx: 0
            property real ty: 0
            property real px: 0
            property real py: 0

            anchors.fill: parent
            opacity: 1 - lockBg.opacity
            visible: opacity > 0.01
            // Kept very minimal: thinned out three times (cellScale 1.3 -> 2 -> 3, then only about half of
            // those), fine soft dots instead of bigger stars with a bright core, no shooting stars
            cellScale: 3
            starSize: 1.2
            strength: 1.2
            density: 0.55
            // Mean flight: slowly upward, slightly to the left; each particle scatters around it
            particles: true
            drift: Qt.point(-1.5, -5)
            pan: Qt.point(-px * 10, -py * 7)
            sparkles: [[0.08, 0.17, 6, 0], [0.9, 0.85, 6, 4.4]]

            HoverHandler {
                onPointChanged: {
                    if (!hovered)
                        return;
                    menuStars.tx = Math.max(-1, Math.min(1, (point.position.x - menuStars.width / 2) / (menuStars.width / 2)));
                    menuStars.ty = Math.max(-1, Math.min(1, (point.position.y - menuStars.height / 2) / (menuStars.height / 2)));
                }
            }

            FrameAnimation {
                running: menuStars.visible && Math.abs(menuStars.tx - menuStars.px) + Math.abs(menuStars.ty - menuStars.py) > 0.0005
                onTriggered: {
                    const k = 1 - Math.exp(-frameTime * 4);
                    menuStars.px += (menuStars.tx - menuStars.px) * k;
                    menuStars.py += (menuStars.ty - menuStars.py) * k;
                }
            }
        }

        // ---------- Uhr ----------
        Column {
            id: clock

            property real slide: 0

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: dock.top
            anchors.bottomMargin: 72 - slide
            opacity: 1 - slide / 24
            spacing: 6

            // Fonts as in the calendar: clock in Fraunces (display cut, without the wonky forms, slightly soft),
            // everything functional in the grotesque. At 96 px a bit lighter than the calendar clock (340)
            Row {
                id: clockRow

                readonly property var serifAxes: ({
                    "opsz": 144,
                    "WONK": 0,
                    "SOFT": 50,
                    "wght": 300
                })

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2

                Text {
                    id: hourText

                    text: powerMenu.hoursText
                    font.family: Theme.fontDisplay
                    font.pixelSize: 96
                    font.weight: 300
                    font.variableAxes: clockRow.serifAxes
                    font.features: {
                        "tnum": 1,
                        "lnum": 1
                    }
                    color: WalColors.color7
                }

                Text {
                    anchors.baseline: hourText.baseline
                    text: ":"
                    font.family: Theme.fontDisplay
                    font.pixelSize: 96
                    font.weight: 300
                    font.variableAxes: clockRow.serifAxes
                    color: WalColors.color4

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: powerMenu.open

                        PauseAnimation {
                            duration: 500
                        }

                        NumberAnimation {
                            to: 0.25
                            duration: 160
                            easing.type: Easing.InOutQuad
                        }

                        PauseAnimation {
                            duration: 340
                        }

                        NumberAnimation {
                            to: 1
                            duration: 160
                            easing.type: Easing.InOutQuad
                        }

                    }

                }

                Text {
                    anchors.baseline: hourText.baseline
                    text: powerMenu.minutesText
                    font.family: Theme.fontDisplay
                    font.pixelSize: 96
                    font.weight: 300
                    font.variableAxes: clockRow.serifAxes
                    font.features: {
                        "tnum": 1,
                        "lnum": 1
                    }
                    color: WalColors.color7
                }

            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: powerMenu.dateText.toUpperCase()
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 2.6
                color: WalColors.withAlpha(WalColors.color7, 0.5)
            }

            Item {
                width: 1
                height: 10
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: powerMenu.userName !== "" ? "See you soon, " + powerMenu.userName : "See you soon"
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.Medium
                color: WalColors.color2
            }

        }

        // ---------- Tiles (minimalist, solid) ----------
        Item {
            id: dock

            property real pop: 1

            anchors.centerIn: parent
            anchors.verticalCenterOffset: 60
            width: cardRow.implicitWidth
            height: powerMenu.cardH + 34
            opacity: pop

            Row {
                id: cardRow

                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: powerMenu.cardSpacing

                Repeater {
                    model: powerMenu.actions

                    delegate: Item {
                        id: btn

                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: powerMenu.currentIndex === index
                        readonly property bool isArmed: powerMenu.armedIndex === index
                        // Warning color for the countdown, otherwise accent
                        readonly property color tone: isArmed ? WalColors.color1 : WalColors.color4
                        // Opening animation: enter = the tile rises + fades in, reveal = icon/name after it
                        property real enter: 1
                        property real reveal: 1
                        // Middle tiles first, outer ones after (symmetric from the middle outward)
                        readonly property int delay: 40 + Math.abs(index - (powerMenu.actions.length - 1) / 2) * 110

                        function hoverSelect() {
                            if (powerMenu.armedIndex < 0 && !intro.running && powerMenu.currentIndex !== index)
                                powerMenu.currentIndex = index;

                        }

                        width: powerMenu.cardW
                        height: powerMenu.cardH
                        z: isCurrent ? 10 : 1
                        scale: btnMouse.pressed ? 0.97 : (isCurrent ? 1.05 : 1)
                        opacity: enter

                        transform: Translate {
                            y: (1 - btn.enter) * 48
                        }

                        Connections {
                            function onRunningChanged() {
                                if (intro.running) {
                                    btn.enter = 0;
                                    btn.reveal = 0;
                                    exitAnim.stop();
                                    enterAnim.restart();
                                }
                            }

                            target: intro
                        }

                        Connections {
                            function onRunningChanged() {
                                if (outro.running) {
                                    enterAnim.stop();
                                    exitAnim.restart();
                                }
                            }

                            target: outro
                        }

                        // Reverse of opening: outer tiles sink away first, then the inner ones
                        SequentialAnimation {
                            id: exitAnim

                            PauseAnimation {
                                duration: Math.max(0, (205 - btn.delay) * 0.5)
                            }

                            NumberAnimation {
                                target: btn
                                property: "enter"
                                to: 0
                                duration: 160
                                easing.type: Easing.InCubic
                            }

                        }

                        SequentialAnimation {
                            id: enterAnim

                            PauseAnimation {
                                duration: btn.delay
                            }

                            ParallelAnimation {
                                // Easing out softly, no bounce
                                NumberAnimation {
                                    target: btn
                                    property: "enter"
                                    to: 1
                                    duration: 560
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
                                }

                                SequentialAnimation {
                                    PauseAnimation {
                                        duration: 160
                                    }

                                    NumberAnimation {
                                        target: btn
                                        property: "reveal"
                                        to: 1
                                        duration: 420
                                        easing.type: Easing.OutCubic
                                    }

                                }

                            }

                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: btn.isCurrent ? powerMenu.surfaceHi : powerMenu.surface
                            border.width: 1
                            border.color: btn.isCurrent ? WalColors.withAlpha(btn.tone, 0.9) : WalColors.withAlpha(WalColors.color7, 0.08)

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }

                            }

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: 200
                                }

                            }

                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 18

                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 52
                                height: 52
                                opacity: btn.reveal
                                scale: 0.7 + 0.3 * btn.reveal

                                Image {
                                    id: iconImg

                                    anchors.fill: parent
                                    source: btn.modelData.icon
                                    sourceSize.width: 52
                                    sourceSize.height: 52
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    visible: false
                                }

                                GE.ColorOverlay {
                                    anchors.fill: iconImg
                                    source: iconImg
                                    color: btn.isCurrent ? btn.tone : WalColors.withAlpha(WalColors.color7, 0.4)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 200
                                        }

                                    }

                                }

                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: btn.modelData.label
                                opacity: btn.reveal

                                transform: Translate {
                                    y: (1 - btn.reveal) * 8
                                }
                                font.family: Theme.fontUi
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                font.letterSpacing: 0.4
                                color: btn.isCurrent ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.45)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 200
                                    }

                                }

                            }

                        }

                        MouseArea {
                            id: btnMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // During the intro the tiles rise under a resting cursor ->
                            // that is no real hover, otherwise the selection jumps right after opening
                            onEntered: btn.hoverSelect()
                            onPositionChanged: btn.hoverSelect()
                            onClicked: powerMenu.trigger(btn.index)
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                }

            }

            // --- gliding underline with a squish bounce; during the countdown it shrinks to 0 ---
            Rectangle {
                id: selectionBar

                readonly property real baseWidth: powerMenu.cardW - 40
                property real squish: 1
                // Opening: grows out of the middle when the tiles have arrived
                property real grow: 1
                // Left edge of the current tile. Only it glides when switching; the centering depends on
                // the width and must not be animated, otherwise the line lags behind while growing/shrinking
                // (grow, countdown) and then catches up jerkily.
                property real slotX: powerMenu.currentIndex * (powerMenu.cardW + powerMenu.cardSpacing)
                // true = next change of slotX without animation (reset on opening)
                property bool snap: false

                width: baseWidth * grow * (powerMenu.armedIndex >= 0 ? 1 - powerMenu.armProgress : 1)
                height: 2
                radius: 1
                color: powerMenu.armedIndex >= 0 ? WalColors.color1 : WalColors.color4
                anchors.top: cardRow.bottom
                anchors.topMargin: 16
                x: slotX + (powerMenu.cardW - width) / 2

                SequentialAnimation {
                    id: squishAnim

                    NumberAnimation {
                        target: selectionBar
                        property: "squish"
                        to: 0.5
                        duration: 140
                        easing.type: Easing.OutQuad
                    }

                    NumberAnimation {
                        target: selectionBar
                        property: "squish"
                        to: 1
                        duration: Appearance.anim.durations.normal
                        easing.type: Easing.OutBack
                        easing.overshoot: 2.2
                    }

                }

                Connections {
                    function onCurrentIndexChanged() {
                        squishAnim.restart();
                    }

                    target: powerMenu
                }

                transform: Scale {
                    origin.x: selectionBar.width / 2
                    origin.y: selectionBar.height / 2
                    xScale: selectionBar.squish
                }

                Behavior on slotX {
                    enabled: !selectionBar.snap

                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

    }

    // Opening: the background fades in, the clock glides down, the tiles rise from the middle outward,
    // last the underline grows
    // Only hide the window when the last outro frame is surely drawn (otherwise a ghost image in the Hyprland fade)
    Timer {
        id: hideTimer

        interval: powerMenu.outroDuration + 60
        onTriggered: powerMenu.closing = false
    }

    ParallelAnimation {
        id: outro

        NumberAnimation {
            target: clock
            property: "slide"
            to: 24
            duration: 200
            easing.type: Easing.InCubic
        }

        NumberAnimation {
            target: selectionBar
            property: "grow"
            to: 0
            duration: 140
            easing.type: Easing.InCubic
        }

    }

    ParallelAnimation {
        id: intro

        NumberAnimation {
            target: backdrop
            property: "opacity"
            from: 0
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: clock
            property: "slide"
            from: 24
            to: 0
            duration: 420
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: dock
            property: "pop"
            from: 0
            to: 1
            duration: 200
            easing.type: Easing.OutCubic
        }

        SequentialAnimation {
            PauseAnimation {
                duration: 520
            }

            NumberAnimation {
                target: selectionBar
                property: "grow"
                from: 0
                to: 1
                duration: 380
                easing.type: Easing.OutCubic
            }

        }

    }

    // Lock screen elements (same component as lock.qml), fall in from the top when locking
    LockForeground {
        id: lockFg

        anchors.fill: parent
        enter: 0
        visible: powerMenu.locking && enter > 0
        primary: !!anchor.screen && anchor.screen.name === MachineConfig.activeBarScreen(Quickshell.screens).name
    }

}
