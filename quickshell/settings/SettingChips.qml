pragma ComponentBehavior: Bound

import "../services"
import QtQuick

// Choice among more options than fit a segmented control (settings window): chips that wrap.
// options = [{ value, label }]
Flow {
    id: chips

    property var options: []
    property var value

    signal picked(var value)

    spacing: Theme.px(6)

    Repeater {
        model: chips.options

        Rectangle {
            id: chip

            required property var modelData
            readonly property bool chosen: modelData.value === chips.value

            width: label.implicitWidth + Theme.px(24)
            height: Theme.px(28)
            radius: height / 2
            color: chosen ? Theme.tint(Theme.accent, 0.2) : Theme.tint(Theme.text, mouse.containsMouse ? 0.1 : 0.06)
            border.width: 1
            border.color: chosen ? Theme.tint(Theme.accent, 0.5) : "transparent"

            Text {
                id: label

                anchors.centerIn: parent
                text: chip.modelData.label
                color: chip.chosen ? Theme.accent : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeBody
                font.weight: chip.chosen ? Font.DemiBold : Font.Normal
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chips.picked(chip.modelData.value)
            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

    }

}
