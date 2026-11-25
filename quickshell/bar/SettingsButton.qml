import "../services"
import QtQuick

// Bar icon for the settings window (settings/SettingsWindow.qml, state services/SettingsState): the gear
// on the left of the bar, between the logo (with its drawer) and the shortcuts button (MainBar.qml).
// It opens no dropdown but a window, so it is not part of an icon group and draws its own tile, the same
// as the shortcuts button next to it. Lit while the window is open.
BarIcon {
    id: root

    // Edge length of the tile; the click area is exactly as wide
    readonly property int size: Theme.px(32)
    readonly property bool active: SettingsState.open

    objectName: "settingsBarButton"
    contentWidth: size - Math.round(padding * BarState.density)
    Accessible.role: Accessible.Button
    Accessible.name: "Settings"
    Accessible.onPressAction: SettingsState.toggle()
    onClicked: SettingsState.toggle()

    Rectangle {
        anchors.centerIn: parent
        width: root.buttonWidth
        height: root.size
        radius: Theme.radiusS
        color: root.active || root.hovered ? Theme.accentSoft : Theme.card
        border.color: Theme.stroke

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    BarGlyph {
        anchors.centerIn: parent
        text: "\u{F0493}"
        font.pixelSize: Theme.px(16)
        hot: root.hovered
        // A quarter turn when the window opens or closes
        rotation: root.active ? 90 : 0

        Behavior on rotation {
            NumberAnimation {
                duration: Appearance.anim.durations.slow
                easing.type: Easing.OutCubic
            }

        }

    }

}
