import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    // ── Languages ──
    // Every language = a folder with its mp3/mp4 (+ .subs/, .thumbs/). New languages live in
    // the languages folder (Settings "languages") as <folder>/<Name>; every subfolder there counts as a
    // language (the plus button in the picker creates one). Settings "languageFolders" adds languages
    // that live somewhere else, e.g. an older folder that should stay where it is.
    readonly property string languagesRoot: Settings.folder("languages")
    readonly property var legacyDirs: Settings.languageFolders()
    // Subtitle language for video downloads (yt-dlp --sub-langs); unknown language -> video without subtitles
    readonly property var languageCodes: ({
        "Arabic": "ar", "Chinese": "zh", "Dutch": "nl", "English": "en", "French": "fr", "German": "de",
        "Greek": "el", "Hindi": "hi", "Indonesian": "id", "Italian": "it", "Japanese": "ja", "Korean": "ko",
        "Polish": "pl", "Portuguese": "pt", "Russian": "ru", "Spanish": "es", "Swedish": "sv", "Thai": "th",
        "Turkish": "tr", "Ukrainian": "uk", "Vietnamese": "vi"
    })
    property var languages: ["Japanese"]
    // Per language for the choice tiles: { name: {dir, audio, video, weekSecs, totalSecs} }
    property var languageInfo: ({
    })
    // Mark + own name for the tiles (otherwise the first two letters)
    readonly property var languageMarks: ({
        "Arabic": ["ع", "العربية"], "Chinese": ["中", "中文"], "Dutch": ["Nl", "Nederlands"],
        "English": ["En", "English"], "French": ["Fr", "Français"], "German": ["De", "Deutsch"],
        "Greek": ["Ω", "Ελληνικά"], "Hindi": ["अ", "हिन्दी"], "Indonesian": ["Id", "Bahasa Indonesia"],
        "Italian": ["It", "Italiano"], "Japanese": ["あ", "日本語"], "Korean": ["한", "한국어"],
        "Polish": ["Pl", "Polski"], "Portuguese": ["Pt", "Português"], "Russian": ["Я", "Русский"],
        "Spanish": ["Es", "Español"], "Swedish": ["Sv", "Svenska"], "Thai": ["ก", "ไทย"],
        "Turkish": ["Tr", "Türkçe"], "Ukrainian": ["Ї", "Українська"], "Vietnamese": ["Vi", "Tiếng Việt"]
    })

    // Character chosen by the user (when adding, <folder>/.language.json) before the known one
    function markOf(name) {
        const own = languageInfo[name] && languageInfo[name].mark;
        return own ? own : defaultMarkOf(name);
    }

    // Suggestion without an own character: known language -> its character, otherwise the first two letters
    function defaultMarkOf(name) {
        const m = languageMarks[name];
        return m ? m[0] : name.slice(0, 2);
    }

    function nativeOf(name) {
        const m = languageMarks[name];
        return m && m[1] !== name ? m[1] : "";
    }
    property string language: "Japanese"
    readonly property bool isJapanese: language === "Japanese"
    readonly property string languageCode: languageCodes[language] || ""
    readonly property string downloadDir: dirOf(language)
    readonly property string statsFile: statsFileOf(language)
    // What is playing can come from another language (switched during playback):
    // remember folder + language of the playing file separately (paths, subtitles, listening time)
    property string playDir: downloadDir
    property string playLanguage: language
    readonly property string ipcSocket: "/tmp/mpv_japanese.sock"
    // Subtitles for videos: yt-dlp puts the .vtt into .subs/, scripts/jp_subs.py turns them into
    // <name>.json (words + dictionary) and <name>.srt (for mpv, only for timing)
    readonly property string subsDir: playDir + "/.subs"
    readonly property string subsScript: Qt.resolvedUrl("../scripts/jp_subs.py").toString().replace("file://", "")
    readonly property string prefsFile: Quickshell.stateDir + "/japanese-audio-prefs.json"
    // YouTube login: yt-dlp reads the cookies fresh from Zen on every call (no cookie file)
    readonly property string cookieArgs: "spec=$(\"$HOME/.config/quickshell/scripts/zen_cookies.sh\") && cookies=(--cookies-from-browser \"$spec\") || cookies=(); "
    // The picker is a normal entry in the PickerManager (before it had its own state with special cases
    // in the PickerWindow)
    readonly property bool isOpen: PickerManager.isOpen("language")
    property bool isPlaying: false
    property string currentFile: ""
    property string statusText: ""
    property var library: []
    property var stats: ({
    })
    property real downloadProgress: 0
    property bool isDownloading: false
    property bool isConverting: false
    property bool cancelled: false
    property bool restarting: false
    property int startPollTries: 0
    property string downloadTitle: ""
    property string downloadError: ""
    property bool isSearching: false
    property string searchError: ""
    property var searchResults: []
    // YouTube search page by page: first page with Enter, more with "Load more"
    readonly property int searchPageSize: 15
    property string lastQuery: ""
    property bool isLoadingMore: false
    property bool hasMoreResults: false
    // Cancelled search: ignore lines of the old yt-dlp process still in the buffer
    property bool searchCancelled: false
    // ── Video + subtitles ──
    // Download as audio (mp3) or video (mp4 + subtitles); remembered in prefsFile
    // Now only videos (listening in the background works with them too); "audio" only stays readable for
    // old prefs, but is no longer set
    property string downloadMode: "video"
    // Morph picker <-> player: last position of the language panel (window coordinates of the monitor),
    // reported by the picker. The player grows out of it and shrinks back into it when going back.
    property rect pickerPanel: Qt.rect(0, 0, 0, 0)
    // Back from the player: the picker appears without its own intro exactly where the card ends
    property bool morphHandoff: false
    // Progress of the player morph (0 = panel, 1 = player), reported by the player; the picker fades
    // its panel content out with it (0-0.12) and the panel away completely as soon as the card covers it
    property real videoMorph: 0
    // windows/LanguageVideoPlayer.qml plays videos (QtMultimedia, like the video tool), mp3 still mpv.
    // The state sends commands via videoCommand, the player reports position/pause back.
    property bool videoLoaded: false
    // Volume of the video player (0..1, perceived; remembered in prefsFile)
    property real videoVolume: 0.7
    // Where every video was last (seconds, remembered in prefsFile): continue watching instead of from the start
    property var videoPositions: ({
    })
    // Last started video per language (remembered in prefsFile): after a restart the stage shows
    // what played last - the positions alone do not tell which video was last
    property var lastVideos: ({
    })
    property bool videoOpen: false
    signal videoCommand(string cmd, var arg)
    // Show the subtitle bar (windows/LanguageSubtitles.qml)
    property bool subsShown: true
    // File names without extension for which prepared subtitles exist
    property var subbed: ({
    })
    // Metadata per file for the list view (scripts/lang_media.py):
    // { "<file>": {kind, size, mtime, duration, thumb} }; comes shortly after library
    property var meta: ({
    })
    property bool isPreparingSubs: false
    property string downloadedFile: ""
    // Subtitles of the playing file and the line being spoken (-1 = none)
    property var cues: []
    property int cueIndex: -1
    property int translatingIdx: -1
    property string translateError: ""
    // Word clicked -> paused; it continues when the explanation is closed
    property bool resumeAfterLookup: false
    readonly property bool mpvRunning: mpvProc.running
    readonly property bool currentIsVideo: isVideo(currentFile)
    readonly property bool mediaActive: currentIsVideo ? videoLoaded : mpvProc.running
    readonly property bool watching: currentIsVideo && videoLoaded && videoOpen
    property real currentPosition: 0
    property real currentDuration: 0
    property double sessionStart: 0
    property double sessionCommitted: 0

    signal downloadCompleted()

    function toggle() {
        PickerManager.toggle("language");
    }

    function isVideo(file) {
        return /\.mp4$/i.test(file || "");
    }

    function stemOf(file) {
        return (file || "").replace(/\.(mp3|mp4)$/i, "");
    }

    // Path -> file:// URL for Image sources. Video titles may contain # or ? ("Podcast #1"): raw, everything after #
    // was taken as the URL fragment and the thumbnail stayed empty. "" stays "" (no image).
    function fileUrl(path) {
        return path ? "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F") : "";
    }

    function hasSubs(file) {
        return root.subbed[stemOf(file)] === true;
    }

    function dirOf(name) {
        return legacyDirs[name] || (languagesRoot + "/" + name);
    }

    // Japanese keeps its previous stats file
    function statsFileOf(name) {
        return name === "Japanese" ? Quickshell.stateDir + "/japanese-audio-stats.json" : Quickshell.stateDir + "/language-stats/" + name.replace(/[^A-Za-z0-9_-]/g, "_") + ".json";
    }

    // Check/normalize a name: "" = invalid (empty, slash, hidden, already exists)
    function cleanLanguageName(raw) {
        let n = (raw || "").trim().replace(/\s+/g, " ");
        if (n === "" || n.length > 40 || /[\/\\]/.test(n) || n.startsWith("."))
            return "";

        n = n.charAt(0).toUpperCase() + n.slice(1);
        const lower = n.toLowerCase();
        for (const l of languages) if (String(l).toLowerCase() === lower)
            return "";

        return n;
    }

    function setLanguage(name) {
        if (name === language || languages.indexOf(name) < 0)
            return ;

        // Remember the last loaded state per language: when switching back the list is right
        // immediately (otherwise first alphabetical, then re-sorted when the metadata arrives)
        let c = Object.assign({
        }, langCache);
        c[language] = {
            "library": library,
            "meta": meta,
            "subbed": subbed
        };
        langCache = c;
        const hit = langCache[name];
        language = name;
        meta = hit ? hit.meta : {
        };
        subbed = hit ? hit.subbed : {
        };
        library = hit ? hit.library : [];
        savePrefs();
        loadLibrary();
        loadStats();
    }

    // New language: create the folder (+ character, + image as cover.<ext>), read the list again, switch
    // there right away. Empty mark = suggestion (defaultMarkOf), then it is not stored
    function addLanguage(raw, mark, image) {
        const name = cleanLanguageName(raw);
        if (name === "")
            return false;

        pendingLanguage = name;
        const c = ["python3", "-I", langMediaScript, "create", dirOf(name)];
        const m = (mark || "").trim();
        if (m !== "" && m !== defaultMarkOf(name))
            c.push("--mark", m);
        if (image)
            c.push("--image", image);
        mkLangProc.command = c;
        mkLangProc.running = true;
        return true;
    }

    // Images to choose from when adding (newest from Downloads/Pictures/Desktop): [{path, name}]
    property var pickImages: []

    function loadPickImages() {
        imagesProc.running = false;
        imagesProc.running = true;
    }

    property string pendingLanguage: ""
    readonly property string langMediaScript: Qt.resolvedUrl("../scripts/lang_media.py").toString().replace("file://", "")
    property var langCache: ({
    })

    // The new language is created and chosen (the picker then goes right into it)
    signal languageAdded(string name)

    function loadLanguages() {
        langScanProc.running = false;
        langScanProc.running = true;
    }

    function savePrefs() {
        prefsWriteProc.command = ["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"', "_", root.prefsFile, JSON.stringify({
            "downloadMode": root.downloadMode,
            "language": root.language,
            "subsShown": root.subsShown,
            "videoVolume": root.videoVolume,
            "videoPositions": root.videoPositions,
            "lastVideos": root.lastVideos
        })];
        prefsWriteProc.running = false;
        prefsWriteProc.running = true;
    }

    function setDownloadMode(mode) {
        downloadMode = mode;
        savePrefs();
    }

    // Watch a video (row clicked in the picker, "Show"): loads it if not loaded yet and opens
    // the player ABOVE the open language window. The picker stays open and provides dimming and
    // blur; only its panel is hidden - a moment later, when the card already lies above it
    // (two windows are not drawn in the same frame).
    function watchVideo(file) {
        if (!(currentFile === file && videoLoaded))
            startVideo(file);

        videoOpen = true;
    }

    // Back from the player (after its morph, the card lies exactly on the panel): show the panel again,
    // the player disappears shortly after. Nothing is opened or shown/hidden -> seamless.
    // If the picker has been closed meanwhile (special case), it is opened without an intro.
    function backToPicker() {
        videoOpen = false;
        videoMorph = 0;
        if (!PickerManager.isOpen("language")) {
            morphHandoff = true;
            handoffTimer.restart();
            PickerManager.open("language");
        }
    }

    // Remember the position of the playing video; shortly before the end = watched -> next time from the start
    function rememberPosition() {
        if (!currentIsVideo || !videoLoaded || currentDuration <= 0)
            return ;

        let p = Object.assign({
        }, videoPositions);
        if (currentPosition > 5 && currentPosition < currentDuration - 10)
            p[currentFile] = Math.round(currentPosition);
        else
            delete p[currentFile];
        if (JSON.stringify(p) !== JSON.stringify(videoPositions)) {
            videoPositions = p;
            savePrefs();
        }
    }

    function startVideo(file) {
        rememberPosition();
        if (isPlaying)
            commitListenTime();

        killMpvProc.running = false;
        killMpvProc.running = true;
        currentFile = file;
        playDir = downloadDir;
        playLanguage = language;
        currentPosition = 0;
        currentDuration = 0;
        cueIndex = -1;
        videoLoaded = true;
        if (lastVideos[language] !== file) {
            let lv = Object.assign({
            }, lastVideos);
            lv[language] = file;
            lastVideos = lv;
            savePrefs();
        }
        videoCommand("load", {
            "path": playDir + "/" + file,
            "at": videoPositions[file] || 0
        });
    }

    // YouTube's automatic subtitles without word times show two blocks at once, so every line officially lasts
    // until the middle of the next one (up to 8 s overlap). videoPosition keeps a line until its end -> the next line
    // came seconds late. A line ends where the next one starts (also done by jp_subs.py build; this covers files
    // prepared before that).
    function clipCues(list) {
        const out = list.slice();
        for (let i = 0; i + 1 < out.length; i++) {
            if (out[i + 1].s < out[i].e && out[i + 1].s > out[i].s)
                out[i] = Object.assign({
                }, out[i], {
                    "e": out[i + 1].s
                });

        }
        return out;
    }

    // From the player: position (seconds) -> running subtitle line
    function videoPosition(sec) {
        currentPosition = sec;
        let i = cueIndex;
        // mostly it is the same or the next line
        if (i >= 0 && i < cues.length && sec >= cues[i].s && sec < cues[i].e)
            return ;

        i = -1;
        for (let k = 0; k < cues.length; k++) {
            if (sec >= cues[k].s && sec < cues[k].e) {
                i = k;
                break;
            }
            if (cues[k].s > sec)
                break;

        }
        cueIndex = i;
    }

    function setSubsShown(on) {
        subsShown = on;
        savePrefs();
    }

    function setPaused(on) {
        if (currentIsVideo && videoLoaded) {
            videoCommand("pause", on);
            return ;
        }
        sendIpc(JSON.stringify({
            "command": ["set_property", "pause", on]
        }));
    }

    function seekTo(seconds) {
        if (currentIsVideo && videoLoaded) {
            videoCommand("seek", Math.max(0, seconds));
            return ;
        }
        sendIpc(JSON.stringify({
            "command": ["seek", Math.max(0, seconds), "absolute"]
        }));
    }

    // Word clicked: pause and remember whether it should continue afterwards
    function holdForLookup() {
        if (isPlaying) {
            resumeAfterLookup = true;
            setPaused(true);
        }
    }

    function releaseLookup() {
        if (resumeAfterLookup)
            setPaused(false);

        resumeAfterLookup = false;
    }

    // Videos whose .vtt is there but was never prepared (downloaded before other languages had subtitles, or a
    // failed preparation): prepare them one after the other in the background. Each one is tried once per run of
    // the shell, so a video without usable subtitles is not tried again on every opening.
    property var subsTried: ({
    })
    property var subsQueue: []

    function prepareMissingSubs(vttStems) {
        const code = languageCodes[language];
        if (!code)
            return ;

        const add = [];
        for (const stem in vttStems) {
            const key = downloadDir + "/" + stem;
            if (subbed[stem] || subsTried[key] || library.indexOf(stem + ".mp4") < 0)
                continue;

            subsTried[key] = true;
            add.push([downloadDir + "/" + stem + ".mp4", code, language]);
        }
        if (add.length === 0)
            return ;

        subsQueue = subsQueue.concat(add);
        if (!lateSubsProc.running)
            nextLateSubs();
    }

    function nextLateSubs() {
        if (subsQueue.length === 0)
            return ;

        const job = subsQueue[0];
        subsQueue = subsQueue.slice(1);
        lateSubsProc.command = ["python3", subsScript, "build"].concat(job);
        lateSubsProc.running = true;
    }

    function translateCue(idx) {
        // Also covers the T key in the video player: without a translator (translation off) nothing happens
        if (idx < 0 || idx >= cues.length || cues[idx].en || translateProc.running || LanguageReadingState.translator === "")
            return ;

        translatingIdx = idx;
        translateError = "";
        // The subtitles belong to the playing file's language (playLanguage), not to the one shown in the picker
        translateProc.command = ["python3", root.subsScript, "translate", root.subsDir + "/" + stemOf(currentFile) + ".json", String(idx), languageCodes[playLanguage] || playLanguage.toLowerCase(), playLanguage];
        translateProc.running = true;
    }

    function onMpvEvent(line) {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return ;
        }
        if (ev.event !== "property-change")
            return ;

        if (ev.name === "pause" && ev.data !== undefined && !currentIsVideo)
            isPlaying = !ev.data;
    }

    function close() {
        if (isOpen)
            PickerManager.close();

    }

    onIsOpenChanged: {
        if (isOpen) {
            loadLanguages();
            loadLibrary();
            loadStats();
        }
    }

    function loadLibrary() {
        listProc.running = false;
        listProc.running = true;
    }

    function loadStats() {
        statsReadProc.running = false;
        statsReadProc.running = true;
    }

    // ── Suche ──
    function searchVideos(query) {
        if (query.trim() === "")
            return ;

        searchResults = [];
        lastQuery = query;
        runSearch(0);
    }

    function loadMoreResults() {
        if (isSearching || !hasMoreResults || lastQuery === "")
            return ;

        isLoadingMore = true;
        runSearch(searchResults.length);
    }

    // Fetches the results offset+1 .. offset+searchPageSize (ytsearchN only gives the first N,
    // --playlist-items cuts off the ones already shown)
    function runSearch(offset) {
        const end = offset + searchPageSize;
        // Cancel a running search silently, its end should not reset the status
        searchCancelled = true;
        searchProc.running = false;
        searchCancelled = false;
        isSearching = true;
        searchError = "";
        // Extend PATH, use the Zen cookies, clients as for the download (see root.ytClients)
        const cmd = "export PATH=\"$PATH:$HOME/.cargo/bin:$HOME/.deno/bin:$HOME/.local/bin:/usr/local/bin\"; " + root.cookieArgs + "exec yt-dlp \"ytsearch$2:$1\" --playlist-items \"$3:$2\" --flat-playlist --dump-json \"${cookies[@]}\" --extractor-args \"" + root.ytClients + "\"";
        searchProc.command = ["bash", "-c", cmd, "qs-ytsearch", lastQuery, String(end), String(offset + 1)];
        searchProc.running = true;
    }

    function clearSearch() {
        searchCancelled = true;
        searchProc.running = false;
        searchResults = [];
        searchError = "";
        isSearching = false;
        isLoadingMore = false;
        hasMoreResults = false;
        lastQuery = "";
    }

    // ── Download ──
    // YouTube clients for yt-dlp: its default ones plus web_embedded (got around 403/bot checks), so the
    // format is picked from both. web_embedded alone sometimes only offers an HLS stream (format 96,
    // "SABR-only streaming experiment") on which yt-dlp stayed at 0 bytes without an error (found on a
    // fresh install, 2026-11-24)
    readonly property string ytClients: "youtube:player_client=default,web_embedded"

    // defaultClient: second try with yt-dlp's default clients only (see the retry in downloadProc.onExited)
    function downloadVideo(url, title, defaultClient) {
        if (isDownloading)
            return ;

        downloadUrl = url;
        downloadDefaultClient = defaultClient === true;

        downloadTitle = title;
        downloadError = "";
        isDownloading = true;
        isConverting = false;
        downloadProgress = 0;
        statusText = "Downloading...";
        downloadProc.running = false;
        cancelled = false;
        downloadedFile = "";
        downloadLanguage = language;
        // Video: mp4 (max. 1080p, H.264 for easy playback) + subtitles (real and
        // automatic; jp_subs.py decides which one is taken) into .subs/
        const format = root.downloadMode === "video" ? "-f \"bv*[height<=1080][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=1080]+ba/b\" --merge-output-format mp4 " + (root.languageCode !== "" ? "--ignore-errors --write-subs --write-auto-subs --sub-langs \"" + root.subLangs(root.languageCode) + "\" --sub-format vtt " + "-o \"subtitle:$1/.subs/%(title)s.%(ext)s\" " : "") : "-x --audio-format mp3 ";
        // Extend PATH, use the Zen cookies, first with both clients (see root.ytClients)
        const client = downloadDefaultClient ? "" : "--extractor-args \"" + root.ytClients + "\" ";
        const cmd = "export PATH=\"$PATH:$HOME/.cargo/bin:$HOME/.deno/bin:$HOME/.local/bin:/usr/local/bin\"; " + root.cookieArgs + "mkdir -p \"$1\" && exec yt-dlp --newline --no-colors --no-playlist --playlist-items 1 " + format + "\"${cookies[@]}\" " + client + "--write-thumbnail --convert-thumbnails jpg -o \"thumbnail:$1/.thumbs/%(title)s.%(ext)s\" " + "-o \"$1/%(title)s.%(ext)s\" -- \"$2\" 2>&1";
        downloadProc.command = ["bash", "-c", cmd, "qs-ytdlp", downloadDir, url];
        downloadProc.running = true;
    }

    // yt-dlp languages: the language, its original track (ja-orig) and regional variants (pt-BR, zh-Hans, es-419).
    // Not "ja-.*": that also takes YouTube's machine translations into the language (ja-bn = from Bengali ...),
    // one request each, and YouTube answers those with 429 Too Many Requests
    function subLangs(code) {
        return code + "," + code + "-orig," + code + "-[A-Z0-9].*";
    }

    property string downloadLanguage: "Japanese"
    property string downloadUrl: ""
    property bool downloadDefaultClient: false

    function cancelDownload() {
        if (!isDownloading)
            return ;

        cancelled = true;
        downloadProc.running = false;
    }

    function downloadFromInput(queryOrUrl) {
        queryOrUrl = queryOrUrl.trim();
        if (queryOrUrl.startsWith("http://") || queryOrUrl.startsWith("https://") || queryOrUrl.startsWith("www.")) {
            downloadVideo(queryOrUrl, "Video");
            return true;
        }
        searchVideos(queryOrUrl);
        return false;
    }

    // ── IPC ──
    function sendIpc(jsonStr) {
        const py = "import socket,sys\n" + "try:\n" + "  s=socket.socket(socket.AF_UNIX)\n" + "  s.connect('" + ipcSocket + "')\n" + "  s.sendall(sys.argv[1].encode()+b'\\n')\n" + "  s.close()\n" + "except: sys.exit(1)";
        ipcProc.command = ["python3", "-c", py, jsonStr];
        ipcProc.running = false;
        ipcProc.running = true;
    }

    // ── Playback ──
    function play(file) {
        // Video via the play button: only the audio in the background (watching = watchVideo)
        if (isVideo(file)) {
            if (currentFile === file && videoLoaded)
                videoCommand("toggle", null);
            else
                startVideo(file);
            return ;
        }
        // mp3: pause a video that may be playing and close the window
        if (videoLoaded) {
            rememberPosition();
            videoCommand("stop", null);
            videoLoaded = false;
            videoOpen = false;
        }
        if (currentFile === file && mpvProc.running) {
            sendIpc('{"command": ["cycle", "pause"]}');
            isPlaying = !isPlaying;
            pollVerifier.restart();
            return ;
        }
        // Credit the running listening time to the previous language before playLanguage changes
        if (isPlaying)
            commitListenTime();

        currentFile = file;
        playDir = downloadDir;
        playLanguage = language;
        isPlaying = true;
        currentPosition = 0;
        currentDuration = 0;
        restarting = true;
        killMpvProc.running = false;
        killMpvProc.running = true;
        startMpvTimer.restart();
    }

    function pollPosition() {
        const py = 'import socket, json\n' + 'try:\n' + '    s = socket.socket(socket.AF_UNIX)\n' + '    s.settimeout(0.3)\n' + '    s.connect("' + ipcSocket + '")\n' + '    def cmd(c):\n' + '        s.sendall((json.dumps({"command": c}) + "\\n").encode())\n' + '        buf = b""\n' + '        while b"\\n" not in buf:\n' + '            chunk = s.recv(4096)\n' + '            if not chunk: break\n' + '            buf += chunk\n' + '        for line in buf.split(b"\\n"):\n' + '            if line:\n' + '                try:\n' + '                    d = json.loads(line)\n' + '                    if "data" in d and "error" in d: return d["data"]\n' + '                except: pass\n' + '        return None\n' + '    pos = cmd(["get_property", "time-pos"])\n' + '    dur = cmd(["get_property", "duration"])\n' + '    pause = cmd(["get_property", "pause"])\n' + '    print(json.dumps({"pos": pos, "dur": dur, "pause": pause}))\n' + '    s.close()\n' + 'except Exception as e:\n' + '    print(json.dumps({"error": str(e)}))\n';
        posPollProc.command = ["python3", "-c", py];
        posPollProc.running = false;
        posPollProc.running = true;
    }

    function seekToFraction(fraction) {
        if (currentDuration <= 0)
            return ;

        const seconds = Math.max(0, Math.min(currentDuration, fraction * currentDuration));
        if (currentIsVideo && videoLoaded) {
            seekTo(seconds);
            return ;
        }
        sendIpc('{"command": ["seek", ' + seconds.toFixed(2) + ', "absolute"]}');
        currentPosition = seconds;
    }

    function seekRelative(delta) {
        if (currentFile === "" || currentDuration <= 0)
            return ;

        if (currentIsVideo && videoLoaded) {
            seekTo(Math.min(currentDuration, currentPosition + delta));
            return ;
        }
        sendIpc('{"command": ["seek", ' + delta + ', "relative"]}');
        currentPosition = Math.max(0, Math.min(currentDuration, currentPosition + delta));
    }

    // Listening time counts for the language of the playing file (even if another one has been chosen
    // in the picker meanwhile). Written by Python with a file lock (added to the state in the file),
    // the display is only updated right away for the chosen language.
    function addListenTime(seconds) {
        const today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        Quickshell.execDetached(["python3", "-I", "-c", root.statsAddPy, statsFileOf(playLanguage), today, String(seconds)]);
        if (playLanguage === language) {
            let newStats = Object.assign({
            }, root.stats);
            newStats[today] = (newStats[today] || 0) + seconds;
            root.stats = newStats;
        }
    }

    // Credit the not yet counted time of the running session (before a language/file change)
    function commitListenTime() {
        if (sessionStart <= 0)
            return ;

        const elapsed = Math.round((Date.now() - sessionStart) / 1000);
        const remaining = elapsed - sessionCommitted;
        if (remaining > 0)
            addListenTime(remaining);

        sessionStart = Date.now();
        sessionCommitted = 0;
    }

    readonly property string statsAddPy: "import fcntl, json, os, sys\n" + "path, day, secs = sys.argv[1], sys.argv[2], int(sys.argv[3])\n" + "os.makedirs(os.path.dirname(path), exist_ok=True)\n" + "with open(path, 'a+') as f:\n" + "    fcntl.flock(f, fcntl.LOCK_EX)\n" + "    f.seek(0)\n" + "    try:\n" + "        data = json.loads(f.read() or '{}')\n" + "    except ValueError:\n" + "        data = {}\n" + "    data[day] = data.get(day, 0) + secs\n" + "    f.seek(0)\n" + "    f.truncate()\n" + "    f.write(json.dumps(data))\n"

    function getStatsForPeriod(period) {
        let now = new Date();
        let totalSeconds = 0;
        for (let dateStr in root.stats) {
            let d = new Date(dateStr);
            let include = false;
            if (period === "day") {
                include = (dateStr === Qt.formatDate(now, "yyyy-MM-dd"));
            } else if (period === "week") {
                let dayOfWeek = (now.getDay() + 6) % 7;
                let monday = new Date(now);
                monday.setDate(now.getDate() - dayOfWeek);
                monday.setHours(0, 0, 0, 0);
                include = (d >= monday);
            } else if (period === "month")
                include = (d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear());
            else if (period === "year")
                include = (d.getFullYear() === now.getFullYear());
            if (include)
                totalSeconds += root.stats[dateStr];

        }
        let h = Math.floor(totalSeconds / 3600);
        let m = Math.floor((totalSeconds % 3600) / 60);
        return h + "h " + m + "m";
    }

    Process {
        id: metaProc

        command: ["python3", "-I", Qt.resolvedUrl("../scripts/lang_media.py").toString().replace("file://", ""), "list", root.downloadDir]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = JSON.parse(text);
                    if (JSON.stringify(m) !== JSON.stringify(root.meta))
                        root.meta = m;

                } catch (e) {
                }
            }
        }

    }

    // Prepares subtitles that were missing (prepareMissingSubs), one video at a time; afterwards the list is read
    // again, so the player finds the new .json. A Process does not start again from its own onExited -> callLater.
    Process {
        id: lateSubsProc

        onExited: {
            if (root.subsQueue.length > 0)
                Qt.callLater(root.nextLateSubs);
            else
                root.loadLibrary();
        }
    }

    Process {
        id: listProc

        // Lines with \x1f in front: subtitles in .subs/ (file name without .json); \x1e: downloaded .vtt files
        // Collect first, swap once at the end (and only on a change): when it was cleared before, the list jumped
        // on every opening and the subtitles of the playing video were briefly dropped
        property var nextLibrary: []
        property var nextSubbed: ({
        })
        property var nextVtt: ({
        })

        command: ["bash", "-c", "mkdir -p \"$1\" && find -H \"$1\" -maxdepth 1 \\( -name '*.mp3' -o -name '*.mp4' \\) -printf '%f\\n' | sort; " + "[ -d \"$1/.subs\" ] && find \"$1/.subs\" -maxdepth 1 -name '*.json' -printf '\\037%f\\n' && find \"$1/.subs\" -maxdepth 1 -name '*.vtt' -printf '\\036%f\\n'; true", "_", root.downloadDir]
        onRunningChanged: {
            if (running) {
                nextLibrary = [];
                nextSubbed = {
                };
                nextVtt = {
                };
                return ;
            }
            if (JSON.stringify(nextLibrary) !== JSON.stringify(root.library))
                root.library = nextLibrary;

            if (JSON.stringify(nextSubbed) !== JSON.stringify(root.subbed))
                root.subbed = nextSubbed;

            root.prepareMissingSubs(nextVtt);
            metaProc.running = false;
            metaProc.running = true;
        }

        stdout: SplitParser {
            onRead: (data) => {
                if (data.startsWith("\x1f")) {
                    listProc.nextSubbed[data.slice(1).replace(/\.json$/, "")] = true;
                    return ;
                }
                if (data.startsWith("\x1e")) {
                    // "<name>.<lang>.vtt" -> name
                    listProc.nextVtt[data.slice(1).replace(/\.[^.]+\.vtt$/, "")] = true;
                    return ;
                }
                if (!listProc.nextLibrary.includes(data))
                    listProc.nextLibrary.push(data);

            }
        }

    }

    Process {
        id: statsReadProc

        command: ["bash", "-c", 'cat -- "$1" 2>/dev/null || true', "_", root.statsFile]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.stats = text.trim() !== "" ? JSON.parse(text) : ({
                    });
                } catch (e) {
                    root.stats = {
                    };
                }
            }
        }

    }

    // Languages = subfolders of the languages folder + Japanese (own legacy folder), with file count and
    // listening time for the tiles (scripts/lang_media.py languages)
    Process {
        id: langScanProc

        running: true
        command: {
            const c = ["python3", "-I", root.langMediaScript, "languages", root.languagesRoot, Quickshell.stateDir];
            for (const n in root.legacyDirs) c.push(n + "=" + root.legacyDirs[n])
            return c;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let list;
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    return ;
                }
                const info = {
                };
                const all = [];
                for (const l of list) {
                    info[l.name] = l;
                    all.push(l.name);
                }
                root.languageInfo = info;
                if (JSON.stringify(all) !== JSON.stringify(root.languages))
                    root.languages = all;

                if (root.pendingLanguage !== "" && all.indexOf(root.pendingLanguage) >= 0) {
                    const n = root.pendingLanguage;
                    root.pendingLanguage = "";
                    root.setLanguage(n);
                    root.languageAdded(n);
                }
                // The remembered language no longer exists (folder deleted/renamed) -> Japanese
                if (all.indexOf(root.language) < 0)
                    root.setLanguage("Japanese");

            }
        }

    }

    Process {
        id: mkLangProc

        onExited: root.loadLanguages()

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("[LanguageAudio] create:", text.trim());

            }
        }

    }

    Process {
        id: imagesProc

        command: ["python3", "-I", root.langMediaScript, "images"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.pickImages = JSON.parse(text);
                } catch (e) {
                    root.pickImages = [];
                }
            }
        }

    }

    Process {
        id: searchProc

        property string errBuffer: ""
        property int received: 0

        onRunningChanged: {
            if (!running) {
                if (root.searchCancelled)
                    return ;

                root.isSearching = false;
                root.isLoadingMore = false;
                // Got a full page -> there are probably more
                root.hasMoreResults = received >= root.searchPageSize;
                if (errBuffer !== "") {
                    console.warn("[LanguageAudio] Search error:", errBuffer);
                    root.searchError = errBuffer.replace(/^ERROR:\s*/gm, "").trim();
                }
            } else {
                errBuffer = "";
                received = 0;
            }
        }

        stdout: SplitParser {
            onRead: (data) => {
                if (root.searchCancelled)
                    return ;

                try {
                    const obj = JSON.parse(data);
                    if (obj && obj.id)
                        searchProc.received++;

                    if (obj && obj.title && obj.id && !root.searchResults.some((r) => {
                        return r.id === obj.id;
                    })) {
                        let arr = root.searchResults.slice();
                        arr.push({
                            "id": obj.id,
                            "title": obj.title,
                            "url": "https://www.youtube.com/watch?v=" + obj.id,
                            "duration": obj.duration_string || "",
                            "thumbnail": obj.thumbnails ? obj.thumbnails[obj.thumbnails.length - 1].url : "",
                            "uploader": obj.uploader || ""
                        });
                        root.searchResults = arr;
                    }
                } catch (e) {
                }
            }
        }

        stderr: SplitParser {
            onRead: (data) => {
                searchProc.errBuffer += data + "\n";
            }
        }

    }

    Process {
        id: downloadProc

        onExited: (exitCode, exitStatus) => {
            if (root.cancelled) {
                root.cancelled = false;
                root.isDownloading = false;
                root.isConverting = false;
                root.downloadProgress = 0;
                root.downloadTitle = "";
                root.statusText = "";
                return ;
            }
            if (root.isDownloading) {
                root.isDownloading = false;
                root.isConverting = false;
                if (exitCode === 0 && root.downloadedFile !== "" && root.languageCodes[root.downloadLanguage]) {
                    // Video: still prepare the subtitles (every language with a known code; furigana and the
                    // dictionary only for Japanese, see scripts/jp_subs.py), only then the download counts as finished
                    root.isDownloading = true;
                    root.isConverting = true;
                    root.isPreparingSubs = true;
                    root.statusText = "Preparing subtitles...";
                    subsProc.command = ["python3", root.subsScript, "build", root.downloadedFile, root.languageCodes[root.downloadLanguage], root.downloadLanguage];
                    subsProc.running = true;
                    return ;
                } else if (exitCode === 0) {
                    root.statusText = "Download finished";
                    root.loadLibrary();
                    root.downloadCompleted();
                } else {
                    if (root.downloadError === "")
                        root.downloadError = "Exit code " + exitCode;

                    // web_embedded with cookies of a browser that is not logged in to YouTube: "This video is
                    // unavailable (152 - 18)" for every video (found on a fresh install). Once more with yt-dlp's
                    // default client; a Process does not start again from its own onExited -> callLater
                    if (!root.downloadDefaultClient && /unavailable/i.test(root.downloadError)) {
                        const url = root.downloadUrl;
                        const title = root.downloadTitle;
                        root.statusText = "Retrying...";
                        Qt.callLater(() => {
                            return root.downloadVideo(url, title, true);
                        });
                        return ;
                    }

                    console.warn("[LanguageAudio] download failed (" + exitCode + "): " + root.downloadError);
                    root.statusText = "Download failed";
                }
                statusTimer.restart();
            }
        }

        stdout: SplitParser {
            onRead: (data) => {
                const pm = data.match(/\[download\]\s+([\d.]+)%/);
                if (pm)
                    root.downloadProgress = parseFloat(pm[1]) / 100;

                if (data.indexOf("[ExtractAudio]") >= 0)
                    root.isConverting = true;

                const line = data.trim();
                if (line.includes("ERROR") && root.downloadError === "")
                    root.downloadError = line.replace(/^ERROR:\s*/, "").trim();

                // Remember the finished mp4 (merged, single part or already there) -> subtitles
                const mp4 = data.match(/\[Merger\] Merging formats into "(.+\.mp4)"/) || data.match(/\[download\]\s+Destination:\s+(.+\.mp4)$/) || data.match(/\[download\]\s+(.+\.mp4) has already been downloaded/);
                if (mp4 && root.downloadMode === "video" && !/\.f\d+\.mp4$/.test(mp4[1]))
                    root.downloadedFile = mp4[1].trim();

                const dm = data.match(/\[download\]\s+Destination:\s+(.+)/);
                if (dm && root.downloadTitle === "Video") {
                    const parts = dm[1].trim().split('/');
                    root.downloadTitle = parts[parts.length - 1].replace(/\.[^.]+$/, "");
                }
            }
        }

    }

    Timer {
        id: statusTimer

        interval: 3500
        onTriggered: {
            root.statusText = "";
            root.downloadProgress = 0;
            root.downloadTitle = "";
            root.downloadError = "";
        }
    }

    Process {
        id: ipcProc
    }

    Process {
        id: killMpvProc

        command: ["bash", "-c", "pkill -f 'mpv.*mpv_japanese.sock' 2>/dev/null || true"]
    }

    Timer {
        id: startMpvTimer

        interval: 150
        onTriggered: {
            // Only mp3 (videos are played by the Quickshell player)
            const script = "M=''; " + "if [ -f /usr/lib/mpv-mpris/mpris.so ]; then M='--script=/usr/lib/mpv-mpris/mpris.so'; " + "elif [ -f /usr/share/mpv/scripts/mpris.so ]; then M='--script=/usr/share/mpv/scripts/mpris.so'; fi; " + "exec mpv --no-video --quiet $M " + "--input-ipc-server=" + ipcSocket + " " + "--force-window=no --terminal=no -- \"$1\"";
            mpvProc.command = ["bash", "-c", script, "qs-mpv", root.playDir + "/" + currentFile];
            mpvSocket.connected = false;

            mpvProc.running = false;
            mpvProc.running = true;
            root.startPollTries = 0;
            startPoll.restart();
            restartGuard.restart();
        }
    }

    Process {
        id: mpvProc

        onRunningChanged: {
            if (running) {
                root.restarting = false;
                return ;
            }
            // The video takes over (play() ends mpv): do not reset its state
            if (root.restarting || root.currentIsVideo)
                return ;

            root.isPlaying = false;
            root.currentPosition = 0;
            root.currentDuration = 0;
            root.resumeAfterLookup = false;
            mpvSocket.connected = false;
        }
    }

    // The handoff only applies to this one opening (picker intro and opening hop in the PickerWindow read it)
    // Remember the position when pausing and every 15 s during playback
    onIsPlayingChanged: {
        if (!isPlaying)
            rememberPosition();

    }

    Timer {
        interval: 15000
        running: root.isPlaying && root.currentIsVideo
        repeat: true
        onTriggered: root.rememberPosition()
    }

    Timer {
        id: handoffTimer

        interval: 600
        onTriggered: root.morphHandoff = false
    }

    // The language window is closed or another picker opened while the player is open
    // (shortcut): close the player, the audio keeps playing
    Connections {
        function onActivePickerChanged() {
            if (PickerManager.activePicker !== "language" && root.videoOpen) {
                root.videoOpen = false;
                root.videoMorph = 0;
            }
        }

        target: PickerManager
    }

    // Permanent connection to mpv: reports pause/resume right away (e.g. via media key/MPRIS)
    Socket {
        id: mpvSocket

        path: root.ipcSocket
        onConnectedChanged: {
            if (!connected)
                return ;

            write('{"command": ["observe_property", 3, "pause"]}\n');
            flush();
        }

        parser: SplitParser {
            onRead: (line) => {
                return root.onMpvEvent(line);
            }
        }

    }

    // Load the subtitles of the playing file
    FileView {
        path: root.currentFile !== "" && (root.playDir !== root.downloadDir || root.hasSubs(root.currentFile)) ? root.subsDir + "/" + root.stemOf(root.currentFile) + ".json" : ""
        onPathChanged: {
            root.cues = [];
            root.cueIndex = -1;
        }
        onLoaded: {
            try {
                root.cues = root.clipCues(JSON.parse(text()).cues || []);
            } catch (e) {
                root.cues = [];
            }
        }
    }

    Process {
        id: subsProc

        property string lastLine: ""

        onRunningChanged: {
            if (running) {
                lastLine = "";
                return ;
            }
            let res = {
            };
            try {
                res = JSON.parse(lastLine);
            } catch (e) {
            }
            root.isPreparingSubs = false;
            root.isDownloading = false;
            root.isConverting = false;
            if (res.ok === false) {
                // The video is there, only the subtitles are missing -> count it as finished anyway
                console.warn("[LanguageAudio] subtitles failed: " + res.error);
                root.statusText = "Downloaded · subtitles failed";
            } else {
                root.statusText = res.cues > 0 ? "Download finished · " + res.cues + " subtitle lines" : "Downloaded · no " + root.downloadLanguage + " subtitles";
            }
            root.loadLibrary();
            root.downloadCompleted();
            statusTimer.restart();
        }

        stdout: SplitParser {
            onRead: (data) => {
                subsProc.lastLine = data;
                try {
                    const p = JSON.parse(data).progress;
                    if (p)
                        root.statusText = p;

                } catch (e) {
                }
            }
        }

    }

    Process {
        id: translateProc

        property string lastLine: ""

        onRunningChanged: {
            if (running) {
                lastLine = "";
                return ;
            }
            try {
                const res = JSON.parse(lastLine);
                if (res.ok && res.idx < root.cues.length) {
                    let arr = root.cues.slice();
                    arr[res.idx] = Object.assign({
                    }, arr[res.idx], {
                        "en": res.en
                    });
                    root.cues = arr;
                } else if (!res.ok) {
                    root.translateError = res.error || "Translation failed";
                }
            } catch (e) {
                root.translateError = "Translation failed";
            }
            root.translatingIdx = -1;
        }

        stdout: SplitParser {
            onRead: (data) => {
                translateProc.lastLine = data;
            }
        }

    }

    Process {
        id: prefsWriteProc
    }

    Process {
        id: prefsReadProc

        running: true
        command: ["cat", root.prefsFile]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text);
                    // downloadMode from old prefs is ignored: it always downloads as video

                    if (typeof p.language === "string" && p.language !== "") {
                        root.language = p.language;
                        root.playLanguage = p.language;
                        root.playDir = root.dirOf(p.language);
                    }

                    if (typeof p.subsShown === "boolean")
                        root.subsShown = p.subsShown;

                    if (p.videoPositions && typeof p.videoPositions === "object")
                        root.videoPositions = p.videoPositions;

                    if (p.lastVideos && typeof p.lastVideos === "object")
                        root.lastVideos = p.lastVideos;

                    if (typeof p.videoVolume === "number")
                        root.videoVolume = Math.max(0, Math.min(1, p.videoVolume));

                } catch (e) {
                }
            }
        }

    }

    Timer {
        id: startPoll

        interval: 300
        repeat: true
        onTriggered: {
            root.startPollTries++;
            // Event connection for subtitles/pause as soon as mpv has its socket open
            if (!mpvSocket.connected)
                mpvSocket.connected = true;

            if ((root.currentDuration > 0 && mpvSocket.connected) || root.startPollTries > 20) {
                stop();
                return ;
            }
            root.pollPosition();
        }
    }

    Timer {
        id: restartGuard

        interval: 3000
        onTriggered: root.restarting = false
    }

    Timer {
        interval: root.isPlaying ? 1000 : 2000
        running: root.currentFile !== "" && mpvProc.running
        repeat: true
        onTriggered: root.pollPosition()
    }

    Timer {
        id: pollVerifier

        interval: 300
        onTriggered: root.pollPosition()
    }

    Process {
        id: posPollProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim());
                    if (d.error)
                        return ;

                    if (d.pos !== null && d.pos !== undefined)
                        root.currentPosition = d.pos;

                    if (d.dur !== null && d.dur !== undefined && d.dur > 0)
                        root.currentDuration = d.dur;

                    if (d.pause !== null && d.pause !== undefined)
                        root.isPlaying = !d.pause;

                } catch (e) {
                }
            }
        }

    }

    Connections {
        function onIsPlayingChanged() {
            if (root.isPlaying) {
                root.sessionStart = Date.now();
                root.sessionCommitted = 0;
            } else {
                if (root.sessionStart > 0) {
                    const elapsed = Math.round((Date.now() - root.sessionStart) / 1000);
                    const remaining = elapsed - root.sessionCommitted;
                    if (remaining > 0)
                        root.addListenTime(remaining);

                }
                root.sessionStart = 0;
                root.sessionCommitted = 0;
            }
        }

        target: root
    }

    Timer {
        interval: 30000
        running: root.isPlaying
        repeat: true
        onTriggered: {
            if (root.sessionStart > 0) {
                const elapsed = Math.round((Date.now() - root.sessionStart) / 1000);
                const remaining = elapsed - root.sessionCommitted;
                if (remaining > 0) {
                    root.addListenTime(remaining);
                    root.sessionCommitted = elapsed;
                }
            }
        }
    }


}
