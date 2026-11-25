import "../services"
import QtQuick

// Seal of a settings page: one kanji in a small stamp (like a hanko on a document). The rail shows one
// per page; active = the page that is open.
Item {
    id: seal

    property string kanji: ""
    property bool active: false
    property real size: Theme.px(22)

    width: size
    height: size

    Rectangle {
        anchors.fill: parent
        radius: seal.size * 0.28
        color: seal.active ? Theme.tint(Theme.accent, 0.16) : "transparent"
        border.width: 1
        border.color: seal.active ? Theme.tint(Theme.accent, 0.55) : Theme.tint(Theme.text, 0.13)

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.normal
            }

        }

        Behavior on border.color {
            ColorAnimation {
                duration: Appearance.anim.durations.normal
            }

        }

    }

    Text {
        anchors.centerIn: parent
        text: seal.kanji
        color: seal.active ? Theme.accent : Theme.textFaint
        font.family: Theme.fontDisplay
        font.pixelSize: Math.round(seal.size * 0.56)

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.normal
            }

        }

    }

}
