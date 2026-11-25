pragma ComponentBehavior: Bound

import "../services"
import QtQuick

// Editor for a setting that is a list of name -> text pairs (own app icons, extra language folders):
// one line per pair, a last line to add one. Every change writes the whole list (SettingsState.apply).
// row = the row from SettingsState.sections: key, label, keyLabel, valueLabel, previews (icon in front).
Column {
    id: editor

    required property var row
    readonly property var map: SettingsState.read(row.key) || ({
    })
    readonly property var keys: Object.keys(map)
    readonly property real keyW: Theme.px(190)
    readonly property real lead: row.previews ? Theme.px(34) : 0

    function save(next) {
        // An empty list is removed from the file
        SettingsState.apply(row.key, Object.keys(next).length > 0 ? next : undefined, row.label);
    }

    // Keeps the order of the lines
    function rename(oldKey, newKey) {
        if (newKey === "" || newKey === oldKey || map[newKey] !== undefined)
            return ;

        const next = {
        };
        for (const k of keys) next[k === oldKey ? newKey : k] = map[k]
        save(next);
    }

    function setValue(key, value) {
        const next = Object.assign({
        }, map);
        next[key] = value;
        save(next);
    }

    function remove(key) {
        const next = Object.assign({
        }, map);
        delete next[key];
        save(next);
    }

    function addPair() {
        const k = newKey.input.text.trim();
        const v = newValue.input.text.trim();
        if (k === "" || v === "" || map[k] !== undefined)
            return ;

        setValue(k, v);
        newKey.input.text = "";
        newValue.input.text = "";
    }

    spacing: Theme.px(6)

    // Column titles
    Item {
        width: editor.width
        height: Theme.px(14)

        Text {
            x: editor.lead
            text: (editor.row.keyLabel || "Name").toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.bold: true
            font.letterSpacing: Theme.microSpacing
        }

        Text {
            x: editor.lead + editor.keyW + Theme.px(8)
            text: (editor.row.valueLabel || "Value").toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.bold: true
            font.letterSpacing: Theme.microSpacing
        }

    }

    Repeater {
        model: editor.keys

        Item {
            id: line

            required property string modelData

            width: editor.width
            height: Theme.px(30)

            Image {
                visible: editor.row.previews === true
                width: Theme.px(24)
                height: Theme.px(24)
                anchors.verticalCenter: parent.verticalCenter
                source: editor.row.previews ? Settings.icon(line.modelData) : ""
                sourceSize: Qt.size(96, 96)
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            SettingField {
                x: editor.lead
                width: editor.keyW
                text: line.modelData
                onCommitted: (t) => {
                    return editor.rename(line.modelData, t);
                }
            }

            SettingField {
                x: editor.lead + editor.keyW + Theme.px(8)
                width: line.width - x - Theme.px(34)
                text: String(editor.map[line.modelData] || "")
                onCommitted: (t) => {
                    if (t !== "")
                        editor.setValue(line.modelData, t);

                }
            }

            // Remove this pair
            Text {
                anchors.right: parent.right
                anchors.rightMargin: Theme.px(4)
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F0156}"
                color: removeMouse.containsMouse ? Theme.bad : Theme.textFaint
                font.family: Theme.font
                font.pixelSize: Theme.sizeLead

                MouseArea {
                    id: removeMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.remove(line.modelData)
                }

            }

        }

    }

    // New pair
    Item {
        width: editor.width
        height: Theme.px(30)

        SettingField {
            id: newKey

            x: editor.lead
            width: editor.keyW
            placeholder: "New " + (editor.row.keyLabel || "name").toLowerCase()
            input.onAccepted: newValue.input.forceActiveFocus()
        }

        SettingField {
            id: newValue

            x: editor.lead + editor.keyW + Theme.px(8)
            width: parent.width - x - Theme.px(34)
            placeholder: (editor.row.valueLabel || "Value")
            input.onAccepted: editor.addPair()
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.px(4)
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0415}"
            color: addMouse.containsMouse ? Theme.accent : Theme.textFaint
            font.family: Theme.font
            font.pixelSize: Theme.sizeLead

            MouseArea {
                id: addMouse

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: editor.addPair()
            }

        }

    }

}
