import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: trigger

    // Height of the trigger area (in px). 4 px is usually enough so you
    // do not trigger it by accident while scrolling.
    readonly property real triggerHeight: 4

    WlrLayershell.namespace: "quickshell:volume-trigger"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    color: "transparent"
    implicitWidth: screen.width
    implicitHeight: triggerHeight
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    margins {
        bottom: 0
    }

    // Completely invisible: only a clickable area without any drawing
    MouseArea {
        id: triggerMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        // Toggle: open -> close, closed -> open
        onClicked: VolumeSliderState.toggle()
    }

}
