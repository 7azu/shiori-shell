pragma ComponentBehavior: Bound

import "../services"
import QtQuick
import Quickshell

// The menu of one tray program as a list: its entries, with separators, check marks and radio dots; an
// entry with a submenu goes one level deeper (stack). Used inside the tray panel of the bar
// (bar/TrayPanel).
// The last line at the top level is the shell's own: hide the program from the tray, or bring it back.
// Whoever shows the menu passes the keys on (handleKey) and reacts to done() and leave().
Item {
    id: root

    // The tray program (SystemTray item) whose menu this is; null = none
    property var program: null
    // Submenus on the way down (QsMenuHandle)
    property var stack: []
    readonly property bool atRoot: stack.length === 0
    readonly property var handle: stack.length > 0 ? stack[stack.length - 1] : (program && program.hasMenu ? program.menu : null)
    property int index: 0
    // For tests: entries instead of the program's own (objects with text, isSeparator, enabled ...)
    property var testEntries: null
    readonly property var entries: testEntries ?? (opener.children ? opener.children.values : [])
    // The entries arrive a moment after the menu is asked for. Until then nothing is shown: otherwise
    // the shell's own line stands there alone first and the list jumps.
    property bool settled: false
    readonly property real entryH: 32
    property real maxListH: 440
    readonly property bool resizing: heightAnim.running
    // { kind: "entry" | "sep" | "own", entry?, text? }
    readonly property var rows: {
        const out = [];
        if (!settled)
            return out;

        for (const entry of entries) out.push({
            "kind": entry.isSeparator ? "sep" : "entry",
            "entry": entry
        })
        if (atRoot && program) {
            if (out.length > 0)
                out.push({
                "kind": "sep"
            });

            out.push({
                "kind": "own",
                "text": TrayState.isHidden(program) ? "Show in tray" : "Hide from tray"
            });
        }
        return out;
    }

    // An entry was carried out: close whatever shows the menu
    signal done()
    // Back at the top level, or the shell's own line was used: nothing more to do here
    signal leave()

    function selectable(i) {
        const r = rows[i];
        if (!r || r.kind === "sep")
            return false;

        return r.kind !== "entry" || r.entry.enabled;
    }

    // Next row that can be chosen in direction dir (stops at the ends)
    function step(dir) {
        for (let i = index + dir; i >= 0 && i < rows.length; i += dir) {
            if (selectable(i)) {
                index = i;
                return ;
            }
        }
    }

    function selectFirst() {
        index = 0;
        if (!selectable(0))
            step(1);

    }

    // Start over at the top level (the program changed, or the menu is opened again)
    function reset() {
        stack = [];
        selectFirst();
    }

    function back() {
        if (atRoot) {
            leave();
            return ;
        }
        stack = stack.slice(0, -1);
        selectFirst();
    }

    function choose(i) {
        const r = rows[i];
        if (!r || !selectable(i))
            return ;

        index = i;
        if (r.kind === "own") {
            TrayState.setHidden(program, !TrayState.isHidden(program));
            leave();
            return ;
        }
        if (r.entry.hasChildren) {
            stack = stack.concat([r.entry]);
            selectFirst();
            return ;
        }
        r.entry.triggered();
        done();
    }

    // Keys of the menu; true = taken. Esc and Left go one level up (leave() at the top).
    function handleKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Left:
        case Qt.Key_Backspace:
            back();
            return true;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            step(-1);
            return true;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            step(1);
            return true;
        case Qt.Key_K:
            if (ctrl)
                step(-1);

            return ctrl;
        case Qt.Key_J:
            if (ctrl)
                step(1);

            return ctrl;
        case Qt.Key_Right:
            if (rows[index] && rows[index].kind === "entry" && rows[index].entry.hasChildren)
                choose(index);

            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            choose(index);
            return true;
        }
        return false;
    }

    implicitHeight: list.height
    height: implicitHeight
    onProgramChanged: reset()
    // Another menu: wait for its entries, at most a moment (it may really be empty)
    onHandleChanged: {
        settled = entries.length > 0;
        if (!settled && handle !== null)
            settle.restart();

    }
    onEntriesChanged: {
        if (entries.length > 0)
            settled = true;

    }
    onRowsChanged: {
        if (index >= rows.length)
            index = Math.max(0, rows.length - 1);

        if (!selectable(index))
            selectFirst();

    }

    Timer {
        id: settle

        interval: 400
        onTriggered: root.settled = true
    }

    QsMenuOpener {
        id: opener

        menu: root.handle
    }

    ListView {
        id: list

        width: parent.width
        // As high as its rows, up to maxListH; whoever shows the menu follows this height
        height: Math.min(root.maxListH, contentHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        model: root.rows
        currentIndex: root.index
        highlightMoveDuration: 140
        highlightResizeDuration: 0

        highlight: Rectangle {
            radius: 12
            color: WalColors.withAlpha(WalColors.color4, 0.13)
        }

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property string kind: modelData.kind
            readonly property var entry: modelData.entry ?? null
            readonly property bool usable: root.selectable(index)
            readonly property bool checked: entry !== null && entry.checkState !== Qt.Unchecked

            width: list.width
            height: kind === "sep" ? 11 : root.entryH
            opacity: !usable && kind !== "sep" ? 0.4 : 1

            Rectangle {
                visible: row.kind === "sep"
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                width: parent.width - 20
                height: 1
                color: Theme.separator
            }

            Row {
                visible: row.kind !== "sep"
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                // Check mark or radio dot of entries that can be on; the eye of the shell's own line
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14

                    Text {
                        anchors.centerIn: parent
                        visible: row.entry !== null && row.entry.buttonType === QsMenuButtonType.CheckBox && row.checked
                        text: "\u{F012C}"
                        color: WalColors.color4
                        font.family: Theme.font
                        font.pixelSize: Theme.sizeLead
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: row.entry !== null && row.entry.buttonType === QsMenuButtonType.RadioButton
                        width: 8
                        height: 8
                        radius: 4
                        color: row.checked ? WalColors.color4 : "transparent"
                        border.width: 1.5
                        border.color: row.checked ? WalColors.color4 : Theme.textFaint
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: row.kind === "own"
                        text: root.program && TrayState.isHidden(root.program) ? "\u{F0208}" : "\u{F0209}"
                        color: Theme.textDim
                        font.family: Theme.font
                        font.pixelSize: Theme.sizeLead
                    }

                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 14 - 10 - (sub.visible ? sub.width + 10 : 0)
                    text: row.kind === "own" ? row.modelData.text : (row.entry ? row.entry.text : "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: row.kind === "own" ? Theme.textDim : Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                }

                // Goes one level deeper
                Text {
                    id: sub

                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.entry !== null && row.entry.hasChildren
                    text: "\u{F0142}"
                    color: Theme.textFaint
                    font.family: Theme.font
                    font.pixelSize: Theme.sizeHeading
                }

            }

            MouseArea {
                anchors.fill: parent
                enabled: row.usable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Hover is the selection, as in the pickers
                onPositionChanged: root.index = row.index
                onClicked: root.choose(row.index)
            }

        }

        Behavior on height {
            NumberAnimation {
                id: heightAnim

                duration: 200
                easing.type: Easing.OutCubic
            }

        }

    }

}
