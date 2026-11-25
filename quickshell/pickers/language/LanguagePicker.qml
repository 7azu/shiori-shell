import "../../common"
import "../../services"
import "../../windows"
import QtQuick

// Language tool (Super+J): the core. State (language choice or a language, tab, search text), size and morphs
// of the panel, the keyboard, and the layout frame. The surfaces are parts in this folder, which get this
// object as picker:
//   LanguageChooser (+ LanguageAddForm)   the languages as tiles when opening, adding a language
//   LanguageHeader                        name of the language, today's listening time, search field, tabs
//   LanguageDownloadCard                  the running download
//   LanguageLibrary (+ Library*)          Listen tab: stage and video grid
//   LanguageSearch                        YouTube results
//   LanguageStats (+ ListenStats)         Stats tab
//   LanguageReader (+ Reader*)            Read tab: shelf and reader
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
    // The search field lives in the header (LanguageHeader): the core reads and clears its text and gives it the focus
    readonly property var searchInput: header.searchInput
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
    readonly property bool isSearchMode: searchQuery !== "" && (LanguageDownloadState.isSearching || LanguageDownloadState.searchResults.length > 0)
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
    readonly property var results: LanguageDownloadState.searchResults
    // Listening time in numbers for the stats tab and the header (ListenStats.qml)
    readonly property ListenStats listenStats: ListenStats {
        picker: root
    }
    // ───────────────────────── Body sizing ─────────────────────────
    readonly property real libH: libraryList.wanted
    readonly property real moreH: LanguageDownloadState.hasMoreResults || LanguageDownloadState.isLoadingMore ? 52 : 0
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
    readonly property bool showDl: LanguageDownloadState.isDownloading || LanguageDownloadState.downloadError !== ""

    // ───────────────────────── Helpers ─────────────────────────
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
                LanguageDownloadState.clearSearch();
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
        if (kbList === "youtube" && i >= n && LanguageDownloadState.hasMoreResults && !LanguageDownloadState.isLoadingMore)
            LanguageDownloadState.loadMoreResults();

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

            if (!LanguageDownloadState.isDownloading)
                LanguageDownloadState.downloadVideo(r.url, r.title);

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

    // Keys of the search field (it has the focus inside a language): tabs, the keyboard selection, chapters
    // in the reader, Enter and Esc
    function handleKey(event) {
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
        if (root.filter === "read" && searchInput.text === "" && LanguageReadingState.view === "reader" && (key === Qt.Key_Left || key === Qt.Key_Right)) {
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
        if (key === Qt.Key_Escape && root.filter === "read" && searchInput.text === "") {
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
            if (searchInput.text !== "") {
                searchInput.text = "";
                LanguageDownloadState.clearSearch();
            } else {
                root.backToChooser();
            }
            event.accepted = true;
        }
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
            LanguageDownloadState.clearSearch();
            root.filter = "library";
        }

        target: LanguageDownloadState
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
            LanguageHeader {
                id: header

                picker: root
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
