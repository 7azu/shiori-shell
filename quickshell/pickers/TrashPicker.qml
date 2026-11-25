import "../common"
import "../dropdowns" as Dropdowns
import "../services"
import "./parts"
import "../common/Format.js" as Fmt
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell

Item {
    id: root

    readonly property real pad: 16
    readonly property real rowH: 56
    readonly property real rowGap: 4
    readonly property real rowStride: rowH + rowGap
    // Whole rows: half a row as a scroll hint looked cut off. That there is more
    // is shown by the flat gradient at the bottom of the list.
    readonly property real listMaxH: rowStride * 7 - rowGap
    readonly property real panelWidth: Math.min(720, width - 48)
    readonly property string mono: Theme.font
    readonly property var bezierOut: Appearance.anim.curves.outQuint
    property string filter: "all"
    property string sortKey: "date"
    property bool sortDesc: true
    property int currentIndex: 0
    property string selectedId: ""
    property string confirmId: ""
    property bool confirmEmpty: false
    // How the next row leaves the window: restore | delete | empty | filter
    property string removeKind: "filter"
    property bool intro: true
    property bool holdList: false
    property int heldRows: 0
    property real shown: 0
    property real lastMouseX: -1
    property real lastMouseY: -1
    readonly property string needle: PickerManager.searchText.toLowerCase()
    readonly property var visibleEntries: {
        const dir = sortDesc ? -1 : 1;
        const key = sortKey;
        const byName = (a, b) => {
            return a.lname < b.lname ? -1 : (a.lname > b.lname ? 1 : 0);
        };
        const list = TrashState.entries.filter((e) => {
            if (filter === "files" && e.isDir)
                return false;

            if (filter === "folders" && !e.isDir)
                return false;

            return needle === "" || e.hay.indexOf(needle) !== -1;
        });
        return list.sort((a, b) => {
            let d = 0;
            if (key === "date")
                d = a.ts - b.ts;
            else if (key === "size")
                d = a.size - b.size;
            else if (key === "type")
                d = a.kind === b.kind ? (a.ext < b.ext ? -1 : (a.ext > b.ext ? 1 : 0)) : (a.kind < b.kind ? -1 : 1);
            else
                d = byName(a, b);
            return dir * d || byName(a, b);
        });
    }
    readonly property real visibleBytes: visibleEntries.reduce((sum, e) => {
        return sum + e.size;
    }, 0)
    property real shownBytes: visibleBytes
    readonly property bool isEmpty: TrashState.loaded && visibleEntries.length === 0 && !holdList
    readonly property var selectedEntry: visibleEntries[currentIndex] || null

    function focusSearch() {
        searchInput.forceActiveFocus();
    }

    function formatSize(bytes) {
        return Fmt.bytes(bytes);
    }

    function formatAge(ts) {
        return Fmt.ago(Date.now() / 1000 - ts, {
            "long": true
        });
    }

    function glyphFor(kind) {
        const glyphs = {
            "folder": "",
            "image": "",
            "video": "",
            "audio": "",
            "archive": "",
            "doc": "",
            "code": "",
            "link": ""
        };
        return glyphs[kind] || "";
    }

    function select(i) {
        const list = visibleEntries;
        currentIndex = Math.max(0, Math.min(i, list.length - 1));
        selectedId = list.length > 0 ? list[currentIndex].id : "";
    }

    // The selection sticks to the entry, not to the row. If it is gone, the next one moves up
    function syncSelection() {
        const i = visibleEntries.findIndex((e) => {
            return e.id === selectedId;
        });
        select(i >= 0 ? i : currentIndex);
    }

    function move(dir) {
        select(currentIndex + dir);
        scrollTo(currentIndex);
    }

    // The list always stands on whole rows (top row flush): keyboard and mouse wheel count in
    // rows, not in pixels. The target is the next row from the running target, not from an
    // intermediate position of the animation.
    function firstRow() {
        return Math.round((listScroll.running ? listScroll.to : list.contentY) / rowStride);
    }

    function scrollTo(i) {
        const rows = Math.max(1, Math.floor((list.height + rowGap) / rowStride));
        let first = firstRow();
        if (i < first)
            first = i;
        else if (i > first + rows - 1)
            first = i - rows + 1;
        animateListTo(first * rowStride);
    }

    // Mouse wheel: n rows on (n < 0 = up)
    function scrollRows(n) {
        animateListTo((firstRow() + n) * rowStride);
    }

    function animateListTo(y) {
        const to = Math.max(0, Math.min(y, Math.max(0, visibleEntries.length * rowStride - rowGap - list.height)));
        listScroll.stop();
        if (Math.abs(to - list.contentY) < 0.5)
            return ;

        listScroll.to = to;
        listScroll.start();
    }

    function resetView() {
        listScroll.stop();
        list.contentY = 0;
        select(0);
    }

    function setFilter(f) {
        if (filter === f)
            return ;

        removeKind = "filter";
        filter = f;
        Qt.callLater(resetView);
    }

    function setSort(key) {
        if (sortKey === key) {
            sortDesc = !sortDesc;
        } else {
            sortKey = key;
            // Newest, biggest first; names and types alphabetically
            sortDesc = key === "date" || key === "size";
        }
        Qt.callLater(resetView);
    }

    function cycle(list, current, dir) {
        return list[(list.indexOf(current) + dir + list.length) % list.length];
    }

    function hoverSelect(target, mouse, idx) {
        const p = target.mapToItem(null, mouse.x, mouse.y);
        if (Math.abs(p.x - lastMouseX) < 3 && Math.abs(p.y - lastMouseY) < 3)
            return ;

        lastMouseX = p.x;
        lastMouseY = p.y;
        select(idx);
    }

    function restore(entry) {
        if (!entry || entry.origin === "")
            return ;

        removeKind = "restore";
        footerCan.flap();
        TrashState.restore(entry);
    }

    // Final: needs a second press on the same entry (changing the selection cancels)
    function requestDelete(entry) {
        if (!entry)
            return ;

        if (confirmId !== entry.id) {
            confirmId = entry.id;
            confirmTimer.restart();
            return ;
        }
        confirmId = "";
        removeKind = "delete";
        footerCan.flap();
        TrashState.remove(entry);
    }

    function requestEmpty() {
        if (TrashState.emptying || TrashState.entries.length === 0)
            return ;

        if (!confirmEmpty) {
            confirmEmpty = true;
            emptyCountdown.restart();
            return ;
        }
        emptyCountdown.stop();
        confirmEmpty = false;
        removeKind = "empty";
        heldRows = visibleEntries.length;
        holdList = true;
        holdTimer.restart();
        TrashState.empty();
    }

    function playIntro() {
        outroAnim.stop();
        intro = true;
        introTimer.restart();
        introAnim.restart();
        confirmId = "";
        confirmEmpty = false;
        resetView();
    }

    function playOutro() {
        introAnim.stop();
        outroAnim.restart();
    }

    Component.onCompleted: playIntro()
    onVisibleChanged: {
        if (visible)
            playIntro();

    }
    onVisibleEntriesChanged: syncSelection()
    onSelectedIdChanged: confirmId = ""
    onNeedleChanged: {
        removeKind = "filter";
        Qt.callLater(resetView);
    }

    Timer {
        id: introTimer

        interval: 700
        onTriggered: root.intro = false
    }

    Timer {
        id: confirmTimer

        interval: 2800
        onTriggered: root.confirmId = ""
    }

    // Keeps the list open until the last entry has fallen into the trash
    Timer {
        id: holdTimer

        interval: 760
        onTriggered: root.holdList = false
    }

    NumberAnimation {
        id: emptyCountdown

        target: countdownBar
        property: "fill"
        from: 1
        to: 0
        duration: 3000
        onFinished: root.confirmEmpty = false
    }

    NumberAnimation {
        id: introAnim

        target: root
        property: "shown"
        from: 0
        to: 1
        duration: 520
        easing.bezierCurve: root.bezierOut
    }

    NumberAnimation {
        id: outroAnim

        target: root
        property: "shown"
        to: 0
        duration: 200
        easing.bezierCurve: Appearance.anim.curves.accelerate
    }

    NumberAnimation {
        id: listScroll

        target: list
        property: "contentY"
        duration: Appearance.anim.durations.normal
        easing.bezierCurve: root.bezierOut
    }

    MouseArea {
        anchors.fill: parent
        onClicked: PickerManager.close()
    }

    Item {
        id: panel

        width: root.panelWidth
        height: column.implicitHeight + 2 * root.pad
        x: (root.width - width) / 2
        y: Math.max(40, root.height * 0.12) + (1 - root.shown) * 24
        opacity: Math.min(1, root.shown * 1.6)
        scale: 0.95 + 0.05 * root.shown
        transformOrigin: Item.Top

        SoftShadow {
            panel: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: WalColors.withAlpha(WalColors.color0, 0.97)
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.09)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: searchInput.forceActiveFocus()
        }

        Column {
            id: column

            x: root.pad
            y: root.pad
            width: panel.width - 2 * root.pad

            Item {
                width: parent.width
                height: 44

                SearchField {
                    id: searchInput

                    anchors.left: parent.left
                    anchors.right: filterControl.left
                    anchors.rightMargin: 12
                    height: parent.height
                    placeholder: "Search trash…"
                    text: PickerManager.searchText
                    onTextChanged: PickerManager.searchText = text
                    onKeyPressed: (event) => {
                        // Ctrl+J/K = arrow down/up, the same in all pickers (PickerManager.navKey)
                        const key = PickerManager.navKey(event);
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0 && key === event.key;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        event.accepted = true;
                        if (key === Qt.Key_Escape) {
                            if (text !== "")
                                text = "";
                            else
                                PickerManager.close();
                        } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
                            // Standalone picker (not in the tab bundle): Tab switches its own
                            // tabs All/Files/Folders, like Ctrl+Left/Right
                            root.setFilter(root.cycle(["all", "files", "folders"], root.filter, shift || key === Qt.Key_Backtab ? -1 : 1));
                        } else if (key === Qt.Key_Down) {
                            root.move(1);
                        } else if (key === Qt.Key_Up) {
                            root.move(-1);
                        } else if (ctrl && key === Qt.Key_Left) {
                            root.setFilter(root.cycle(["all", "files", "folders"], root.filter, -1));
                        } else if (ctrl && key === Qt.Key_Right) {
                            root.setFilter(root.cycle(["all", "files", "folders"], root.filter, 1));
                        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                            root.restore(root.selectedEntry);
                        } else if (ctrl && key === Qt.Key_D) {
                            root.requestDelete(root.selectedEntry);
                        } else if (ctrl && key === Qt.Key_S) {
                            root.setSort(root.cycle(["date", "name", "size", "type"], root.sortKey, 1));
                        } else if (ctrl && key === Qt.Key_R) {
                            root.setSort(root.sortKey);
                        } else if (ctrl && key === Qt.Key_E) {
                            root.requestEmpty();
                        } else {
                            event.accepted = false;
                        }
                    }
                }

                PillSegmented {
                    id: filterControl

                    anchors.right: parent.right
                    height: parent.height
                    segW: 66
                    current: root.filter
                    options: [{
                        "key": "all",
                        "label": "All"
                    }, {
                        "key": "files",
                        "label": "Files"
                    }, {
                        "key": "folders",
                        "label": "Folders"
                    }]
                    onPicked: (key) => {
                        root.setFilter(key);
                        searchInput.forceActiveFocus();
                    }
                }

            }

            Item {
                width: parent.width
                height: 12 + sortTabs.height

                // Sorting as plain tabs as in the stats dropdown (gliding accent line), here without the
                // gray base line (on purpose). The active tab shows the direction; clicking again reverses
                // it (setSort).
                Dropdowns.Tabs {
                    id: sortTabs

                    y: 12
                    showLine: false
                    width: 4 * 68
                    current: root.sortKey
                    model: [["date", "Date"], ["name", "Name"], ["size", "Size"], ["type", "Type"]].map((t) => {
                        return {
                            "key": t[0],
                            "label": t[1] + (t[0] === root.sortKey ? (root.sortDesc ? " ↓" : " ↑") : "")
                        };
                    })
                    onSelected: (key) => {
                        root.setSort(key);
                        searchInput.forceActiveFocus();
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    y: 12
                    height: sortTabs.height
                    verticalAlignment: Text.AlignVCenter
                    text: root.visibleEntries.length + (root.visibleEntries.length === 1 ? " item" : " items") + "  ·  " + root.formatSize(root.shownBytes)
                    font.family: root.mono
                    font.pixelSize: 11
                    color: WalColors.withAlpha(WalColors.color7, 0.45)
                }

            }

            Item {
                id: listSection

                readonly property bool hasRows: root.visibleEntries.length > 0 || root.holdList

                width: parent.width
                height: hasRows ? 12 + Math.min((root.holdList ? root.heldRows : root.visibleEntries.length) * root.rowStride - root.rowGap, root.listMaxH) : 0
                visible: height > 0.5
                clip: true

                ListView {
                    id: list

                    y: 12
                    width: parent.width
                    height: Math.max(0, parent.height - 12)
                    cacheBuffer: 400
                    boundsBehavior: Flickable.StopAtBounds
                    onMovementStarted: listScroll.stop()

                    Rectangle {
                        parent: list.contentItem
                        z: -1
                        y: root.currentIndex * root.rowStride
                        width: list.width
                        height: root.rowH
                        radius: 16
                        color: WalColors.withAlpha(root.confirmId !== "" ? Theme.bad : WalColors.color4, 0.13)
                        opacity: root.visibleEntries.length > 0 ? 1 : 0

                        Behavior on y {
                            Springy {
                            }

                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                            }

                        }

                        Behavior on opacity {
                            Smooth {
                                duration: 160
                            }

                        }

                    }

                    model: ScriptModel {
                        values: root.visibleEntries
                        objectProp: "id"
                    }

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property var entry: modelData
                        readonly property bool selected: root.selectedId === entry.id && leaving === 0
                        readonly property bool confirming: root.confirmId === entry.id
                        property real enter: 1
                        property real leaving: 0

                        width: list.width
                        height: root.rowStride

                        Item {
                            width: parent.width
                            height: root.rowH
                            opacity: row.enter * (1 - row.leaving)
                            scale: rowMouse.pressed ? 0.985 : 1 - 0.04 * row.leaving

                            // A touch when leaving: accent color for restored, red for deleted. Subtle (before
                            // 40 % and a full flash, that felt glaring); comes right away and goes with the row
                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: WalColors.withAlpha(root.removeKind === "restore" ? WalColors.color4 : Theme.bad, 0.2)
                                opacity: root.removeKind === "filter" ? 0 : Math.min(1, row.leaving * 4)
                            }

                            Rectangle {
                                id: badge

                                anchors.left: parent.left
                                anchors.leftMargin: 11
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38
                                height: 38
                                radius: 12
                                color: row.selected ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.07)

                                Text {
                                    anchors.centerIn: parent
                                    text: root.glyphFor(row.entry.kind)
                                    font.family: root.mono
                                    font.pixelSize: 16
                                    color: row.selected ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.55)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.anim.durations.fast
                                        }

                                    }

                                }

                                Loader {
                                    anchors.fill: parent
                                    active: row.entry.kind === "image" && row.entry.ext !== "svg"

                                    sourceComponent: Item {
                                        Image {
                                            id: thumb

                                            anchors.fill: parent
                                            visible: false
                                            source: "file://" + TrashState.filesDir + "/" + row.entry.id
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize: Qt.size(76, 76)
                                        }

                                        Rectangle {
                                            id: thumbMask

                                            anchors.fill: parent
                                            radius: 12
                                            visible: false
                                        }

                                        OpacityMask {
                                            anchors.fill: parent
                                            source: thumb
                                            maskSource: thumbMask
                                            opacity: thumb.status === Image.Ready ? 1 : 0

                                            Behavior on opacity {
                                                Smooth {
                                                    duration: 320
                                                }

                                            }

                                        }

                                    }

                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                            }

                            Column {
                                anchors.left: badge.right
                                anchors.leftMargin: 12
                                anchors.right: rightArea.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: row.entry.name
                                    font.family: root.mono
                                    font.pixelSize: 13
                                    elide: Text.ElideMiddle
                                    color: row.selected ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.78)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.anim.durations.fast
                                        }

                                    }

                                }

                                Text {
                                    width: parent.width
                                    text: row.entry.place + (row.entry.isDir ? "  ·  " + row.entry.count + (row.entry.count === 1 ? " file" : " files") : "")
                                    font.family: root.mono
                                    font.pixelSize: 10
                                    elide: Text.ElideLeft
                                    color: WalColors.withAlpha(WalColors.color7, 0.38)
                                }

                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: (mouse) => {
                                    root.hoverSelect(rowMouse, mouse, row.index);
                                }
                                onClicked: {
                                    root.select(row.index);
                                    searchInput.forceActiveFocus();
                                }
                            }

                            // Size and age make way for the actions as soon as the row is selected
                            Item {
                                id: rightArea

                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: row.confirming ? 186 : 118
                                height: 30

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    opacity: row.selected ? 0 : 1
                                    visible: opacity > 0.01

                                    Text {
                                        text: root.formatSize(row.entry.size)
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        color: WalColors.withAlpha(WalColors.color7, 0.55)
                                    }

                                    Text {
                                        width: 26
                                        horizontalAlignment: Text.AlignRight
                                        text: root.formatAge(row.entry.ts)
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        color: WalColors.withAlpha(WalColors.color7, 0.32)
                                    }

                                    transform: Translate {
                                        x: row.selected ? -8 : 0

                                        Behavior on x {
                                            Smooth {
                                                duration: 200
                                            }

                                        }

                                    }

                                    Behavior on opacity {
                                        Smooth {
                                            duration: 140
                                        }

                                    }

                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    opacity: row.selected ? 1 : 0
                                    visible: opacity > 0.01

                                    ActionPill {
                                        glyph: ""
                                        label: "Restore"
                                        showLabel: !row.confirming
                                        visible: row.entry.origin !== ""
                                        onClicked: root.restore(row.entry)
                                    }

                                    ActionPill {
                                        glyph: ""
                                        label: "Delete forever"
                                        showLabel: row.confirming
                                        danger: true
                                        armed: row.confirming
                                        onClicked: root.requestDelete(row.entry)
                                    }

                                    transform: Translate {
                                        x: row.selected ? 0 : 10

                                        Behavior on x {
                                            Springy {
                                            }

                                        }

                                    }

                                    Behavior on opacity {
                                        Smooth {
                                            duration: 160
                                        }

                                    }

                                }

                                Behavior on width {
                                    Springy {
                                    }

                                }

                            }

                            transform: Translate {
                                x: row.leaving * (root.removeKind === "restore" ? 56 : root.removeKind === "delete" ? -56 : 0)
                                y: (1 - row.enter) * 14 + row.leaving * (root.removeKind === "empty" ? 44 : root.removeKind === "restore" ? -10 : 0)
                            }

                            Behavior on scale {
                                Springy {
                                }

                            }

                        }

                    }

                    populate: Transition {
                        id: populateTransition

                        SequentialAnimation {
                            PropertyAction {
                                property: "enter"
                                value: 0
                            }

                            PauseAnimation {
                                duration: Math.min(Math.max(0, populateTransition.ViewTransition.index), 9) * 30 + 60
                            }

                            NumberAnimation {
                                property: "enter"
                                to: 1
                                duration: 460
                                easing.bezierCurve: root.bezierOut
                            }

                        }

                    }

                    add: Transition {
                        id: addTransition

                        SequentialAnimation {
                            PropertyAction {
                                property: "enter"
                                value: 0
                            }

                            PauseAnimation {
                                duration: root.intro ? Math.min(Math.max(0, addTransition.ViewTransition.index), 9) * 30 + 60 : 0
                            }

                            NumberAnimation {
                                property: "enter"
                                to: 1
                                duration: 320
                                easing.bezierCurve: root.bezierOut
                            }

                        }

                    }

                    remove: Transition {
                        id: removeTransition

                        SequentialAnimation {
                            // When emptying, one row after the other falls into the bin from top to bottom
                            PauseAnimation {
                                duration: root.removeKind === "empty" ? Math.min(Math.max(0, removeTransition.ViewTransition.index - list.indexAt(0, list.contentY)), 8) * 42 : 0
                            }

                            // Swipe away: accelerating out (delete/restore), otherwise soft
                            NumberAnimation {
                                property: "leaving"
                                to: 1
                                duration: root.removeKind === "filter" ? 140 : root.removeKind === "empty" ? 340 : 240
                                easing.bezierCurve: root.removeKind === "delete" || root.removeKind === "restore" ? Appearance.anim.curves.accelerate : [0.4, 0, 0.6, 1, 1, 1]
                            }

                        }

                    }

                    move: GlideTransition {
                    }

                    moveDisplaced: GlideTransition {
                    }

                    // The gap only closes when the row is almost gone: before, the next row moved up
                    // right away and lay over the still visible one (texts on top of each other)
                    removeDisplaced: GlideTransition {
                        delay: root.removeKind === "delete" || root.removeKind === "restore" ? 220 : 0
                    }

                    addDisplaced: GlideTransition {
                    }

                    displaced: GlideTransition {
                    }

                }

                // Mouse wheel: one notch = exactly one row (like the clipboard's image strip). Own
                // MouseArea that only takes the wheel, so clicks and hover arrive at the rows; a
                // WheelHandler with PointerDevice.Mouse never arrives with some mice. Touchpad: 60 px of travel = one
                // row, fine movement is collected.
                MouseArea {
                    property real pending: 0

                    anchors.fill: list
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        // Detect a touchpad by the scroll phase: the mouse wheel also sends pixel values here
                        const touchpad = wheel.phase !== Qt.NoScrollPhase;
                        const d = touchpad ? wheel.pixelDelta.y : wheel.angleDelta.y;
                        const unit = touchpad ? 60 : 120;
                        if (d === 0)
                            return ;

                        if (pending !== 0 && Math.sign(pending) !== Math.sign(d))
                            pending = 0;

                        pending += d;
                        const steps = Math.trunc(pending / unit);
                        if (steps === 0)
                            return ;

                        pending -= steps * unit;
                        // Wheel up (steps > 0) = list up
                        root.scrollRows(-steps);
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    // Only as high as the empty margin below the text of the last row, otherwise it looks
                    // cut off again
                    height: 16
                    opacity: list.contentY + list.height < root.visibleEntries.length * root.rowStride - root.rowGap - 4 ? 1 : 0

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: WalColors.withAlpha(WalColors.color0, 0)
                        }

                        GradientStop {
                            position: 1
                            color: WalColors.withAlpha(WalColors.color0, 0.9)
                        }

                    }

                    Behavior on opacity {
                        Smooth {
                            duration: 200
                        }

                    }

                }

                Behavior on height {
                    Smooth {
                    }

                }

            }

            Item {
                width: parent.width
                height: root.isEmpty ? 190 : 0
                opacity: root.isEmpty ? 1 : 0
                visible: height > 0.5
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    TrashCan {
                        id: bigCan

                        anchors.horizontalCenter: parent.horizontalCenter
                        size: 54
                        tint: WalColors.withAlpha(WalColors.color7, 0.28)
                        lid: TrashState.emptying ? 34 : 0

                        SequentialAnimation on floatY {
                            running: root.isEmpty && root.visible
                            loops: Animation.Infinite

                            NumberAnimation {
                                to: -4
                                duration: 1700
                                easing.type: Easing.InOutSine
                            }

                            NumberAnimation {
                                to: 0
                                duration: 1700
                                easing.type: Easing.InOutSine
                            }

                        }

                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: TrashState.emptying ? "Emptying…" : (TrashState.entries.length === 0 ? "Trash is empty" : "Nothing found")
                        font.family: root.mono
                        font.pixelSize: 12
                        color: WalColors.withAlpha(WalColors.color7, 0.38)
                    }

                }

                Behavior on height {
                    Smooth {
                    }

                }

                Behavior on opacity {
                    Smooth {
                        duration: 220
                    }

                }

            }

            Item {
                width: parent.width
                height: 12 + 32

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.right: emptyButton.left
                    anchors.rightMargin: 12
                    y: 12
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                    text: TrashState.message
                    font.family: root.mono
                    font.pixelSize: 10
                    color: TrashState.messageIsError ? Theme.bad : WalColors.color4

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }

                    }

                }

                Rectangle {
                    id: emptyButton

                    readonly property bool enabledNow: TrashState.entries.length > 0 && !TrashState.emptying

                    anchors.right: parent.right
                    y: 12
                    width: emptyRow.implicitWidth + 26
                    height: 32
                    radius: height / 2
                    clip: true
                    color: root.confirmEmpty ? WalColors.withAlpha(Theme.bad, 0.14) : WalColors.withAlpha(WalColors.color7, emptyArea.containsMouse && enabledNow ? 0.12 : 0.06)
                    opacity: enabledNow || TrashState.emptying ? 1 : 0.45
                    scale: emptyArea.pressed && enabledNow ? 0.95 : 1

                    // When the confirmation runs out, the bar melts: so you see how long it still holds
                    Rectangle {
                        id: countdownBar

                        property real fill: 1

                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * fill
                        radius: parent.radius
                        color: WalColors.withAlpha(Theme.bad, 0.28)
                        visible: root.confirmEmpty
                    }

                    Row {
                        id: emptyRow

                        anchors.centerIn: parent
                        spacing: 8

                        TrashCan {
                            id: footerCan

                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                            tint: root.confirmEmpty ? Theme.bad : WalColors.withAlpha(WalColors.color7, 0.7)
                            lid: TrashState.emptying || root.confirmEmpty ? 34 : (emptyArea.containsMouse && emptyButton.enabledNow ? 22 : 0)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: TrashState.emptying ? "Emptying…" : (root.confirmEmpty ? "Click again to empty" : "Empty trash")
                            font.family: root.mono
                            font.pixelSize: 11
                            color: root.confirmEmpty ? Theme.bad : WalColors.withAlpha(WalColors.color7, 0.7)

                            Behavior on color {
                                ColorAnimation {
                                    duration: 160
                                }

                            }

                        }

                    }

                    MouseArea {
                        id: emptyArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: emptyButton.enabledNow ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.requestEmpty();
                            searchInput.forceActiveFocus();
                        }
                    }

                    Behavior on width {
                        Springy {
                        }

                    }

                    Behavior on scale {
                        Springy {
                        }

                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 160
                        }

                    }

                }

            }

        }

    }

    component GlideTransition: Transition {
        property int delay: 0

        SequentialAnimation {
            PauseAnimation {
                duration: delay
            }

            NumberAnimation {
                properties: "x,y"
                duration: 380
                easing.bezierCurve: root.bezierOut
            }

        }

    }

    component ActionPill: Rectangle {
        id: pill

        property string glyph: ""
        property string label: ""
        property bool showLabel: false
        property bool danger: false
        property bool armed: false
        readonly property color accent: danger ? Theme.bad : WalColors.color4

        signal clicked()

        implicitWidth: pillRow.implicitWidth + 18
        width: implicitWidth
        height: 28
        radius: height / 2
        clip: true
        color: armed || pillArea.containsMouse ? WalColors.withAlpha(accent, 0.9) : WalColors.withAlpha(WalColors.color7, 0.09)
        scale: pillArea.pressed ? 0.92 : 1

        Row {
            id: pillRow

            anchors.centerIn: parent
            spacing: pill.showLabel ? 6 : 0

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.glyph
                font.family: root.mono
                font.pixelSize: 12
                color: pill.armed || pillArea.containsMouse ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.7)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.showLabel
                text: pill.label
                font.family: root.mono
                font.pixelSize: 11
                color: pill.armed || pillArea.containsMouse ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.7)
            }

        }

        MouseArea {
            id: pillArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }

        Behavior on width {
            Springy {
            }

        }

        Behavior on scale {
            Springy {
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 130
            }

        }

    }

    // Bin made of rectangles (no font icon): this way the lid can really open
    component TrashCan: Item {
        id: can

        property real size: 16
        property color tint: WalColors.color7
        property real lid: 0
        property real floatY: 0
        property real flapAngle: 0
        property real dip: 0
        readonly property real stroke: Math.max(1.3, size * 0.075)

        function flap() {
            flapAnim.restart();
        }

        width: size
        height: size

        Item {
            anchors.fill: parent

            Rectangle {
                x: can.size * 0.19
                y: can.size * 0.3
                width: can.size * 0.62
                height: can.size * 0.66
                radius: can.size * 0.1
                color: "transparent"
                border.width: can.stroke
                border.color: can.tint

                Repeater {
                    model: can.size > 30 ? 3 : 0

                    Rectangle {
                        required property int index

                        x: parent.width * (0.27 + index * 0.23) - width / 2
                        y: parent.height * 0.22
                        width: can.stroke
                        height: parent.height * 0.56
                        radius: width / 2
                        color: can.tint
                    }

                }

            }

            Item {
                anchors.fill: parent

                Rectangle {
                    x: can.size * 0.08
                    y: can.size * 0.17
                    width: can.size * 0.84
                    height: can.stroke
                    radius: height / 2
                    color: can.tint
                }

                Rectangle {
                    x: can.size * 0.36
                    y: can.size * 0.04
                    width: can.size * 0.28
                    height: can.size * 0.14
                    radius: can.size * 0.05
                    color: "transparent"
                    border.width: can.stroke
                    border.color: can.tint
                }

                transform: Rotation {
                    origin.x: can.size * 0.92
                    origin.y: can.size * 0.2
                    angle: Math.max(can.lid, can.flapAngle)
                }

            }

            transform: Translate {
                y: can.floatY + can.dip
            }

        }

        SequentialAnimation {
            id: flapAnim

            ParallelAnimation {
                NumberAnimation {
                    target: can
                    property: "flapAngle"
                    to: 38
                    duration: 110
                    easing.type: Easing.OutQuad
                }

                NumberAnimation {
                    target: can
                    property: "dip"
                    to: 1.5
                    duration: 110
                }

            }

            PauseAnimation {
                duration: 110
            }

            ParallelAnimation {
                NumberAnimation {
                    target: can
                    property: "flapAngle"
                    to: 0
                    duration: 380
                    easing.type: Easing.OutBounce
                }

                NumberAnimation {
                    target: can
                    property: "dip"
                    to: 0
                    duration: Appearance.anim.durations.normal
                    easing.type: Easing.OutBack
                }

            }

        }

        Behavior on lid {
            Springy {
            }

        }

    }

    Behavior on shownBytes {
        NumberAnimation {
            duration: 520
            easing.bezierCurve: root.bezierOut
        }

    }

}
