import QtQuick
import "../services"

// Calm status change: a small pulsing dot, then the real connection status.
Item {
    id: indicator

    property bool active: false
    property bool busy: false
    property bool pulseEnabled: true
    property real pulse: 0
    property real busyK: busy ? 1 : 0
    property real activeK: active ? 1 : 0

    width: 20
    height: 20
    opacity: busy || active ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 180 } }
    Behavior on busyK { NumberAnimation { duration: 180 } }
    Behavior on activeK { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    SequentialAnimation on pulse {
        running: indicator.busy && indicator.visible && indicator.pulseEnabled
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 650; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 12
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: WalColors.color4
        scale: 1 + indicator.pulse * 0.25
        opacity: indicator.pulseEnabled ? indicator.busyK * (0.45 - 0.2 * indicator.pulse) : 0
    }

    Rectangle {
        anchors.centerIn: parent
        width: 4
        height: width
        radius: width / 2
        color: WalColors.color4
        opacity: indicator.pulseEnabled ? indicator.busyK * (0.5 + 0.5 * indicator.pulse) : 0
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.good
        opacity: indicator.activeK * (1 - indicator.busyK)
        scale: 0.85 + 0.15 * indicator.activeK

        Text {
            anchors.centerIn: parent
            text: "󰄬"
            font.family: Theme.font
            font.pixelSize: 12
            color: WalColors.color0
        }
    }
}
