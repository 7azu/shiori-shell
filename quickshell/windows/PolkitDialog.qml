import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Password prompt of the shell (polkit, see services/PolkitState): a small card in the middle of the
// focused monitor over a dimmed, blurred background, like the settings window: the card on
// "quickshell:polkit-card", dimming + blur in the backdrop "quickshell:polkit" below (common/ModalBackdrop,
// blur rule in hypr/modules/windows.lua); on closing the card evaporates (common/Evaporate) while the
// backdrop fades. Enter sends, Esc cancels.
//
// The look follows the visual language of the shell (star = done, orbiting dot = busy):
// - the lock sits in a ring of fine dots; a bright head runs around it like a comet, slowly while
//   waiting for the password, fast while polkit checks
// - every typed character becomes a small star that pops into a row instead of a bullet
// - wrong password: the ring flashes red, the stars fall and fade, the card shakes
// - right password: the stars rise into the lock, the ring lights up all the way round, the lock
//   opens and the star fires on it
PanelWindow {
    id: win

    readonly property var flow: PolkitState.flow
    // 0 -> 1 while opening; the parts arrive one after another out of it
    property real reveal: 0
    // The monitor that had the focus when the request came; it stays there
    property string screenName: ""
    // Name of the account whose password is asked (usually your own)
    readonly property string who: {
        const id = flow ? flow.selectedIdentity : null;
        if (!id)
            return "";

        return String(id.displayName || id.name || "");
    }
    readonly property string prompt: {
        const p = flow ? String(flow.inputPrompt || "").trim().replace(/:$/, "") : "";
        return p !== "" ? p : "Password";
    }
    readonly property string errorText: {
        // Quiet while polkit checks and after success
        if (!flow || PolkitState.checking || PolkitState.succeeded)
            return "";

        if (flow.supplementaryIsError && flow.supplementaryMessage)
            return flow.supplementaryMessage;

        return PolkitState.failures > 0 ? "Wrong password. Try again." : "";
    }
    readonly property bool echo: !!flow && flow.responseVisible
    // Stars that were sent: shown while polkit checks and while they fall or rise afterwards
    property int sentCount: 0
    // 0..1: the sent stars fall away (wrong) or rise into the lock (right)
    property real fall: 0
    property real rise: 0
    // Brightness kick of the lock and ring on every key press
    property real keyKick: 0
    readonly property color tone: PolkitState.failures > 0 && !PolkitState.succeeded && !PolkitState.checking ? Theme.bad : Theme.accent

    function send() {
        if (field.text === "" || PolkitState.checking || PolkitState.succeeded)
            return ;

        sentCount = Math.min(field.text.length, 24);
        fall = 0;
        rise = 0;
        PolkitState.submit(field.text);
        field.text = "";
    }

    // Part of the opening: starts at `from` (0..1 of reveal), takes 0.5 of it
    function part(from) {
        const k = Math.max(0, Math.min(1, (reveal - from) / 0.5));
        return 1 - Math.pow(1 - k, 3);
    }

    screen: Quickshell.screens.find((s) => {
        return s.name === win.screenName;
    }) || Quickshell.screens[0]
    visible: ev.held
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    WlrLayershell.namespace: "quickshell:polkit-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible && !ev.closing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region {
        item: card
    }
    onVisibleChanged: {
        opening.stop();
        if (visible)
            win.playOpening();

    }

    function playOpening() {
        reveal = 0;
        sentCount = 0;
        fall = 0;
        rise = 0;
        opening.restart();
        field.text = "";
        field.forceActiveFocus();
    }
    onFlowChanged: {
        if (flow)
            screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";

    }

    Evaporate {
        id: ev

        window: win
        open: PolkitState.showing
        // A new request while the last one evaporates: start over
        onReopened: win.playOpening()
    }

    Connections {
        function onFailuresChanged() {
            if (PolkitState.failures > 0) {
                shake.restart();
                fallAnim.restart();
                ring.flash();
            }
        }

        function onSucceededChanged() {
            if (PolkitState.succeeded) {
                riseAnim.restart();
                ring.complete();
            }
        }

        target: PolkitState
    }

    NumberAnimation {
        id: opening

        target: win
        property: "reveal"
        from: 0
        to: 1
        duration: 900
    }

    SequentialAnimation {
        id: fallAnim

        NumberAnimation {
            target: win
            property: "fall"
            from: 0
            to: 1
            duration: 520
            easing.type: Easing.InCubic
        }

        ScriptAction {
            script: {
                win.sentCount = 0;
                win.fall = 0;
            }
        }

    }

    SequentialAnimation {
        id: riseAnim

        NumberAnimation {
            target: win
            property: "rise"
            from: 0
            to: 1
            duration: 420
            easing.type: Easing.InCubic
        }

        ScriptAction {
            script: star.play()
        }

    }

    NumberAnimation {
        id: kick

        target: win
        property: "keyKick"
        from: 1
        to: 0
        duration: 420
        easing.type: Easing.OutCubic
    }

    // As in the pickers: alpha via ignore_alpha on the whole screen, so Hyprland blurs the background
    // outside the card too. A click next to the card does nothing (it is caught here): a password
    // question should not vanish by accident.
    ModalBackdrop {
        screen: win.screen
        name: "quickshell:polkit"
        shown: PolkitState.showing
        dim: WalColors.withAlpha(WalColors.color0, 0.45 * Math.min(1, win.reveal * 2))
    }

    Item {
        id: card

        property real shakeX: 0

        anchors.centerIn: parent
        anchors.verticalCenterOffset: Theme.px(18) * (1 - win.part(0))
        width: Theme.px(392)
        height: body.implicitHeight + Theme.px(60)
        scale: (0.94 + 0.06 * win.part(0)) * (PolkitState.succeeded ? 1.012 : 1)
        opacity: win.part(0) * ev.opacity
        enabled: !ev.closing
        layer.enabled: ev.closing
        // Evaporate scale as its own transform: the Behavior on scale would restart every frame
        transform: [
            Translate {
                x: card.shakeX
            },
            Scale {
                origin.x: card.width / 2
                origin.y: card.height / 2
                xScale: ev.scale
                yScale: ev.scale
            }
        ]

        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: true
            blur: ev.blur
            blurMax: 64
            blurMultiplier: 0.6
        }

        Behavior on scale {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }

        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXL
            color: WalColors.color0
            border.width: 1
            border.color: Theme.glass
        }

        // A soft glow of the accent around the lock; brighter on each key and on success
        Shape {
            id: glow

            readonly property real cy: Theme.px(30) + Theme.px(42)

            anchors.fill: parent
            opacity: 0.55 + 0.25 * win.keyKick + (PolkitState.succeeded ? 0.35 : 0)
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: 0

                fillGradient: RadialGradient {
                    centerX: glow.width / 2
                    centerY: glow.cy
                    centerRadius: Theme.px(120)
                    focalX: centerX
                    focalY: centerY

                    GradientStop {
                        position: 0
                        color: Theme.tint(win.tone, 0.16)
                    }

                    GradientStop {
                        position: 0.45
                        color: Theme.tint(win.tone, 0.05)
                    }

                    GradientStop {
                        position: 1
                        color: "transparent"
                    }

                }

                PathLine {
                    x: glow.width
                    y: 0
                }

                PathLine {
                    x: glow.width
                    y: glow.cy * 2
                }

                PathLine {
                    x: 0
                    y: glow.cy * 2
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                }

            }

        }

        Column {
            id: body

            x: Theme.px(30)
            y: Theme.px(30)
            width: parent.width - 2 * x
            spacing: 0

            // ---- The lock in its ring ----
            Item {
                id: emblem

                readonly property real k: win.part(0.05)

                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.px(84)
                height: Theme.px(84)
                opacity: k
                scale: 0.8 + 0.2 * k

                Ring {
                    id: ring

                    anchors.fill: parent
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Theme.px(46)
                    height: width
                    radius: width / 2
                    color: Theme.tint(win.tone, 0.13 + 0.07 * win.keyKick)

                    Behavior on color {
                        ColorAnimation {
                            duration: 260
                        }

                    }

                }

                Text {
                    id: lockGlyph

                    property real bounce: 0

                    anchors.centerIn: parent
                    text: PolkitState.succeeded ? "󰿆" : "󰌾"
                    color: win.tone
                    font.family: Theme.font
                    font.pixelSize: Theme.px(20)
                    scale: 1 + 0.12 * win.keyKick + 0.22 * bounce

                    SequentialAnimation {
                        running: PolkitState.succeeded

                        NumberAnimation {
                            target: lockGlyph
                            property: "bounce"
                            from: 0
                            to: 1
                            duration: 140
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            target: lockGlyph
                            property: "bounce"
                            to: 0
                            duration: 420
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }

                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 260
                        }

                    }

                }

                StarBurst {
                    id: star

                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -Theme.px(22)
                    size: Theme.px(6)
                }

            }

            Item {
                width: 1
                height: Theme.px(18)
            }

            // ---- Title and what the app wants ----
            Column {
                id: heading

                readonly property real k: win.part(0.15)

                width: parent.width
                spacing: Theme.px(8)
                opacity: k

                transform: Translate {
                    y: (1 - heading.k) * Theme.px(8)
                }

                CrossText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: PolkitState.succeeded ? "Unlocked" : "Authentication required"
                    color: Theme.text
                    font.family: Theme.fontDisplay
                    font.pixelSize: Theme.px(23)
                    font.weight: 380
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    text: win.flow ? win.flow.message : ""
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                    lineHeight: 1.15
                }

            }

            Item {
                width: 1
                height: Theme.px(24)
            }

            // ---- Password: the typed characters as stars ----
            Item {
                id: fieldBox

                readonly property real k: win.part(0.25)
                readonly property bool focused: field.activeFocus

                width: parent.width
                height: Theme.px(52)
                opacity: k

                transform: Translate {
                    y: (1 - fieldBox.k) * Theme.px(8)
                }

                // Soft glow around the field while it has the keyboard
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -Theme.px(4)
                    radius: Theme.px(20)
                    color: "transparent"
                    border.width: Theme.px(4)
                    border.color: Theme.tint(win.tone, 0.12)
                    opacity: fieldBox.focused && !PolkitState.succeeded ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 260
                        }

                    }

                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.px(16)
                    color: fieldMouse.containsMouse ? Theme.cardHover : Theme.card
                    border.width: 1
                    border.color: win.errorText !== "" ? Theme.tint(Theme.bad, 0.55) : (fieldBox.focused ? Theme.tint(win.tone, 0.55) : Theme.stroke)

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 220
                        }

                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 160
                        }

                    }

                }

                MouseArea {
                    id: fieldMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.IBeamCursor
                    onClicked: field.forceActiveFocus()
                }

                // The real input, invisible: what shows is the row of stars (or the text when the
                // question allows to see it)
                TextInput {
                    id: field

                    anchors.fill: parent
                    opacity: 0
                    focus: true
                    enabled: !PolkitState.checking && !PolkitState.succeeded
                    echoMode: win.echo ? TextInput.Normal : TextInput.Password
                    onTextChanged: {
                        if (text.length > 0)
                            kick.restart();

                    }
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            win.send();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            PolkitState.cancel();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: win.prompt
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                    opacity: field.text === "" && win.sentCount === 0 ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                        }

                    }

                }

                // Visible text, only for questions that are not secret
                Text {
                    anchors.centerIn: parent
                    width: parent.width - Theme.px(40)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideLeft
                    visible: win.echo
                    text: field.text
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.px(15)
                }

                Row {
                    id: stars

                    readonly property int count: win.sentCount > 0 ? win.sentCount : Math.min(field.text.length, 24)
                    // Narrower spacing for long passwords, so the row stays inside the field
                    readonly property real gap: count > 16 ? Theme.px(5) : Theme.px(9)

                    anchors.centerIn: parent
                    spacing: gap
                    visible: !win.echo

                    Behavior on spacing {
                        NumberAnimation {
                            duration: 200
                        }

                    }

                    Repeater {
                        model: stars.count

                        delegate: Item {
                            id: dot

                            required property int index
                            // Arrival: from nothing with a little overshoot
                            property real pop: 0
                            // While polkit checks a wave of brightness runs along the row
                            readonly property real wave: PolkitState.checking ? 0.5 + 0.5 * Math.sin(ring.head * 2 * Math.PI * 3 - index * 0.7) : 1
                            // Falling or rising one after the other, from the left
                            readonly property real out: win.fall > 0 ? win.fall : win.rise
                            readonly property real stagger: Math.max(0, Math.min(1, stars.count > 1 ? out * 1.6 - index / (stars.count - 1) * 0.6 : out))

                            width: Theme.px(8)
                            height: Theme.px(8)
                            Component.onCompleted: popAnim.start()

                            Sparkle {
                                anchors.centerIn: parent
                                size: Theme.px(3.2)
                                rays: 2.2
                                color: win.tone
                                twinkle: 0.4 + 0.6 * dot.wave
                                opacity: dot.pop * (0.45 + 0.55 * dot.wave) * (1 - dot.stagger)
                                scale: dot.pop

                                transform: Translate {
                                    // Falling down (wrong) or rising towards the lock (right)
                                    y: win.fall > 0 ? dot.stagger * Theme.px(18) : -dot.stagger * Theme.px(70)
                                    x: win.rise > 0 ? -(dot.x + dot.width / 2 - stars.width / 2) * dot.stagger * 0.9 : 0
                                }

                            }

                            NumberAnimation {
                                id: popAnim

                                target: dot
                                property: "pop"
                                from: 0
                                to: 1
                                duration: 260
                                easing.type: Easing.OutBack
                                easing.overshoot: 2.2
                            }

                        }

                    }

                }

                // The caret after the last star
                Rectangle {
                    x: stars.x + stars.width + Theme.px(7)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.px(2)
                    height: Theme.px(18)
                    radius: 1
                    color: win.tone
                    visible: fieldBox.focused && !win.echo && !PolkitState.checking && !PolkitState.succeeded && win.sentCount === 0 && field.text !== ""

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: fieldBox.focused

                        NumberAnimation {
                            to: 0.15
                            duration: 520
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            to: 1
                            duration: 520
                            easing.type: Easing.InOutSine
                        }

                    }

                    Behavior on x {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

            // Error or whose password; keeps its place, so the card does not jump
            Item {
                width: parent.width
                height: Theme.px(34)
                opacity: win.part(0.3)

                CrossText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: win.errorText !== "" ? win.errorText : (PolkitState.checking ? "CHECKING" : (win.who !== "" ? "AS " + win.who.toUpperCase() : ""))
                    color: win.errorText !== "" ? Theme.bad : Theme.textFaint
                    travel: 0.25
                    font.pixelSize: win.errorText !== "" ? Theme.sizeSmall : Theme.sizeMicro
                    font.weight: win.errorText !== "" ? Font.Normal : Font.Bold
                    font.letterSpacing: win.errorText !== "" ? 0 : 1.6
                }

            }

            // ---- Buttons ----
            Row {
                id: buttons

                readonly property real k: win.part(0.38)

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.px(10)
                // Step back once it is done; the card closes a moment later
                opacity: k * (PolkitState.succeeded ? 0.35 : 1)

                transform: Translate {
                    y: (1 - buttons.k) * Theme.px(8)
                }

                Pill {
                    text: "Cancel"
                    filled: false
                    onClicked: PolkitState.cancel()
                }

                Pill {
                    text: PolkitState.checking ? "Checking" : "Unlock"
                    glyph: "󰁔"
                    filled: true
                    busy: PolkitState.checking
                    onClicked: win.send()
                }

            }

        }

        SequentialAnimation {
            id: shake

            NumberAnimation {
                target: card
                property: "shakeX"
                to: -10
                duration: 55
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                target: card
                property: "shakeX"
                to: 8
                duration: 85
                easing.type: Easing.InOutQuad
            }

            NumberAnimation {
                target: card
                property: "shakeX"
                to: -5
                duration: 80
                easing.type: Easing.InOutQuad
            }

            NumberAnimation {
                target: card
                property: "shakeX"
                to: 2
                duration: 70
                easing.type: Easing.InOutQuad
            }

            NumberAnimation {
                target: card
                property: "shakeX"
                to: 0
                duration: 90
                easing.type: Easing.OutQuad
            }

        }

    }

    // A ring of fine dots around the lock with a bright head running round like a comet: slowly while
    // waiting, fast while polkit checks. It draws itself when the card opens, flashes on a wrong
    // password and lights up all the way round on success.
    component Ring: Item {
        id: r

        readonly property int n: 40
        // Angle of the comet's head in turns, integrated, so a change of speed never jumps
        property real head: 0
        property real speed: PolkitState.checking ? 1.1 : 0.16
        // 0..1 how much of the ring has been drawn (opening)
        readonly property real drawn: win.part(0.05)
        // 0..1 a red flash, and the light that runs all the way round on success
        property real flashK: 0
        property real fill: 0

        function flash() {
            flashAnim.restart();
        }

        function complete() {
            fillAnim.restart();
        }

        FrameAnimation {
            running: win.visible
            onTriggered: r.head = (r.head + Math.min(frameTime, 0.05) * r.speed) % 1
        }

        Repeater {
            model: r.n

            delegate: Rectangle {
                required property int index
                readonly property real at: index / r.n
                // Distance behind the head (0 = the head, towards 1 = the tail end)
                readonly property real behind: ((r.head - at) % 1 + 1) % 1
                readonly property real comet: Math.pow(Math.max(0, 1 - behind / 0.3), 2)
                readonly property bool isDrawn: at <= r.drawn
                readonly property bool isFilled: at <= r.fill

                x: r.width / 2 + Math.sin(at * 2 * Math.PI) * (r.width / 2 - 2) - width / 2
                y: r.height / 2 - Math.cos(at * 2 * Math.PI) * (r.height / 2 - 2) - height / 2
                width: Theme.px(2) * (1 + 0.5 * comet)
                height: width
                radius: width / 2
                color: r.flashK > 0.01 ? Theme.bad : (isFilled || comet > 0.05 ? win.tone : Theme.text)
                opacity: !isDrawn ? 0 : Math.max(isFilled ? 0.95 : 0.16 + 0.1 * win.keyKick, comet, r.flashK)
            }

        }

        NumberAnimation {
            id: flashAnim

            target: r
            property: "flashK"
            from: 1
            to: 0
            duration: 700
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: fillAnim

            target: r
            property: "fill"
            from: 0
            to: 1.001
            duration: 520
            easing.type: Easing.InOutCubic
        }

    }

    // A rounded button: filled = the main action in the accent. Under the pointer it grows a little,
    // a soft sheen runs across it and its arrow leans forward.
    component Pill: Item {
        id: pill

        property string text: ""
        property string glyph: ""
        property bool filled: false
        property bool busy: false
        property real sheen: 0

        signal clicked()

        width: row.implicitWidth + Theme.px(40)
        height: Theme.px(38)
        scale: mouse.pressed ? 0.95 : (mouse.containsMouse ? 1.04 : 1)
        onBusyChanged: {
            if (busy)
                sheenAnim.stop();

        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: pill.filled ? Theme.accent : (mouse.containsMouse ? Theme.cardHover : Theme.card)
            border.width: pill.filled ? 0 : 1
            border.color: mouse.containsMouse ? Theme.tint(Theme.text, 0.16) : Theme.stroke
            clip: true

            // The sheen: a light band that crosses once when the pointer arrives
            Rectangle {
                visible: pill.filled
                x: -width + (parent.width + width) * pill.sheen
                width: parent.height * 1.2
                height: parent.height
                opacity: Math.sin(Math.PI * pill.sheen) * 0.5
                rotation: 18

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: "transparent"
                    }

                    GradientStop {
                        position: 0.5
                        color: Qt.rgba(1, 1, 1, 0.55)
                    }

                    GradientStop {
                        position: 1
                        color: "transparent"
                    }

                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 160
                }

            }

            Behavior on border.color {
                ColorAnimation {
                    duration: 160
                }

            }

        }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Theme.px(8)

            // A circling dot while polkit checks
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.px(10)
                height: Theme.px(10)
                visible: pill.busy

                Rectangle {
                    x: parent.width / 2 - width / 2
                    width: Theme.px(3)
                    height: width
                    radius: width / 2
                    color: pill.filled ? Theme.onAccent : Theme.text
                }

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: pill.busy
                }

            }

            CrossText {
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                text: pill.text
                color: pill.filled ? Theme.onAccent : Theme.text
                font.pixelSize: Theme.sizeLabel
                font.weight: Font.Medium
            }

            Text {
                id: arrow

                anchors.verticalCenter: parent.verticalCenter
                visible: pill.glyph !== "" && !pill.busy
                text: pill.glyph
                color: pill.filled ? Theme.onAccent : Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(14)

                transform: Translate {
                    x: mouse.containsMouse ? Theme.px(3) : 0

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
            onContainsMouseChanged: {
                if (containsMouse && pill.filled && !pill.busy)
                    sheenAnim.restart();

            }
        }

        NumberAnimation {
            id: sheenAnim

            target: pill
            property: "sheen"
            from: 0
            to: 1
            duration: 650
            easing.type: Easing.InOutCubic
        }

        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }

        }

        Behavior on width {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }

        }

    }

}
