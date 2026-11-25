import "../services"
import QtQuick

// Header every dropdown starts with: symbol + TITLE on the left, any content on the right
// (status chip, timestamp ...). Simply hang the right content in as a child.
Item {
    id: header

    property string glyph: ""
    property string title: ""
    default property alias trailing: trailingSlot.data

    width: parent ? parent.width : 0
    height: Theme.chipHeight

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: header.glyph
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: Theme.sizeBody + 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: header.title.toUpperCase()
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
            font.bold: true
            font.letterSpacing: Theme.microSpacing
        }

    }

    Row {
        id: trailingSlot

        anchors.right: pin.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }

    // Pin: pin/unpin the dropdown (stays open even when the mouse leaves). Unobtrusive
    // until you need it: faint, brighter on hover, in the accent color when pinned.
    Text {
        id: pin

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: DropdownState.pinned ? "\u{F0403}" : "\u{F0931}"
        color: DropdownState.pinned ? Theme.accent : (pinMouse.containsMouse ? Theme.text : Theme.textFaint)
        font.family: Theme.font
        font.pixelSize: Theme.sizeLabel
        scale: pinMouse.pressed ? 0.85 : 1

        MouseArea {
            id: pinMouse

            anchors.fill: parent
            anchors.margins: -5
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: DropdownState.togglePin()
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

}
