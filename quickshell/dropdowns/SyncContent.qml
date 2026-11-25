import "../common"
import "../services"
import QtQuick
import QtQuick.Controls.Basic as Controls

// Dropdown: Sync (data: SyncState, progress: SyncProgress). Header with the overall state, a card with one
// row per sync entry ("sync" in the settings: git, rclone or own command), below the files not uploaded yet
// (the first few) and at the bottom the last sync + button.
// While syncing the rows expand: step, thin bar, up to three files (arrow = up/down); the result stays
// for a moment. The dropdown animates its height itself (resizing), DropdownHost then follows it directly.
Item {
    id: dropdown

    readonly property real cornerRadius: 20
    readonly property real menuWidth: 340
    readonly property real innerW: menuWidth - 2 * Theme.padX
    readonly property bool running: SyncState.running
    readonly property int pending: SyncState.pending
    readonly property int shownFiles: 4
    // For DropdownHost: while true the shell follows the height without its own animation
    readonly property bool resizing: rowsRepeater.anyResizing || pendingBox.resizing
    // Overall state for the chip: text, color, dot pulses
    readonly property var overall: {
        if (running)
            return ["Syncing", Theme.accent, true];

        if (SyncState.failedEntry)
            return [SyncState.entries.length > 1 ? SyncState.failedEntry.name + " failed" : "Failed", Theme.bad, false];

        if (SyncState.inputEntry)
            return [SyncState.inputEntry.name + " needs sign-in", Theme.warn, false];

        if (SyncState.locked)
            return ["Key locked", Theme.warn, false];

        if (SyncState.offlineEntry)
            return [SyncState.offlineEntry.name + " offline", Theme.warn, false];

        if (pending > 0)
            return [pending + " pending", Theme.accent, false];

        return ["Up to date", Theme.good, false];
    }

    // Header status during a run: percent or waiting, otherwise the normal status
    function liveStatus(info, normal) {
        if (info.phase === "queued")
            return ["waiting", Theme.textDim];

        if (info.phase === "running")
            return [info.progress >= 0 ? Math.round(info.progress * 100) + "%" : "syncing…", Theme.accent];

        return normal;
    }

    function toneColor(tone) {
        return tone === "good" ? Theme.good : (tone === "bad" ? Theme.bad : (tone === "warn" ? Theme.warn : Theme.accent));
    }

    function count(n, word) {
        return n + " " + word + (n === 1 ? "" : "s");
    }

    // Status on the right of a row: [text, color]. "syncing…" comes from liveStatus (SyncProgress knows
    // which entry is running)
    function entryStatus(e) {
        const c = SyncState.checks[e.id] || {};
        const st = SyncState.lastState(e.id);
        if (SyncState.isRunning(e.id))
            return ["syncing…", Theme.accent];

        if (st === "input")
            return ["sign-in needed", Theme.warn];

        if (c.changed > 0)
            return [c.changed + " changed", Theme.accent];

        if (c.unpushed > 0)
            return [count(c.unpushed, "commit") + " to push", Theme.accent];

        if (c.pending > 0)
            return [c.pending + " pending", Theme.accent];

        if (st === "waiting")
            return ["not run yet", Theme.textDim];

        if (st === "offline")
            return ["unavailable", Theme.warn];

        if (st === "locked")
            return ["key locked", Theme.warn];

        const ago = SyncState.agoOf(SyncState.finishedAt(e.id));
        if (st === "error")
            return ["failed" + (ago ? " · " + ago : ""), Theme.bad];

        // Entries without a check (e.g. rclone) only know when they last synced
        return e.hasCheck && e.kind !== "rclone" ? ["up to date", Theme.good] : [SyncState.agoOf(SyncState.syncedAt(e.id)) || "up to date", Theme.good];
    }

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight
    // Count fresh when opening, every 20 s while open (local, without network)
    Component.onCompleted: SyncState.check()

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: SyncState.check()
    }

    Column {
        id: content

        width: dropdown.innerW
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gap
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        DropdownHeader {
            glyph: "\u{F04E6}"
            title: "Sync"
            settingsSection: "sync"

            Chip {
                tone: dropdown.overall[1]
                dot: true
                pulse: dropdown.overall[2]
                text: dropdown.overall[0]
            }

        }

        // Error message of the last run
        Card {
            width: parent.width
            height: errorText.implicitHeight + 18
            visible: SyncState.failedEntry !== null && SyncState.lastMessage(SyncState.failedEntry.id) !== ""
            color: Theme.tint(Theme.bad, 0.12)

            Text {
                id: errorText

                anchors.centerIn: parent
                width: parent.width - 24
                text: SyncState.failedEntry ? SyncState.lastMessage(SyncState.failedEntry.id) : ""
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Theme.bad
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
            }

        }

        // Card + pending files as one group: the list collapses together with its spacing
        Column {
            width: parent.width

            // What is synced and how current it is
            Card {
                width: parent.width
                height: rows.implicitHeight + 8

                Column {
                    id: rows

                    width: parent.width - 24
                    anchors.centerIn: parent

                    Repeater {
                        id: rowsRepeater

                        // Hidden entries (command check says "unavailable", e.g. a service that is not set up here)
                        readonly property bool anyResizing: {
                            for (let i = 0; i < count; i++) {
                                const it = itemAt(i);
                                if (it && it.resizing)
                                    return true;

                            }
                            return false;
                        }

                        model: SyncState.entries.filter((e) => {
                            return SyncState.lastState(e.id) !== "unavailable";
                        })

                        delegate: Column {
                            id: entryItem

                            required property var modelData
                            required property int index
                            readonly property bool resizing: entryRow.resizing

                            width: rows.width

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Theme.separator
                                visible: entryItem.index > 0
                            }

                            SyncRow {
                                id: entryRow

                                glyph: entryItem.modelData.icon || "\u{F04E6}"
                                title: entryItem.modelData.name || entryItem.modelData.id
                                part: entryItem.modelData.id
                                busy: SyncState.isRunning(entryItem.modelData.id) || SyncState.inputBusy === entryItem.modelData.id
                                subtitle: (SyncState.checks[entryItem.modelData.id] || {}).subtitle || entryItem.modelData.subtitle || ""
                                info: SyncProgress.info(entryItem.modelData.id)
                                status: dropdown.liveStatus(info, dropdown.entryStatus(entryItem.modelData))
                                statusContent: SyncState.lastState(entryItem.modelData.id) === "input" && entryItem.modelData.hasInput && !SyncState.isRunning(entryItem.modelData.id) ? codeEntry : null
                            }

                        }

                    }

                }

            }

            // Files not uploaded yet: the first few, the rest as a number. While the rows are expanded,
            // they already show what goes up -> the list collapses for that time (at the same time, same curve)
            Item {
                id: pendingBox

                readonly property bool open: SyncState.pendingFiles.length > 0 && !SyncProgress.anyActive
                readonly property bool resizing: pendingAnim.running

                width: parent.width
                height: open ? pendingList.implicitHeight + Theme.gap : 0
                visible: height > 0
                clip: true

                Behavior on height {
                    Anim {
                        id: pendingAnim
                    }

                }

                Column {
                    id: pendingList

                    y: Theme.gap
                    width: parent.width
                    spacing: 4

                    Item {
                        width: parent.width
                        height: filesLabel.implicitHeight

                        Text {
                            id: filesLabel

                            text: "TO UPLOAD"
                            color: Theme.textFaint
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                            font.bold: true
                            font.letterSpacing: Theme.microSpacing
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.baseline: filesLabel.baseline
                            text: dropdown.count(SyncState.changedCount, "file")
                            color: Theme.textFaint
                            font.family: Theme.fontUi
                            font.features: Theme.tabular
                            font.pixelSize: Theme.sizeMicro
                        }

                    }

                    Repeater {
                        model: SyncState.pendingFiles.slice(0, dropdown.shownFiles)

                        delegate: Row {
                            id: fileRow

                            required property var modelData

                            width: parent.width
                            spacing: 8

                            // + new, − deleted, • changed
                            Text {
                                width: 10
                                horizontalAlignment: Text.AlignHCenter
                                text: fileRow.modelData.k === "+" ? "+" : (fileRow.modelData.k === "-" ? "−" : "•")
                                color: fileRow.modelData.k === "+" ? Theme.good : (fileRow.modelData.k === "-" ? Theme.bad : Theme.accent)
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeBody
                                font.bold: true
                            }

                            Text {
                                width: parent.width - 18
                                text: fileRow.modelData.p
                                elide: Text.ElideMiddle
                                color: Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                            }

                        }

                    }

                    Text {
                        visible: SyncState.changedCount > dropdown.shownFiles
                        leftPadding: 18
                        text: "+" + (SyncState.changedCount - dropdown.shownFiles) + " more"
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                }

            }

        }

        // Last sync + button
        Item {
            width: parent.width
            height: Theme.controlHeight

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "LAST SYNC"
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.bold: true
                    font.letterSpacing: Theme.microSpacing
                }

                Text {
                    text: SyncState.lastTime > 0 ? SyncState.agoOf(SyncState.lastTime) : "not yet"
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.features: Theme.tabular
                    font.pixelSize: Theme.sizeBody
                }

            }

            CardButton {
                anchors.right: parent.right
                width: 132
                glyph: "\u{F04E6}"
                text: dropdown.running ? "Syncing…" : "Sync now"
                active: !dropdown.running
                tone: Theme.accent
                onClicked: SyncState.sync()
            }

        }

    }

    // Field for entries that need input (state "input", e.g. a 2FA code); entryId is set by the row
    Component {
        id: codeEntry

        Row {
            id: codeRow

            property string entryId: ""
            readonly property var entryData: SyncState.entry(entryId) || {}

            spacing: 5

            Controls.TextField {
                id: codeInput

                function submit() {
                    if (enabled && text !== "") {
                        SyncState.submitInput(codeRow.entryId, text);
                        clear();
                    }
                }

                width: 118
                height: 30
                leftPadding: 8
                rightPadding: 8
                enabled: SyncState.inputBusy === ""
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                placeholderText: enabled ? (SyncState.inputErrors[codeRow.entryId] || codeRow.entryData.prompt || "Code") : "Signing in…"
                Accessible.name: (codeRow.entryData.name || "") + " " + (codeRow.entryData.prompt || "code")
                color: Theme.text
                placeholderTextColor: SyncState.inputErrors[codeRow.entryId] ? Theme.warn : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                onAccepted: submit()
                background: Rectangle {
                    radius: 8
                    color: Theme.card
                    border.color: codeInput.activeFocus ? Theme.accent : Theme.stroke
                }
            }

            CardButton {
                width: 30
                height: 30
                glyph: "\u{F0054}"
                active: enabled
                enabled: codeInput.enabled && codeInput.text !== ""
                Accessible.role: Accessible.Button
                Accessible.name: "Submit " + (codeRow.entryData.prompt || "code")
                Accessible.onPressAction: codeInput.submit()
                onClicked: codeInput.submit()
            }
        }
    }

    // Row of the card: symbol, name + content below it, status on the right (dot + text).
    // Below it the progress expands during a sync (info from SyncProgress).
    component SyncRow: Item {
        id: row

        property string glyph: ""
        property string title: ""
        property string subtitle: ""
        property var status: ["", Theme.textDim]
        property Component statusContent: null
        // Button on the right: sync only this entry (SyncState.syncEntry). "" = no button
        property string part: ""
        // The entry is already running (or shares the running git run) -> button off
        property bool busy: false
        property var info: SyncProgress.idle
        readonly property bool expanded: info.phase !== "idle"
        // The last state stays while collapsing, otherwise the content would collapse empty
        property var shown: SyncProgress.idle
        readonly property color tone: dropdown.toneColor(shown.tone)
        readonly property real headHeight: 48
        // Text starts below the title (symbol 18 + spacing 10)
        readonly property real indent: 28
        readonly property bool resizing: detailAnim.running

        onInfoChanged: {
            if (info.phase !== "idle")
                shown = info;

        }
        width: parent.width
        height: headHeight + detail.height

        Text {
            id: rowGlyph

            x: 0
            y: (row.headHeight - height) / 2
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: row.glyph
            color: Theme.tint(Theme.accent, 0.8)
            font.family: Theme.font
            font.pixelSize: Theme.sizeBody + 3
        }

        Column {
            x: row.indent
            y: (row.headHeight - height) / 2
            width: (row.statusContent ? statusLoader.x : statusRow.x) - x - 10
            spacing: 2

            Text {
                width: parent.width
                text: row.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLabel
                font.bold: true
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: row.subtitle
                elide: Text.ElideRight
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
            }

        }

        Row {
            id: statusRow

            visible: !row.statusContent
            x: row.width - width - (partButton.visible ? partButton.width + 8 : 0)
            y: (row.headHeight - height) / 2
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: row.status[1]
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: row.status[0]
                color: row.status[1]
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeSmall
                font.bold: true
            }

        }

        // Gone during the 2FA input: there the row needs the room for the code field
        CardButton {
            id: partButton

            visible: row.part !== "" && !row.statusContent
            x: row.width - width
            y: (row.headHeight - height) / 2
            width: 28
            height: 28
            glyph: "\u{F04E6}"
            enabled: !row.busy
            opacity: enabled ? 1 : 0.4
            Accessible.role: Accessible.Button
            Accessible.name: "Sync " + row.title + " only"
            onClicked: SyncState.syncEntry(row.part)
        }

        Loader {
            id: statusLoader

            x: row.width - width
            y: (row.headHeight - height) / 2
            sourceComponent: row.statusContent
            onLoaded: {
                if (item.entryId !== undefined)
                    item.entryId = row.part;

            }
        }

        // Progress: step + counter, bar, files
        Item {
            id: detail

            y: row.headHeight
            width: parent.width
            height: row.expanded ? detailCol.implicitHeight + 12 : 0
            opacity: row.expanded ? 1 : 0
            visible: height > 0
            clip: true

            Column {
                id: detailCol

                x: row.indent
                width: parent.width - row.indent
                spacing: 6

                Item {
                    width: parent.width
                    height: stepText.implicitHeight

                    Text {
                        id: stepText

                        anchors.left: parent.left
                        anchors.right: counterText.left
                        anchors.rightMargin: 8
                        text: row.shown.label || ""
                        elide: Text.ElideRight
                        color: row.shown.phase === "done" ? row.tone : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                        font.bold: row.shown.phase === "done"
                    }

                    Text {
                        id: counterText

                        anchors.right: parent.right
                        anchors.baseline: stepText.baseline
                        text: row.shown.detail || ""
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.features: Theme.tabular
                        font.pixelSize: Theme.sizeSmall
                    }

                }

                ProgressLine {
                    width: parent.width
                    value: row.shown.progress === undefined ? -1 : row.shown.progress
                    tone: row.tone
                    // Waiting: leave the bar calm instead of running
                    resting: row.shown.phase === "queued"
                }

                // Files tighter than the other parts, so it stays a list
                Column {
                    width: parent.width
                    spacing: 1
                    visible: (row.shown.files || []).length > 0

                    Repeater {
                        model: row.shown.files || []

                        delegate: FileLine {
                            width: detailCol.width
                        }

                    }

                }

                Text {
                    visible: (row.shown.more || 0) > 0
                    leftPadding: 16
                    text: "+" + row.shown.more + " more"
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.features: Theme.tabular
                    font.pixelSize: Theme.sizeSmall
                }

            }

            Behavior on height {
                Anim {
                    id: detailAnim
                }

            }

            Behavior on opacity {
                Anim {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

    }

    // Thin bar: value 0..1, -1 = indeterminate (a piece runs through)
    component ProgressLine: Item {
        id: line

        property real value: -1
        property color tone: Theme.accent
        property bool resting: false

        height: 3

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.track
        }

        Rectangle {
            visible: line.value >= 0
            width: Math.max(height, line.width * Math.max(0, Math.min(1, line.value)))
            height: parent.height
            radius: height / 2
            color: line.tone

            Behavior on width {
                Anim {
                    duration: Appearance.anim.durations.slow
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.normal
                }

            }

        }

        Item {
            anchors.fill: parent
            visible: line.value < 0 && !line.resting
            clip: true

            Rectangle {
                id: segment

                width: line.width * 0.3
                height: parent.height
                radius: height / 2
                color: line.tone

                NumberAnimation on x {
                    from: -segment.width
                    to: line.width
                    duration: 1300
                    loops: Animation.Infinite
                    easing.type: Easing.InOutSine
                    running: segment.visible
                }

            }

        }

    }

    // File in progress: arrow (up = accent, down = accent2), name, during a running transfer
    // percent + a light fill behind it. Deleted files crossed out, finished ones fainter.
    component FileLine: Item {
        id: file

        required property var modelData
        readonly property bool up: modelData.dir === "up"
        readonly property bool live: modelData.pct >= 0

        height: 18

        Rectangle {
            visible: file.live
            width: file.width * Math.min(1, file.modelData.pct / 100)
            height: parent.height
            radius: Theme.radiusXS
            color: Theme.tint(Theme.accent, 0.12)
        }

        Text {
            id: arrow

            x: 2
            anchors.verticalCenter: parent.verticalCenter
            text: file.up ? "\u{F005D}" : "\u{F0045}"
            color: file.up ? Theme.accent : Theme.accent2
            opacity: file.modelData.done ? 0.6 : 1
            font.family: Theme.font
            font.pixelSize: Theme.sizeSmall
        }

        Text {
            anchors.left: arrow.right
            anchors.leftMargin: 6
            anchors.right: pctText.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: file.modelData.name
            elide: Text.ElideMiddle
            color: file.modelData.done ? Theme.textFaint : Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
            font.strikeout: file.modelData.kind === "D"
        }

        Text {
            id: pctText

            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: file.live ? file.modelData.pct + "%" : ""
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeMicro
        }

    }

}
