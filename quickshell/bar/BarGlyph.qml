import "../services"
import QtQuick

// Nerd Font symbol of a bar icon: bar color, grows on hover (hot) like all icons of the bar.
Text {
    property bool hot: false

    color: WalColors.color2
    font.family: Theme.font
    font.pixelSize: 18
    scale: hot ? 1.3 : 1

    Behavior on scale {
        NumberAnimation {
            duration: Appearance.anim.durations.fast
            easing.type: Easing.OutCubic
        }

    }

}
