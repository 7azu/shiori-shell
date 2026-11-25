pragma ComponentBehavior: Bound

import "../../common"
import "../../services"
import QtQuick

// Option at the bottom of the Wi-Fi/Bluetooth picker (RadarPicker.options): deliberately without a pill, matching the starry sky.
// On = small sparkle, off = hollow dot.
// - Hover: a fine light ring blooms, a tiny moon circles the indicator.
// - Turning on ("star birth"): the dot contracts, the star fires with a rotation and slight
//   overshoot, a shock wave runs out, sparks fly away, the text lights up briefly.
// - Turning off ("collapse"): the star rotates away and shrinks, a ring contracts inward, the dot comes back.
// Scaling only happens during the animation, at rest all values stand exactly at 1 or 0 (otherwise the
// 1 px rays of the star tremble, see Sparkle.qml). The animations are started in onCheckedChanged instead of via
// Behaviors with a changing curve (they still took the old curve at start).
Item {
    id: chip

    property string label: ""
    property bool checked: false
    readonly property bool hot: chipArea.containsMouse
    // State of the indicator (set by the animations; start values without animation in Component.onCompleted)
    property real starScale: 1
    property real starOpacity: 0
    property real starRot: 0
    property real dotScale: 1
    property real dotOpacity: 1
    // 0..1: shock wave + sparks (turning on), suction ring (turning off); 1 = over
    property real burstT: 1
    property real implodeT: 1
    // Short flash of the text when turning on
    property real flare: 0
    // Fade the hover in/out softly
    property real hoverK: hot ? 1 : 0
    property real moonAngle: 0

    signal toggled()

    function sync() {
        onAnim.stop();
        offAnim.stop();
        starScale = 1;
        starRot = 0;
        starOpacity = checked ? 1 : 0;
        dotScale = 1;
        dotOpacity = checked ? 0 : 1;
        burstT = 1;
        implodeT = 1;
        flare = 0;
    }

    implicitWidth: chipRow.implicitWidth + 8
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1 : 0.4
    Component.onCompleted: sync()
    onCheckedChanged: {
        // Invisible (picker closed) or while loading: without animation
        if (!visible) {
            sync();
            return ;
        }
        if (checked) {
            offAnim.stop();
            onAnim.restart();
        } else {
            onAnim.stop();
            offAnim.restart();
        }
    }

    Row {
        id: chipRow

        x: 4
        anchors.verticalCenter: parent.verticalCenter
        // Room for the horizontal ray of the star
        spacing: 10

        Item {
            id: mark

            width: 12
            height: 12
            anchors.verticalCenter: parent.verticalCenter

            // Hover: light ring that blooms
            Rectangle {
                anchors.centerIn: parent
                width: 8 + 8 * chip.hoverK
                height: width
                radius: width / 2
                color: WalColors.withAlpha(WalColors.vividAccent, 0.07 * chip.hoverK)
                border.width: 1
                border.color: WalColors.withAlpha(WalColors.vividAccent, 0.32 * chip.hoverK)
                visible: chip.hoverK > 0.01
            }

            // Hover: moon on a slightly tilted orbit
            Rectangle {
                readonly property real a: chip.moonAngle
                x: mark.width / 2 + Math.cos(a) * 10 - width / 2
                y: mark.height / 2 + Math.sin(a) * 4 - height / 2
                width: 2
                height: 2
                radius: 1
                color: Qt.lighter(WalColors.color7, 1.1)
                // Fainter behind the indicator (at the top of the orbit): looks spatial
                opacity: chip.hoverK * (Math.sin(a) < 0 ? 0.45 : 0.95)
                visible: chip.hoverK > 0.01
            }

            // Turning on: shock wave
            Rectangle {
                anchors.centerIn: parent
                width: 4 + 24 * chip.burstT
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: WalColors.withAlpha(Qt.lighter(WalColors.vividAccent, 1.15), 0.7 * (1 - chip.burstT))
                visible: chip.burstT < 0.999
            }

            // Turning on: sparks diagonally (between the rays of the star)
            Repeater {
                model: 6

                Rectangle {
                    required property int index
                    readonly property real a: (index * 60 + 30) * Math.PI / 180
                    readonly property real d: 3 + 13 * chip.burstT

                    x: mark.width / 2 + Math.cos(a) * d - width / 2
                    y: mark.height / 2 + Math.sin(a) * d - height / 2
                    width: index % 2 ? 1.5 : 2
                    height: width
                    radius: width / 2
                    color: Qt.lighter(WalColors.color7, 1.1)
                    opacity: Math.min(1, chip.burstT * 6) * (1 - chip.burstT)
                    visible: chip.burstT < 0.999
                }

            }

            // Turning off: ring that contracts inward
            Rectangle {
                anchors.centerIn: parent
                width: 4 + 18 * (1 - chip.implodeT)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: WalColors.withAlpha(WalColors.color7, 0.45 * Math.sin(Math.PI * chip.implodeT))
                visible: chip.implodeT < 0.999
            }

            Sparkle {
                anchors.centerIn: parent
                size: 5
                color: Qt.lighter(WalColors.color7, 1.1)
                glowColor: WalColors.vividAccent
                twinkle: 0.7 + 0.3 * chip.hoverK
                opacity: chip.starOpacity
                scale: chip.starScale
                rotation: chip.starRot
                visible: opacity > 0.01
            }

            Rectangle {
                anchors.centerIn: parent
                width: 5
                height: 5
                radius: 2.5
                color: "transparent"
                border.width: 1
                border.color: WalColors.withAlpha(WalColors.color7, 0.35 + 0.3 * chip.hoverK)
                opacity: chip.dotOpacity
                scale: chip.dotScale
                visible: opacity > 0.01
            }

        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            font.family: Theme.fontUi
            font.pixelSize: 12
            // Base brightness by state + hover, on top the short flash when turning on
            color: Qt.lighter(WalColors.withAlpha(WalColors.color7, Math.min(1, (chip.checked ? 0.88 : 0.42) + 0.25 * chip.hoverK + 0.3 * chip.flare)), 1 + 0.25 * chip.flare)
        }

    }

    MouseArea {
        id: chipArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            chip.toggled();
            PickerManager.requestFocus();
        }
    }

    Behavior on hoverK {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }

    }

    // The moon only circles while it is visible
    NumberAnimation on moonAngle {
        from: 0
        to: 2 * Math.PI
        duration: 1800
        loops: Animation.Infinite
        running: chip.hoverK > 0.01 && chip.visible
    }

    // Star birth
    SequentialAnimation {
        id: onAnim

        // The dot contracts
        ParallelAnimation {
            NumberAnimation { target: chip; property: "dotScale"; to: 0.2; duration: 140; easing.type: Easing.InCubic }
            NumberAnimation { target: chip; property: "dotOpacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
        }

        PropertyAction { target: chip; property: "starScale"; value: 0.15 }
        PropertyAction { target: chip; property: "starRot"; value: -90 }
        PropertyAction { target: chip; property: "burstT"; value: 0 }

        // The star fires, shock wave and sparks run out
        ParallelAnimation {
            NumberAnimation { target: chip; property: "starOpacity"; to: 1; duration: 160 }
            NumberAnimation { target: chip; property: "starScale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            NumberAnimation { target: chip; property: "starRot"; to: 0; duration: 620; easing.type: Easing.OutCubic }
            NumberAnimation { target: chip; property: "burstT"; to: 1; duration: 620; easing.type: Easing.OutCubic }

            SequentialAnimation {
                NumberAnimation { target: chip; property: "flare"; to: 1; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { target: chip; property: "flare"; to: 0; duration: 520; easing.type: Easing.OutCubic }
            }

        }

        // Exactly to the rest values (no leftover fraction -> no trembling)
        PropertyAction { target: chip; property: "starScale"; value: 1 }
        PropertyAction { target: chip; property: "starRot"; value: 0 }
        PropertyAction { target: chip; property: "dotScale"; value: 1 }
    }

    // Kollaps
    SequentialAnimation {
        id: offAnim

        PropertyAction { target: chip; property: "implodeT"; value: 0 }
        PropertyAction { target: chip; property: "flare"; value: 0 }

        ParallelAnimation {
            NumberAnimation { target: chip; property: "starScale"; to: 0.1; duration: 300; easing.type: Easing.InBack; easing.overshoot: 1.6 }
            NumberAnimation { target: chip; property: "starRot"; to: 120; duration: 300; easing.type: Easing.InCubic }
            NumberAnimation { target: chip; property: "starOpacity"; to: 0; duration: 300; easing.type: Easing.InQuad }
            NumberAnimation { target: chip; property: "implodeT"; to: 1; duration: 420; easing.type: Easing.InOutCubic }
        }

        PropertyAction { target: chip; property: "dotScale"; value: 0 }

        ParallelAnimation {
            NumberAnimation { target: chip; property: "dotOpacity"; to: 1; duration: 200 }
            NumberAnimation { target: chip; property: "dotScale"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        }

        PropertyAction { target: chip; property: "starScale"; value: 1 }
        PropertyAction { target: chip; property: "starRot"; value: 0 }
        PropertyAction { target: chip; property: "dotScale"; value: 1 }
    }

}
