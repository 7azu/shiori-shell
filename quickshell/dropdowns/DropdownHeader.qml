import "../services"
import QtQuick

// Header every dropdown starts with: symbol + TITLE on the left, any content on the right
// (status chip, timestamp ...). Simply hang the right content in as a child.
// At the far right the gear (opens the settings window at settingsSection, "" = no gear) and the pin.
Item {
    id: header

    property string glyph: ""
    property string title: ""
    // Page of the settings window that belongs to this dropdown (services/SettingsState.sections)
    property string settingsSection: "bar"
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

        anchors.right: gear.visible ? gear.left : pin.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }

    // Gear: to the settings of this dropdown. As unobtrusive as the pin
    Text {
        id: gear

        anchors.right: pin.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: header.settingsSection !== ""
        text: "\u{F0493}"
        color: gearMouse.containsMouse ? Theme.text : Theme.textFaint
        font.family: Theme.font
        font.pixelSize: Theme.sizeLabel
        scale: gearMouse.pressed ? 0.85 : 1

        MouseArea {
            id: gearMouse

            anchors.fill: parent
            anchors.margins: -5
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: SettingsState.openAt(header.settingsSection)
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
