import "../services"
import QtQuick
import Quickshell

// Drawer button for the monitor choice.
// Left click = the bar morphs into the monitor panel (clicked()), right-click = directly the next monitor.
// Only appears when more than one monitor is connected.
Item {
    id: slot

    signal clicked()

    property real reveal: 1
    readonly property bool hovered: slotHover.hovered
    readonly property color ink: hovered ? WalColors.color4 : WalColors.withAlpha(WalColors.color2, 0.85)

    visible: Quickshell.screens.length > 1
    width: Math.round(16 + 16 * BarState.density)
    height: 32
    opacity: reveal
    scale: 0.6 + 0.4 * reveal

    Item {
        id: icon

        property real kick: 0

        anchors.centerIn: parent
        width: 18
        height: 18
        scale: (slot.hovered ? 1.12 : 1) * (1 - 0.12 * kick)

        // Monitor-Rahmen
        Rectangle {
            x: 1
            y: 2
            width: 16
            height: 11
            radius: 3
            color: "transparent"
            antialiasing: true
            border.width: 1.6
            border.color: slot.ink
        }

        // Standfuss
        Rectangle {
            x: 6
            y: 14.6
            width: 6
            height: 1.6
            radius: 0.8
            color: slot.ink
        }

        // Mini bar in the monitor (gets shorter on hover = "ready to move")
        Rectangle {
            x: 3.6
            y: 4.6
            height: 2
            radius: 1
            width: slot.hovered ? 6 : 10.8
            color: slot.ink

            Behavior on width {
                NumberAnimation {
                    duration: 200
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

    SequentialAnimation {
        id: pulse

        NumberAnimation {
            target: icon
            property: "kick"
            to: 1
            duration: 110
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: icon
            property: "kick"
            to: 0
            duration: 240
            easing.type: Easing.OutBack
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
            pulse.restart();
            if (mouse.button === Qt.RightButton)
                MachineConfig.moveBar(Quickshell.screens, 1);
            else
                slot.clicked();
        }
    }
}
