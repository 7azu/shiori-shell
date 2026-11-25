import "../../common"
import "../../services"
import QtQuick

// ───────── Read ─────────
// Shelf (books from LanguageReadingState) and reader. Running text chapters: a click on a sentence
// shows it at the bottom with rōmaji + English; the switches show both under every paragraph.
// Sentence cards (notes) as before. Search field: typing filters the shelf, Enter searches
// an ISBN (book data + free full texts) or the Aozora Bunko catalog.
// Part of LanguagePicker.qml (picker = core).
Item {
    id: readView

    required property var picker
    property alias bookGrid: bookGrid
    property alias resultList: resultList
    readonly property var current: LanguageReadingState.current
    readonly property var book: LanguageReadingState.currentBook
    readonly property bool flow: LanguageReadingState.isFlow
    readonly property bool currentRead: LanguageReadingState.currentId !== "" && LanguageReadingState.readIds[LanguageReadingState.currentId] !== undefined
    readonly property bool showResults: LanguageReadingState.searching || LanguageReadingState.results !== null
    readonly property bool inReader: LanguageReadingState.view === "reader" && picker.searchQuery === "" && !showResults
    readonly property real st: picker.stage(picker.readProgress, 0)
    // Running text: selected sentence (paragraph, sentence) - still for the keyboard/legacy paths
    property int selPara: -1
    property int selSent: -1
    // Clicked word: paragraph/card (pickKey), the word in it (pickIdx), its sentence (pickSi)
    property string pickKey: ""
    property int pickIdx: -1
    property int pickSi: -1
    property var pickedWord: null
    property var pickedSentence: null
    // Position of the word in the reader (for the word card next to it)
    property rect pickRect: Qt.rect(0, 0, 0, 0)
    readonly property var selected: flow ? pickedSentence : null
    // Second line under the text: kana in Japanese, otherwise only where the import stored a transliteration
    // (Cyrillic, Greek); Latin-script languages have none, so no "Latin" chip there
    readonly property bool hasReading: LanguageReadingState.isJapanese || (!!current && !!current.paras && current.paras.some((p) => {
        return p.some((s) => {
            return !!s.ro;
        });
    }))
    readonly property bool needsTranslation: !!book && !!book.imported && !!current && !current.translated
    // Without a translator (setting translation.provider) the chip only shows what is already translated
    readonly property bool canTranslate: needsTranslation && LanguageReadingState.translator !== ""
    readonly property bool translating: LanguageReadingState.busyWhat === "translate" && LanguageReadingState.busyBook === LanguageReadingState.currentBookId && LanguageReadingState.busyChapter === LanguageReadingState.currentIndex
    readonly property var shelfBooks: {
        const all = LanguageReadingState.books;
        if (picker.terms.length === 0)
            return all;

        return all.filter((b) => {
            const hay = (LanguageReadingState.plainText(b.title) + " " + b.subtitle + " " + b.level).toLowerCase();
            return picker.terms.every((t) => {
                return hay.includes(t);
            });
        });
    }
    property real readerK: inReader ? 1 : 0
    // Text change: the content fades out briefly and glides in anew
    property real swapK: 1

    // When showing/hiding furigana/kana/English the topmost visible paragraph stays
    // pixel-exact: if a paragraph ABOVE it grows by d, everything below slides by d -> move the
    // viewport (contentY) along by d right away. Before, the whole list was re-laid out on every
    // height change (forceLayout) - with many paragraphs in every frame of the animation,
    // that stuttered. A correction only in the next frame trembles.
    property int anchorIdx: -1
    property real anchorOff: 0
    property int keepIdx: -1
    readonly property var activeList: flow ? flowList : sentenceList
    // Only build paragraphs when the words for the start of the chapter are there (from the cache
    // ~0.2 s): otherwise every paragraph is created twice (first characters, then words) - that stuttered
    // when opening. Show it anyway after 1 s at the latest (then without clickable words).
    readonly property bool headWordsReady: {
        const w = LanguageReadingState.words;
        const list = LanguageReadingState.sentencesOf(current).slice(0, 80);
        for (const sn of list) if (w[sn] === undefined)
            return false;
        return true;
    }
    property bool waitedLong: false
    readonly property bool contentReady: headWordsReady || waitedLong

    onContentReadyChanged: {
        if (contentReady && swapK < 1 && !swapAnim.running)
            swapAnim.restart();

    }

    Timer {
        id: wordsWait

        interval: 1000
        onTriggered: readView.waitedLong = true
    }

    function holdAnchor() {
        const l = activeList;
        const idx = l.visible && l.contentY > l.originY + 1 ? l.indexAt(l.width / 2, l.contentY + 1) : -1;
        const it = idx >= 0 ? l.itemAtIndex(idx) : null;
        anchorIdx = it ? idx : -1;
        anchorOff = it ? it.y - l.contentY : 0;
        anchorStop.restart();
    }

    function heightDelta(list, item, index, d) {
        if (anchorIdx < 0 || list !== activeList || index >= anchorIdx || d === 0)
            return ;

        // If the paragraph lies completely above the visible area, the list moves it up by itself
        // (originY) - then do nothing, otherwise it is corrected twice
        if (item.y + item.height - d <= list.contentY)
            return ;

        list.contentY += d;
    }

    function pick(p, s) {
        if (selPara === p && selSent === s) {
            selPara = -1;
            selSent = -1;
        } else {
            selPara = p;
            selSent = s;
        }
    }

    // Click on a word: word card next to it + its sentence at the bottom (click again = close)
    function pickWord(key, idx, item, word, sentence, si) {
        if (pickKey === key && pickIdx === idx) {
            closePick();
            return ;
        }
        pickKey = key;
        pickIdx = idx;
        pickSi = si;
        pickedSentence = sentence;
        if (item)
            pickRect = item.mapToItem(reader, 0, 0, item.width, item.height);

        pickedWord = word;
    }

    // Click on a punctuation mark: only select the sentence (without a word card)
    function pickSentence(key, sentence, si) {
        if (pickKey === key && pickSi === si && pickIdx < 0) {
            closePick();
            return ;
        }
        pickedWord = null;
        pickKey = key;
        pickIdx = -1;
        pickSi = si;
        pickedSentence = sentence;
    }

    // Mouse wheel: scroll softly by ~3 rows (instead of jerkily), close the word card (the word moves away)
    function wheelScroll(list, anim, event) {
        const d = event.angleDelta.y;
        if (d === 0)
            return ;

        pickedWord = null;
        pickIdx = -1;
        const minY = list.originY;
        const maxY = Math.max(minY, list.originY + list.contentHeight - list.height);
        const base = anim.running ? anim.to : list.contentY;
        const step = Math.abs(d) >= 120 ? Math.round(d / 120) * 140 : d * 1.2;
        anim.stop();
        anim.to = Math.max(minY, Math.min(maxY, base - step));
        anim.start();
        event.accepted = true;
    }

    function closePick() {
        pickedWord = null;
        pickedSentence = null;
        pickKey = "";
        pickIdx = -1;
        pickSi = -1;
    }

    // fixed target width (shelf columns would jump during the animation otherwise)
    x: Math.round((parent.width - width) / 2)
    width: picker.readWidth - 2 * picker.pad
    height: picker.readH
    opacity: (picker.filter === "read" ? Math.min(1, picker.readProgress * 2.5) * (picker.switching ? 1 : picker.morphGate) : picker.readProgress) * (picker.choosing ? 0 : 1)
    visible: opacity > 0.01

    Connections {
        function onCurrentIdChanged() {
            readView.waitedLong = false;
            wordsWait.restart();
            readView.selPara = -1;
            readView.selSent = -1;
            readView.closePick();
            readView.swapK = 0;
            sentenceList.positionViewAtBeginning();
            flowList.positionViewAtBeginning();
            // Only fade in when the text is there (see contentReady) - otherwise it pops up half visible
            swapAnim.stop();
            if (readView.contentReady)
                swapAnim.restart();

        }

        target: LanguageReadingState
    }

    NumberAnimation {
        id: swapAnim

        target: readView
        property: "swapK"
        to: 1
        duration: 340
        easing.type: Easing.OutCubic
    }

    Behavior on readerK {
        Smooth {
            duration: 380
        }

    }

    Connections {
        function onShowKanaChanged() {
            readView.holdAnchor();
        }

        function onShowTranslationChanged() {
            readView.holdAnchor();
        }

        function onShowFuriganaChanged() {
            readView.holdAnchor();
        }

        target: LanguageReadingState
    }

    // longer than the animations (Reveal 260 ms, furigana 260 ms)
    Timer {
        id: anchorStop

        interval: 650
        onTriggered: readView.anchorIdx = -1
    }

    // ═════ Shelf ═════
    Item {
        id: shelf

        anchors.fill: parent
        opacity: readView.st * (1 - readView.readerK)
        visible: opacity > 0.01
        transform: Translate {
            x: -readView.readerK * 24
        }

        // ── Kopfzeile ──
        Item {
            id: shelfHead

            y: 12
            width: parent.width
            height: 34

            Row {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: readView.showResults ? (LanguageReadingState.results && LanguageReadingState.results.kind === "isbn" ? "ISBN" : "AOZORA BUNKO") : "LIBRARY"
                    font.family: picker.mono
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.5
                    color: WalColors.withAlpha(WalColors.color7, 0.5)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: readView.showResults ? (LanguageReadingState.searching ? "searching …" : LanguageReadingState.resultsQuery) : readView.shelfBooks.length + (readView.shelfBooks.length === 1 ? " book" : " books")
                    font.family: LanguageReadingState.resultsQuery !== "" && readView.showResults ? picker.jp : picker.mono
                    font.pixelSize: 11
                    color: WalColors.withAlpha(WalColors.color7, 0.35)
                }

            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ToggleChip {
                    picker: readView.picker
                    visible: readView.showResults
                    label: "✕ Close"
                    onClicked: LanguageReadingState.clearResults()
                }

                ToggleChip {
                    picker: readView.picker
                    label: "󰉋 Import folder"
                    onClicked: {
                        LanguageReadingState.openImportDir();
                        LanguageReadingState.scan();
                    }
                }

            }

        }

        // ── Status (import, errors) ──
        Rectangle {
            id: shelfStatus

            readonly property bool failed: LanguageReadingState.error !== ""
            readonly property string msg: failed ? LanguageReadingState.error : LanguageReadingState.busy ? (LanguageReadingState.status || "Updating library …") : LanguageReadingState.status
            readonly property bool shown: msg !== "" && !(LanguageReadingState.busyWhat === "scan" && LanguageReadingState.status === "")

            anchors.top: shelfHead.bottom
            anchors.topMargin: shown ? 8 : 0
            width: parent.width
            height: shown ? statusText.implicitHeight + 16 : 0
            radius: 12
            clip: true
            color: failed ? WalColors.withAlpha(WalColors.color1, 0.12) : WalColors.withAlpha(WalColors.color4, 0.1)
            visible: height > 0.5

            Text {
                id: statusText

                x: 14
                y: 8
                width: parent.width - 50
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: (LanguageReadingState.busy ? "⟳  " : shelfStatus.failed ? "!  " : "✓  ") + shelfStatus.msg
                font.family: picker.mono
                font.pixelSize: 11
                color: shelfStatus.failed ? WalColors.color1 : WalColors.color4
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                y: 8
                visible: !LanguageReadingState.busy
                text: "✕"
                font.pixelSize: 11
                color: WalColors.withAlpha(WalColors.color7, 0.5)

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        LanguageReadingState.error = "";
                        LanguageReadingState.status = "";
                    }
                }

            }

            Behavior on height {
                Smooth {
                }

            }

        }

        // ── Books ──
        GridView {
            id: bookGrid

            anchors.top: shelfStatus.bottom
            anchors.topMargin: 10
            anchors.bottom: parent.bottom
            width: parent.width
            // Columns by width (~190 px), card = cover in book format + title lines
            readonly property int columns: Math.max(3, Math.round(width / 190))

            cellWidth: Math.floor(width / columns)
            cellHeight: Math.round((cellWidth - 20) * 1.42) + 84
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: !readView.showResults
            // last slot: import hint
            model: readView.shelfBooks.concat([{
                "id": "",
                "add": true
            }])

            delegate: Item {
                id: cell

                required property var modelData
                required property int index

                width: bookGrid.cellWidth
                height: bookGrid.cellHeight

                BookCard {
                    picker: readView.picker
                    anchors.fill: parent
                    anchors.margins: 10
                    book: cell.modelData
                    visible: !cell.modelData.add
                    cellIndex: cell.index
                    selected: picker.kbList === "shelf" && picker.kbIndex === cell.index
                }

                AddCard {
                    picker: readView.picker
                    anchors.fill: parent
                    anchors.margins: 10
                    visible: !!cell.modelData.add
                    cellIndex: cell.index
                    selected: picker.kbList === "shelf" && picker.kbIndex === cell.index
                }

            }

        }

        // ── Search results ──
        // Header (ISBN card, hints) outside the list: a ListView header slides
        // up and away if it only gets its height after the results
        Column {
            id: resultHead

            readonly property var res: LanguageReadingState.results
            readonly property bool isbn: !!res && res.kind === "isbn"
            readonly property int count: !res ? 0 : isbn ? (res.free || []).length : (res.results || []).length

            anchors.top: shelfStatus.bottom
            anchors.topMargin: 10
            width: parent.width
            spacing: 10
            visible: readView.showResults

            Text {
                visible: LanguageReadingState.searching
                x: 14
                text: "Searching …"
                font.family: picker.mono
                font.pixelSize: 12
                color: WalColors.withAlpha(WalColors.color7, 0.45)
            }

            IsbnCard {
                picker: readView.picker
                visible: resultHead.isbn
                width: parent.width
                info: resultHead.isbn ? resultHead.res.book : null
            }

            Text {
                visible: !!resultHead.res && resultHead.count === 0 && !resultHead.isbn
                x: 14
                width: parent.width - 28
                wrapMode: Text.Wrap
                text: "Nothing found in the Aozora catalog. Aozora Bunko only has public-domain works (mostly before 1970). For an ISBN book, enter the 10- or 13-digit number."
                font.family: picker.mono
                font.pixelSize: 11
                color: WalColors.withAlpha(WalColors.color7, 0.5)
            }

        }

        ListView {
            id: resultList

            anchors.top: resultHead.bottom
            anchors.topMargin: resultHead.implicitHeight > 0 ? 10 : 0
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            visible: readView.showResults
            model: !resultHead.res ? [] : resultHead.isbn ? resultHead.res.free : resultHead.res.results

            SelectionPill {
                picker: readView.picker
                view: resultList
                listName: "aozora"
                stride: 62
                rowH: 58
            }

            delegate: AozoraRow {
                picker: readView.picker
                required property int index

                width: resultList.width
                rowIndex: index
                selected: picker.kbList === "aozora" && picker.kbIndex === index
            }

        }

    }

    // ═════ Reader ═════
    Item {
        id: reader

        anchors.fill: parent
        opacity: readView.st * readView.readerK
        visible: opacity > 0.01
        transform: Translate {
            x: (1 - readView.readerK) * 24
        }

        // ── Back + chapter choice ──
        ToggleChip {
            picker: readView.picker
            id: backChip

            y: 15
            label: "‹ Shelf"
            onClicked: LanguageReadingState.closeBook()
        }

        // Window even bigger (almost the whole screen, bigger font); the reading position stays
        ToggleChip {
            picker: readView.picker
            id: bigChip

            anchors.right: parent.right
            y: 15
            label: LanguageReadingState.big ? "󰊔 Smaller" : "󰊓 Bigger"
            on: LanguageReadingState.big
            onClicked: {
                const l = readView.activeList;
                readView.keepIdx = l.indexAt(l.width / 2, l.contentY + 1);
                LanguageReadingState.toggle("big");
                keepTimer.restart();
            }
        }

        // after rewrapping to the new width back to the same paragraph (invisible while the
        // panel is still growing: morphGate)
        Timer {
            id: keepTimer

            interval: 60
            onTriggered: {
                if (readView.keepIdx > 0)
                    readView.activeList.positionViewAtIndex(readView.keepIdx, ListView.Beginning);

            }
        }

        // Flickable + Row instead of ListView: all chips are there, the width is exact
        // (ListView estimates it and could not fully show the last chip)
        Flickable {
            id: textList

            // Bring the current chip to the middle (at the edge the strip stays at its stop)
            function showCurrent() {
                const c = chipRepeater.itemAt(LanguageReadingState.currentIndex);
                if (!c)
                    return ;

                const max = Math.max(0, contentWidth - width);
                contentX = Math.max(0, Math.min(max, c.x + c.width / 2 - width / 2));
            }

            anchors.left: backChip.right
            anchors.leftMargin: 8
            anchors.right: bigChip.left
            anchors.rightMargin: 8
            y: 12
            height: 34
            contentWidth: chipsRow.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            onContentWidthChanged: Qt.callLater(showCurrent)
            onWidthChanged: Qt.callLater(showCurrent)

            Connections {
                function onCurrentIndexChanged() {
                    Qt.callLater(textList.showCurrent);
                }

                target: LanguageReadingState
            }

            Behavior on contentX {
                enabled: !textList.moving

                Smooth {
                    duration: 360
                }

            }

            Row {
                id: chipsRow

                spacing: 8

                Repeater {
                    id: chipRepeater

                    model: LanguageReadingState.chapters

                    delegate: Rectangle {
                        id: chip

                        required property var modelData
                        required property int index
                        readonly property bool active: index === LanguageReadingState.currentIndex
                        readonly property bool done: LanguageReadingState.readIds[LanguageReadingState.chapterId(readView.book, index)] !== undefined

                        width: chipRow.implicitWidth + 26
                        height: 34
                        radius: height / 2
                        color: active ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, chipMouse.containsMouse ? 0.1 : 0.05)
                        border.width: 1
                        border.color: active ? WalColors.withAlpha(WalColors.color4, 0.5) : "transparent"

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: 7

                            // Read: small sparkle (visual language) instead of a check mark
                            Sparkle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: chip.done
                                size: 3.5
                                rays: 1.7
                                color: WalColors.color4
                                glowColor: WalColors.vividAccent
                                twinkle: 0.8
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !chip.done && !!chip.modelData.fromNotes
                                text: "󰠮"
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.bold: true
                                color: chip.done ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.45)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 200)
                                elide: Text.ElideRight
                                text: LanguageReadingState.plainText(chip.modelData.title)
                                font.family: picker.jp
                                font.pixelSize: 13
                                color: chip.active ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.65)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: text !== ""
                                text: String(chip.modelData.level || "").toUpperCase()
                                font.family: picker.mono
                                font.pixelSize: 8
                                font.bold: true
                                font.letterSpacing: 1
                                color: WalColors.withAlpha(chip.active ? WalColors.color4 : WalColors.color7, 0.5)
                            }

                        }

                        MouseArea {
                            id: chipMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: LanguageReadingState.select(chip.index)
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

        EdgeFade {
            anchors.left: textList.left
            y: textList.y
            height: textList.height
            visible: textList.contentX > 1
        }

        EdgeFade {
            anchors.right: textList.right
            y: textList.y
            height: textList.height
            rightSide: true
            visible: textList.contentWidth - textList.contentX - textList.width > 1
        }

        // ── Reading progress in the chapter: thin line below the chapter chips ──
        Rectangle {
            id: progressTrack

            readonly property var l: readView.activeList
            readonly property real p: l && l.contentHeight > l.height + 1 ? Math.max(0, Math.min(1, (l.contentY - l.originY) / (l.contentHeight - l.height))) : 0

            anchors.top: textList.bottom
            anchors.topMargin: 5
            width: parent.width
            height: 2
            radius: 1
            color: WalColors.withAlpha(WalColors.color7, 0.06)
            opacity: l && l.contentHeight > l.height + 1 ? 1 : 0

            Rectangle {
                width: Math.max(height, parent.width * progressTrack.p)
                height: parent.height
                radius: 1
                color: WalColors.withAlpha(WalColors.color4, 0.7)
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.normal
                }

            }

        }

        // ── Sentence cards (notes) ──
        ListView {
            id: sentenceList

            anchors.top: textList.bottom
            anchors.topMargin: 10
            anchors.bottom: readFooter.top
            anchors.bottomMargin: 6
            width: parent.width
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            visible: !readView.flow
            model: !readView.flow && readView.current && readView.contentReady ? readView.current.sentences : []
            opacity: readView.swapK

            NumberAnimation {
                id: sentenceListScroll

                target: sentenceList
                property: "contentY"
                duration: 280
                easing.type: Easing.OutCubic
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    return readView.wheelScroll(sentenceList, sentenceListScroll, event);
                }
            }

            onMovementStarted: {
                sentenceListScroll.stop();
                readView.pickedWord = null;
                readView.pickIdx = -1;
            }
            // The header is only measured correctly after the build -> then to the start
            onModelChanged: Qt.callLater(positionViewAtBeginning)
            onVisibleChanged: {
                if (visible)
                    Qt.callLater(positionViewAtBeginning);

            }

            header: Item {
                width: sentenceList.width
                height: titleCol.implicitHeight + 14

                Column {
                    id: titleCol

                    x: 14
                    width: parent.width - 28
                    spacing: 4

                    Ruby {
                        picker: readView.picker
                        width: parent.width
                        text: readView.current ? readView.current.title : ""
                        size: 24
                        bold: true
                    }

                    Text {
                        text: readView.current && readView.current.sentences ? readView.current.titleDe + " · " + readView.current.sentences.length + (readView.current.fromNotes ? " entries from your notes" : " sentences") : ""
                        font.family: picker.mono
                        font.pixelSize: 10
                        color: WalColors.withAlpha(WalColors.color7, 0.45)
                    }

                }

            }

            delegate: Rectangle {
                id: sent

                required property var modelData
                required property int index
                property bool open: false
                readonly property bool showRo: LanguageReadingState.showKana || open
                readonly property bool showDe: (LanguageReadingState.showTranslation || open) && !!modelData.de

                width: sentenceList.width
                height: sentCol.implicitHeight + 18
                radius: 16
                // remember the last height: only the change is reported (see heightDelta)
                property real lastH: -1
                Component.onCompleted: lastH = height
                onHeightChanged: {
                    if (lastH >= 0)
                        readView.heightDelta(sentenceList, sent, index, height - lastH);

                    lastH = height;
                }
                color: open ? WalColors.withAlpha(WalColors.color4, 0.08) : WalColors.withAlpha(WalColors.color7, sentMouse.containsMouse ? 0.05 : 0)

                transform: Translate {
                    y: (1 - readView.swapK) * (10 + sent.index * 4)
                }

                Rectangle {
                    id: badge

                    x: 12
                    y: 9 + 22 * 0.55
                    width: 24
                    height: 24
                    radius: height / 2
                    color: WalColors.withAlpha(WalColors.color4, sent.open ? 0.28 : 0.14)

                    Text {
                        anchors.centerIn: parent
                        text: sent.modelData.sp || (sent.index + 1)
                        font.family: picker.mono
                        font.pixelSize: 10
                        font.bold: true
                        color: WalColors.color4
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

                Column {
                    id: sentCol

                    x: 48
                    y: 9
                    width: parent.width - 60
                    spacing: 0

                    WordFlow {
                        view: readView
                        picker: readView.picker
                        width: parent.width
                        para: [sent.modelData]
                        key: "c" + sent.index
                        size: 22
                        passClicks: true
                    }

                    Reveal {
                        picker: readView.picker
                        shown: sent.showRo
                        text: LanguageReadingState.kanaText(sent.modelData.ja)
                        family: picker.jp
                        pixelSize: 13
                        color: WalColors.withAlpha(WalColors.color4, 0.85)
                    }

                    Reveal {
                        picker: readView.picker
                        shown: sent.showDe
                        text: sent.modelData.de || ""
                        pixelSize: 12
                        color: WalColors.withAlpha(WalColors.color7, 0.6)
                    }

                }

                MouseArea {
                    id: sentMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sent.open = !sent.open
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

            // Vocabulary for the text
            footer: Item {
                id: wordsFooter

                readonly property var words: readView.current && readView.current.words ? readView.current.words : []

                width: sentenceList.width
                height: words.length > 0 ? wordsCol.implicitHeight + 24 : 8
                visible: words.length > 0

                Column {
                    id: wordsCol

                    x: 14
                    y: 14
                    width: parent.width - 28
                    spacing: 8

                    Text {
                        text: "WORDS"
                        font.family: picker.mono
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.5
                        color: WalColors.withAlpha(WalColors.color7, 0.4)
                    }

                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: wordsFooter.words

                            delegate: Rectangle {
                                required property var modelData

                                width: wordRow.implicitWidth + 20
                                height: 30
                                radius: 10
                                color: WalColors.withAlpha(WalColors.color7, 0.05)
                                border.width: 1
                                border.color: WalColors.withAlpha(WalColors.color7, 0.06)

                                Row {
                                    id: wordRow

                                    anchors.centerIn: parent
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: LanguageReadingState.plainText(modelData.ja)
                                        font.family: picker.jp
                                        font.pixelSize: 13
                                        color: WalColors.color7
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: text !== LanguageReadingState.plainText(modelData.ja)
                                        text: LanguageReadingState.kanaText(modelData.ja)
                                        font.family: picker.jp
                                        font.pixelSize: 11
                                        color: WalColors.withAlpha(WalColors.color4, 0.85)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.de
                                        font.family: picker.mono
                                        font.pixelSize: 10
                                        color: WalColors.withAlpha(WalColors.color7, 0.55)
                                    }

                                }

                            }

                        }

                    }

                }

            }

        }

        // ── Running text ──
        // The chapter header is the first row of the model (no ListView header: it slides
        // up and away when its height changes, e.g. when the English title fades in)
        ListView {
            id: flowList

            anchors.top: textList.bottom
            anchors.topMargin: 10
            anchors.bottom: sentCard.top
            anchors.bottomMargin: 4
            width: parent.width
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            visible: readView.flow
            model: readView.flow && readView.current && readView.contentReady ? [{
                "head": true
            }].concat(readView.current.paras || []).concat([{
                "foot": true
            }]) : []
            opacity: readView.swapK
            // do not prebuild too much invisibly: every paragraph is hundreds of elements
            cacheBuffer: 300

            NumberAnimation {
                id: flowListScroll

                target: flowList
                property: "contentY"
                duration: 280
                easing.type: Easing.OutCubic
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    return readView.wheelScroll(flowList, flowListScroll, event);
                }
            }

            onMovementStarted: {
                flowListScroll.stop();
                readView.pickedWord = null;
                readView.pickIdx = -1;
            }

            // Limit the line length (~42 characters), column centered
            readonly property real side: Math.round(Math.max(14, (width - (picker.readBig ? 1150 : 900)) / 2))

            delegate: Item {
                id: paraItem

                required property var modelData
                required property int index
                // Paragraph arrays arrive as sequence wrappers (Array.isArray is false for them)
                readonly property bool isPara: !modelData.head && !modelData.foot
                readonly property bool hasEn: isPara && modelData.some((s) => {
                    return !!s.en;
                })

                width: flowList.width
                height: isPara ? paraCol.implicitHeight + 24 : modelData.head ? flowTitle.implicitHeight + 26 : 56
                // remember the last height: only the change is reported (see heightDelta)
                property real lastH: -1
                Component.onCompleted: lastH = height
                onHeightChanged: {
                    if (lastH >= 0)
                        readView.heightDelta(flowList, paraItem, index, height - lastH);

                    lastH = height;
                }

                transform: Translate {
                    y: (1 - readView.swapK) * (10 + Math.min(paraItem.index, 6) * 5)
                }

                Column {
                    id: flowTitle

                    x: flowList.side
                    width: parent.width - 2 * flowList.side
                    spacing: 4
                    visible: !!paraItem.modelData.head

                    Text {
                        text: readView.book ? LanguageReadingState.plainText(readView.book.title) + "  ·  " + (LanguageReadingState.currentIndex + 1) + " / " + LanguageReadingState.chapters.length : ""
                        font.family: picker.jp
                        font.pixelSize: 11
                        color: WalColors.withAlpha(WalColors.color7, 0.4)
                    }

                    Ruby {
                        picker: readView.picker
                        width: parent.width
                        text: readView.current ? readView.current.title : ""
                        size: 24
                        bold: true
                    }

                    Reveal {
                        picker: readView.picker
                        shown: LanguageReadingState.showTranslation && !!readView.current && !!readView.current.en
                        text: readView.current && readView.current.en ? readView.current.en : ""
                        pixelSize: 11
                        color: WalColors.withAlpha(WalColors.color7, 0.5)
                    }

                    Text {
                        visible: !!readView.book && !!readView.book.note
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: readView.book && readView.book.note ? "ⓘ " + readView.book.note : ""
                        font.family: picker.mono
                        font.pixelSize: 10
                        color: WalColors.withAlpha(WalColors.color3, 0.8)
                    }

                    Text {
                        visible: !!readView.current && readView.current.loading === true
                        text: "Loading chapter …"
                        font.family: picker.mono
                        font.pixelSize: 11
                        color: WalColors.withAlpha(WalColors.color7, 0.45)
                    }

                }

                Column {
                    id: paraCol

                    x: flowList.side
                    width: parent.width - 2 * flowList.side
                    // 0: columns skip elements with height 0 together with the spacing - otherwise the kana/English row
                    // caused a 2 px jump per paragraph when expanding/collapsing (the spacing is inside the Reveal)
                    spacing: 0
                    visible: paraItem.isPara

                    WordFlow {
                        view: readView
                        picker: readView.picker
                        width: parent.width
                        size: picker.readBig ? 26 : 22
                        para: paraItem.isPara ? paraItem.modelData : []
                        key: "p" + paraItem.index
                    }

                    // Sentence as reading (hiragana, katakana words stay katakana) or, in other languages, as
                    // Latin transliteration (sentences joined with spaces there)
                    Reveal {
                        picker: readView.picker
                        shown: LanguageReadingState.showKana && paraItem.isPara && readView.hasReading
                        text: paraItem.isPara ? paraItem.modelData.map((s) => {
                            return LanguageReadingState.readingOf(s);
                        }).join(LanguageReadingState.isJapanese ? "" : " ") : ""
                        family: picker.jp
                        pixelSize: picker.readBig ? 15 : 13
                        color: WalColors.withAlpha(WalColors.color4, 0.85)
                    }

                    Reveal {
                        picker: readView.picker
                        shown: LanguageReadingState.showTranslation && paraItem.hasEn
                        text: paraItem.isPara ? paraItem.modelData.map((s) => {
                            return s.en || "";
                        }).join(" ") : ""
                        pixelSize: 12
                        color: WalColors.withAlpha(WalColors.color7, 0.6)
                    }

                }

                Text {
                    anchors.centerIn: parent
                    visible: !!paraItem.modelData.foot && flowList.count > 3
                    text: LanguageReadingState.currentIndex < LanguageReadingState.chapters.length - 1 ? "— End of chapter · “Next ›” marks it as read —" : "— End of book —"
                    font.family: picker.mono
                    font.pixelSize: 10
                    color: WalColors.withAlpha(WalColors.color7, 0.3)
                }

            }

        }

        // ── Selected sentence: rōmaji + English ──
        Rectangle {
            id: sentCard

            readonly property var s: readView.selected
            property real k: s ? 1 : 0

            anchors.bottom: readFooter.top
            anchors.bottomMargin: 6 * k
            width: parent.width
            height: (cardCol.implicitHeight + 20) * k
            radius: 16
            clip: true
            visible: readView.flow && k > 0.01
            color: WalColors.withAlpha(WalColors.color4, 0.08)
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color4, 0.22)

            Column {
                id: cardCol

                x: 16
                y: 10 + (1 - sentCard.k) * 12
                width: parent.width - 52
                spacing: 4
                opacity: sentCard.k

                Ruby {
                    picker: readView.picker
                    width: parent.width
                    text: sentCard.s ? sentCard.s.ja : ""
                    size: 16
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: text !== ""
                    text: LanguageReadingState.readingOf(sentCard.s)
                    font.family: picker.jp
                    font.pixelSize: 13
                    color: WalColors.withAlpha(WalColors.color4, 0.9)
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: sentCard.s ? (sentCard.s.en || (readView.translating ? "Translating …" : readView.canTranslate ? "No translation yet – use “→ English” below" : "No translation yet")) : ""
                    font.family: picker.mono
                    font.pixelSize: 12
                    font.italic: !!sentCard.s && !sentCard.s.en
                    color: WalColors.withAlpha(WalColors.color7, sentCard.s && sentCard.s.en ? 0.75 : 0.4)
                }

            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                y: 10
                text: "✕"
                font.pixelSize: 12
                color: WalColors.withAlpha(WalColors.color7, 0.5)

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: readView.closePick()
                }

            }

            Behavior on k {
                Smooth {
                    duration: 260
                }

            }

        }

        // ── Word card next to the clicked word ──
        // Below the word if there is room (otherwise above it); grows out of the word.
        // It closes when scrolling (the word would otherwise move away under it).
        Item {
            id: wordPop

            readonly property bool open: readView.pickedWord !== null
            readonly property rect r: readView.pickRect
            readonly property bool below: r.y + r.height + 10 + height <= (sentCard.visible ? sentCard.y : readFooter.y) - 4
            property var shownWord: null

            z: 20
            width: Math.min(Theme.px(380), parent.width - 16)
            height: wpCard.implicitHeight + 2 * Theme.px(18)
            x: Math.max(8, Math.min(parent.width - width - 8, r.x + r.width / 2 - width / 2))
            y: below ? r.y + r.height + 8 : Math.max(textList.y + textList.height, r.y - height - 8)
            opacity: open ? 1 : 0
            scale: open ? 1 : 0.94
            transformOrigin: below ? Item.Top : Item.Bottom
            visible: opacity > 0.01
            onOpenChanged: {
                if (open)
                    shownWord = readView.pickedWord;

            }

            Connections {
                function onPickedWordChanged() {
                    if (readView.pickedWord)
                        wordPop.shownWord = readView.pickedWord;

                }

                target: readView
            }

            SoftShadow {
                radius: Theme.radiusL
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusL
                // opaque: lies over running text, which would shine through otherwise
                color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.04))
                border.width: 1
                border.color: WalColors.withAlpha(WalColors.color4, 0.3)
            }

            MouseArea {
                anchors.fill: parent
            }

            LanguageWordCard {
                id: wpCard

                x: Theme.px(20)
                y: Theme.px(18)
                width: parent.width - 2 * Theme.px(20)
                word: wordPop.shownWord
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.anim.durations.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.emphasizedDecelerate
                }

            }

        }

        // ── Switches + progress ──
        Item {
            id: readFooter

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            width: parent.width
            height: 34

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ToggleChip {
                    picker: readView.picker
                    visible: LanguageReadingState.isJapanese
                    label: "ふりがな"
                    jpLabel: true
                    on: LanguageReadingState.showFurigana
                    onClicked: LanguageReadingState.toggle("showFurigana")
                }

                ToggleChip {
                    picker: readView.picker
                    visible: readView.hasReading
                    label: LanguageReadingState.isJapanese ? "かな" : "Latin"
                    jpLabel: LanguageReadingState.isJapanese
                    on: LanguageReadingState.showKana
                    onClicked: LanguageReadingState.toggle("showKana")
                }

                // Imported chapters without a translation: a click translates (backend from scripts/jp_translate.py)
                // and turns it on
                ToggleChip {
                    picker: readView.picker
                    label: !readView.flow ? "Translation" : readView.translating ? "Translating …" : readView.canTranslate ? "→ English" : "English"
                    on: LanguageReadingState.showTranslation && !readView.canTranslate
                    opacity: LanguageReadingState.busy && readView.canTranslate && !readView.translating ? 0.4 : 1
                    onClicked: {
                        if (readView.canTranslate) {
                            LanguageReadingState.translate();
                            if (!LanguageReadingState.showTranslation)
                                LanguageReadingState.toggle("showTranslation");

                        } else {
                            LanguageReadingState.toggle("showTranslation");
                        }
                    }
                }

            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: LanguageReadingState.readCount + " / " + LanguageReadingState.chapters.length
                    font.family: picker.mono
                    font.pixelSize: 10
                    color: WalColors.withAlpha(WalColors.color7, 0.4)
                }

                ToggleChip {
                    picker: readView.picker
                    label: "Read"
                    star: true
                    on: readView.currentRead
                    onClicked: {
                        if (LanguageReadingState.currentId !== "")
                            LanguageReadingState.setRead(LanguageReadingState.currentId, !readView.currentRead);

                    }
                }

                ToggleChip {
                    picker: readView.picker
                    label: "Next ›"
                    enabled: LanguageReadingState.currentIndex < LanguageReadingState.chapters.length - 1
                    opacity: enabled ? 1 : 0.35
                    onClicked: {
                        if (readView.flow && !readView.currentRead)
                            LanguageReadingState.setRead(LanguageReadingState.currentId, true);

                        LanguageReadingState.step(1);
                    }
                }

            }

        }

    }

}
