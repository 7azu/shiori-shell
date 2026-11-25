import "../services"
import QtQuick
import QtQuick.Shapes

Item {
    id: slot

    property string icon: "clipboard"
    property bool active: false
    property bool playing: false
    // Language learning tool: character of the language in the speech bubble (あ, 한, De ...)
    property string mark: ""
    // Bluetooth/Wi-Fi: connected (signal dots or arcs stay) or off (fainter)
    property bool linked: false
    property bool dimmed: false
    // Wi-Fi: connection is being established/disconnected (arcs pulse)
    property bool busy: false
    property real reveal: 1
    readonly property bool hovered: slotHover.hovered
    readonly property color ink: (hovered || active) ? WalColors.color4 : WalColors.withAlpha(WalColors.color2, dimmed ? 0.4 : 0.85)
    // Language learning tool: while playing the character makes way for three swinging bars (only then, not on
    // hover - the bars say "playing right now")
    property real waveEnergy: icon === "language" && playing ? 1 : 0
    property real wavePhase: 0

    signal clicked()
    signal rightClicked()

    width: Math.round(16 + 16 * BarState.density)
    height: 32
    opacity: reveal
    scale: 0.6 + 0.4 * reveal

    // Bin: on hover the lid opens (as in the trash window)
    Item {
        anchors.centerIn: parent
        width: 18
        height: 18
        visible: slot.icon === "trash"
        scale: slot.hovered ? 1.12 : 1

        Rectangle {
            x: 3.5
            y: 5.5
            width: 11
            height: 12
            radius: 2
            color: "transparent"
            border.width: 1.6
            border.color: slot.ink
        }

        Item {
            anchors.fill: parent

            Rectangle {
                x: 1.5
                y: 3
                width: 15
                height: 1.6
                radius: 0.8
                color: slot.ink
            }

            Rectangle {
                x: 6.5
                y: 0.5
                width: 5
                height: 3
                radius: 1
                color: "transparent"
                border.width: 1.4
                border.color: slot.ink
            }

            transform: Rotation {
                origin.x: 16.5
                origin.y: 3.8
                angle: slot.hovered || slot.active ? 24 : 0

                Behavior on angle {
                    SpringAnimation {
                        spring: 5.5
                        damping: 0.4
                        epsilon: 0.2
                    }

                }

            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

    }

    Item {
        anchors.centerIn: parent
        width: 18
        height: 18
        visible: slot.icon === "clipboard"
        scale: slot.hovered ? 1.12 : 1

        Rectangle {
            x: 2
            y: 3
            width: 14
            height: 14
            radius: 3
            color: "transparent"
            border.width: 1.6
            border.color: slot.ink
        }

        Rectangle {
            x: 5
            y: 8
            width: slot.hovered ? 8 : 6
            height: 1.6
            radius: 0.8
            color: slot.ink

            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }

            }

        }

        Rectangle {
            x: 5
            y: 12
            width: slot.hovered ? 5 : 8
            height: 1.6
            radius: 0.8
            color: WalColors.withAlpha(slot.ink, 0.65)

            Behavior on width {
                NumberAnimation {
                    duration: 240
                    easing.type: Easing.OutCubic
                }

            }

        }

        Rectangle {
            x: 6
            y: slot.hovered ? 0.5 : 1
            width: 6
            height: 4.5
            radius: 2
            color: slot.ink

            Behavior on y {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }

            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

    }

    Item {
        id: appsIcon

        property real spread: slot.hovered ? 1 : 0

        anchors.centerIn: parent
        width: 18
        height: 18
        visible: slot.icon === "apps"
        scale: slot.hovered ? 1.12 : 1

        Repeater {
            model: 4

            delegate: Rectangle {
                required property int index
                readonly property int cx: index % 2
                readonly property int cy: Math.floor(index / 2)

                x: 2.2 + cx * 7.6 + (cx === 0 ? -1 : 1) * appsIcon.spread
                y: 2.2 + cy * 7.6 + (cy === 0 ? -1 : 1) * appsIcon.spread
                width: 6.2
                height: 6.2
                radius: 2
                antialiasing: true
                color: slot.ink
                rotation: (slot.active && index === 1) ? 45 : 0

                Behavior on rotation {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutBack
                    }

                }

            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

        Behavior on spread {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }

        }

    }

    // Media icon: small screen with a play triangle
    Item {
        id: mediaIcon

        property real nudge: slot.hovered ? 0.9 : 0

        anchors.centerIn: parent
        width: 18
        height: 18
        visible: slot.icon === "media"
        scale: slot.hovered ? 1.12 : 1

        Rectangle {
            x: 1
            y: 3
            width: 16
            height: 12
            radius: 3.5
            color: "transparent"
            antialiasing: true
            border.width: 1.6
            border.color: slot.ink
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: slot.ink
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 7.4 + mediaIcon.nudge
                startY: 6.3

                PathLine {
                    x: 12 + mediaIcon.nudge
                    y: 9
                }

                PathLine {
                    x: 7.4 + mediaIcon.nudge
                    y: 11.7
                }

                PathLine {
                    x: 7.4 + mediaIcon.nudge
                    y: 6.3
                }

            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

        Behavior on nudge {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }

        }

    }

    // Bluetooth rune; two dots left/right as "signal" (hover or connected)
    Item {
        id: btIcon

        property real beam: (slot.hovered || slot.linked) ? 1 : 0

        anchors.centerIn: parent
        width: 18
        height: 18
        visible: slot.icon === "bluetooth"
        scale: slot.hovered ? 1.12 : 1

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: slot.ink
                strokeWidth: 1.6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: 5
                startY: 5.5

                PathLine {
                    x: 12.5
                    y: 12.2
                }

                PathLine {
                    x: 9
                    y: 15.6
                }

                PathLine {
                    x: 9
                    y: 2.4
                }

                PathLine {
                    x: 12.5
                    y: 5.8
                }

                PathLine {
                    x: 5
                    y: 12.5
                }

            }

        }

        Repeater {
            model: 2

            delegate: Rectangle {
                required property int index

                x: (index === 0 ? 2.2 : 14.6) + (index === 0 ? -1 : 1) * btIcon.beam - width / 2 + 0.6
                y: 9 - height / 2
                width: 2.2
                height: 2.2
                radius: 1.1
                color: slot.ink
                opacity: btIcon.beam
                scale: 0.4 + 0.6 * btIcon.beam
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

        Behavior on beam {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutBack
            }

        }

    }

    // Wi-Fi: dot + three arcs, same height as the Bluetooth glyph. The dot and two arcs are
    // always there; on hover/connected the outer one extends (like the signal dots on the Bluetooth icon),
    // while connecting all arcs pulse from the inside out.
    Item {
        id: wifiIcon

        property real beam: (slot.hovered || slot.linked) ? 1 : 0
        property real pulse: 0

        anchors.centerIn: parent
        width: 18
        height: 18
        visible: slot.icon === "wifi"
        scale: slot.hovered ? 1.12 : 1

        Repeater {
            model: 3

            delegate: Shape {
                id: arc

                required property int index
                // Arcs 0 and 1 always there, the outer one (2) comes with beam
                readonly property real shownK: index < 2 ? 1 : Math.max(0, Math.min(1, wifiIcon.beam))
                // While connecting: a wave from the inside out
                readonly property real wave: slot.busy ? 0.35 + 0.65 * Math.max(0, Math.sin(wifiIcon.pulse * 2 * Math.PI - index * 1.1)) : 1

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: (slot.busy ? 1 : shownK) * wave
                scale: slot.busy ? 1 : 0.7 + 0.3 * shownK

                ShapePath {
                    strokeColor: slot.ink
                    strokeWidth: 1.6
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: 9
                        centerY: 15
                        radiusX: 4 + arc.index * 3.4
                        radiusY: 4 + arc.index * 3.4
                        startAngle: 225
                        sweepAngle: 90
                        moveToStart: true
                    }

                }

            }

        }

        Rectangle {
            x: 9 - width / 2
            y: 15 - height / 2
            width: 2.4
            height: 2.4
            radius: 1.2
            color: slot.ink
        }

        NumberAnimation on pulse {
            from: 0
            to: 1
            duration: 1200
            loops: Animation.Infinite
            running: slot.icon === "wifi" && slot.busy
        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

        Behavior on beam {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutBack
            }

        }

    }

    // Language learning tool: speech bubble with the character of the language; while something plays, it turns into three
    // swinging bars. Hover lifts the bubble a bit (like the other icons + a slight lift).
    Item {
        id: langIcon

        // Latin abbreviations (De, En) smaller and in the grotesque, characters in Noto CJK
        readonly property bool latin: /^[A-Za-z]/.test(slot.mark)
        // Middle of the bubble body (without the tail)
        readonly property real bodyMid: 7.5
        // Change character <-> bars as a sequence on one value (waveEnergy, linear 0..1): first
        // the character turns away small, then the bars pop up one after another (slight overshoot).
        // Backwards (pause) exactly in reverse: bars sink in from the right, the character pops back.
        readonly property real t: slot.waveEnergy
        readonly property real glyphK: backOut(clamp01(1 - t / 0.4))
        // The bubble breathes up once briefly on the change (anchored at the tail, as if it were speaking)
        readonly property real pop: Math.sin(Math.PI * t)

        function clamp01(x) {
            return Math.max(0, Math.min(1, x));
        }

        // Easing OutBack by hand, because the parts run offset from one shared value
        function backOut(x) {
            const c = 1.70158;
            const u = x - 1;
            return 1 + (c + 1) * u * u * u + c * u * u;
        }

        function barK(i) {
            return backOut(clamp01((t - 0.35 - i * 0.12) / 0.4));
        }

        anchors.centerIn: parent
        width: 18
        height: 18
        visible: slot.icon === "language"
        scale: slot.hovered ? 1.12 : 1

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Rounded body 1.2..16.8 x 1.8..13.2, tail at the bottom left (tip 5/16.6)
            ShapePath {
                strokeColor: slot.ink
                strokeWidth: 1.6
                fillColor: "transparent"
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                startX: 5
                startY: 1.8

                PathLine {
                    x: 13
                    y: 1.8
                }

                PathArc {
                    x: 16.8
                    y: 5.6
                    radiusX: 3.8
                    radiusY: 3.8
                }

                PathLine {
                    x: 16.8
                    y: 9.4
                }

                PathArc {
                    x: 13
                    y: 13.2
                    radiusX: 3.8
                    radiusY: 3.8
                }

                PathLine {
                    x: 9
                    y: 13.2
                }

                PathLine {
                    x: 5
                    y: 16.6
                }

                PathLine {
                    x: 5
                    y: 13.2
                }

                PathArc {
                    x: 1.2
                    y: 9.4
                    radiusX: 3.8
                    radiusY: 3.8
                }

                PathLine {
                    x: 1.2
                    y: 5.6
                }

                PathArc {
                    x: 5
                    y: 1.8
                    radiusX: 3.8
                    radiusY: 3.8
                }

            }

        }

        Text {
            width: parent.width
            height: 2 * langIcon.bodyMid
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: slot.mark
            font.family: langIcon.latin ? Theme.fontUi : "Noto Sans CJK JP"
            font.pixelSize: langIcon.latin ? 7 : 8
            font.bold: true
            color: slot.ink
            opacity: langIcon.clamp01(langIcon.glyphK)
            scale: 0.3 + 0.7 * langIcon.glyphK
            rotation: -25 * (1 - langIcon.glyphK)
            visible: opacity > 0.01
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: langIcon.bodyMid - height / 2
            spacing: 1.5
            visible: langIcon.t > 0.001

            Repeater {
                model: 3

                delegate: Item {
                    id: waveBar

                    required property int index
                    readonly property real k: langIcon.barK(index)

                    width: 1.6
                    height: 7

                    Rectangle {
                        width: parent.width
                        // Grows out of a point (k = 0) to the full, swinging height
                        height: Math.max(width, waveBar.k * ((waveBar.index === 1 ? 4.5 : 3) + 2.5 * (0.5 + 0.5 * Math.sin(slot.wavePhase - waveBar.index * 1.1))))
                        y: (parent.height - height) / 2
                        opacity: langIcon.clamp01(waveBar.k * 3)
                        radius: width / 2
                        antialiasing: true
                        color: slot.ink
                    }

                }

            }

        }

        transform: [
            Scale {
                origin.x: 5
                origin.y: 16.6
                xScale: 1 + 0.08 * langIcon.pop
                yScale: 1 + 0.08 * langIcon.pop
            },
            Translate {
                y: slot.hovered ? -0.8 : 0

                Behavior on y {
                    NumberAnimation {
                        duration: Appearance.anim.durations.fast
                        easing.type: Easing.OutCubic
                    }

                }

            }
        ]

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

    }

    HoverHandler {
        id: slotHover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                slot.rightClicked();
            else
                slot.clicked();
        }
    }

    // Linear: the curves sit in langIcon (glyphK/barK), otherwise the sequence would be distorted twice
    Behavior on waveEnergy {
        NumberAnimation {
            duration: 700
            easing.type: Easing.Linear
        }

    }

    NumberAnimation on wavePhase {
        from: 0
        to: 2 * Math.PI
        duration: 1600
        loops: Animation.Infinite
        running: slot.icon === "language" && slot.waveEnergy > 0.001
    }

}
