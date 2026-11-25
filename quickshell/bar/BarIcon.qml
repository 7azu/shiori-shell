import "../services"
import QtQuick

// Base of the icons on the right of the bar (audio, stats, VPN, Claude, battery, power): a tile at
// bar height with mouse state. The hover marker is not drawn by the icon but by the shared
// gliding pill of the icon group (BarIconGroup); the icon itself only grows (BarGlyph or hovered).
// Exception: the power icon stands outside the group and draws its tile itself.
// Hang the content in as a child and report its width via contentWidth.
Item {
    id: root

    // Width of the content (glyph, maybe with a number next to it)
    property real contentWidth: 0
    // Padding left + right together at a monitor width of 2560 px (BarState.density makes it tighter)
    property real padding: 16
    // This much wider than the tile the MainBar's hover pill becomes (icons with a number next to them)
    property real pillExtra: 0
    property real itemGap: 0
    property real reveal: 1
    readonly property real sideGap: itemGap * reveal / 2
    readonly property real buttonWidth: (contentWidth + Math.round(padding * BarState.density)) * reveal
    property alias acceptedButtons: mouseArea.acceptedButtons
    readonly property bool hovered: mouseArea.containsMouse

    signal clicked(var mouse)

    // Fade in the spacing too, so the neighbor icons move up without a jump.
    width: buttonWidth + 2 * sideGap
    height: parent ? parent.height : 40
    visible: reveal > 0
    opacity: reveal
    scale: 0.6 + 0.4 * reveal

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        anchors.leftMargin: root.sideGap
        anchors.rightMargin: root.sideGap
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            return root.clicked(mouse);
        }
    }

}
