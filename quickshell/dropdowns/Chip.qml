import "../services"
import QtQuick

// Small pill for status/source: optional (pulsing) dot, symbol, TEXT in the micro font.
// Simply hang more elements (e.g. a mini equalizer) in as children.
Rectangle {
    id: chip

    property color tone: Theme.accent
    property string glyph: ""
    property string text: ""
    property bool dot: false
    property bool pulse: false
    default property alias extra: extraSlot.data

    width: row.implicitWidth + 18
    height: Theme.chipHeight
    radius: height / 2
    color: Theme.tint(tone, 0.13)
    border.width: 1
    border.color: Theme.tint(tone, 0.3)

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.dot
            width: 6
            height: 6
            radius: height / 2
            color: chip.tone

            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: chip.pulse

                NumberAnimation {
                    to: 1.35
                    duration: 1100
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    to: 1
                    duration: 1100
                    easing.type: Easing.InOutSine
                }

            }

        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.glyph !== ""
            text: chip.glyph
            color: chip.tone
            font.family: Theme.font
            font.pixelSize: Theme.sizeSmall
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.text !== ""
            text: chip.text.toUpperCase()
            color: chip.tone
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.bold: true
            font.letterSpacing: Theme.microSpacing
        }

        Row {
            id: extraSlot

            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
        }

    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.normal
        }

    }

}
