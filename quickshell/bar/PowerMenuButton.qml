import "../services"
import QtQuick
import Quickshell

// Bar icon for the power menu (windows/PowerMenu.qml). Stands on its own at the far right after the clock
// (MainBar.qml), not in the icon group: it opens no dropdown but the fullscreen menu.
// Own tile with rounded corners (Theme.radiusS), colors like the group pill (BarIconGroup):
// at rest color4 0.12, on hover 0.3.
BarIcon {
    id: root

    // Edge length of the tile = height of the group pill; the click area is exactly as wide
    readonly property int size: 32
    // Hover state (own property, so tests can set it)
    property bool hot: hovered

    contentWidth: size - Math.round(padding * BarState.density)
    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "powermenu", "toggle"])

    Rectangle {
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: Theme.radiusS
        color: WalColors.withAlpha(WalColors.color4, root.hot ? 0.3 : 0.12)
        scale: root.hot ? 1.06 : 1

        Behavior on color {
            ColorAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.08
            }

        }

    }

    BarGlyph {
        anchors.centerIn: parent
        text: "⏻"
        font.pixelSize: 18
        scale: root.hot ? 1.2 : 1
    }

}
