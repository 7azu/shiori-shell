import "../common"
import "../services"
import "./parts"
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell

Item {
    id: root

    // ───────────────────────── Layout constants ─────────────────────────
    readonly property real pad: 16
    readonly property real bleed: 8
    readonly property real cardSize: 120
    readonly property real cardGap: 12
    readonly property real cardStride: cardSize + cardGap
    readonly property real rowH: 52
    readonly property real rowGap: 4
    readonly property real rowStride: rowH + rowGap
    readonly property real listMaxH: 6 * rowStride - rowGap
    readonly property real panelWidth: Math.min(680, width - 48)
    readonly property real innerWidth: panelWidth - 2 * pad
    readonly property string mono: Theme.font
    // ───────────────────────── State ─────────────────────────
    property string filter: "all"
    property string zone: "text"
    property int textIndex: 0
    property int imageIndex: 0
    property string flashId: ""
    property string dyingId: ""
    property bool confirmWipe: false
    property bool intro: true
    property real shown: 0
    property real lastMouseX: -1
    property real lastMouseY: -1
    // ───────────────────────── Data ─────────────────────────
    readonly property string needle: PickerManager.searchText.toLowerCase()
    readonly property var entries: ClipboardState.entries
    readonly property var allImages: entries.filter((e) => {
        return e.isImage && matches(e);
    }).slice(0, ClipboardState.imageLimit)
    readonly property var allTexts: entries.filter((e) => {
        return !e.isImage && matches(e);
    }).slice(0, ClipboardState.textLimit)
    readonly property bool showImages: filter !== "text" && allImages.length > 0
    readonly property bool showTexts: filter !== "images" && allTexts.length > 0
    readonly property bool isEmpty: ClipboardState.loaded && !showImages && !showTexts
    readonly property real textTotal: Math.max(0, allTexts.length * rowStride - rowGap)
    readonly property var filterModel: [{
        "key": "all",
        "label": "All"
    }, {
        "key": "text",
        "label": "Text"
    }, {
        "key": "images",
        "label": "Images"
    }]

    function matches(e) {
        return needle === "" || e.hay.indexOf(needle) !== -1;
    }

    function focusSearch() {
        searchInput.forceActiveFocus();
    }

    // ───────────────────────── Selection ─────────────────────────
    function normalizeZone() {
        if (zone === "images" && !showImages)
            zone = "text";
        else if (zone === "text" && !showTexts && showImages)
            zone = "images";
    }

    function clampSelection() {
        textIndex = Math.max(0, Math.min(textIndex, allTexts.length - 1));
        imageIndex = Math.max(0, Math.min(imageIndex, allImages.length - 1));
        normalizeZone();
    }

    function resetSelection() {
        listScroll.stop();
        stripScroll.stop();
        textIndex = 0;
        imageIndex = 0;
        textList.positionViewAtBeginning();
        strip.contentX = -strip.leftMargin;
        const fi = allImages.length > 0 ? entries.findIndex((e) => {
            return e.id === allImages[0].id;
        }) : 1e+09;
        const ft = allTexts.length > 0 ? entries.findIndex((e) => {
            return e.id === allTexts[0].id;
        }) : 1e+09;
        zone = (showImages && (!showTexts || fi < ft)) ? "images" : "text";
        if (ClipboardState.returnToId !== "")
            Qt.callLater(restoreReturnSelection);

    }

    // Back from the editor: stand on the image you came from again. When opening, the list may
    // still change (Save creates a new entry), so it looks for the id again every time
    function restoreReturnSelection() {
        const id = ClipboardState.returnToId;
        const i = allImages.findIndex((e) => {
            return String(e.id) === String(id);
        });
        if (i < 0)
            return ;

        zone = "images";
        imageIndex = i;
        scrollStripTo(i);
    }

    function setFilter(f) {
        if (filter === f)
            return ;

        filter = f;
        Qt.callLater(resetSelection);
    }

    function cycleFilter(dir) {
        const keys = ["all", "text", "images"];
        const i = keys.indexOf(filter);
        setFilter(keys[(i + dir + keys.length) % keys.length]);
    }

    function hoverSelect(target, mouse, zoneName, idx) {
        const p = target.mapToItem(null, mouse.x, mouse.y);
        if (Math.abs(p.x - lastMouseX) < 3 && Math.abs(p.y - lastMouseY) < 3)
            return ;

        lastMouseX = p.x;
        lastMouseY = p.y;
        zone = zoneName;
        if (zoneName === "text")
            textIndex = idx;
        else
            imageIndex = idx;
    }

    // ───────────────────────── Scrolling (animated) ─────────────────────────
    function animateListTo(y) {
        const minY = textList.originY;
        const maxY = minY + Math.max(0, textTotal - textList.height);
        listScroll.stop();
        const to = Math.max(minY, Math.min(y, maxY));
        if (Math.abs(to - textList.contentY) < 0.5)
            return ;

        listScroll.to = to;
        listScroll.start();
    }

    function animateStripTo(x) {
        const minX = -strip.leftMargin;
        const maxX = Math.max(minX, allImages.length * cardStride + strip.rightMargin - strip.width);
        const to = Math.max(minX, Math.min(x, maxX));
        const running = stripScroll.running;
        stripScroll.stop();
        if (!running && Math.abs(to - strip.contentX) < 0.5)
            return ;

        stripScroll.to = to;
        stripScroll.start();
    }

    function scrollTextTo(i) {
        const top = textList.originY + i * rowStride;
        const bottom = top + rowH;
        let to = textList.contentY;
        if (top < to)
            to = top;
        else if (bottom > to + textList.height)
            to = bottom - textList.height;
        animateListTo(to);
    }

    function scrollStripTo(i) {
        const left = i * cardStride;
        const right = left + cardSize;
        let to = strip.contentX;
        if (left - 10 < to)
            to = left - 10;
        else if (right + 10 > to + strip.width)
            to = right + 10 - strip.width;
        animateStripTo(to);
    }

    // ───────────────────────── Navigation ─────────────────────────
    function moveVertical(dir) {
        if (dir > 0) {
            if (zone === "images") {
                if (showTexts) {
                    zone = "text";
                    scrollTextTo(textIndex);
                }
            } else if (textIndex < allTexts.length - 1) {
                textIndex++;
                scrollTextTo(textIndex);
            }
        } else if (zone === "text") {
            if (textIndex > 0) {
                textIndex--;
                scrollTextTo(textIndex);
            } else if (showImages) {
                zone = "images";
                scrollStripTo(imageIndex);
            }
        }
    }

    function moveHorizontal(dir) {
        const n = imageIndex + dir;
        if (n >= 0 && n < allImages.length) {
            imageIndex = n;
            scrollStripTo(n);
        }
    }

    // ───────────────────────── Actions ─────────────────────────
    function currentEntry() {
        if (zone === "images" && showImages)
            return allImages[imageIndex];

        if (showTexts)
            return allTexts[textIndex];

        return undefined;
    }

    function copyItem(e) {
        ClipboardState.copyEntry(e);
        flashId = e.id;
        closeTimer.restart();
    }

    function openImage(e) {
        if (!ClipboardState.readyIds[e.id])
            return ;

        ClipboardState.openImage(e);
        PickerManager.close();
    }

    function activateCurrent(alt) {
        const e = currentEntry();
        if (!e)
            return ;

        if (e.isImage && !alt)
            openImage(e);
        else
            copyItem(e);
    }

    function commitDelete() {
        if (dyingId !== "") {
            ClipboardState.deleteEntry(dyingId);
            dyingId = "";
        }
    }

    function requestDelete(e) {
        if (dyingId !== "")
            commitDelete();

        dyingId = e.id;
        deleteTimer.restart();
    }

    function deleteCurrent() {
        const e = currentEntry();
        if (e)
            requestDelete(e);

    }

    function playIntro() {
        outroAnim.stop();
        intro = true;
        introTimer.restart();
        introAnim.restart();
        resetSelection();
    }

    // Closing: reverse of the intro (panel glides down, shrinks, fades out).
    // Called by PickerWindow, the window stays visible briefly for it.
    function playOutro() {
        introAnim.stop();
        outroAnim.restart();
    }

    Component.onCompleted: playIntro()
    onVisibleChanged: {
        if (visible)
            playIntro();

    }
    onAllTextsChanged: clampSelection()
    onAllImagesChanged: clampSelection()
    onEntriesChanged: {
        if (intro)
            Qt.callLater(resetSelection);

    }

    // ───────────────────────── Timers & animations ─────────────────────────
    Timer {
        id: introTimer

        interval: 700
        running: true
        onTriggered: {
            root.intro = false;
            ClipboardState.returnToId = "";
        }
    }

    Timer {
        id: closeTimer

        // Feedback duration only: after copying, the picker stays open.
        interval: 900
        onTriggered: root.flashId = ""
    }

    Timer {
        id: deleteTimer

        interval: 230
        onTriggered: root.commitDelete()
    }

    Timer {
        id: wipeTimer

        interval: 2600
        onTriggered: root.confirmWipe = false
    }

    NumberAnimation {
        id: introAnim

        target: root
        property: "shown"
        from: 0
        to: 1
        duration: 520
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    // Faster than the intro and accelerating (ease-in) -> feels snappy instead of sluggish
    NumberAnimation {
        id: outroAnim

        target: root
        property: "shown"
        to: 0
        duration: 200
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.accelerate
    }

    NumberAnimation {
        id: listScroll

        target: textList
        property: "contentY"
        duration: Appearance.anim.durations.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    NumberAnimation {
        id: stripScroll

        target: strip
        property: "contentX"
        duration: 340
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    Connections {
        function onSearchTextChanged() {
            Qt.callLater(root.resetSelection);
        }

        target: PickerManager
    }

    // Click outside the panel closes the picker.
    MouseArea {
        anchors.fill: parent
        onClicked: PickerManager.close()
    }

    // ═════════════════════════ Panel ═════════════════════════
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

        // Swallows clicks on the panel so the backdrop doesn't close it.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column

            x: root.pad
            y: root.pad
            width: root.innerWidth
            spacing: 0

            // ───────────── Header: search + filter ─────────────
            Item {
                id: header

                width: parent.width
                height: 44

                SearchField {
                    id: searchInput

                    anchors.left: parent.left
                    anchors.right: segmented.left
                    anchors.rightMargin: 12
                    height: parent.height
                    placeholder: "Search clipboard…"
                    text: PickerManager.searchText
                    onTextChanged: PickerManager.searchText = text
                    onKeyPressed: (event) => {
                        // Ctrl+J/K = arrow down/up, the same in all pickers (PickerManager.navKey)
                        const key = PickerManager.navKey(event);
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0 && key === event.key;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        switch (key) {
                        case Qt.Key_Escape:
                            if (text !== "")
                                text = "";
                            else
                                PickerManager.close();
                            event.accepted = true;
                            break;
                        case Qt.Key_Tab:
                        case Qt.Key_Backtab:
                            // Standalone picker (not in the tab bundle): Tab switches its own
                            // tabs All/Text/Images, like Ctrl+Left/Right
                            root.cycleFilter(shift || key === Qt.Key_Backtab ? -1 : 1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Down:
                            root.moveVertical(1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Up:
                            root.moveVertical(-1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Left:
                            if (ctrl) {
                                root.cycleFilter(-1);
                                event.accepted = true;
                            } else if (root.zone === "images" && root.showImages) {
                                root.moveHorizontal(-1);
                                event.accepted = true;
                            }
                            break;
                        case Qt.Key_Right:
                            if (ctrl) {
                                root.cycleFilter(1);
                                event.accepted = true;
                            } else if (root.zone === "images" && root.showImages) {
                                root.moveHorizontal(1);
                                event.accepted = true;
                            }
                            break;
                        // Ctrl+H/L = left/right in the image strip (as in the Read tab of the language picker).
                        // Local instead of in navKey: other pickers may use Ctrl+H/L differently
                        case Qt.Key_H:
                        case Qt.Key_L:
                            if (ctrl) {
                                if (root.zone === "images" && root.showImages)
                                    root.moveHorizontal(key === Qt.Key_L ? 1 : -1);

                                event.accepted = true;
                            }
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.activateCurrent(shift);
                            event.accepted = true;
                            break;
                        case Qt.Key_D:
                            if (ctrl) {
                                root.deleteCurrent();
                                event.accepted = true;
                            }
                            break;
                        }
                    }
                }

                // iOS-style segmented control with springy pill
                PillSegmented {
                    id: segmented

                    anchors.right: parent.right
                    height: parent.height
                    segW: 66
                    current: root.filter
                    options: root.filterModel
                    onPicked: (key) => {
                        root.setFilter(key);
                        searchInput.forceActiveFocus();
                    }
                }

            }

            // ───────────── Image strip ─────────────
            Item {
                id: imgSection

                x: -root.bleed
                width: parent.width + 2 * root.bleed
                height: root.showImages ? 14 + root.cardSize + 12 : 0
                opacity: root.showImages ? 1 : 0
                visible: height > 0.5
                clip: true

                ListView {
                    id: strip

                    y: 14
                    width: parent.width
                    height: root.cardSize + 12
                    orientation: ListView.Horizontal
                    leftMargin: root.bleed
                    rightMargin: root.bleed
                    spacing: 0
                    clip: true
                    currentIndex: root.imageIndex
                    cacheBuffer: 400
                    boundsBehavior: Flickable.StopAtBounds
                    onMovementStarted: stripScroll.stop()

                    // Sync instead of replace (key: cliphist id): while typing and with new
                    // entries the existing cards stay, including their loaded image
                    model: ScriptModel {
                        values: root.allImages
                        objectProp: "id"
                    }

                    delegate: Item {
                        id: card

                        required property var modelData
                        required property int index
                        readonly property var entry: modelData
                        readonly property bool selected: root.zone === "images" && root.imageIndex === index
                        readonly property bool ready: ClipboardState.readyIds[entry.id] === true
                        readonly property bool dying: root.dyingId === entry.id
                        readonly property bool flashing: root.flashId === entry.id
                        // 0..1: copy flash. Fast on, soft off (before: gone after 0.9 s in 0.14 s).
                        // Started imperatively: a Behavior with changing duration/curve still took the old one at start
                        property real flashK: 0

                        onFlashingChanged: {
                            cardFlash.stop();
                            cardFlash.to = flashing ? 1 : 0;
                            cardFlash.duration = flashing ? 120 : 750;
                            cardFlash.easing.type = flashing ? Easing.OutCubic : Easing.InOutSine;
                            cardFlash.start();
                        }

                        NumberAnimation {
                            id: cardFlash

                            target: card
                            property: "flashK"
                        }
                        property real enter: 1

                        width: dying ? 0 : root.cardStride
                        height: strip.height
                        opacity: enter
                        clip: dying
                        Component.onCompleted: {
                            if (root.intro) {
                                enter = 0;
                                enterAnim.start();
                            }
                        }

                        SequentialAnimation {
                            id: enterAnim

                            PauseAnimation {
                                duration: Math.min(Math.max(0, card.index), 8) * 35 + 60
                            }

                            NumberAnimation {
                                target: card
                                property: "enter"
                                to: 1
                                duration: 480
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.anim.curves.outQuint
                            }

                        }

                        Item {
                            id: body

                            anchors.verticalCenter: parent.verticalCenter
                            width: root.cardSize
                            height: root.cardSize
                            opacity: card.dying ? 0 : 1
                            scale: (card.selected ? 1.05 : 1) * (cardMouse.pressed ? 0.96 : 1)

                            // Placeholder until image is loaded
                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: WalColors.withAlpha(WalColors.color7, 0.07)

                                SequentialAnimation on opacity {
                                    running: !card.ready
                                    loops: Animation.Infinite

                                    NumberAnimation {
                                        to: 0.45
                                        duration: 800
                                        easing.type: Easing.InOutSine
                                    }

                                    NumberAnimation {
                                        to: 1
                                        duration: 800
                                        easing.type: Easing.InOutSine
                                    }

                                }

                            }

                            Image {
                                id: thumb

                                anchors.fill: parent
                                visible: false
                                source: card.ready ? "file://" + card.entry.path : ""
                                asynchronous: true
                                cache: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(260, 260)
                            }

                            Rectangle {
                                id: thumbMask

                                anchors.fill: parent
                                radius: 18
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: thumb
                                maskSource: thumbMask
                                opacity: thumb.status === Image.Ready ? 1 : 0

                                Behavior on opacity {
                                    Smooth {
                                        duration: 360
                                    }

                                }

                            }

                            // Selection ring
                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: "transparent"
                                border.width: 2
                                border.color: WalColors.color4
                                opacity: card.selected ? 1 : 0

                                Behavior on opacity {
                                    Smooth {
                                        duration: 180
                                    }

                                }

                            }

                            // Meta pill (resolution · size)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                width: metaText.implicitWidth + 10
                                height: 15
                                radius: height / 2
                                color: WalColors.withAlpha(WalColors.color0, 0.4)
                                opacity: card.selected && card.entry.meta !== "" ? 1 : 0
                                visible: opacity > 0.01

                                Text {
                                    id: metaText

                                    anchors.centerIn: parent
                                    text: card.entry.meta
                                    font.family: root.mono
                                    font.pixelSize: 8
                                    color: WalColors.withAlpha(WalColors.color7, 0.6)
                                }

                                Behavior on opacity {
                                    Smooth {
                                        duration: 180
                                    }

                                }

                            }

                            // Copy confirmation: a dark tinted surface on which a sparkle fires (star birth
                            // as when turning on an option in the Bluetooth picker, the shell's visual language). Dark instead of
                            // accent, so the bright star is visible on bright images too
                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: Qt.tint(WalColors.withAlpha(WalColors.color0, 0.62), WalColors.withAlpha(WalColors.vividAccent, 0.18))
                                opacity: card.flashK
                                visible: opacity > 0.01

                                StarBurst {
                                    anchors.centerIn: parent
                                    size: 11
                                    active: card.flashing
                                }

                            }

                            MouseArea {
                                id: cardMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onPositionChanged: (mouse) => {
                                    return root.hoverSelect(cardMouse, mouse, "images", card.index);
                                }
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.MiddleButton)
                                        root.requestDelete(card.entry);
                                    else if (mouse.button === Qt.RightButton)
                                        root.copyItem(card.entry);
                                    else
                                        root.openImage(card.entry);
                                }
                            }

                            Row {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                spacing: 0
                                opacity: card.selected && !card.flashing ? 1 : 0
                                visible: opacity > 0.01

                                IconButton {
                                    glyph: "✕"
                                    danger: true
                                    onClicked: root.requestDelete(card.entry)
                                }

                                Behavior on opacity {
                                    Smooth {
                                        duration: 160
                                    }

                                }

                            }

                            transform: Translate {
                                y: (1 - card.enter) * 16
                            }

                            Behavior on scale {
                                Springy {
                                }

                            }

                            Behavior on opacity {
                                Smooth {
                                    duration: 180
                                }

                            }

                        }

                        Behavior on width {
                            Smooth {
                                duration: 240
                            }

                        }

                    }

                }

                // Wheel over the strip: own MouseArea above the ListView that only takes the wheel
                // (no keys, no hover -> clicks and hover go on to the cards below).
                // A WheelHandler in the ListView never arrived, a vertical wheel never moved the strip.
                // One scroll step = exactly one card, snapped to the card borders. Fine events
                // (high-resolution wheels, touchpad) are collected until a whole step is reached.
                MouseArea {
                    property real pending: 0

                    anchors.fill: strip
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        // Detect a touchpad by the scroll phase, not by pixelDelta or the device type: under
                        // Wayland the mouse wheel also sends pixel values (-15 per notch) and Qt reports the mouse as
                        // "TouchPad" (measured). Only real swiping has Begin/Update/End.
                        const touchpad = wheel.phase !== Qt.NoScrollPhase;
                        const v = touchpad ? wheel.pixelDelta : wheel.angleDelta;
                        const d = Math.abs(v.x) > Math.abs(v.y) ? v.x : v.y;
                        // One step = 120 (one notch) or 60 px of touchpad travel
                        const unit = touchpad ? 60 : 120;
                        if (d === 0)
                            return;
                        // Change of direction: discard what was collected
                        if (pending !== 0 && Math.sign(pending) !== Math.sign(d))
                            pending = 0;
                        pending += d;
                        const steps = Math.trunc(pending / unit);
                        if (steps === 0)
                            return;

                        pending -= steps * unit;
                        // Keep counting from the snapped target card (not from an intermediate position)
                        const base = stripScroll.running ? stripScroll.to : strip.contentX;
                        // To the next card border in scroll direction (steps > 0 = wheel up = to the left)
                        const pos = (base + strip.leftMargin) / root.cardStride;
                        const first = steps < 0 ? Math.floor(pos + 0.02) : Math.ceil(pos - 0.02);
                        root.animateStripTo(-strip.leftMargin + (first - steps) * root.cardStride);
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

            // ───────────── Text list ─────────────
            Item {
                id: textSection

                width: parent.width
                height: root.showTexts ? 14 + Math.min(root.textTotal, root.listMaxH) : 0
                opacity: root.showTexts ? 1 : 0
                visible: height > 0.5
                clip: true

                ListView {
                    id: textList

                    y: 14
                    width: parent.width
                    height: Math.max(0, textSection.height - 14)
                    spacing: root.rowGap
                    clip: true
                    snapMode: ListView.SnapToItem
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: root.textIndex
                    cacheBuffer: 400
                    highlightFollowsCurrentItem: false
                    onMovementStarted: listScroll.stop()

                    model: ScriptModel {
                        values: root.allTexts
                        objectProp: "id"
                    }

                    // Single selection pill that slides to current row via spring.
                    highlight: Rectangle {
                        y: textList.originY + root.textIndex * root.rowStride
                        width: textList.width
                        height: root.rowH
                        radius: 16
                        color: WalColors.withAlpha(WalColors.color4, 0.13)
                        opacity: root.zone === "text" ? 1 : 0

                        Behavior on y {
                            Springy {
                            }

                        }

                        Behavior on opacity {
                            Smooth {
                                duration: 160
                            }

                        }

                    }

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property var entry: modelData
                        readonly property bool selected: root.zone === "text" && root.textIndex === index
                        readonly property bool dying: root.dyingId === entry.id
                        readonly property bool flashing: root.flashId === entry.id
                        // 0..1: copy flash. Fast on, soft off (before: gone after 0.9 s in 0.14 s).
                        // Started imperatively: a Behavior with changing duration/curve still took the old one at start
                        property real flashK: 0

                        onFlashingChanged: {
                            rowFlash.stop();
                            rowFlash.to = flashing ? 1 : 0;
                            rowFlash.duration = flashing ? 120 : 750;
                            rowFlash.easing.type = flashing ? Easing.OutCubic : Easing.InOutSine;
                            rowFlash.start();
                        }

                        NumberAnimation {
                            id: rowFlash

                            target: row
                            property: "flashK"
                        }
                        property real enter: 1

                        width: textList.width
                        height: dying ? 0 : root.rowH
                        opacity: enter
                        clip: dying
                        Component.onCompleted: {
                            if (root.intro) {
                                enter = 0;
                                rowEnter.start();
                            }
                        }

                        SequentialAnimation {
                            id: rowEnter

                            PauseAnimation {
                                duration: Math.min(Math.max(0, row.index), 9) * 30 + 60
                            }

                            NumberAnimation {
                                target: row
                                property: "enter"
                                to: 1
                                duration: 460
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.anim.curves.outQuint
                            }

                        }

                        Item {
                            id: rowBody

                            width: parent.width
                            height: root.rowH
                            opacity: row.dying ? 0 : 1
                            scale: rowMouse.pressed ? 0.985 : 1

                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: WalColors.withAlpha(WalColors.color4, 0.3)
                                opacity: row.flashK
                                visible: opacity > 0.01

                            }

                            // Type badge: color swatch, link, or text
                            Rectangle {
                                id: badge

                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 34
                                radius: 11
                                color: row.selected ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.07)

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    radius: 6
                                    visible: row.entry.kind === "color"
                                    color: row.entry.kind === "color" ? row.entry.label : "transparent"
                                    border.width: 1
                                    border.color: WalColors.withAlpha(WalColors.color7, 0.25)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: row.entry.kind !== "color"
                                    text: row.entry.kind === "url" ? "//" : "Aa"
                                    font.family: root.mono
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: row.selected ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.5)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.anim.durations.fast
                                        }

                                    }

                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                            }

                            Text {
                                anchors.left: badge.right
                                anchors.leftMargin: 12
                                anchors.right: rightArea.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.entry.label
                                font.family: root.mono
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                wrapMode: Text.NoWrap
                                color: row.selected ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.72)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onPositionChanged: (mouse) => {
                                    return root.hoverSelect(rowMouse, mouse, "text", row.index);
                                }
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.MiddleButton)
                                        root.requestDelete(row.entry);
                                    else
                                        root.copyItem(row.entry);
                                }
                            }

                            Row {
                                id: rightArea

                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                // Copy confirmation: a small star fires before "Copied" (as with the images)
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    // fades with the flash
                                    opacity: row.flashK
                                    visible: opacity > 0.01
                                    // Room for the horizontal ray of the star (reaches beyond its width)
                                    spacing: 9

                                    StarBurst {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 4.5
                                        active: row.flashing
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Copied"
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: WalColors.color4
                                    }

                                }

                                IconButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 20
                                    glyph: "✕"
                                    danger: true
                                    opacity: row.selected && !row.flashing ? 1 : 0
                                    visible: opacity > 0.01
                                    onClicked: root.requestDelete(row.entry)

                                    Behavior on opacity {
                                        Smooth {
                                            duration: 160
                                        }

                                    }

                                }

                            }

                            transform: Translate {
                                y: (1 - row.enter) * 12
                            }

                            Behavior on scale {
                                Springy {
                                }

                            }

                            Behavior on opacity {
                                Smooth {
                                    duration: 180
                                }

                            }

                        }

                        Behavior on height {
                            Smooth {
                                duration: 220
                            }

                        }

                    }

                }

                // Wheel over the text list: one notch = exactly one row (like the image strip and the trash).
                // Before, a WheelHandler with PointerDevice.Mouse: it never arrives with some mice, then
                // the ListView scrolled itself with momentum (~73 px) and SnapToItem pulled it back to the
                // row afterwards (visible back and forth). Sibling instead of child of the
                // ListView: children of a Flickable end up in the contentItem and would scroll along.
                MouseArea {
                    property real pending: 0

                    anchors.fill: textList
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
                        // Keep counting from the running target, not from an intermediate position
                        const base = listScroll.running ? listScroll.to : textList.contentY;
                        const firstRow = Math.round((base - textList.originY) / root.rowStride);
                        root.animateListTo(textList.originY + (firstRow - steps) * root.rowStride);
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

            // ───────────── Empty state ─────────────
            Item {
                id: emptyState

                width: parent.width
                height: root.isEmpty ? 150 : 0
                opacity: root.isEmpty ? 1 : 0
                visible: height > 0.5
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "◌"
                        font.pixelSize: 36
                        color: WalColors.withAlpha(WalColors.color7, 0.2)
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: PickerManager.searchText === "" ? "Clipboard is empty" : "Nothing found"
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

            // ───────────── Footer ─────────────
            Item {
                id: footer

                width: parent.width
                height: 14 + 18

                Text {
                    id: wipeLabel

                    anchors.right: parent.right
                    y: 14
                    height: 18
                    verticalAlignment: Text.AlignVCenter
                    text: root.confirmWipe ? "Click again to clear" : "Clear all"
                    font.family: root.mono
                    font.pixelSize: 10
                    color: root.confirmWipe ? WalColors.color1 : WalColors.withAlpha(WalColors.color7, wipeArea.containsMouse ? 0.75 : 0.32)

                    MouseArea {
                        id: wipeArea

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.confirmWipe) {
                                ClipboardState.wipe();
                                root.confirmWipe = false;
                                wipeTimer.stop();
                            } else {
                                root.confirmWipe = true;
                                wipeTimer.restart();
                            }
                            searchInput.forceActiveFocus();
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

    component IconButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool danger: false
        property real size: 20

        signal clicked()

        width: size
        height: size
        radius: size / 2
        color: btnArea.containsMouse ? WalColors.withAlpha(danger ? WalColors.color1 : WalColors.color4, 0.9) : WalColors.withAlpha(WalColors.color0, 0.4)
        scale: btnArea.pressed ? 0.9 : 1

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: root.mono
            font.pixelSize: btn.size * 0.42
            color: btnArea.containsMouse ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.55)
        }

        MouseArea {
            id: btnArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
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

}
