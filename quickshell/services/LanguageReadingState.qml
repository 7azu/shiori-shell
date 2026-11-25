// Reading material for the Read tab of the language tool (pickers/language/LanguagePicker.qml), as books with
// chapters, for the language that is open (LanguageAudioState.language):
//   - imported books, managed by scripts/jp_library.py (EPUB/TXT/PDF from the books folder):
//     Japanese in ~/.local/share/quickshell/jp-reader with the books folder from the setting "books"
//     (plus Aozora Bunko); any other language in ~/.local/share/quickshell/reader/<Name> with
//     <language folder>/Books. The script learns which one from readerEnv.
//   - Japanese only: "Notes" = every Markdown table with a column "Kana" in the notes folder (setting
//     "notes", sentence cards); furigana, clickable words (JMdict) and the Aozora/ISBN search
// Chapters are either "cards" (sentences: [{ja, ro, de, sp}]) or "flow" (paras: [[{ja, ro, en}]]); "ja" is the
// sentence text in every language, "ro" its rōmaji / Latin transliteration (empty for Latin scripts).
// Progress (read chapters, switches, last opened): Quickshell.stateDir/japanese-reading.json
// Furigana in the text: {kanji|reading}, spaces are break points.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    property var noteTexts: []
    property var imported: []
    // Content of the open imported book (the index only knows chapter titles)
    property var bookData: null
    readonly property var books: {
        const out = [];
        if (isJapanese && noteTexts.length > 0)
            out.push({
            "id": "notes",
            "title": "メモ",
            "subtitle": "From your notes",
            "level": "Note",
            "kind": "cards",
            "chapters": noteTexts
        });

        const imp = imported.slice().sort((x, y) => {
            return (y.added || 0) - (x.added || 0);
        });
        for (const b of imp) out.push({
            "id": b.id,
            "title": b.title,
            "subtitle": b.author || "",
            "level": b.level,
            "kind": "flow",
            "imported": true,
            "source": b.source,
            "cover": b.cover || "",
            "note": b.note || "",
            "chapters": b.chapters
        })
        return out;
    }
    readonly property string view: currentBookId !== "" && currentBook ? "reader" : "shelf"
    property string currentBookId: ""
    // Book ID -> last opened chapter
    property var lastChapter: ({
    })
    // id -> time (ms) when marked as read (sentence cards: text ID, otherwise "<book>#<chapter>")
    property var readIds: ({
    })
    readonly property var currentBook: {
        for (const b of books) {
            if (b.id === currentBookId)
                return b;

        }
        return null;
    }
    readonly property bool isFlow: !!currentBook && currentBook.kind === "flow"
    readonly property var chapters: currentBook ? currentBook.chapters : []
    readonly property int currentIndex: {
        if (!currentBook || chapters.length === 0)
            return -1;

        const i = lastChapter[currentBookId] || 0;
        return Math.max(0, Math.min(chapters.length - 1, i));
    }
    // Current chapter with content: cards -> {title, titleDe, sentences, words}, flow -> {title, en, paras}
    readonly property var current: {
        // briefly inconsistent when switching/closing (binding order)
        const c = currentIndex >= 0 && currentBook ? chapters[currentIndex] : null;
        if (!c)
            return null;

        if (!currentBook.imported)
            return c;

        const d = bookData && bookData.id === currentBookId ? bookData.chapters[currentIndex] : null;
        return {
            "title": c.title,
            "en": "",
            "translated": c.translated,
            "paras": d ? d.paras : [],
            "loading": !d
        };
    }
    readonly property string currentId: currentIndex >= 0 ? chapterId(currentBook, currentIndex) : ""
    readonly property int readCount: currentBook ? bookReadCount(currentBook) : 0
    property bool showFurigana: true
    // Sentence also as reading (hiragana; katakana words stay katakana) - replaces the old rōmaji
    property bool showKana: false
    property bool showTranslation: false
    // Reader in the big window ("Bigger" button in the picker)
    property bool big: false
    property bool loaded: false
    // ── Bibliothek verwalten (scripts/jp_library.py) ──
    property bool busy: false
    property string busyWhat: ""     // "scan" | "import" | "translate" | "delete"
    property string busyBook: ""
    property int busyChapter: -1
    property string status: ""
    property string error: ""
    property bool searching: false
    // Translation backend that "translation.provider" resolves to (scripts/jp_translate.py provider):
    // "claude" | "codex" | "ollama" | "deepl" | "argos", "" = off -> no translate buttons
    property string translator: ""
    // yazi is open to choose books (pickBooks); resumeRead = open the picker again in the Read tab
    property bool pickingBooks: false
    property bool resumeRead: false
    // {kind: "isbn", book, free} | {kind: "aozora", results, title} | null
    property var results: null
    property string resultsQuery: ""
    property var jobResult: null
    // old progress file: last opened text ID, resolved as soon as the books are loaded
    property string pendingLegacy: ""
    // Language of the books (the one open in the picker); Japanese keeps its old folders
    readonly property string language: LanguageAudioState.language
    readonly property bool isJapanese: LanguageAudioState.isJapanese
    // ISO code for the scripts (translation, encodings); unknown languages pass their name
    readonly property string languageCode: LanguageAudioState.languageCodes[language] || language.toLowerCase()
    // Settings "notes" (Markdown notes with a "Kana" table column, optional, Japanese only) and "books"
    readonly property string notesDir: Settings.folder("notes")
    readonly property string importDir: isJapanese ? Settings.folder("books") : LanguageAudioState.dirOf(language) + "/Books"
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + (isJapanese ? "/quickshell/jp-reader" : "/quickshell/reader/" + language)
    // Tells scripts/jp_library.py which language and folders it works on
    readonly property var readerEnv: ({
        "SHIORI_READER_LANG": languageCode,
        "SHIORI_READER_LANG_NAME": language,
        "SHIORI_READER_DATA": dataDir,
        "SHIORI_READER_BOOKS": importDir
    })
    readonly property string script: Qt.resolvedUrl("../scripts/jp_library.py").toString().replace("file://", "")
    readonly property string translateScript: Qt.resolvedUrl("../scripts/jp_translate.py").toString().replace("file://", "")
    readonly property string bookPickScript: Qt.resolvedUrl("../scripts/book_pick.sh").toString().replace("file://", "")
    readonly property string progressFile: Quickshell.stateDir + "/japanese-reading.json"

    function chapterId(book, i) {
        if (!book)
            return "";

        return book.kind === "cards" ? book.chapters[i].id : book.id + "#" + i;
    }

    function bookReadCount(book) {
        let n = 0;
        for (let i = 0; i < book.chapters.length; i++) {
            if (readIds[chapterId(book, i)])
                n++;

        }
        return n;
    }

    function hasBook(id) {
        for (const b of books) {
            if (b.id === id)
                return true;

        }
        return false;
    }

    function openBook(id) {
        currentBookId = id;
        save();
    }

    function closeBook() {
        currentBookId = "";
        save();
    }

    function select(i) {
        if (!currentBook || i === currentIndex || i < 0 || i >= chapters.length)
            return ;

        const m = Object.assign({
        }, lastChapter);
        m[currentBookId] = i;
        lastChapter = m;
        save();
    }

    function step(delta) {
        if (currentIndex >= 0)
            select(Math.max(0, Math.min(chapters.length - 1, currentIndex + delta)));

    }

    function isRead(id) {
        return !!readIds[id];
    }

    function setRead(id, on) {
        const r = Object.assign({
        }, readIds);
        if (on)
            r[id] = Date.now();
        else
            delete r[id];
        readIds = r;
        save();
    }

    function toggle(name) {
        root[name] = !root[name];
        save();
    }

    function refreshNotes() {
        notesProc.running = false;
        notesProc.running = true;
    }

    // Which translator is ready can change (CLI installed, Ollama started, key added): checked at start,
    // whenever the Read tab scans and when the settings change
    function refreshTranslator() {
        translatorProc.running = false;
        translatorProc.running = true;
    }

    // ── Jobs ──
    function run(what, args, book, chapter) {
        if (busy)
            return ;

        busy = true;
        busyWhat = what;
        busyBook = book || "";
        busyChapter = chapter === undefined ? -1 : chapter;
        status = "";
        error = "";
        jobProc.command = ["python3", script].concat(args);
        jobProc.running = true;
    }

    // Take new files from the import folder (when opening the tab; nothing new, no tokenizer start)
    function scan() {
        refreshTranslator();
        run("scan", ["scan"]);
    }

    function importAozora(id) {
        run("import", ["aozora-import", id], "aozora-" + id);
    }

    function translate() {
        if (currentBook && currentBook.imported)
            run("translate", ["translate", currentBookId, String(currentIndex)], currentBookId, currentIndex);

    }

    function deleteBook(id) {
        if (currentBookId === id)
            closeBook();

        run("delete", ["delete", id], id);
    }

    function openImportDir() {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && xdg-open \"$1\"", "_", importDir]);
    }

    // "Add a book" card: choose files in yazi (scripts/book_pick.sh copies them into the books folder).
    // The picker lies above all windows, so it closes for yazi and afterwards opens again right in the
    // Read tab (resumeRead, see LanguagePicker.playIntro); its scan then imports the new files.
    function pickBooks() {
        if (pickingBooks || importDir === "")
            return ;

        pickingBooks = true;
        PickerManager.close();
        bookPickProc.command = ["bash", bookPickScript, importDir];
        bookPickProc.running = true;
    }

    // Enter in the search field: ISBN -> book data + free full texts, otherwise the Aozora catalog
    function search(q) {
        q = String(q || "").trim();
        // Aozora and the ISBN data (NDL) are Japanese; other languages only filter the shelf
        if (q === "" || !isJapanese)
            return ;

        const isbn = q.replace(/[-\s]/g, "");
        resultsQuery = q;
        searching = true;
        error = "";
        searchProc.running = false;
        searchProc.command = ["python3", script].concat(/^(97[89])?\d{9}[\dXx]$/.test(isbn) ? ["isbn", isbn] : ["aozora-search", q]);
        searchProc.running = true;
    }

    function clearResults() {
        searchProc.running = false;
        searching = false;
        results = null;
        resultsQuery = "";
    }

    function lastJson(lines) {
        for (let i = lines.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(lines[i]);
                if (o.ok !== undefined)
                    return o;

            } catch (e) {
            }
        }
        return {
            "ok": false,
            "error": "No answer from jp_library.py"
        };
    }

    function jobLine(line) {
        try {
            const o = JSON.parse(line);
            if (o.progress)
                status = o.progress;
            else if (o.ok !== undefined)
                jobResult = o;
        } catch (e) {
        }
    }

    function jobDone() {
        const o = jobResult || {
            "ok": false,
            "error": "Cancelled"
        };
        jobResult = null;
        const what = busyWhat;
        busy = false;
        busyWhat = "";
        status = "";
        if (!o.ok) {
            error = o.error || "Error";
        } else if (what === "scan") {
            if (o.errors && o.errors.length > 0)
                error = o.errors.join("\n");
            else if (o.imported && o.imported.length > 0)
                status = "Imported: " + o.imported.join(", ");
        } else if (what === "import" && o.id) {
            status = "「" + o.title + "」 is now in your library";
        }
        indexView.reload();
        bookView.reload();
    }

    // "{日本|にほん}語です" -> [{t:"日本", r:"にほん"}, {t:"語"}, {t:"で"}, {t:"す"}, ...]
    // Spaces become {gap:true}. Kana/punctuation one by one, so Flow can break anywhere;
    // Latin words (names) stay in one piece.
    function tokens(ja, si) {
        const out = [];
        const re = /\{([^|}]+)\|([^}]+)\}/g;
        let last = 0;
        let m;
        const plain = (s) => {
            // Words of alphabetic scripts stay in one piece (Latin incl. extended, Greek, Cyrillic, Hebrew,
            // Arabic, Devanagari, Hangul); kana, kanji and punctuation one by one so lines can break anywhere
            const parts = s.match(/[A-Za-z0-9À-ɏ̀-ͯͰ-ϿЀ-ԯ֐-׿؀-ۿऀ-ॿḀ-ỿ가-힯'’-]+|\s+|./gu) || [];
            for (const p of parts) {
                if (/^\s+$/.test(p))
                    out.push({
                    "t": "",
                    "r": "",
                    "gap": true,
                    "si": si
                });
                else if (/^[、。，．！？!?…）」』,.;:»”)]$/.test(p) && out.length > 0 && !out[out.length - 1].gap && !out[out.length - 1].r)
                    out[out.length - 1].t += p; // punctuation never at the start of a line
                else
                    out.push({
                    "t": p,
                    "r": "",
                    "gap": false,
                    "si": si
                });
            }
        };
        while ((m = re.exec(ja)) !== null) {
            plain(ja.slice(last, m.index));
            out.push({
                "t": m[1],
                "r": m[2],
                "gap": false,
                "si": si
            });
            last = re.lastIndex;
        }
        plain(ja.slice(last));
        return out;
    }

    // Paragraph (list of sentences) -> tokens, each with sentence number si
    function paraTokens(para) {
        let out = [];
        for (let i = 0; i < para.length; i++) out = out.concat(tokens(para[i].ja, i))
        return out;
    }

    // Only the visible text, without furigana markup
    function plainText(ja) {
        return String(ja || "").replace(/\{([^|}]+)\|[^}]+\}/g, "$1");
    }

    // ── Clickable words (scripts/jp_subs.py words: splitting + JMdict, cached there) ──
    // Sentence markup -> [{t, f?, l?, lr?, d?, gap?}, …] (null = failed); fetched for the open and the
    // next chapter
    property var words: ({
    })
    property var wordsPending: []
    readonly property string subsScript: Qt.resolvedUrl("../scripts/jp_subs.py").toString().replace("file://", "")

    // Sentence as reading: {kanji|reading} -> reading, everything else (kana, katakana words, characters) stays
    function kanaText(ja) {
        return String(ja || "").replace(/\{([^|}]+)\|([^}]+)\}/g, "$2");
    }

    // Second line under a sentence ("かな" / "Latin" chip): Japanese the kana reading from the furigana,
    // other languages the transliteration stored at import ("" for Latin scripts)
    function readingOf(sentence) {
        if (!sentence)
            return "";

        return isJapanese ? kanaText(sentence.ja) : (sentence.ro || "");
    }

    function sentencesOf(ch) {
        if (!ch)
            return [];

        if (ch.paras) {
            const out = [];
            for (const para of ch.paras) for (const sn of para) out.push(sn.ja)
            return out;
        }
        return (ch.sentences || []).map((sn) => {
            return sn.ja;
        });
    }

    function needWords(list) {
        // Clickable words come from fugashi + JMdict: Japanese only, elsewhere a click selects the sentence
        if (!isJapanese)
            return ;

        const miss = list.filter((sn) => {
            return sn && words[sn] === undefined && wordsPending.indexOf(sn) < 0;
        });
        if (miss.length === 0)
            return ;

        wordsPending = wordsPending.concat(miss);
        if (!wordsProc.running)
            runWords();

    }

    function runWords() {
        if (wordsPending.length === 0)
            return ;

        // in packages: one call per chapter is usually enough, very long chapters come piece by piece
        wordsProc.batch = wordsPending.slice(0, 300);
        wordsProc.command = ["python3", subsScript, "words", JSON.stringify(wordsProc.batch)];
        wordsProc.running = true;
    }

    function prefetchWords() {
        if (!currentBook || currentIndex < 0)
            return ;

        let list = sentencesOf(current);
        // the next chapter along with it (library/notes have the content directly, imported ones in bookData)
        const ni = currentIndex + 1;
        if (ni < chapters.length) {
            const next = currentBook.imported ? (bookData && bookData.id === currentBookId ? bookData.chapters[ni] : null) : chapters[ni];
            list = list.concat(sentencesOf(next));
        }
        needWords(list);
    }

    onCurrentChanged: Qt.callLater(prefetchWords)

    function save() {
        if (!loaded)
            return ;

        progressView.setText(JSON.stringify({
            "read": readIds,
            "book": currentBookId,
            "chapters": lastChapter,
            "furigana": showFurigana,
            "kana": showKana,
            "translation": showTranslation,
            "big": big
        }, null, 2) + "\n");
    }

    function applyProgress(raw) {
        let p = {
        };
        try {
            p = JSON.parse(raw && raw.length > 0 ? raw : "{}");
        } catch (e) {
            console.warn("LanguageReadingState: progress invalid:", e);
        }
        readIds = (p.read && typeof p.read === "object") ? p.read : ({
        });
        lastChapter = (p.chapters && typeof p.chapters === "object") ? p.chapters : ({
        });
        currentBookId = typeof p.book === "string" ? p.book : "";
        // Old format: only "current" (a note's text ID)
        if (p.book === undefined && typeof p.current === "string" && p.current.startsWith("note:")) {
            pendingLegacy = p.current;
            currentBookId = "notes";
        }
        showFurigana = p.furigana !== false;
        showKana = p.kana === true || p.romaji === true; // take over the old "romaji"
        showTranslation = p.translation === true;
        big = p.big === true;
        loaded = true;
        resolveLegacy();
    }

    function resolveLegacy() {
        if (pendingLegacy === "" || !currentBook)
            return ;

        for (let i = 0; i < chapters.length; i++) {
            if (chapters[i].id === pendingLegacy) {
                const m = Object.assign({
                }, lastChapter);
                m[currentBookId] = i;
                lastChapter = m;
                pendingLegacy = "";
                save();
                return ;
            }
        }
    }

    onBooksChanged: resolveLegacy()

    // ---- Obsidian notes -> reading texts ----
    function cleanCell(s) {
        return String(s || "").replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2").replace(/\[\[([^\]]+)\]\]/g, "$1").replace(/[*`_]/g, "").replace(/<[^>]+>/g, "").trim();
    }

    function hasJapanese(s) {
        return /[぀-ヿ一-鿿]/.test(s);
    }

    function hasKanji(s) {
        return /[一-鿿]/.test(s);
    }

    function cells(line) {
        let l = line.trim();
        if (l.startsWith("|"))
            l = l.slice(1);

        if (l.endsWith("|"))
            l = l.slice(0, -1);

        return l.split("|").map((c) => {
            return c.trim();
        });
    }

    function parseNote(path, md) {
        const lines = md.split("\n");
        const file = path.split("/").pop().replace(/\.md$/, "");
        const h1 = (md.match(/^#\s+(.+)$/m) || [])[1];
        const noteTitle = cleanCell(h1 || file);
        const result = [];
        let heading = "";
        for (let i = 0; i < lines.length; i++) {
            const hm = lines[i].match(/^#{2,4}\s+(.+)$/);
            if (hm) {
                heading = cleanCell(hm[1]);
                continue;
            }
            const isRow = lines[i].trim().startsWith("|");
            const next = lines[i + 1] || "";
            if (!isRow || !/^\s*\|?\s*:?-{2,}/.test(next))
                continue;

            const head = cells(lines[i]).map((h) => {
                return cleanCell(h).toLowerCase();
            });
            const kana = head.findIndex((h) => {
                return /^(kana|hiragana|katakana|japanisch|japanese)$/.test(h);
            });
            if (kana < 0)
                continue;

            const ro = head.findIndex((h) => {
                return /r[oō]maji/.test(h);
            });
            const kanji = head.findIndex((h) => {
                return h === "kanji";
            });
            const de = head.findIndex((h) => {
                return /bedeutung|deutsch|meaning|übersetzung|english|translation/.test(h);
            });
            const sentences = [];
            let j = i + 2;
            for (; j < lines.length && lines[j].trim().startsWith("|"); j++) {
                const c = cells(lines[j]);
                const k = cleanCell(c[kana]);
                if (!hasJapanese(k))
                    continue;

                const kj = kanji >= 0 ? cleanCell(c[kanji]) : "";
                let meaning = de >= 0 ? cleanCell(c[de]) : "";
                if (!meaning) {
                    // e.g. a number table: first remaining column ("1", "2" ...)
                    for (let x = 0; x < c.length; x++) {
                        const v = cleanCell(c[x]);
                        if (x !== kana && x !== ro && x !== kanji && v && !hasJapanese(v)) {
                            meaning = v;
                            break;
                        }
                    }
                }
                sentences.push({
                    "ja": hasKanji(kj) && !hasKanji(k) ? "{" + kj + "|" + k + "}" : k,
                    "ro": ro >= 0 ? cleanCell(c[ro]) : "",
                    "de": meaning
                });
            }
            i = j - 1;
            if (sentences.length === 0)
                continue;

            const rel = path.slice(notesDir.length + 1);
            result.push({
                "id": "note:" + rel + "#" + (heading || result.length),
                "level": "Note",
                "title": heading || noteTitle,
                "titleDe": noteTitle,
                "fromNotes": true,
                "sentences": sentences,
                "words": []
            });
        }
        return result;
    }

    function applyNotes(raw) {
        const out = [];
        const chunks = raw.split("\u001e");
        for (const chunk of chunks) {
            const nl = chunk.indexOf("\n");
            if (nl <= 0)
                continue;

            try {
                for (const t of parseNote(chunk.slice(0, nl), chunk.slice(nl + 1))) out.push(t)
            } catch (e) {
                console.warn("LanguageReadingState: note not readable:", chunk.slice(0, nl), e);
            }
        }
        noteTexts = out;
    }

    Component.onCompleted: {
        refreshNotes();
        refreshTranslator();
    }

    Connections {
        function onDataChanged() {
            root.refreshTranslator();
        }

        target: Settings
    }

    Process {
        id: bookPickProc

        onExited: {
            root.pickingBooks = false;
            root.resumeRead = true;
            PickerManager.open("language");
        }
    }

    Process {
        id: translatorProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.translator = JSON.parse(text).provider || "";
                } catch (e) {
                    root.translator = "";
                }
            }
        }

        command: ["python3", root.translateScript, "provider"]
    }

    // Index of the imported books; reloaded after every job (os.replace -> new file)
    FileView {
        id: indexView

        path: root.dataDir + "/index.json"
        printErrors: false
        onLoaded: {
            try {
                root.imported = JSON.parse(text()).books || [];
            } catch (e) {
                console.warn("LanguageReadingState: index.json invalid:", e);
            }
        }
        onLoadFailed: root.imported = []
    }

    FileView {
        id: bookView

        path: root.currentBook && root.currentBook.imported ? root.dataDir + "/books/" + root.currentBookId + ".json" : ""
        printErrors: false
        onPathChanged: root.bookData = null
        onLoaded: {
            try {
                root.bookData = JSON.parse(text());
            } catch (e) {
                console.warn("LanguageReadingState: book not readable:", e);
                root.bookData = null;
            }
        }
    }

    FileView {
        id: progressView

        path: root.progressFile
        printErrors: false
        onLoaded: root.applyProgress(text())
        onLoadFailed: root.applyProgress("")
    }

    Process {
        id: wordsProc

        property var batch: []
        property string lastLine: ""

        onRunningChanged: {
            if (running) {
                lastLine = "";
                return ;
            }
            let res = null;
            try {
                res = JSON.parse(lastLine);
            } catch (e) {
            }
            let w = Object.assign({
            }, root.words);
            if (res && res.ok && res.words)
                Object.assign(w, res.words);
            else
                console.warn("LanguageReadingState: words failed:", lastLine.slice(0, 200));
            // do not ask again endlessly: remember what is missing as empty
            for (const sn of batch) if (w[sn] === undefined)
                w[sn] = null;
            root.words = w;
            root.wordsPending = root.wordsPending.filter((sn) => {
                return batch.indexOf(sn) < 0;
            });
            root.runWords();
        }

        stdout: SplitParser {
            onRead: (data) => {
                if (data.indexOf('"progress"') < 0)
                    wordsProc.lastLine = data;

            }
        }

    }

    Process {
        id: jobProc

        environment: root.readerEnv
        onExited: root.jobDone()

        stdout: SplitParser {
            onRead: (line) => {
                return root.jobLine(line);
            }
        }

    }

    Process {
        id: searchProc

        environment: root.readerEnv

        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.lastJson(text.split("\n"));
                root.searching = false;
                if (!o.ok) {
                    root.error = o.error || "Search failed";
                    root.results = null;
                } else if (o.book) {
                    root.results = {
                        "kind": "isbn",
                        "book": o.book,
                        "free": o.free || []
                    };
                } else {
                    root.results = {
                        "kind": "aozora",
                        "results": o.results || []
                    };
                }
            }
        }

    }

    // All notes (without Excalidraw) in one go, each introduced by \x1e + path
    Process {
        id: notesProc

        command: ["bash", "-c", "[ -d \"$1\" ] || exit 0; find \"$1\" -name '*.md' ! -name '*.excalidraw.md' ! -path '*/.*' -print0 | sort -z | while IFS= read -r -d '' f; do printf '\\036%s\\n' \"$f\"; cat -- \"$f\"; printf '\\n'; done", "_", root.notesDir]

        stdout: StdioCollector {
            onStreamFinished: root.applyNotes(text)
        }

    }

}
