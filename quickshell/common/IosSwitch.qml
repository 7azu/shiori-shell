import "../services"
import QtQuick

// Switch like on iOS: the track takes on color, the bright knob glides to the right.
Rectangle {
    id: sw

    property bool checked: false

    signal toggled()

    width: Theme.px(42)
    height: Theme.px(25)
    radius: height / 2
    color: checked ? Theme.accent : Theme.tint(Theme.text, 0.16)

    Rectangle {
        x: sw.checked ? sw.width - width - 2 : 2
        anchors.verticalCenter: parent.verticalCenter
        width: sw.height - 4
        height: width
        radius: width / 2
        color: Theme.knob

        Behavior on x {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }

        }

    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
        }

    }

}
