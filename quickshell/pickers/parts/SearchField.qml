import "../../common"
import "../../services"
import QtQuick

// Search field of the pickers (task manager, clipboard, trash, language): pill with magnifier, placeholder and
// clear button. FocusScope, so searchInput.forceActiveFocus()/activeFocus work in the picker as with a TextInput.
// Keys go to the picker via keyPressed(event) (it sets event.accepted), Enter also as accepted().
FocusScope {
    id: field

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    // Shorten long hints in the placeholder
    property bool placeholderElide: false
    // Take the focus on creation
    property bool focusOnStart: true

    signal keyPressed(var event)
    signal accepted()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: WalColors.withAlpha(WalColors.color7, input.activeFocus ? 0.09 : 0.06)
        border.width: 1.5
        border.color: input.activeFocus ? WalColors.withAlpha(WalColors.color4, 0.55) : WalColors.withAlpha(WalColors.color4, 0)

        Text {
            id: lens

            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            // Center the visible glyph, not its text line: "⌕" sits 2.5 px below the middle in the line of the
            // fallback font (measured). Computed from the real shape, not as a fixed
            // number, so it also fits with another fallback font (another machine).
            anchors.verticalCenterOffset: Math.round(height / 2 - (baselineOffset + lensMetrics.tightBoundingRect.y + lensMetrics.tightBoundingRect.height / 2))
            text: "⌕"
            font.pixelSize: 20

            TextMetrics {
                id: lensMetrics

                font: lens.font
                text: lens.text
            }
            color: input.activeFocus ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.45)

            Behavior on color {
                ColorAnimation {
                    duration: 180
                }

            }

        }

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: 48
            anchors.rightMargin: 44
            focus: true
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.font
            font.pixelSize: 14
            color: WalColors.color7
            selectionColor: WalColors.withAlpha(WalColors.color4, 0.4)
            clip: true
            Component.onCompleted: {
                if (field.focusOnStart)
                    forceActiveFocus();

            }
            Keys.onPressed: (event) => {
                return field.keyPressed(event);
            }
            onAccepted: field.accepted()
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 48
            anchors.right: field.placeholderElide ? parent.right : undefined
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            elide: field.placeholderElide ? Text.ElideRight : Text.ElideNone
            text: field.placeholder
            font.family: Theme.font
            font.pixelSize: 14
            color: WalColors.withAlpha(WalColors.color7, 0.3)
            opacity: input.text === "" ? 1 : 0

            Behavior on opacity {
                Smooth {
                    duration: 160
                }

            }

        }

        // Clear button
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: height / 2
            color: WalColors.withAlpha(WalColors.color7, clearArea.containsMouse ? 0.28 : 0.14)
            opacity: input.text !== "" ? 1 : 0
            scale: input.text !== "" ? 1 : 0.5
            visible: opacity > 0.01

            Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 9
                color: WalColors.color7
            }

            MouseArea {
                id: clearArea

                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    input.text = "";
                    input.forceActiveFocus();
                }
            }

            Behavior on opacity {
                Smooth {
                    duration: 160
                }

            }

            Behavior on scale {
                Springy {
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 120
                }

            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 180
            }

        }

        Behavior on border.color {
            ColorAnimation {
                duration: 180
            }

        }

    }

}
