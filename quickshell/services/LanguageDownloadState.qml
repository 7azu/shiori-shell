import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Getting new videos for the language tool: the YouTube search (page by page) and the download with yt-dlp
// (video + thumbnail + subtitles, which are prepared right after). Language and folder come from
// LanguageAudioState, the finished file shows up through its loadLibrary().
Singleton {
    id: root

    // YouTube login: yt-dlp reads the cookies fresh from Zen on every call (no cookie file)
    readonly property string cookieArgs: "spec=$(\"$HOME/.config/quickshell/scripts/zen_cookies.sh\") && cookies=(--cookies-from-browser \"$spec\") || cookies=(); "
    property string statusText: ""
    property real downloadProgress: 0
    property bool isDownloading: false
    property bool isConverting: false
    property bool cancelled: false
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
    // Download as audio (mp3) or video (mp4 + subtitles); remembered in LanguageAudioState.prefsFile
    // Now only videos (listening in the background works with them too); "audio" only stays readable for
    // old prefs, but is no longer set
    property string downloadMode: "video"
    property bool isPreparingSubs: false
    property string downloadedFile: ""

    signal downloadCompleted()

    function setDownloadMode(mode) {
        downloadMode = mode;
        LanguageAudioState.savePrefs();
    }

    // ── Search ──
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
        downloadLanguage = LanguageAudioState.language;
        // Video: mp4 (max. 1080p, H.264 for easy playback) + subtitles (real and
        // automatic; jp_subs.py decides which one is taken) into .subs/
        const format = root.downloadMode === "video" ? "-f \"bv*[height<=1080][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=1080]+ba/b\" --merge-output-format mp4 " + (LanguageAudioState.languageCode !== "" ? "--ignore-errors --write-subs --write-auto-subs --sub-langs \"" + root.subLangs(LanguageAudioState.languageCode) + "\" --sub-format vtt " + "-o \"subtitle:$1/.subs/%(title)s.%(ext)s\" " : "") : "-x --audio-format mp3 ";
        // Extend PATH, use the Zen cookies, first with both clients (see root.ytClients)
        const client = downloadDefaultClient ? "" : "--extractor-args \"" + root.ytClients + "\" ";
        const cmd = "export PATH=\"$PATH:$HOME/.cargo/bin:$HOME/.deno/bin:$HOME/.local/bin:/usr/local/bin\"; " + root.cookieArgs + "mkdir -p \"$1\" && exec yt-dlp --newline --no-colors --no-playlist --playlist-items 1 " + format + "\"${cookies[@]}\" " + client + "--write-thumbnail --convert-thumbnails jpg -o \"thumbnail:$1/.thumbs/%(title)s.%(ext)s\" " + "-o \"$1/%(title)s.%(ext)s\" -- \"$2\" 2>&1";
        downloadProc.command = ["bash", "-c", cmd, "qs-ytdlp", LanguageAudioState.downloadDir, url];
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
                if (exitCode === 0 && root.downloadedFile !== "" && LanguageAudioState.languageCodes[root.downloadLanguage]) {
                    // Video: still prepare the subtitles (every language with a known code; furigana and the
                    // dictionary only for Japanese, see scripts/jp_subs.py), only then the download counts as finished
                    root.isDownloading = true;
                    root.isConverting = true;
                    root.isPreparingSubs = true;
                    root.statusText = "Preparing subtitles...";
                    subsProc.command = ["python3", LanguageSubtitleState.subsScript, "build", root.downloadedFile, LanguageAudioState.languageCodes[root.downloadLanguage], root.downloadLanguage];
                    subsProc.running = true;
                    return ;
                } else if (exitCode === 0) {
                    root.statusText = "Download finished";
                    LanguageAudioState.loadLibrary();
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
            LanguageAudioState.loadLibrary();
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

}
