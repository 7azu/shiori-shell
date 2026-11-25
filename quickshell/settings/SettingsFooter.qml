pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick

// Bottom line of the settings window. There is no Save button: every change is written at once.
// Left the state, with the shell's sparkle lighting up on each save; right Undo (the last change of
// this session, Ctrl+Z) and Reset page (rows of the open page back to their defaults).
Item {
    id: footer

    readonly property var current: SettingsState.sectionById(SettingsState.section)
    readonly property var last: SettingsState.undoStack.length > 0 ? SettingsState.undoStack[SettingsState.undoStack.length - 1] : null
    // The file behind the open page
    readonly property string file: SettingsState.query === "" && current !== null ? SettingsState.fileOf(current) : ""
    readonly property bool canReset: SettingsState.query === "" && current !== null && SettingsState.changedRows(current).length > 0
    // 1 right after a save, falls back to 0
    property real pulse: 0

    height: Theme.px(52)

    component FootButton: Rectangle {
        id: btn

        property string text: ""
        property string glyph: ""
        property bool possible: true

        signal clicked()

        width: Math.min(row.implicitWidth + Theme.px(26), Theme.px(260))
        height: Theme.px(30)
        radius: height / 2
        color: Theme.tint(Theme.text, mouse.pressed && possible ? 0.15 : (mouse.containsMouse && possible ? 0.1 : 0.06))
        opacity: possible ? 1 : 0.35

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Theme.px(7)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.glyph
                color: Theme.textDim
                font.family: Theme.font
                font.pixelSize: Theme.sizeBody
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Theme.px(200))
                text: btn.text
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeBody
            }

        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.possible ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.possible)
                    btn.clicked();

            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.separator
    }

    Connections {
        function onSavesChanged() {
            pulseAnim.restart();
        }

        target: SettingsState
    }

    NumberAnimation {
        id: pulseAnim

        target: footer
        property: "pulse"
        from: 1
        to: 0
        duration: 1400
        easing.type: Easing.OutCubic
    }

    Row {
        x: Theme.px(40)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(8)

        Item {
            width: Theme.px(16)
            height: Theme.px(16)
            anchors.verticalCenter: parent.verticalCenter

            // Only the brightness changes (see Sparkle)
            Sparkle {
                anchors.centerIn: parent
                size: 3
                color: Theme.text
                glowColor: Theme.accent
                twinkle: 0.25 + 0.75 * footer.pulse
                opacity: SettingsState.saves > 0 ? 1 : 0.5
            }

        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: SettingsState.saves > 0 ? "Saved · live on your desktop" : "Changes apply right away"
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
        }

        // Where it is saved: a click opens the file
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: footer.file !== ""
            text: "·   " + footer.file.substring(footer.file.lastIndexOf("/") + 1) + "  \u{F03CC}"
            color: fileMouse.containsMouse ? Theme.text : Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody

            MouseArea {
                id: fileMouse

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsState.openPath(footer.file)
            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(26)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(8)

        FootButton {
            glyph: "\u{F099B}"
            text: "Reset page"
            possible: footer.canReset
            onClicked: SettingsState.resetSection(footer.current)
        }

        FootButton {
            glyph: "\u{F054C}"
            text: footer.last ? "Undo · " + footer.last.label : "Undo"
            possible: footer.last !== null
            onClicked: SettingsState.undo()
        }

    }

}
