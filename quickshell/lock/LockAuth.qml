import "../common"
import "../services"
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets

// Avatar orb with a ring + password pill. The ring is the feedback: it charges with every
// character, circles while checking, turns red on errors (shake) and closes into a full circle when
// unlocking.
Item {
    id: root

    readonly property int orbSize: Theme.px(132)
    readonly property int ringGap: Theme.px(10)
    readonly property int pillW: Theme.px(320)
    readonly property int pillH: Theme.px(48)
    // The error tone fades out slowly after the shake
    property real failGlow: 0
    property real shakeX: 0
    readonly property color ringTone: Qt.tint(WalColors.color4, Theme.tint(Theme.bad, failGlow))
    readonly property string userName: Quickshell.env("USER") || "user"

    implicitWidth: pillW
    implicitHeight: column.implicitHeight

    Connections {
        function onFailTickChanged() {
            shake.restart();
        }

        target: LockState
    }

    SequentialAnimation {
        id: shake

        PropertyAction {
            target: root
            property: "failGlow"
            value: 1
        }

        // Damped head shake (like macOS), then the red fades out
        NumberAnimation {
            target: root
            property: "shakeX"
            to: -16
            duration: 60
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: root
            property: "shakeX"
            to: 12
            duration: 90
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: root
            property: "shakeX"
            to: -7
            duration: 80
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: root
            property: "shakeX"
            to: 3
            duration: 70
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: root
            property: "shakeX"
            to: 0
            duration: 60
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: root
            property: "failGlow"
            to: 0
            duration: 1600
            easing.type: Easing.InQuad
        }

    }

    Column {
        id: column

        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.px(18)

        // ---------- Orb ----------
        Item {
            id: orb

            // Charge of the ring: characters fill it, full at 16 (longer passwords stay full)
            property real charge: LockState.unlocking ? 1 : Math.min(LockState.buffer.length / 16, 1)
            property real spin: 0

            anchors.horizontalCenter: parent.horizontalCenter
            width: root.orbSize + 2 * root.ringGap + Theme.px(8)
            height: width
            scale: LockState.unlocking ? 1.12 : 1
            transform: Translate {
                x: root.shakeX
            }

            // Constant, slow circling; faster while checking
            NumberAnimation on spin {
                from: 0
                to: 360
                loops: Animation.Infinite
                duration: LockState.checking ? 900 : 14000
                running: true
            }

            // Soft glow behind the avatar in the ring color. glow.frag instead of RadialGradient (no rings from
            // banding, see LockBackdrop); same extent, the old gradient ended at the edge of the item.
            ShaderEffect {
                property color tint: root.ringTone
                property real strength: 0.3

                anchors.centerIn: parent
                width: root.orbSize * 2.4
                height: width
                opacity: 0.4 + 0.6 * Math.max(orb.charge, root.failGlow)
                fragmentShader: Qt.resolvedUrl("../windows/shaders/glow.frag.qsb")
            }

            ClippingRectangle {
                anchors.centerIn: parent
                width: root.orbSize
                height: width
                radius: width / 2
                color: WalColors.color0

                // The same profile picture as in the notification center: ~/.face (chosen there with yazi),
                // otherwise common/DefaultAvatar in the pywal colors. Deliberately not using NotificationState: the
                // lock is its own qs instance and would otherwise need the whole notification service.
                DefaultAvatar {
                    anchors.fill: parent
                    visible: faceImg.status !== Image.Ready
                }

                Image {
                    id: faceImg

                    anchors.fill: parent
                    source: "file://" + Quickshell.env("HOME") + "/.face"
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: root.orbSize * 2
                    sourceSize.height: root.orbSize * 2
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }

                // The avatar darkens slightly while checking
                Rectangle {
                    anchors.fill: parent
                    color: WalColors.color0
                    opacity: LockState.checking ? 0.35 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.anim.durations.normal
                        }

                    }

                }

            }

            // Ring: track + charged arc
            Shape {
                id: ring

                readonly property real r: root.orbSize / 2 + root.ringGap
                // While checking a short circling arc, otherwise the charge (at least one spark)
                property real sweep: LockState.checking ? 80 : Math.max(orb.charge * 360, 6)

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: WalColors.withAlpha(WalColors.color7, 0.12)
                    strokeWidth: Theme.px(2)
                    fillColor: "transparent"

                    PathAngleArc {
                        centerX: ring.width / 2
                        centerY: ring.height / 2
                        radiusX: ring.r
                        radiusY: ring.r
                        startAngle: 0
                        sweepAngle: 360
                    }

                }

                ShapePath {
                    strokeColor: root.ringTone
                    strokeWidth: Theme.px(3)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: ring.width / 2
                        centerY: ring.height / 2
                        radiusX: ring.r
                        radiusY: ring.r
                        startAngle: orb.spin - 90
                        sweepAngle: ring.sweep
                    }

                }

                Behavior on sweep {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.outQuint
                    }

                }

            }

            // Spark at the tip of the arc
            Rectangle {
                readonly property real a: (orb.spin - 90 + ring.sweep) * Math.PI / 180

                width: Theme.px(7)
                height: width
                radius: width / 2
                color: root.ringTone
                x: orb.width / 2 + Math.cos(a) * ring.r - width / 2
                y: orb.height / 2 + Math.sin(a) * ring.r - height / 2
                opacity: LockState.checking ? 0 : 0.9
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                }

            }

        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userName
            font.family: Theme.fontDisplay
            font.pixelSize: Theme.px(26)
            font.weight: 400
            font.variableAxes: ({
                "opsz": 72,
                "SOFT": 50,
                "WONK": 0
            })
            color: WalColors.color7
        }

        // ---------- Password pill ----------
        Rectangle {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            width: root.pillW
            height: root.pillH
            radius: height / 2
            color: WalColors.withAlpha(WalColors.color0, 0.55)
            border.width: 1
            border.color: root.failGlow > 0.01 ? WalColors.withAlpha(Theme.bad, 0.6 * root.failGlow + 0.1) : (LockState.buffer.length > 0 ? WalColors.withAlpha(WalColors.color4, 0.55) : Theme.stroke)

            transform: Translate {
                x: root.shakeX * 0.6
            }

            Text {
                anchors.centerIn: parent
                visible: LockState.buffer.length === 0
                text: LockState.checking ? "Checking" : "Enter password"
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLabel
                font.letterSpacing: 0.6
                color: Theme.textFaint
            }

            // Dots: each pops up on its own; while checking a wave runs through
            Row {
                id: dots

                readonly property int maxDots: 18

                anchors.centerIn: parent
                spacing: Theme.px(7)

                Repeater {
                    model: Math.min(LockState.buffer.length, dots.maxDots)

                    delegate: Rectangle {
                        id: dot

                        required property int index
                        property real pop: 0
                        property real wave: 0

                        width: Theme.px(9)
                        height: width
                        radius: width / 2
                        color: WalColors.color7
                        scale: pop * (1 + 0.35 * wave)
                        opacity: 0.55 + 0.45 * pop - 0.3 * wave
                        Component.onCompleted: popIn.start()

                        NumberAnimation {
                            id: popIn

                            target: dot
                            property: "pop"
                            to: 1
                            duration: 260
                            easing.type: Easing.OutBack
                            easing.overshoot: 2.4
                        }

                        SequentialAnimation on wave {
                            running: LockState.checking
                            loops: Animation.Infinite
                            alwaysRunToEnd: true

                            PauseAnimation {
                                duration: dot.index * 45
                            }

                            NumberAnimation {
                                to: 1
                                duration: 220
                                easing.type: Easing.OutQuad
                            }

                            NumberAnimation {
                                to: 0
                                duration: 320
                                easing.type: Easing.InOutQuad
                            }

                            PauseAnimation {
                                duration: Math.max(0, (dots.maxDots - dot.index) * 45)
                            }

                        }

                    }

                }

            }

            // Caps Lock warning on the right in the pill
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Theme.px(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.px(32)
                height: width
                radius: width / 2
                color: WalColors.withAlpha(Theme.warn, 0.16)
                opacity: LockState.capsLock ? 1 : 0
                scale: LockState.capsLock ? 1 : 0.6

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13)
                    color: Theme.warn
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }

                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutBack
                    }

                }

            }

            Behavior on border.color {
                ColorAnimation {
                    duration: 200
                }

            }

        }

        // Status line below the pill
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.pillW + Theme.px(120)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: {
                if (LockState.message !== "")
                    return LockState.message + (LockState.failures > 1 ? "  ·  " + LockState.failures + " attempts" : "");

                if (LockState.capsLock)
                    return "Caps Lock is on";

                if (LockState.checking)
                    return "Authenticating…";

                return LockState.buffer.length > 0 ? "Press Enter to unlock" : "Type to unlock  ·  Esc to dim";
            }
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
            font.weight: Font.Medium
            font.letterSpacing: 0.4
            color: LockState.messageIsError && LockState.message !== "" ? Theme.bad : (LockState.capsLock ? Theme.warn : Theme.textFaint)
        }

    }

}
