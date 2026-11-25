import "../common"
import "../services"
import QtQuick
import QtQuick.Shapes

// Round plus/X next to the search bar of music, VPN and wallpaper: opens the side view
// (song download, .conf import, wallhaven) and closes it again. ONE building block for all three,
// so look, hover and animation are exactly the same (the model was the VPN button).
// Deliberately smaller/subtler than the search bar (40 instead of 56): a side feature, should not compete.
Rectangle {
    id: btn

    // 0 = plus (closed), 1 = X (side view open); animated softly by the picker (browseT / addT)
    property real progress: 0
    // Something is running (import/download): a ring spins instead of plus/X
    property bool busy: false
    // Block clicks (e.g. during the VPN import)
    property bool locked: false
    // Number at the top right (marked files / running downloads); 0 = none
    property int count: 0
    // Green dot: finished in the background (e.g. a song download with the view closed)
    property bool doneDot: false
    readonly property bool open: progress > 0.5
    // Last number > 0: stays while the badge fades out (instead of briefly showing "0")
    property int lastCount: count
    readonly property bool hot: mouse.containsMouse

    signal clicked()

    onCountChanged: {
        if (count > 0)
            lastCount = count;

    }

    width: 40
    height: 40
    radius: width / 2
    color: hot ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.06)
    border.width: 1
    border.color: hot || open ? WalColors.withAlpha(WalColors.color4, 0.6) : WalColors.withAlpha(WalColors.color2, 0.15)
    scale: mouse.pressed ? 0.88 : (hot && !busy ? 1.1 : 1)

    // Soft halo on hover
    Rectangle {
        anchors.centerIn: parent
        width: parent.width + 12
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: WalColors.withAlpha(WalColors.color4, 0.35)
        opacity: btn.hot && !btn.busy ? 1 : 0
        scale: opacity > 0.5 ? 1 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
            }

        }

    }

    // Plus and X rotate into each other instead of switching hard
    Item {
        anchors.fill: parent
        opacity: btn.busy ? 0 : 1
        scale: btn.busy ? 0.6 : 1

        Text {
            anchors.centerIn: parent
            text: "󰐕"
            font.family: Theme.font
            font.pixelSize: 17
            color: btn.hot ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.5)
            opacity: 1 - btn.progress
            rotation: btn.progress * 135
            scale: 1 - 0.4 * btn.progress

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        Text {
            anchors.centerIn: parent
            text: "󰅖"
            font.family: Theme.font
            font.pixelSize: 17
            color: WalColors.color4
            opacity: btn.progress
            rotation: (btn.progress - 1) * 135
            scale: 0.6 + 0.4 * btn.progress
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }

        }

    }

    // During import/download a ring spins. Deliberately drawn instead of a font symbol:
    // a text item is not exactly centered on the symbol because of ascenders/descenders and wobbles when rotating.
    Item {
        id: spinner

        readonly property real size: 16
        readonly property real thick: 2

        anchors.centerIn: parent
        width: size
        height: size
        opacity: btn.busy ? 1 : 0
        scale: btn.busy ? 1 : 0.6
        visible: opacity > 0.01

        // Faint track as a full circle, on it the rotating arc (center = pivot)
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: spinner.thick
            border.color: WalColors.withAlpha(WalColors.color4, 0.18)
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: WalColors.color4
                strokeWidth: spinner.thick
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: spinner.size / 2
                    centerY: spinner.size / 2
                    radiusX: (spinner.size - spinner.thick) / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 100
                }

            }

        }

        RotationAnimator on rotation {
            running: btn.busy
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }

        }

    }

    // Done (in the background): a sparkle fires at the top right (visual language: star = done; before a
    // green dot). Only without a number, otherwise they share the place; disappears softly
    StarBurst {
        x: parent.width - width / 2 - 6
        y: -height / 2 + 6
        size: 4.5
        color: WalColors.color2
        glowColor: WalColors.color2
        fadeOut: true
        active: btn.doneDot && !badge.shown
    }

    // Number: pops in and hops briefly on every change
    Rectangle {
        id: badge

        readonly property bool shown: btn.count > 0

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: -4
        width: Math.max(18, badgeText.implicitWidth + 8)
        height: 18
        radius: height / 2
        color: WalColors.color7
        border.width: 2
        border.color: WalColors.color0
        scale: shown ? badgeBump.value : 0
        visible: scale > 0.01

        Text {
            id: badgeText

            anchors.centerIn: parent
            text: btn.lastCount
            font.family: Theme.font
            font.pixelSize: 9
            font.bold: true
            color: WalColors.color0
        }

        QtObject {
            id: badgeBump

            property real value: 1
        }

        SequentialAnimation {
            id: bumpAnim

            NumberAnimation {
                target: badgeBump
                property: "value"
                to: 1.3
                duration: 90
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                target: badgeBump
                property: "value"
                to: 1
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }

        }

        Connections {
            function onCountChanged() {
                if (badge.shown)
                    bumpAnim.restart();

            }

            target: btn
        }

        Behavior on scale {
            enabled: !bumpAnim.running

            NumberAnimation {
                duration: Appearance.anim.durations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
            }

        }

    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: !btn.locked
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    Behavior on scale {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutBack
            easing.overshoot: 2
        }

    }

    Behavior on color {
        ColorAnimation {
            duration: 180
        }

    }

    Behavior on border.color {
        ColorAnimation {
            duration: 180
        }

    }

}
