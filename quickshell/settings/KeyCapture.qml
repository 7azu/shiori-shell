pragma ComponentBehavior: Bound

import "../services"
import QtQuick

// Control of a shortcut row (row type "key", services/Keybinds): the keys as caps, like in the shortcuts
// panel. A click starts capturing: the caps show the modifiers held so far and a pulsing cap waits for
// the key (SettingsView sends the key presses to Keybinds meanwhile). A shortcut that another binding
// has turns into a question: the new keys next to Replace and Cancel.
// Caps with an accent border differ from the default; the arrow next to them brings the default back.
// Rows with fixed: true (groups, special keys) show their keys without frames and take no click.
Item {
    id: cap

    required property var row
    readonly property bool fixed: row.fixed === true
    readonly property string bindId: !fixed && row.key ? SettingsState.nameOf(row.key) : ""
    readonly property string keys: fixed ? (row.keys || "") : Keybinds.keysOf(bindId)
    readonly property bool capturing: bindId !== "" && Keybinds.captureId === bindId
    readonly property bool asking: bindId !== "" && Keybinds.pending !== null && Keybinds.pending.id === bindId
    readonly property bool changed: bindId !== "" && Keybinds.defaultOf(bindId) !== undefined && keys !== Keybinds.defaultOf(bindId)
    readonly property bool hovered: hover.containsMouse || resetMouse.containsMouse
    readonly property var labels: {
        if (capturing)
            return Keybinds.held.map((m) => {
            return Keybinds.modNames[m];
        });

        return Keybinds.caps(asking ? Keybinds.pending.keys : keys);
    }
    readonly property real capH: Theme.px(26)

    implicitWidth: line.implicitWidth
    implicitHeight: Theme.px(30)
    width: implicitWidth
    height: implicitHeight

    // Click anywhere on the caps
    MouseArea {
        id: hover

        anchors.fill: line
        anchors.margins: -Theme.px(4)
        enabled: !cap.fixed && !cap.asking
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (cap.capturing)
                Keybinds.cancel();
            else
                Keybinds.startCapture(cap.bindId);
        }
    }

    Row {
        id: line

        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(8)

        // Back to the default; only there when the row differs and the mouse is near
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(22)
            height: cap.capH
            visible: cap.changed && !cap.capturing && !cap.asking
            opacity: cap.hovered ? 1 : 0

            Text {
                anchors.centerIn: parent
                text: "\u{F099B}"
                color: resetMouse.containsMouse ? Theme.text : Theme.textDim
                font.family: Theme.font
                font.pixelSize: Theme.sizeLead
            }

            MouseArea {
                id: resetMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsState.apply(cap.row.key, Keybinds.defaultOf(cap.bindId), cap.row.label)
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(4)

            Repeater {
                model: cap.labels

                Rectangle {
                    id: key

                    required property string modelData

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(cap.capH, keyText.implicitWidth + Theme.px(16))
                    height: cap.capH
                    radius: Theme.radiusXS
                    color: cap.fixed ? "transparent" : (cap.hovered && !cap.asking ? Theme.glassHover : Theme.glass)
                    border.width: cap.fixed ? 0 : 1
                    border.color: cap.asking ? Theme.tint(Theme.warn, 0.6) : (cap.changed && !cap.capturing ? Theme.tint(Theme.accent, 0.55) : Theme.stroke)

                    Text {
                        id: keyText

                        anchors.centerIn: parent
                        text: key.modelData
                        textFormat: Text.PlainText
                        color: cap.fixed ? Theme.textDim : Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                        font.weight: Font.Medium
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

            }

            // Capturing: the cap that waits for the key. Not bound: says so.
            Rectangle {
                id: waiting

                anchors.verticalCenter: parent.verticalCenter
                visible: cap.capturing || (cap.labels.length === 0 && !cap.asking)
                width: waitText.implicitWidth + Theme.px(18)
                height: cap.capH
                radius: Theme.radiusXS
                color: cap.capturing ? Theme.tint(Theme.accent, 0.14) : (cap.hovered ? Theme.glassHover : "transparent")
                border.width: 1
                border.color: cap.capturing ? Theme.accent : Theme.stroke

                Text {
                    id: waitText

                    anchors.centerIn: parent
                    text: cap.capturing ? "PRESS KEYS" : "NOT SET"
                    color: cap.capturing ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.bold: true
                    font.letterSpacing: Theme.microSpacing
                }

                // Waiting breathes; only the brightness moves
                SequentialAnimation on opacity {
                    running: cap.capturing
                    loops: Animation.Infinite
                    alwaysRunToEnd: true

                    NumberAnimation {
                        to: 0.55
                        duration: 700
                        easing.type: Easing.InOutSine
                    }

                    NumberAnimation {
                        to: 1
                        duration: 700
                        easing.type: Easing.InOutSine
                    }

                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

        }

        // The keys are taken: replace the other binding or leave it
        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: cap.asking
            spacing: Theme.px(6)

            Repeater {
                model: cap.asking ? ["Replace", "Cancel"] : []

                Rectangle {
                    id: choice

                    required property string modelData
                    required property int index
                    readonly property bool main: index === 0

                    width: choiceText.implicitWidth + Theme.px(24)
                    height: cap.capH
                    radius: height / 2
                    color: main ? Theme.tint(Theme.accent, choiceMouse.containsMouse ? 0.3 : 0.2) : Theme.tint(Theme.text, choiceMouse.containsMouse ? 0.12 : 0.06)

                    Text {
                        id: choiceText

                        anchors.centerIn: parent
                        text: choice.modelData
                        color: choice.main ? Theme.accent : Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: choiceMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (choice.main)
                                Keybinds.replace();
                            else
                                Keybinds.cancel();
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

            }

        }

    }

}
