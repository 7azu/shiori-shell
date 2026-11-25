pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick
import Quickshell

// One row of a settings page, drawn from its description (SettingsState.sections): name and one
// sentence on the left, the control on the right. The type picks the control:
//   toggle, choice (segmented control up to four options, chips beyond), number, text, path (a text
//   field plus a button that opens the folder browser, see SettingsView),
//   info (read only), map (list of pairs, full width), link (search result that leads to a page),
//   key (a keybinding: KeyCapture, see services/Keybinds).
// Below the sentence: what is missing (a program that is not installed, a folder that does not exist),
// for a keybinding what it waits for or why the pressed keys were not taken.
Item {
    id: rowItem

    required property var row
    property bool first: false
    readonly property var value: row.key ? SettingsState.read(row.key) : undefined
    readonly property var opts: {
        if (row.type !== "choice")
            return [];

        if (row.options === "screens")
            return Quickshell.screens.map((s) => {
            return {
                "value": s.name,
                "label": s.name
            };
        });

        return row.options;
    }
    readonly property bool isMap: row.type === "map"
    // The control gets a line of its own
    readonly property bool wide: row.type === "choice" && opts.length > 4
    readonly property var missing: SettingsState.missing(row)
    readonly property bool folderMissing: row.type === "path" && !!value && SettingsState.probe.paths[Settings.expand(value)] === false
    readonly property real pad: Theme.px(14)
    // Keybinding: what the row has to say right now ({ text, tone }); null otherwise
    readonly property var keyNote: row.type === "key" && row.key ? Keybinds.noteOf(SettingsState.nameOf(row.key)) : null

    function set(v) {
        SettingsState.apply(row.key, v, row.label);
    }

    width: parent ? parent.width : 0
    height: content.height + Theme.px(22)

    // Lights up after a jump from the search
    Rectangle {
        anchors.fill: parent
        color: Theme.tint(Theme.accent, 0.13)
        opacity: SettingsState.flashKey !== "" && SettingsState.flashKey === rowItem.row.key ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 500
                easing.type: Easing.OutCubic
            }

        }

    }

    Rectangle {
        x: rowItem.pad
        width: parent.width - x
        height: 1
        visible: !rowItem.first
        color: Theme.separator
    }

    MouseArea {
        anchors.fill: parent
        enabled: rowItem.row.type === "link"
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: SettingsState.jump(rowItem.row.target, "")
    }

    Column {
        id: content

        x: rowItem.pad
        y: Theme.px(11)
        width: rowItem.width - 2 * rowItem.pad
        spacing: Theme.px(10)

        Item {
            width: parent.width
            height: rowItem.isMap ? 0 : Math.max(texts.height, rowItem.wide ? 0 : control.height)
            visible: !rowItem.isMap

            Column {
                id: texts

                anchors.verticalCenter: parent.verticalCenter
                width: rowItem.wide ? parent.width : parent.width - control.width - Theme.px(18)
                spacing: Theme.px(3)

                Text {
                    width: parent.width
                    text: rowItem.row.label
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLead
                    font.weight: Font.Medium
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: rowItem.row.desc || ""
                    wrapMode: Text.WordWrap
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                    lineHeight: 1.15
                }

                // What is missing: a program that is not installed, a folder that does not exist
                Text {
                    visible: text !== ""
                    topPadding: Theme.px(2)
                    text: rowItem.missing.length > 0 ? "Needs " + rowItem.missing.join(", ") + ", which is not installed" : (rowItem.folderMissing ? "This folder does not exist" : "")
                    color: Theme.warn
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                }

                Text {
                    width: parent.width
                    visible: rowItem.keyNote !== null
                    topPadding: Theme.px(2)
                    text: rowItem.keyNote ? rowItem.keyNote.text : ""
                    wrapMode: Text.WordWrap
                    color: rowItem.keyNote && rowItem.keyNote.tone === "warn" ? Theme.warn : Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                }

            }

            Loader {
                id: control

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                active: !rowItem.wide && !rowItem.isMap
                sourceComponent: {
                    switch (rowItem.row.type) {
                    case "toggle":
                        return toggleControl;
                    case "choice":
                        return segmentControl;
                    case "number":
                        return numberControl;
                    case "text":
                    case "path":
                        return fieldControl;
                    case "info":
                        return infoControl;
                    case "link":
                        return linkControl;
                    case "key":
                        return keyControl;
                    }
                    return null;
                }
            }

        }

        Loader {
            width: parent.width
            active: rowItem.wide
            visible: active
            sourceComponent: chipsControl
        }

        Loader {
            width: parent.width
            active: rowItem.isMap
            visible: active
            sourceComponent: mapControl
        }

    }

    Component {
        id: toggleControl

        IosSwitch {
            checked: rowItem.value === true
            onToggled: rowItem.set(!checked)
        }

    }

    Component {
        id: segmentControl

        IosSegmented {
            width: Theme.px(88) * Math.max(1, rowItem.opts.length)
            items: rowItem.opts.map((o) => {
                return {
                    "text": o.label
                };
            })
            currentIndex: rowItem.opts.findIndex((o) => {
                return o.value === rowItem.value;
            })
            onActivated: (index) => {
                return rowItem.set(rowItem.opts[index].value);
            }
        }

    }

    Component {
        id: chipsControl

        SettingChips {
            options: rowItem.opts
            value: rowItem.value
            onPicked: (v) => {
                return rowItem.set(v);
            }
        }

    }

    Component {
        id: numberControl

        SettingStepper {
            value: Number(rowItem.value) || 0
            min: rowItem.row.min
            max: rowItem.row.max
            step: rowItem.row.step
            decimals: rowItem.row.decimals || 0
            unit: rowItem.row.unit || ""
            onPicked: (v) => {
                return rowItem.set(v);
            }
        }

    }

    Component {
        id: fieldControl

        Row {
            spacing: Theme.px(6)

            SettingField {
                width: Theme.px(rowItem.row.type === "path" ? 254 : 290)
                text: rowItem.value === undefined || rowItem.value === null ? "" : String(rowItem.value)
                placeholder: {
                    const d = SettingsState.defaultOf(rowItem.row.key);
                    return d ? String(d) : (rowItem.row.type === "path" ? "No folder" : "");
                }
                warn: rowItem.folderMissing
                onCommitted: (t) => {
                    return rowItem.set(t);
                }
            }

            // Folders: pick in the folder browser instead of typing
            Rectangle {
                visible: rowItem.row.type === "path"
                width: Theme.px(30)
                height: Theme.px(30)
                radius: Theme.px(8)
                color: Theme.tint(Theme.text, browseMouse.pressed ? 0.16 : (browseMouse.containsMouse ? 0.11 : 0.06))

                Text {
                    anchors.centerIn: parent
                    text: "\u{F0256}"
                    color: browseMouse.containsMouse ? Theme.text : Theme.textDim
                    font.family: Theme.font
                    font.pixelSize: Theme.sizeLead
                }

                MouseArea {
                    id: browseMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SettingsState.browseKey = rowItem.row.key
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

        }

    }

    Component {
        id: infoControl

        Text {
            text: String(rowItem.value || "")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
        }

    }

    Component {
        id: linkControl

        Text {
            text: "\u{F0142}"
            color: Theme.textFaint
            font.family: Theme.font
            font.pixelSize: Theme.sizeLarge
        }

    }

    Component {
        id: keyControl

        KeyCapture {
            row: rowItem.row
        }

    }

    Component {
        id: mapControl

        MapEditor {
            row: rowItem.row
        }

    }

}
