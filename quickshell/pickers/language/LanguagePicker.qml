import "../../common"
import "../../services"
import "../../windows"
import "../parts"
import QtQuick

Item {
    id: root

    // ───────────────────────── Layout / state ─────────────────────────
    readonly property real pad: 16
    // Language and navigation, below it the search.
    readonly property real titleH: 44
    readonly property real headGap: 12
    readonly property real fieldH: 42
    // The air below the search row belongs to the header, so every tab starts equally far below it
    readonly property real headH: titleH + headGap + fieldH + 10
    // Read tab: wider, higher and further up (shelf with covers, more pleasant lines for reading);
    // in the reader even bigger with a button (LanguageReadingState.big)
    // Language choice when opening (LanguageChooser, like the categories in the media picker); Esc/the back button
    // lead from a language back here.
    property bool choosing: true
    readonly property var chooser: chooserView
    // Two-phase view change like MediaPicker.setCategory.
    property real switchOut: 0
    property real switchIn: 1
    property string pendingLanguage: ""
    readonly property bool switching: languageSwitch.running
    readonly property bool wide: filter === "read" && !choosing
    readonly property bool bigReader: LanguageReadingState.big && LanguageReadingState.view === "reader"
    readonly property bool readBig: wide && bigReader
    readonly property real narrowWidth: Math.min(720, width - 48)
    // List tab wider: big video previews in three columns
    readonly property real listenWidth: Math.min(940, width - 48)
    readonly property real readWidth: bigReader ? Math.min(1680, width - 64) : Math.min(1120, width - 96)
    // Language choice in the same dimensions as the media picker's category choice: tiles as wide as its
    // innerWidth (min(1180, width - 48) - 2 * 16), 30 margin all around, 10 % of the height on top.
    // But the panel is only as wide as the used columns (chooserView.implicitWidth)
    readonly property real chooserFullW: Math.min(1180, width - 48) - 32
    readonly property real chooserW: chooserView.implicitWidth
    readonly property real chooserMargin: 30
    // Image choice when adding a language (LanguageAddForm -> Browse): the panel morphs into the folder browser
    // of the image/video editors (windows/MediaBrowser), Enter on an image takes it and morphs back
    property bool browsingImage: false
    property real browseK: browsingImage ? 1 : 0
    readonly property real browseW: Math.min(1400, width - 96)
    readonly property real browseH: Math.max(420, Math.min(860, height - targetTop - 80))
    readonly property real targetWidth: browsingImage ? browseW : choosing ? chooserW + 2 * chooserMargin : wide ? readWidth : filter === "library" ? listenWidth : narrowWidth
    readonly property real targetTop: choosing ? Math.max(40, height * 0.1) : readBig ? Math.max(16, height * 0.025) : wide ? Math.max(32, height * 0.05) : Math.max(40, height * 0.12)
    property real panelWidth: targetWidth
    property real panelTop: targetTop
    readonly property real innerWidth: panelWidth - 2 * pad
    // Tab change with a size change: the new content only appears when the panel has almost its target width
    // (otherwise the old and new content run into each other during the animation)
    readonly property real morphGate: 1 - Math.min(1, Math.abs(panelWidth - targetWidth) / 60)
    // Font of the controls in all parts (Read tab, books, chips): since the redesign the
    // UI grotesque as in the rest of the shell; the parts set Nerd Font symbols in Theme.font themselves
    readonly property string mono: Theme.fontUi
    // Japanese font with JP glyphs (the fallback font would be the Korean variant)
    readonly property string jp: "Noto Sans CJK JP"
    property string filter: "library"
    // Tabs of the header. Read exists for every language (own books, translation); furigana, the dictionary
    // and the Aozora search only for Japanese (LanguageReadingState)
    readonly property var tabKeys: ["library", "read", "stats"]

    Connections {
        function onLanguageChanged() {
            if (root.tabKeys.indexOf(root.filter) < 0)
                root.filter = "library";

            // Every language has its own books: look into the new books folder right away
            if (root.filter === "read")
                LanguageReadingState.scan();

            root.kbIndex = -1;
        }

        target: LanguageAudioState
    }
    property string searchQuery: ""
    property bool intro: true
    property real shown: 0
    property string activePeriod: "day"
    readonly property bool isSearchMode: searchQuery !== "" && (LanguageAudioState.isSearching || LanguageAudioState.searchResults.length > 0)
    // ── File search: typing filters the library (all words must occur),
    // Enter searches on YouTube instead ──
    readonly property var terms: searchQuery.toLowerCase().split(/\s+/).filter((t) => {
        return t !== "";
    })
    readonly property var filteredLibrary: {
        const lib = LanguageAudioState.library;
        if (terms.length === 0)
            return lib;

        return lib.filter((f) => {
            const name = f.toLowerCase();
            return terms.every((t) => {
                return name.includes(t);
            });
        });
    }
    // Only videos, newest first (no audios anymore, listening in the background works with videos;
    // old mp3 stay on the disk but no longer appear)
    readonly property var entries: {
        const meta = LanguageAudioState.meta;
        return filteredLibrary.filter((f) => LanguageAudioState.isVideo(f)).sort((a, b) => {
            return ((meta[b] && meta[b].mtime) || 0) - ((meta[a] && meta[a].mtime) || 0) || a.localeCompare(b);
        });
    }
    readonly property var results: LanguageAudioState.searchResults
    // ───────────────────────── Stats data ─────────────────────────
    readonly property var currentStats: parseTime(LanguageAudioState.getStatsForPeriod(activePeriod))
    readonly property real currentMinutes: (parseInt(currentStats.h) * 60) + parseInt(currentStats.m)
    readonly property real maxMinutes: {
        switch (activePeriod) {
        case "day":
            return 60;
        case "week":
            return 300;
        case "month":
            return 1200;
        case "year":
            return 14400;
        }
        return 60;
    }
    readonly property string goalLabel: Math.round(maxMinutes / 60) + "h"
    readonly property real progress: Math.min(1, currentMinutes / maxMinutes)
    property real shownMinutes: currentMinutes
    property real displayProgress: progress
    readonly property real introK: stage(statsProgress, 0.1)
    readonly property real heroMinutes: shownMinutes * introK
    readonly property real heroProgress: displayProgress * introK
    readonly property var weekData: {
        const s = LanguageAudioState.stats || ({
        });
        const out = [];
        for (let i = 6; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            out.push({
                "label": Qt.formatDate(d, "ddd"),
                "secs": s[Qt.formatDate(d, "yyyy-MM-dd")] || 0,
                "today": i === 0
            });
        }
        return out;
    }
    readonly property real weekMaxSecs: {
        let m = 1;
        for (let i = 0; i < weekData.length; i++) m = Math.max(m, weekData[i].secs)
        return m;
    }
    readonly property real weekAvgMinutes: {
        let t = 0;
        for (let i = 0; i < weekData.length; i++) t += weekData[i].secs
        return t / 7 / 60;
    }
    // Header: listening time today against the daily goal (the same goal as "Day" in the stats tab)
    readonly property real dailyGoal: 60
    readonly property real todayMinutes: ((LanguageAudioState.stats || ({}))[Qt.formatDate(new Date(), "yyyy-MM-dd")] || 0) / 60
    readonly property int streak: {
        const s = LanguageAudioState.stats || ({
        });
        let n = 0;
        for (let i = 0; i < 3650; i++) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const v = s[Qt.formatDate(d, "yyyy-MM-dd")] || 0;
            if (v > 0)
                n++;
            else if (i > 0)
                break;
        }
        return n;
    }
    // ───────────────────────── Body sizing ─────────────────────────
    readonly property real libH: libraryList.wanted
    readonly property real moreH: LanguageAudioState.hasMoreResults || LanguageAudioState.isLoadingMore ? 52 : 0
    readonly property real searchH: Math.min(results.length * 64 + moreH, 448) + 40
    readonly property real statsH: statsView.implicitHeight
    readonly property real readH: Math.round(Math.max(520, Math.min(readBig ? 4000 : 900, height - targetTop - headH - 2 * pad - (readBig ? 24 : 40))))
    // Panel = content + 2 * pad; the rest up to chooserMargin lies in the content area
    readonly property real chooserH: chooserView.implicitHeight + 2 * (chooserMargin - pad)
    readonly property real bodyTarget: browsingImage ? browseH : choosing ? chooserH : filter === "stats" ? statsH : filter === "read" ? readH : (isSearchMode ? searchH : libH)
    property real bodyH: bodyTarget
    property real statsProgress: filter === "stats" && !choosing ? 1 : 0
    property real readProgress: filter === "read" && !choosing ? 1 : 0
    // Furigana on/off: readings fade in/out softly, the lines move together
    property real furiK: LanguageReadingState.showFurigana ? 1 : 0
    property real libraryProgress: (filter === "library" && !isSearchMode && !choosing) ? 1 : 0
    property real searchProgress: (filter === "library" && isSearchMode && !choosing) ? 1 : 0
    readonly property bool showDl: LanguageAudioState.isDownloading || LanguageAudioState.downloadError !== ""

    // ───────────────────────── Helpers ─────────────────────────
    function parseTime(str) {
        const h = str.match(/(\d+)h/);
        const m = str.match(/(\d+)m/);
        return {
            "h": h ? h[1] : "0",
            "m": m ? m[1] : "0"
        };
    }

    function formatTime(seconds) {
        if (!seconds || seconds < 0 || isNaN(seconds))
            return "0:00";

        const totalSecs = Math.floor(seconds);
        const h = Math.floor(totalSecs / 3600);
        const m = Math.floor((totalSecs % 3600) / 60);
        const s = totalSecs % 60;
        const sStr = s < 10 ? "0" + s : s.toString();
        if (h > 0) {
            const mStr = m < 10 ? "0" + m : m.toString();
            return h + ":" + mStr + ":" + sStr;
        }
        return m + ":" + sStr;
    }

    function formatMinutes(mins) {
        const t = Math.round(mins);
        if (t < 60)
            return t + "m";

        return Math.floor(t / 60) + "h " + (t % 60) + "m";
    }

    // ── Read tab: clickable words ──
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

    function clearSearchText() {
        searchInput.text = "";
    }

    // As in the other pickers: when opening the search field gets the focus. All keys
    // (arrows, Ctrl+J/K, Enter, Esc) depend on its Keys handler.
    function focusSearch() {
        if (browsingImage)
            browseKeys.forceActiveFocus();
        else if (choosing)
            chooserView.focusCurrent();
        else
            searchInput.forceActiveFocus();
    }

    // Open a language (tile/Enter, or right after "Add Language")
    function enterLanguage(name) {
        if (switching || !choosing || !name)
            return;
        chooserView.index = Math.max(0, chooserView.langs.indexOf(name));
        pendingLanguage = name;
        languageSwitch.start();
    }

    // startPath: file whose folder the browser shows (and which it selects)
    function openImageBrowser(startPath) {
        browsingImage = true;
        imageBrowser.filter = 1;
        imageBrowser.currentPath = startPath;
        browseKeys.forceActiveFocus();
        // Only read once the panel is already growing: the browser then zooms into the almost finished panel
        browseStartTimer.restart();
    }

    function closeImageBrowser() {
        browseStartTimer.stop();
        imageBrowser.preparing = false;
        imageBrowser.open = false;
        if (!browsingImage)
            return ;

        browsingImage = false;
        Qt.callLater(focusSearch);
    }

    function imagePicked(path, kind) {
        if (kind !== "image") {
            imageBrowser.hint = "Choose an image (jpg, png or webp)";
            return ;
        }
        closeImageBrowser();
        chooserView.imageChosen(path);
    }

    // Back to the language choice (back button, Esc without search text)
    function backToChooser() {
        if (switching || choosing)
            return;
        pendingLanguage = "";
        languageSwitch.start();
    }

    function applyLanguageSwitch() {
        switchIn = 0;
        switchOut = 0;
        if (pendingLanguage === "") {
            if (searchInput.text !== "") {
                searchInput.text = "";
                LanguageAudioState.clearSearch();
            }
            chooserView.reset();
        } else {
            LanguageAudioState.setLanguage(pendingLanguage);
        }
        kbIndex = -1;
        choosing = pendingLanguage === "";
        Qt.callLater(focusSearch);
    }

    Connections {
        function onLanguageAdded(name) {
            root.enterLanguage(name);
        }

        target: LanguageAudioState
    }

    // ── Keyboard selection (as in the other pickers: arrows / Ctrl+J/K, Enter) ──
    // Which list is visible right now; none in the reader and in stats.
    readonly property string kbList: filter === "library" ? (isSearchMode ? "youtube" : "audio") : (filter === "read" && LanguageReadingState.view !== "reader") ? (readView.showResults ? "aozora" : "shelf") : ""
    readonly property int kbCount: kbList === "audio" ? entries.length : kbList === "youtube" ? searchView.searchList.count : kbList === "shelf" ? readView.bookGrid.count : kbList === "aozora" ? readView.resultList.count : 0
    // -1 = nothing selected: then Enter searches as before; only arrow down/up selects something
    property int kbIndex: -1
    // Last mouse position for hoverSelect (window coordinates)
    property real lastMouseX: -1
    property real lastMouseY: -1

    onKbListChanged: kbIndex = -1

    // As in clipboard/trash/task manager: hover IS the selection (one pill, no
    // own hover background). Only a real mouse move counts, otherwise a row that slides under the
    // resting mouse while scrolling by keyboard would grab the selection.
    function hoverSelect(target, mouse, listName, idx) {
        const p = target.mapToItem(null, mouse.x, mouse.y);
        if (Math.abs(p.x - lastMouseX) < 3 && Math.abs(p.y - lastMouseY) < 3)
            return ;

        lastMouseX = p.x;
        lastMouseY = p.y;
        if (kbList === listName)
            kbIndex = idx;

    }
    onKbCountChanged: {
        if (kbIndex >= kbCount)
            kbIndex = kbCount - 1;

    }

    function kbView() {
        return kbList === "audio" ? libraryList : kbList === "youtube" ? searchView.searchList : kbList === "shelf" ? readView.bookGrid : kbList === "aozora" ? readView.resultList : null;
    }

    function kbMove(delta) {
        const n = kbCount;
        if (n === 0)
            return ;

        let i = kbIndex < 0 ? (delta > 0 ? 0 : n - 1) : kbIndex + delta;
        // YouTube: beyond the end = load more results (like "Load more")
        if (kbList === "youtube" && i >= n && LanguageAudioState.hasMoreResults && !LanguageAudioState.isLoadingMore)
            LanguageAudioState.loadMoreResults();

        kbIndex = Math.max(0, Math.min(n - 1, i));
        const v = kbView();
        if (v)
            v.positionViewAtIndex(kbIndex, ListView.Contain);

    }

    // Does what a click on the selected entry does. false = nothing done.
    function kbActivate() {
        const i = kbIndex;
        if (kbList === "audio") {
            const f = entries[i];
            if (f === undefined)
                return false;

            // Enter like a click on the row: watch videos, play audio
            if (LanguageAudioState.isVideo(f))
                LanguageAudioState.watchVideo(f);
            else
                LanguageAudioState.play(f);
            return true;
        }
        if (kbList === "youtube") {
            const r = results[i];
            if (!r)
                return false;

            if (!LanguageAudioState.isDownloading)
                LanguageAudioState.downloadVideo(r.url, r.title);

            return true;
        }
        if (kbList === "shelf") {
            const b = readView.bookGrid.model[i];
            if (!b)
                return false;

            if (b.add) {
                LanguageReadingState.pickBooks();
            } else {
                LanguageReadingState.openBook(b.id);
            }
            return true;
        }
        if (kbList === "aozora") {
            const a = readView.resultList.model[i];
            if (!a)
                return false;

            // like the button in AozoraRow: there -> read, otherwise import
            if (LanguageReadingState.hasBook("aozora-" + a.id)) {
                LanguageReadingState.clearResults();
                clearSearchText();
                LanguageReadingState.openBook("aozora-" + a.id);
            } else if (!LanguageReadingState.busy) {
                LanguageReadingState.importAozora(a.id);
            }
            return true;
        }
        return false;
    }

    function stage(p, d) {
        return Math.max(0, Math.min(1, (p - d) / (1 - d)));
    }

    // Closing: reverse of the intro (panel glides down, shrinks, fades out).
    // Called by PickerWindow, the window stays visible briefly for it.
    function playOutro() {
        introAnim.stop();
        outroAnim.restart();
    }

    function playIntro() {
        outroAnim.stop();
        // Back from choosing books in yazi (LanguageReadingState.pickBooks): straight into the Read tab of the
        // language that was open, instead of the language choice. Set before the scan below, so it imports.
        const resume = LanguageReadingState.resumeRead;
        LanguageReadingState.resumeRead = false;
        if (resume)
            filter = "read";

        // Notes and the import folder may have changed since the last opening
        LanguageReadingState.refreshNotes();
        if (filter === "read")
            LanguageReadingState.scan();

        kbIndex = -1;
        // Back from the video player: its card has just shrunk into this panel -> there right away
        // (and stay in the language)
        if (LanguageAudioState.morphHandoff) {
            introAnim.stop();
            shown = 1;
            return ;
        }
        languageSwitch.stop();
        switchOut = 0;
        switchIn = 1;
        // Every opening starts with the language choice (except right after choosing books)
        closeImageBrowser();
        choosing = !resume;
        if (!resume)
            chooserView.reset();

        Qt.callLater(focusSearch);
        intro = true;
        introTimer.restart();
        introAnim.restart();
    }

    // Report the position of the panel (without the intro offset) for the morph into the video player
    function reportPanel() {
        if (!visible || panel.width <= 0)
            return ;

        // The picker fills the borderless picker window -> own coordinates = monitor coordinates (without
        // mapToItem: that would also measure the window's opening hop)
        LanguageAudioState.pickerPanel = Qt.rect(panel.x, root.panelTop, panel.width, panel.height);
    }

    Component.onCompleted: playIntro()
    onFilterChanged: {
        if (filter === "read")
            LanguageReadingState.scan();

    }
    onVisibleChanged: {
        if (visible)
            playIntro();

    }
    onPanelTopChanged: Qt.callLater(reportPanel)

    Connections {
        function onDownloadCompleted() {
            searchInput.text = "";
            root.searchQuery = "";
            LanguageAudioState.clearSearch();
            root.filter = "library";
        }

        target: LanguageAudioState
    }

    Timer {
        id: introTimer

        interval: 700
        onTriggered: root.intro = false
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

    MouseArea {
        anchors.fill: parent
        onClicked: LanguageAudioState.close()
    }

    // ═════════════════════════ Panel ═════════════════════════
    Item {
        id: panel

        width: root.panelWidth
        height: column.implicitHeight + 2 * root.pad
        x: (root.width - width) / 2
        y: root.panelTop + (1 - root.shown) * 24
        // The video player grows out of exactly this area: as soon as its card covers the panel (morph > 0.12),
        // the panel is gone; before that only the content fades out (see column)
        opacity: LanguageAudioState.videoMorph >= 0.12 ? 0 : Math.min(1, root.shown * 1.6)
        onWidthChanged: Qt.callLater(root.reportPanel)
        onHeightChanged: Qt.callLater(root.reportPanel)
        onXChanged: Qt.callLater(root.reportPanel)
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
        }

        Item {
            id: viewport
            anchors.fill: parent
            clip: root.switching
        }

        LanguageChooser {
            id: chooserView
            parent: viewport
            z: 1
            picker: root
            fullWidth: root.chooserFullW
            x: root.chooserMargin
            y: root.chooserMargin
            width: root.chooserW
            visible: root.choosing && opacity > 0.01
            opacity: 1 - root.browseK
            enabled: !root.browsingImage
        }

        Column {
            id: column
            parent: viewport

            x: root.pad
            y: root.pad
            width: root.innerWidth
            spacing: 0
            // Like the bar content during the calendar morph: off at the start of the player morph, on again at the end
            // of the morph back
            opacity: (1 - Math.max(0, Math.min(1, LanguageAudioState.videoMorph / 0.12))) * (root.choosing ? 1 : (1 - root.switchOut) * root.switchIn)
            transformOrigin: Item.Top
            scale: root.choosing ? 1 : 0.98 + 0.02 * root.switchIn
            transform: Translate {
                y: root.choosing ? 0 : (1 - root.switchIn) * 18 - root.switchOut * 10
            }

            // ═══════════ Header ═══════════
            Item {
                id: header

                width: parent.width
                height: root.choosing ? 0 : root.headH
                opacity: root.choosing ? 0 : 1
                visible: height > 0.5
                clip: true

                Behavior on height {
                    Smooth {
                        duration: 420
                    }

                }

                // Title row: back + name of the language (native name big, English name small next to it),
                // on the right today's listening time as a small ring (click = stats)
                Item {
                    id: titleRow

                    width: parent.width
                    height: root.titleH

                    Rectangle {
                        id: backBtn

                        // Flush with the search field: the header clips (for its height animation), at x: -4 the
                        // left edge of the round hover pill was cut off
                        x: 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        radius: height / 2
                        color: backMouse.containsMouse ? Theme.glassHover : WalColors.withAlpha(WalColors.color7, 0)
                        scale: backMouse.pressed ? 0.9 : 1

                        Text {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: -1
                            text: String.fromCodePoint(0xF053)
                            color: backMouse.containsMouse ? Theme.text : Theme.textDim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: backMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.backToChooser()
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }

                        }

                        Behavior on scale {
                            Springy {
                            }

                        }

                    }

                    Text {
                        id: langTitle

                        readonly property string nativeName: LanguageAudioState.nativeOf(LanguageAudioState.language)

                        anchors.left: backBtn.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: nativeName !== "" ? nativeName : LanguageAudioState.language
                        color: Theme.text
                        // Latin names in the serif (like the shell's big titles), otherwise a font with the characters
                        font.family: /^[\u0000-\u024F\s]+$/.test(text) ? Theme.fontDisplay : root.jp
                        font.pixelSize: 24
                        font.weight: /^[\u0000-\u024F\s]+$/.test(text) ? Font.Normal : Font.Medium
                    }

                    Text {
                        anchors.left: langTitle.right
                        anchors.leftMargin: 12
                        anchors.baseline: langTitle.baseline
                        visible: langTitle.nativeName !== ""
                        text: LanguageAudioState.language.toUpperCase()
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                        font.weight: Font.DemiBold
                        font.letterSpacing: Theme.microSpacing
                    }

                    Row {
                        id: today

                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        opacity: todayMouse.containsMouse ? 1 : 0.85

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                anchors.right: parent.right
                                text: Math.floor(root.todayMinutes) + " / " + Math.round(root.dailyGoal) + " min"
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeBody
                                font.weight: Font.Medium
                                font.features: Theme.tabular
                            }

                            Text {
                                anchors.right: parent.right
                                text: root.streak > 1 ? root.streak + "-DAY STREAK" : "TODAY"
                                color: Theme.textFaint
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeMicro
                                font.weight: Font.DemiBold
                                font.letterSpacing: Theme.microSpacing
                            }

                        }

                        ProgressRing {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            thickness: 3
                            color: Theme.accent
                            trackColor: Theme.track
                            value: Math.min(1, root.todayMinutes / root.dailyGoal)
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                            }

                        }

                    }

                    MouseArea {
                        id: todayMouse

                        anchors.fill: today
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.filter = "stats"
                    }

                }

                SearchField {
                    id: searchInput

                    anchors.left: parent.left
                    anchors.right: segmented.left
                    anchors.rightMargin: 10
                    y: root.titleH + root.headGap
                    height: root.fieldH
                    placeholder: root.filter === "read" ? (LanguageAudioState.isJapanese ? "Filter books · Enter: ISBN / Aozora" : "Filter books") : root.filter === "stats" ? "Search files · Enter: YouTube" : "Search · Enter: YouTube · paste link"
                    placeholderElide: true
                    focusOnStart: false
                    text: root.searchQuery
                    onTextChanged: {
                        root.searchQuery = text;
                        // Typing changes the list -> reset the keyboard selection
                        root.kbIndex = -1;
                        // Keep typing after a YouTube search -> back to the file search
                        if (LanguageAudioState.lastQuery !== "" && text !== LanguageAudioState.lastQuery)
                            LanguageAudioState.clearSearch();

                        if (text !== "" && root.filter !== "read")
                            root.filter = "library";

                        if (text === "" && root.filter === "read")
                            LanguageReadingState.clearResults();

                    }
                    onAccepted: {
                        if (text === "")
                            return ;

                        if (root.filter === "read")
                            LanguageReadingState.search(text);
                        else
                            LanguageAudioState.downloadFromInput(text);
                    }
                    onKeyPressed: (event) => {
                        // Ctrl+J/K = arrow down/up, the same in all pickers (PickerManager.navKey)
                        const key = PickerManager.navKey(event);
                        // Tab / Shift+Tab switch the tabs list/Read/stats (like a click at the top right)
                        if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
                            const tabs = root.tabKeys;
                            const dir = (key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) ? -1 : 1;
                            root.filter = tabs[(tabs.indexOf(root.filter) + dir + tabs.length) % tabs.length];
                            event.accepted = true;
                            return ;
                        }
                        // Read tab: Ctrl+H/L = left/right (shelf: selection, reader: chapter). Only here and
                        // not in navKey, because Ctrl+H/L may be taken in other pickers. Unlike the
                        // arrows they move no text cursor -> allowed even without a selection / with search text
                        if (root.filter === "read" && (event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_H || event.key === Qt.Key_L)) {
                            const dir = event.key === Qt.Key_L ? 1 : -1;
                            if (LanguageReadingState.view === "reader")
                                LanguageReadingState.step(dir);
                            else if (root.kbList === "shelf")
                                root.kbMove(dir);
                            event.accepted = true;
                            return ;
                        }
                        // Reading: arrow keys change the chapter (while nothing is typed)
                        if (root.filter === "read" && text === "" && LanguageReadingState.view === "reader" && (key === Qt.Key_Left || key === Qt.Key_Right)) {
                            LanguageReadingState.step(key === Qt.Key_Right ? 1 : -1);
                            event.accepted = true;
                            return ;
                        }
                        // Keyboard selection in the visible list (audio, YouTube, shelf, Aozora)
                        if (root.kbList !== "") {
                            const grid = root.kbList === "shelf";
                            if (key === Qt.Key_Down || key === Qt.Key_Up) {
                                const direction = key === Qt.Key_Down ? 1 : -1;
                                root.kbMove(root.kbList === "audio" ? libraryList.verticalStep(root.kbIndex, direction) : direction * (grid ? readView.bookGrid.columns : 1));
                                event.accepted = true;
                                return ;
                            }
                            // Left/right only on the shelf and only with a selection, otherwise they move the text cursor
                            if ((grid || root.kbList === "audio") && root.kbIndex >= 0 && (key === Qt.Key_Left || key === Qt.Key_Right)) {
                                root.kbMove(key === Qt.Key_Right ? 1 : -1);
                                event.accepted = true;
                                return ;
                            }
                            // Enter with a selection runs it, without a selection Enter searches as before (onAccepted)
                            if ((key === Qt.Key_Return || key === Qt.Key_Enter) && root.kbIndex >= 0 && root.kbActivate()) {
                                event.accepted = true;
                                return ;
                            }
                        }
                        // Escape while reading: first the search results, then back to the shelf, then close
                        if (key === Qt.Key_Escape && root.filter === "read" && text === "") {
                            if (readView.pickedWord !== null || readView.pickedSentence !== null)
                                readView.closePick();
                            else if (LanguageReadingState.results !== null || LanguageReadingState.searching)
                                LanguageReadingState.clearResults();
                            else if (LanguageReadingState.view === "reader")
                                LanguageReadingState.closeBook();
                            else
                                root.backToChooser();
                            event.accepted = true;
                            return ;
                        }
                        if (key === Qt.Key_Escape) {
                            if (text !== "") {
                                text = "";
                                LanguageAudioState.clearSearch();
                            } else {
                                root.backToChooser();
                            }
                            event.accepted = true;
                        }
                    }
                }

                PillSegmented {
                    id: segmented

                    anchors.right: parent.right
                    y: root.titleH + root.headGap
                    height: root.fieldH
                    segW: 76
                    current: root.filter
                    options: root.tabKeys.map((k) => {
                        return {
                            "label": k === "library" ? "Listen" : k === "read" ? "Read" : "Stats",
                            "key": k
                        };
                    })
                    onPicked: (key) => {
                        root.filter = key;
                    }
                }

            }

            // ═══════════ Download card ═══════════
            LanguageDownloadCard {
                id: dlCard

                picker: root
            }

            // ═══════════ Body ═══════════
            Item {
                id: body

                width: parent.width
                height: root.bodyH
                clip: true

                // ───────── Library ─────────
                // Image choice for a new language. Fixed final size: the panel grows over it instead of
                // rewrapping the grid constantly during the animation
                MediaBrowser {
                    id: imageBrowser

                    width: root.browseW - 2 * root.pad
                    height: root.browseH
                    onPicked: (path, kind) => {
                        return root.imagePicked(path, kind);
                    }
                    onDismissed: root.closeImageBrowser()
                    // After a vault's password field: keys back to the browser
                    onWantsKeys: browseKeys.forceActiveFocus()
                }

                // The browser takes no keys itself (as in the editors): everything to handleKey
                Item {
                    id: browseKeys

                    Keys.onPressed: (event) => {
                        imageBrowser.handleKey(event);
                        event.accepted = true;
                    }
                }

                Timer {
                    id: browseStartTimer

                    interval: 160
                    onTriggered: {
                        if (!root.browsingImage)
                            return ;

                        imageBrowser.show(false);
                        // Only select the start image, do not mark it as "Open" (nothing is opened here)
                        imageBrowser.currentPath = "";

                    }
                }

                // Fixed width instead of parent.width: when switching to the wide Read tab the list is not
                // stretched along, only cut off while it fades out
                Item {
                    id: libView

                    x: Math.round((parent.width - width) / 2)
                    width: root.listenWidth - 2 * root.pad
                    height: root.libH
                    opacity: (root.filter === "library" ? root.libraryProgress * (root.switching ? 1 : root.morphGate) : root.libraryProgress) * (root.choosing ? 0 : 1)
                    visible: opacity > 0.01

                    LanguageLibrary {
                        id: libraryList

                        // Room down to just above the bottom screen edge (header, margin, air subtracted)
                        maxHeight: Math.max(300, Math.min(820, root.height - root.targetTop - root.headH - 2 * root.pad - 90))
                        picker: root
                        width: parent.width
                        height: parent.height
                    }

                    transform: Translate {
                        y: (1 - root.libraryProgress) * 8
                    }

                }

                // ───────── Search results ─────────
                LanguageSearch {
                    id: searchView

                    picker: root
                }

                // ───────── Stats ─────────
                LanguageStats {
                    id: statsView

                    picker: root
                }

                // Read-Tab: pickers/language/LanguageReader.qml
                LanguageReader {
                    id: readView

                    picker: root
                }

            }

        }

    }

    // ───────────────────────── Behaviors ─────────────────────────
    SequentialAnimation {
        id: languageSwitch

        NumberAnimation {
            target: root
            property: "switchOut"
            from: 0
            to: 1
            duration: 190
            easing.type: Easing.InCubic
        }

        ScriptAction { script: root.applyLanguageSwitch() }

        Smooth {
            target: root
            property: "switchIn"
            from: 0
            to: 1
            duration: 460
        }
    }

    Behavior on bodyH {
        Smooth {
            duration: root.switching ? 460 : 420
        }

    }

    Behavior on browseK {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }

    }

    Behavior on panelWidth {
        Smooth {
            duration: root.switching ? 460 : 420
        }

    }

    Behavior on panelTop {
        Smooth {
            duration: root.switching ? 460 : 420
        }

    }

    Behavior on displayProgress {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }

    }

    Behavior on shownMinutes {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }

    }

    // Duration by target value (fade in slowly, fade out fast). Decided via root.filter
    // the animation still started with the old duration depending on the evaluation order.
    Behavior on statsProgress {
        enabled: !root.switching
        id: statsBehavior

        NumberAnimation {
            duration: statsBehavior.targetValue > 0.5 ? 760 : 150
            easing.type: Easing.OutCubic
        }

    }

    Behavior on readProgress {
        enabled: !root.switching
        id: readBehavior

        NumberAnimation {
            duration: readBehavior.targetValue > 0.5 ? 600 : 150
            easing.type: Easing.OutCubic
        }

    }

    // like Reveal: even, because the whole text shifts meanwhile
    Behavior on furiK {
        NumberAnimation {
            duration: 340
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.inOutSoft
        }

    }

    Behavior on libraryProgress {
        enabled: !root.switching
        id: libraryBehavior

        NumberAnimation {
            duration: libraryBehavior.targetValue > 0.5 ? 380 : 150
            easing.type: Easing.OutCubic
        }

    }

    Behavior on searchProgress {
        enabled: !root.switching
        id: searchBehavior

        NumberAnimation {
            duration: searchBehavior.targetValue > 0.5 ? 380 : 150
            easing.type: Easing.OutCubic
        }

    }

}
