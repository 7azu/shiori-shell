import "../../common"
import "../../services"
import QtQuick

// ───────── Read ─────────
// Read tab: shelf (books from LanguageReadingState) and reader. This file holds what both share: which of the
// two is shown, the selected word and sentence, the words of a paragraph, and keeping the scroll position
// while lines fade in. The surfaces are the parts Reader*.qml, which get this object as view:
//   ReaderShelf     books, import status, search results (ISBN card, Aozora Bunko list)
//   ReaderChapters  back, chapter chips, size button, reading progress
//   ReaderNotes     a text from the notes as sentence cards
//   ReaderText      a book chapter as running text (click on a word or sentence)
//   ReaderSentence  the selected sentence with reading + English
//   ReaderWordPop   the word card next to the clicked word
//   ReaderFooter    switches (furigana, reading, translation), read / next
// Search field: typing filters the shelf, Enter searches an ISBN (book data + free full texts) or the
// Aozora Bunko catalog.
// Part of LanguagePicker.qml (picker = core).
Item {
    id: readView

    required property var picker
    property alias bookGrid: shelf.bookGrid
    property alias resultList: shelf.resultList
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

    // ── Clickable words ──
    // Paragraph [{ja, …}, …] -> words with sentence number si. Words come from LanguageReadingState.words
    // (scripts/jp_subs.py); while they are missing, the old character tokens (not clickable). Punctuation
    // sticks to the word before (never at the start of a line), opening brackets to the word after.
    function wordItems(para) {
        const raw = [];
        for (let si = 0; si < para.length; si++) {
            const ws = LanguageReadingState.words[para[si].ja];
            if (ws) {
                for (const w of ws) raw.push({
                    "t": w.t,
                    "f": w.f || "",
                    "word": w.d ? w : null,
                    "gap": !!w.gap,
                    "si": si
                })
            } else {
                for (const tk of LanguageReadingState.tokens(para[si].ja, si)) raw.push({
                    "t": tk.t,
                    "f": tk.r ? "{" + tk.t + "|" + tk.r + "}" : "",
                    "word": null,
                    "gap": tk.gap,
                    "si": si
                })
            }
        }
        const out = [];
        let head = "";
        for (const it of raw) {
            if (!it.word && /^[「『（(【〈《“]+$/.test(it.t)) {
                head += it.t;
                continue;
            }
            if (!it.word && out.length > 0 && !out[out.length - 1].gap && /^[、。，．！？!?…」』）)】〉》”・〜ー]+$/.test(it.t)) {
                out[out.length - 1].tail += it.t;
                continue;
            }
            it.head = head;
            it.tail = "";
            head = "";
            out.push(it);
        }
        return out;
    }

    // Furigana markup -> [{t, r}] (kanji with reading, kana in between in one piece)
    function segs(f, t) {
        const src = f || t;
        const out = [];
        const re = /\{([^|}]+)\|([^}]+)\}/g;
        let last = 0;
        let m;
        while ((m = re.exec(src)) !== null) {
            if (m.index > last)
                out.push({
                "t": src.slice(last, m.index),
                "r": ""
            });

            out.push({
                "t": m[1],
                "r": m[2]
            });
            last = re.lastIndex;
        }
        if (last < src.length)
            out.push({
            "t": src.slice(last),
            "r": ""
        });

        return out;
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
    ReaderShelf {
        id: shelf

        picker: readView.picker
        view: readView
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

        // ── Back + chapter choice, reading progress ──
        ReaderChapters {
            id: chapterBar

            picker: readView.picker
            view: readView
        }

        // ── Sentence cards (notes) ──
        ReaderNotes {
            id: sentenceList

            picker: readView.picker
            view: readView
            anchors.top: chapterBar.bottom
            anchors.topMargin: 10
            anchors.bottom: readFooter.top
            anchors.bottomMargin: 6
        }

        // ── Running text ──
        ReaderText {
            id: flowList

            picker: readView.picker
            view: readView
            anchors.top: chapterBar.bottom
            anchors.topMargin: 10
            anchors.bottom: sentCard.top
            anchors.bottomMargin: 4
        }

        // ── Selected sentence: rōmaji + English ──
        ReaderSentence {
            id: sentCard

            picker: readView.picker
            view: readView
            anchors.bottom: readFooter.top
            anchors.bottomMargin: 6 * k
        }

        // ── Word card next to the clicked word ──
        ReaderWordPop {
            id: wordPop

            picker: readView.picker
            view: readView
            ceilY: chapterBar.y + chapterBar.height
            floorY: sentCard.visible ? sentCard.y : readFooter.y
        }

        // ── Switches + progress ──
        ReaderFooter {
            id: readFooter

            picker: readView.picker
            view: readView
        }

    }

}
