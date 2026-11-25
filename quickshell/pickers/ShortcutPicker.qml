pragma ComponentBehavior: Bound

import "../common"
import "../services"
import "./parts"
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    readonly property bool active: PickerManager.isOpen("shortcuts")
    readonly property var results: ShortcutState.search(searchField.text)
    // List with a heading per section. A heading takes up a whole row slot: this way the
    // math with a fixed row height (rowStride) stays valid for selection, scrolling and whole rows.
    readonly property var rows: {
        const counts = {};
        for (const entry of results)
            counts[entry.category] = (counts[entry.category] || 0) + 1;

        const out = [];
        let last = null;
        for (const entry of results) {
            if (entry.category !== last) {
                last = entry.category;
                out.push({
                    "header": true,
                    "category": entry.category,
                    "count": counts[entry.category]
                });
            }
            out.push(entry);
        }
        return out;
    }
    property int copiedIndex: -1
    readonly property string copied: isEntry(copiedIndex) ? "Copied " + rows[copiedIndex].combo : ""
    property point lastHoverPosition: Qt.point(-1, -1)
    property real shown: 0
    property bool introRows: false

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    function isEntry(index) {
        return index >= 0 && index < rows.length && rows[index].header !== true;
    }

    function resetSelection() {
        wheelScroll.stop();
        rowWheel.pendingDelta = 0;
        // The first row is a heading -> selection on the first entry below it
        let first = 0;
        while (first < list.count && !isEntry(first))
            ++first;
        list.currentIndex = first < list.count ? first : -1;
        list.positionViewAtBeginning();
    }

    function scrollTo(y) {
        const top = list.originY;
        const bottom = top + Math.max(0, list.contentHeight - list.height);
        const target = Math.max(top, Math.min(y, bottom));
        wheelScroll.stop();
        if (Math.abs(target - list.contentY) < 0.5)
            return;

        wheelScroll.to = target;
        wheelScroll.start();
    }

    function moveSelection(step) {
        if (list.count === 0)
            return;

        wheelScroll.stop();
        // Skip headings; at the edge the selection stays
        let next = list.currentIndex + step;
        while (next >= 0 && next < list.count && !isEntry(next))
            next += step;
        if (next < 0 || next >= list.count)
            return;

        list.currentIndex = next;
        const top = list.originY + next * list.rowStride;
        // First entry of a section: bring the heading above it into view too
        const shownTop = isEntry(next - 1) ? top : top - list.rowStride;
        scrollTo(Math.max(top + list.rowHeight - list.height, Math.min(shownTop, list.contentY)));
    }

    function copyShortcut(index) {
        if (!isEntry(index))
            return;

        const entry = rows[index];

        Quickshell.execDetached(["wl-copy", "--", entry.combo]);
        copiedIndex = index;
        copyFeedback.restart();
    }

    function loadShortcuts() {
        if (!active)
            return;

        searchField.text = "";
        copiedIndex = -1;
        lastHoverPosition = Qt.point(-1, -1);
        introRows = true;
        panelIntro.restart();
        ShortcutState.refresh();
    }

    onActiveChanged: {
        if (active)
            Qt.callLater(root.loadShortcuts);
    }

    Component.onCompleted: {
        if (active)
            Qt.callLater(root.loadShortcuts);
    }

    Connections {
        target: ShortcutState

        function onStatusChanged() {
            if (ShortcutState.status === "loading")
                root.copiedIndex = -1;
            else if (root.introRows)
                introTimer.restart();
        }
    }

    Timer {
        id: introTimer

        interval: 700
        onTriggered: root.introRows = false
    }

    Smooth {
        id: panelIntro

        target: root
        property: "shown"
        from: 0
        to: 1
        duration: 520
    }

    Timer {
        id: copyFeedback

        interval: 900
        onTriggered: root.copiedIndex = -1
    }

    MouseArea {
        anchors.fill: parent
        onClicked: PickerManager.close()
    }

    Item {
        id: panel

        readonly property real restY: Math.max(Theme.px(40), root.height * 0.12)

        width: Math.min(Theme.px(680), Math.max(0, root.width - Theme.px(48)))
        height: Math.max(0, Math.min(Theme.px(600), root.height - restY - Theme.px(24)))
        anchors.horizontalCenter: parent.horizontalCenter
        y: restY + (1 - root.shown) * Theme.px(24)
        opacity: Math.min(1, root.shown * 1.6)
        scale: 0.95 + 0.05 * root.shown
        transformOrigin: Item.Top

        SoftShadow {
            panel: true
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXL
            color: WalColors.withAlpha(WalColors.color0, 0.97)
            border.color: Theme.stroke
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.focusSearch()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padX
            spacing: Theme.gap

            // Header without a close button (on purpose): Esc or a click next to the panel closes
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.gapSmall
                Layout.rightMargin: Theme.gapSmall
                spacing: Theme.gapSmall

                Text {
                    Layout.fillWidth: true
                    text: "Shortcuts"
                    font.family: Theme.fontDisplay
                    font.pixelSize: Theme.px(25)
                    color: Theme.text
                    elide: Text.ElideRight
                }

                // Copy confirmation: a star fires before "Copied ..." (star birth as in the clipboard, visual language)
                StarBurst {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: Theme.px(3)
                    size: 4.5
                    active: root.copied !== ""
                    visible: root.copied !== ""
                }

                Text {
                    Layout.maximumWidth: panel.width * 0.43
                    visible: ShortcutState.status === "ready" && (root.copied !== "" || panel.width >= Theme.px(310))
                    text: root.copied || (root.results.length === 1 ? "1 shortcut" : root.results.length + " shortcuts")
                    textFormat: Text.PlainText
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                    font.features: Theme.tabular
                    color: root.copied ? Theme.accent : Theme.textDim
                    elide: Text.ElideRight
                }
            }

            SearchField {
                id: searchField

                objectName: "shortcutsSearch"
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(42)
                placeholder: text === "" ? "Search by action or key…" : ""
                placeholderElide: true
                focusOnStart: false
                Component.onCompleted: input.Accessible.name = "Search shortcuts"
                onTextChanged: {
                    root.copiedIndex = -1;
                    root.introRows = false;
                    Qt.callLater(root.resetSelection);
                }
                onKeyPressed: event => {
                    const key = PickerManager.navKey(event);
                    event.accepted = true;
                    switch (key) {
                    case Qt.Key_Escape:
                        if (text.length > 0)
                            text = "";
                        else
                            PickerManager.close();
                        break;
                    case Qt.Key_Down:
                        root.moveSelection(1);
                        break;
                    case Qt.Key_Up:
                        root.moveSelection(-1);
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.copyShortcut(list.currentIndex);
                        break;
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab:
                        break;
                    default:
                        event.accepted = false;
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    visible: ShortcutState.status !== "ready" || list.count === 0
                    width: parent.width - Theme.gap
                    anchors.centerIn: parent
                    spacing: Theme.gapSmall

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            if (ShortcutState.status === "loading")
                                return "Loading shortcuts…";
                            if (ShortcutState.status === "error")
                                return "Couldn’t read Hyprland shortcuts.";

                            return searchField.text.trim() ? "No matching shortcuts" : "No shortcuts found";
                        }
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeLarge
                        color: Theme.textDim
                    }

                    RoundButton {
                        visible: ShortcutState.status === "error"
                        Layout.alignment: Qt.AlignHCenter
                        glyph: "󰑐"
                        Accessible.role: Accessible.Button
                        Accessible.name: "Retry loading shortcuts"
                        Accessible.onPressAction: ShortcutState.refresh()
                        onClicked: ShortcutState.refresh()
                    }
                }

                ListView {
                    id: list

                    readonly property int rowHeight: Theme.px(44)
                    readonly property real rowStride: rowHeight + spacing
                    readonly property int visibleRows: Math.floor((parent.height + spacing) / rowStride)

                    objectName: "shortcutsList"
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    // Only show complete rows, even if the screen height limits the panel.
                    height: visibleRows > 0 ? visibleRows * rowStride - spacing : parent.height
                    visible: ShortcutState.status === "ready"
                    model: ShortcutState.status === "ready" ? root.rows : []
                    spacing: Theme.px(3)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationWraps: false
                    highlightFollowsCurrentItem: false
                    onCountChanged: root.resetSelection()
                    onMovementStarted: wheelScroll.stop()

                    NumberAnimation {
                        id: wheelScroll

                        target: list
                        property: "contentY"
                        duration: Appearance.anim.durations.fast
                        easing.type: Easing.OutCubic
                    }

                    highlight: Rectangle {
                        y: list.originY + Math.max(0, list.currentIndex) * list.rowStride
                        width: list.width - Theme.px(8)
                        height: list.rowHeight
                        radius: Theme.px(16)
                        color: WalColors.withAlpha(WalColors.color4, 0.13)
                        opacity: list.currentIndex >= 0 && list.currentItem ? list.currentItem.enter : 0

                        Behavior on y {
                            enabled: list.count > 0
                            Springy {
                            }
                        }
                    }

                    Controls.ScrollBar.vertical: Controls.ScrollBar {
                        policy: Controls.ScrollBar.AsNeeded
                        width: Theme.px(4)
                        padding: 0
                        contentItem: Rectangle {
                            implicitHeight: Theme.px(22)
                            radius: width / 2
                            color: Theme.textDim
                        }
                    }

                    delegate: Item {
                        id: row

                        required property int index
                        required property var modelData
                        readonly property bool isHeader: modelData.header === true
                        readonly property bool selected: ListView.isCurrentItem
                        property real enter: 1
                        readonly property bool splitCaps: !isHeader && width >= Theme.px(470)
                            && modelData.keys.length <= 4 && modelData.keys.join("").length <= 26

                        width: list.width - Theme.px(8)
                        height: list.rowHeight
                        opacity: enter
                        Accessible.role: isHeader ? Accessible.Heading : Accessible.Button
                        Accessible.name: isHeader ? modelData.category : modelData.title + ", " + modelData.combo
                        Accessible.description: isHeader ? "" : "Copy shortcut"
                        Accessible.onPressAction: root.copyShortcut(row.index)

                        Component.onCompleted: {
                            if (root.introRows && index < list.visibleRows && !wheelScroll.running && !list.moving) {
                                enter = 0;
                                rowIntro.start();
                            }
                        }

                        SequentialAnimation {
                            id: rowIntro

                            PauseAnimation {
                                duration: Math.min(Math.max(0, row.index), 9) * 30 + 60
                            }

                            Smooth {
                                target: row
                                property: "enter"
                                to: 1
                                duration: 460
                            }
                        }

                        // Section heading: at the bottom of the row slot, close to its entries
                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.gap
                            anchors.rightMargin: Theme.gap
                            visible: row.isHeader

                            transform: Translate {
                                y: (1 - row.enter) * Theme.px(12)
                            }

                            Text {
                                id: headerLabel

                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Theme.px(6)
                                text: row.isHeader ? row.modelData.category.toUpperCase() : ""
                                textFormat: Text.PlainText
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.2
                                color: Theme.textDim
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.baseline: headerLabel.baseline
                                text: row.isHeader ? row.modelData.count : ""
                                textFormat: Text.PlainText
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                                font.features: Theme.tabular
                                color: Theme.textFaint
                            }
                        }

                        // Copy flash: fast on, soft off after 0.9 s (as in the clipboard picker)
                        Rectangle {
                            id: copyGlow

                            property real k: 0
                            readonly property bool on: root.copiedIndex === row.index

                            anchors.fill: parent
                            radius: Theme.px(16)
                            color: WalColors.withAlpha(WalColors.color4, 0.3)
                            opacity: k
                            visible: k > 0.01
                            // Imperative: a Behavior with changing duration/curve still took the old one at start
                            onOnChanged: {
                                glowAnim.stop();
                                glowAnim.to = on ? 1 : 0;
                                glowAnim.duration = on ? 120 : 750;
                                glowAnim.easing.type = on ? Easing.OutCubic : Easing.InOutSine;
                                glowAnim.start();
                            }

                            NumberAnimation {
                                id: glowAnim

                                target: copyGlow
                                property: "k"
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.gap
                            anchors.rightMargin: Theme.gap
                            visible: !row.isHeader
                            spacing: Theme.gapSmall
                            scale: rowMouse.pressed ? 0.985 : 1

                            transform: Translate {
                                y: (1 - row.enter) * Theme.px(12)
                            }

                            Behavior on scale {
                                Springy {
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: Theme.px(2)

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.title || ""
                                    textFormat: Text.PlainText
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.sizeLarge
                                    font.weight: Font.DemiBold
                                    color: row.selected ? Theme.text : WalColors.withAlpha(Theme.text, 0.72)
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        ColorAnimation { duration: Appearance.anim.durations.fast }
                                    }
                                }

                                // The section is already in the heading; only show a submap ("section · submap")
                                Text {
                                    Layout.fillWidth: true
                                    visible: !row.isHeader && row.modelData.context !== row.modelData.category
                                    text: visible ? row.modelData.context : ""
                                    textFormat: Text.PlainText
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.sizeSmall
                                    color: Theme.textDim
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: keycaps

                                Layout.maximumWidth: row.width * 0.55
                                Layout.preferredWidth: implicitWidth
                                spacing: Theme.px(4)
                                clip: true

                                Repeater {
                                    model: row.isHeader ? [] : (row.splitCaps ? row.modelData.keys : [row.modelData.combo])

                                    Rectangle {
                                        id: keycap

                                        required property string modelData

                                        width: Math.min(capText.implicitWidth + Theme.px(14), row.width * 0.55)
                                        height: Theme.px(25)
                                        radius: Theme.radiusXS
                                        color: row.selected ? WalColors.withAlpha(WalColors.color4, 0.2) : Theme.glass
                                        border.color: Theme.stroke

                                        Behavior on color {
                                            ColorAnimation { duration: Appearance.anim.durations.fast }
                                        }

                                        Text {
                                            id: capText

                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.px(7)
                                            anchors.rightMargin: Theme.px(7)
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: keycap.modelData
                                            textFormat: Text.PlainText
                                            font.family: Theme.font
                                            font.pixelSize: Theme.sizeBody
                                            color: row.selected ? Theme.accent : Theme.text
                                            elide: Text.ElideRight

                                            Behavior on color {
                                                ColorAnimation { duration: Appearance.anim.durations.fast }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse

                            anchors.fill: parent
                            enabled: !row.isHeader
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: mouse => {
                                // Scrolling moves the row under the mouse, not the pointer.
                                const position = row.mapToItem(null, mouse.x, mouse.y);
                                if (Math.abs(position.x - root.lastHoverPosition.x) < 3
                                    && Math.abs(position.y - root.lastHoverPosition.y) < 3)
                                    return;

                                root.lastHoverPosition = position;
                                if (!list.moving && !wheelScroll.running)
                                    list.currentIndex = row.index;
                            }
                            onClicked: {
                                list.currentIndex = row.index;
                                root.copyShortcut(row.index);
                                root.focusSearch();
                            }
                        }
                    }
                }

                // Mouse wheel: one notch = exactly one row (like the clipboard and the trash). Own MouseArea
                // next to the ListView that only takes the wheel (clicks and hover go to the rows). Before, a
                // WheelHandler with PointerDevice.Mouse: it never arrives with some mouse wheels (they report as a
                // touchpad), then the ListView scrolled itself with momentum and stopped between the rows.
                // Sibling instead of child: children of a Flickable end up in the contentItem and scroll along.
                MouseArea {
                    id: rowWheel

                    property real pendingDelta: 0

                    anchors.fill: list
                    acceptedButtons: Qt.NoButton
                    enabled: list.visible && list.contentHeight > list.height
                    onWheel: wheel => {
                        // Detect a touchpad by the scroll phase: the mouse wheel also sends pixel values here
                        const touchpad = wheel.phase !== Qt.NoScrollPhase;
                        const d = touchpad ? wheel.pixelDelta.y : wheel.angleDelta.y;
                        const unit = touchpad ? 60 : 120;
                        if (d === 0)
                            return;

                        if (pendingDelta !== 0 && Math.sign(pendingDelta) !== Math.sign(d))
                            pendingDelta = 0;

                        pendingDelta += d;
                        const steps = Math.trunc(pendingDelta / unit);
                        if (steps === 0)
                            return;

                        pendingDelta -= steps * unit;
                        // Keep counting from the running target, not from an intermediate position
                        const base = wheelScroll.running ? wheelScroll.to : list.contentY;
                        const firstRow = Math.round((base - list.originY) / list.rowStride);
                        root.scrollTo(list.originY + (firstRow - steps) * list.rowStride);
                    }
                }
            }
        }
    }
}
