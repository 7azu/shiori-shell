pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick

// Page "Sync" of the settings window: the entries of the sync dropdown ("sync" in settings.json,
// see scripts/shiori_sync.py). A click opens an entry: name and, by type, the Git folder or the rclone
// remote with its folder pairs, plus the SSH key. Entries of the type command keep their commands in the
// file (lists of arguments are not something to type into one field); name and key can be set here.
// Every change writes the whole list (SettingsState.apply), so Undo takes it back as one step.
Column {
    id: page

    readonly property var entries: Settings.data.sync || []
    // Open entry / entry whose removal waits for the second click
    property int openIndex: -1
    property int confirmIndex: -1

    function typeOf(e) {
        return e.type || "command";
    }

    function save(list, label) {
        SettingsState.apply("settings:sync", list.length > 0 ? list : undefined, label);
    }

    function patch(index, key, value) {
        const list = entries.map((e) => {
            return Object.assign({
            }, e);
        });
        if (value === "" || value === undefined || (Array.isArray(value) && value.length === 0 && key !== "folders"))
            delete list[index][key];
        else
            list[index][key] = value;
        save(list, "Sync: " + (list[index].name || list[index].id));
    }

    function addEntry(type) {
        const base = type === "git" ? "notes" : "drive";
        let id = base;
        let n = 2;
        while (entries.some((e) => {
            return e.id === id;
        }))id = base + n++
        const entry = type === "git" ? {
            "id": id,
            "name": "New Git folder",
            "type": "git",
            "path": ""
        } : {
            "id": id,
            "name": "New drive",
            "type": "rclone",
            "remote": "",
            "folders": []
        };
        openIndex = entries.length;
        save(entries.concat([entry]), "Add sync entry");
    }

    function remove(index) {
        const list = entries.slice();
        const gone = list.splice(index, 1)[0];
        openIndex = -1;
        confirmIndex = -1;
        save(list, "Remove " + (gone.name || gone.id));
    }

    // "~/Music = Music, ~/Pictures = Pictures" <-> [["~/Music", "Music"], ...]
    function foldersText(e) {
        return (e.folders || []).filter((f) => {
            return Array.isArray(f) && f.length === 2;
        }).map((f) => {
            return f[0] + " = " + f[1];
        }).join(", ");
    }

    function parseFolders(text) {
        return text.split(",").map((p) => {
            return p.split("=").map((x) => {
                return x.trim();
            });
        }).filter((p) => {
            return p.length === 2 && p[0] !== "" && p[1] !== "";
        });
    }

    // true = the keys in the agent, a path = that key, nothing = no key
    function keyText(e) {
        return e.sshKey === true ? "agent" : (typeof e.sshKey === "string" ? e.sshKey : "");
    }

    function parseKey(text) {
        return text === "agent" ? true : text;
    }

    function targetOf(e) {
        const t = typeOf(e);
        if (t === "git")
            return e.path || "no folder yet";

        if (t === "rclone")
            return (e.remote || "no remote yet") + (e.folders && e.folders.length > 0 ? " · " + e.folders.length + (e.folders.length === 1 ? " folder" : " folders") : "");

        return Array.isArray(e.run) ? e.run[0] : "own command";
    }

    spacing: Theme.px(22)

    // Labelled field of an open entry
    component Field: Item {
        id: fieldRow

        property string label: ""
        property string hint: ""
        property alias text: field.text
        property alias placeholder: field.placeholder

        signal committed(string text)

        width: parent ? parent.width : 0
        height: Theme.px(hint !== "" ? 50 : 36)

        Text {
            x: Theme.px(42)
            y: Theme.px(9)
            width: Theme.px(92)
            text: fieldRow.label
            elide: Text.ElideRight
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
        }

        SettingField {
            id: field

            x: Theme.px(140)
            y: Theme.px(3)
            width: parent.width - x - Theme.px(14)
            onCommitted: (t) => {
                return fieldRow.committed(t);
            }
        }

        Text {
            x: field.x + Theme.px(2)
            y: field.y + field.height + Theme.px(4)
            width: field.width
            visible: fieldRow.hint !== ""
            text: fieldRow.hint
            elide: Text.ElideRight
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
        }

    }

    IosGroup {
        width: page.width
        title: "Entries"
        footer: page.entries.length === 0 ? "No entries yet. Without entries the bar shows no sync icon." : "Changes show in the sync dropdown at once."

        Repeater {
            model: page.entries.length

            Column {
                id: entry

                required property int index
                // From the list itself, not from the Repeater: it hands nested lists (folders, run) on as
                // Qt lists, which are no JavaScript arrays any more
                readonly property var modelData: page.entries[index] || ({
                })
                readonly property bool isOpen: page.openIndex === index
                readonly property string type: page.typeOf(modelData)

                width: parent ? parent.width : 0

                IosRow {
                    divider: entry.index > 0
                    glyph: entry.modelData.icon || "\u{F04E6}"
                    title: entry.modelData.name || entry.modelData.id
                    subtitle: entry.type + " · " + page.targetOf(entry.modelData)
                    trailingGlyph: entry.isOpen ? "\u{F0140}" : "\u{F0142}"
                    onClicked: {
                        page.confirmIndex = -1;
                        page.openIndex = entry.isOpen ? -1 : entry.index;
                    }
                }

                Column {
                    width: parent.width
                    visible: entry.isOpen
                    bottomPadding: Theme.px(10)

                    Field {
                        label: "Name"
                        text: entry.modelData.name || ""
                        onCommitted: (t) => {
                            return page.patch(entry.index, "name", t);
                        }
                    }

                    Field {
                        visible: entry.type === "git"
                        label: "Folder"
                        placeholder: "~/Documents/Notes"
                        hint: "A Git folder whose branch follows a remote branch."
                        text: entry.modelData.path || ""
                        onCommitted: (t) => {
                            return page.patch(entry.index, "path", t);
                        }
                    }

                    Field {
                        visible: entry.type === "rclone"
                        label: "Remote"
                        placeholder: "gdrive:"
                        hint: "Name of the rclone remote, with the colon."
                        text: entry.modelData.remote || ""
                        onCommitted: (t) => {
                            return page.patch(entry.index, "remote", t);
                        }
                    }

                    Field {
                        visible: entry.type === "rclone"
                        label: "Folders"
                        placeholder: "~/Music = Music, ~/Pictures = Pictures"
                        hint: "Local folder = folder in the remote, pairs separated by commas."
                        text: page.foldersText(entry.modelData)
                        onCommitted: (t) => {
                            return page.patch(entry.index, "folders", page.parseFolders(t));
                        }
                    }

                    Field {
                        label: "SSH key"
                        placeholder: "none"
                        hint: "Empty = none, agent = the keys in your agent, or the path of a key."
                        text: page.keyText(entry.modelData)
                        onCommitted: (t) => {
                            return page.patch(entry.index, "sshKey", page.parseKey(t));
                        }
                    }

                    Text {
                        x: Theme.px(42)
                        width: parent.width - x - Theme.px(14)
                        visible: entry.type === "command"
                        topPadding: Theme.px(4)
                        text: "The commands of this entry (check, run, input) are edited in settings.json."
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                    // Remove: asks once more in place
                    Item {
                        width: parent.width
                        height: Theme.px(34)

                        Text {
                            x: Theme.px(42)
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.confirmIndex === entry.index ? "Click again to remove" : "Remove entry"
                            color: Theme.bad
                            opacity: removeMouse.containsMouse || page.confirmIndex === entry.index ? 1 : 0.7
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeBody
                            font.weight: Font.Medium

                            MouseArea {
                                id: removeMouse

                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (page.confirmIndex === entry.index)
                                        page.remove(entry.index);
                                    else
                                        page.confirmIndex = entry.index;
                                }
                            }

                        }

                    }

                }

            }

        }

    }

    Row {
        spacing: Theme.px(10)

        IosButton {
            width: Theme.px(190)
            height: Theme.px(36)
            kind: "tinted"
            glyph: "\u{F02A2}"
            text: "Add Git folder"
            onClicked: page.addEntry("git")
        }

        IosButton {
            width: Theme.px(190)
            height: Theme.px(36)
            kind: "tinted"
            glyph: "\u{F12D6}"
            text: "Add rclone remote"
            onClicked: page.addEntry("rclone")
        }

    }

    Text {
        width: page.width
        text: "An entry of your own (type command) is added in settings.json: check, run and input are commands as lists of arguments. The README describes the protocol."
        wrapMode: Text.WordWrap
        color: Theme.textFaint
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeSmall
        lineHeight: 1.2
    }

}
