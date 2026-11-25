import "../services"
import QtQuick

// Button in card style (glyph + text) for dropdowns and the language video player. active = tinted in its color
// (switch on / main action). Not to be confused with pickers/parts/PillButton (filled text pill).
Rectangle {
    id: btn

    property string glyph: ""
    property string text: ""
    property bool active: false
    property color tone: Theme.accent
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    height: Theme.controlHeight
    radius: height / 2
    color: active ? Theme.tint(tone, hovered ? 0.3 : 0.2) : (hovered ? Theme.cardHover : Theme.card)
    border.width: 1
    border.color: active ? Theme.tint(tone, 0.45) : Theme.stroke
    scale: mouse.pressed ? 0.95 : 1

    Row {
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.glyph !== ""
            text: btn.glyph
            color: btn.active ? btn.tone : (btn.hovered ? Theme.text : Theme.textDim)
            font.family: Theme.font
            font.pixelSize: Theme.sizeBody + 2
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.text !== ""
            text: btn.text
            color: btn.active ? btn.tone : (btn.hovered ? Theme.text : Theme.textDim)
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
            font.bold: true
        }

    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.fast
        }

    }

    Behavior on scale {
        NumberAnimation {
            duration: 120
        }

    }

}
