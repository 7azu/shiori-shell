import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

QtObject {
    id: root

    readonly property bool pickerVisible: PickerManager.isOpen("music")
    // Settings "music" (default $MUSIC), with trailing slash. Must match music_directory in mpd.conf
    readonly property string musicDir: Settings.folder("music") + "/"
    // ==== Song list (stays as a small string array in RAM) ====
    property var allSongs: []
    property bool songsLoaded: false
    property bool songsLoading: false
    // When each song came into the library (file mtime from mpd = download time, yt-dlp keeps --no-mtime):
    // song path -> ms since epoch. For the "Recent" order.
    property var songAdded: ({
    })
    // ==== Order of the grid ("top" = most played, "name", "recent") and play counts ====
    // Like the app launcher: a song counts as played after 30 s of playback, from anywhere (picker,
    // queue, mpc). Lives in <stateDir>/music-plays.json as
    // { "sort": "top", "plays": { "<song path>": { "n": count, "t": last time } } }.
    readonly property var sortModes: ["top", "name", "recent"]
    property string sortMode: "top"
    property var plays: ({
    })
    property bool playsLoaded: false
    readonly property string playsFile: Quickshell.stateDir + "/music-plays.json"
    property string countPath: ""
    // ==== Cover cache (song path -> small preview image on disk) ====
    // Preview images (216 px, square) stay permanently in ~/.cache/quickshell/music-covers,
    // so they are only taken from the MP3 once per song. Small = decoded fast, so
    // they are back right away also when a tile is rebuilt (searching, reopening).
    property var coverCache: ({
    })
    // Songs without an embedded cover (do not try again and again)
    property var noCover: ({
    })
    readonly property int coverSize: 216
    readonly property string coverDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/music-covers"
    readonly property string coverScript: Qt.resolvedUrl("../scripts/music_covers.sh").toString().replace("file://", "")
    property var coverQueue: []
    // md5 -> song path of the songs the running script is working on right now
    property var coverInFlight: ({
    })
    // Collect finished covers and take them over in bulk (do not rebind all tiles per cover)
    property var coverPending: ({
    })
    // ==== Queue ("Up next") ====
    // Song paths that are played directly after the playing song.
    // Mirrors the block after the playing song in the mpd playlist.
    property alias queue: queueState.songs
    property PersistentProperties _queuePersistence: PersistentProperties {
        id: queueState

        reloadableId: "musicQueue"
        property var songs: []
        property string lastPlayingId: ""
    }
    // Song whose "Now playing" notification is still waiting for the cover
    property string announcePath: ""
    // File of the song playing right now ("" = nothing is playing)
    property string nowPlaying: ""
    property var queueJobs: []
    property bool queueBusy: false
    property bool queueSyncing: true
    readonly property string queueScript: Qt.resolvedUrl("../scripts/music_queue.sh").toString().replace("file://", "")
    // ==== Link-Download (Spotify / SoundCloud / YouTube -> mp3) ====
    // Phases: "idle" | "busy" | "done" | "error"
    property string dlPhase: "idle"
    readonly property bool dlBusy: dlPhase === "busy"
    property string dlStatus: ""
    property real dlProgress: -1 // 0..1, -1 = unknown
    property string dlName: ""
    property string dlError: ""
    property int dlDoneCounter: 0
    // Stage: 0 searching, 1 download, 2 converting, 3 library, 4 done
    property int dlStage: 0
    property bool _dlOk: false
    // Queue: links that come during a running download run automatically
    // one after another afterwards (also with the picker closed)
    property string dlUrl: ""
    property var dlQueue: []
    readonly property string dlScript: Qt.resolvedUrl("../scripts/music_download.sh").toString().replace("file://", "")
    // ==== Process instances in the singleton ====
    property Process songsProcess
    property Process coverProcess
    // Quickshell starts before start.sh starts MPD: the first queue snapshot fails then, try again
    property int queueRetries: 0
    property Timer queueRetryTimer: Timer {
        interval: 2000
        onTriggered: root.refreshQueue()
    }

    property Timer coverFlushTimer: Timer {
        interval: 60
        onTriggered: root.flushCovers()
    }
    property Process dlProcess
    property Process queueProcess
    property Process nowProcess
    // Download without an open picker:  qs ipc call music download <link>
    property IpcHandler ipc: IpcHandler {
        function download(url: string): string {
            return root.downloadUrl(url);
        }

        function status(): string {
            return root.dlPhase + (root.dlBusy ? " " + root.dlStatus : "") + " | queue: " + root.dlQueue.length;
        }

        target: "music"
    }
    // If the cover does not come in time, it reports without
    property Timer announceTimer: Timer {
        interval: 1500
        onTriggered: {
            if (root.announcePath !== "")
                root.announceNow(root.announcePath);

        }
    }

    // Detect the service by the link: "spotify" | "soundcloud" | "youtube" | ""
    function serviceOf(url) {
        const u = String(url || "").trim().toLowerCase();
        if (/^https:\/\/(open\.spotify\.com|spotify\.link)\//.test(u) || u.indexOf("spotify:track:") === 0)
            return "spotify";

        if (/^https:\/\/((www|m|on)\.)?soundcloud\.com\//.test(u) || /^https:\/\/snd\.sc\//.test(u))
            return "soundcloud";

        if (/^https:\/\/((www|m|music)\.)?youtube\.com\//.test(u) || /^https:\/\/youtu\.be\//.test(u))
            return "youtube";

        return "";
    }

    // Status message of the script (scripts/music_download.sh, English) -> stage
    function stageOf(t) {
        const s = String(t || "").toLowerCase();
        if (s.indexOf("library") !== -1)
            return 3;

        if (s.indexOf("convert") !== -1 || s.indexOf("tags") !== -1)
            return 2;

        if (s.indexOf("downloading") !== -1)
            return 1;

        return 0;
    }

    // Starts right away or queues. Returns: "started" | "queued" | "invalid"
    function downloadUrl(url) {
        const u = String(url || "").trim();
        if (serviceOf(u) === "") {
            if (!root.dlBusy) {
                root.dlError = "Not a Spotify, SoundCloud or YouTube link";
                root.dlPhase = "error";
            }
            return "invalid";
        }
        if (root.dlBusy) {
            if (u !== root.dlUrl && root.dlQueue.indexOf(u) === -1)
                root.dlQueue = root.dlQueue.concat([u]);

            return "queued";
        }
        root._startDownload(u);
        return "started";
    }

    function _startDownload(u) {
        root.dlUrl = u;
        root.dlError = "";
        root.dlName = "";
        root._dlOk = false;
        root.dlProgress = -1;
        root.dlStage = 0;
        root.dlStatus = "Starting …";
        root.dlPhase = "busy";
        root.dlProcess.command = ["bash", root.dlScript, u, root.musicDir];
        root.dlProcess.running = true;
    }

    // Start the next link from the queue (after success or error)
    function _startNext() {
        root.dlUrl = "";
        if (root.dlQueue.length === 0)
            return ;

        const next = root.dlQueue[0];
        root.dlQueue = root.dlQueue.slice(1);
        root._startDownload(next);
    }

    // Acknowledge the done/error message (e.g. when the user keeps typing)
    function dlAck() {
        if (root.dlPhase !== "busy") {
            root.dlPhase = "idle";
            root.dlError = "";
        }
    }

    function loadSongs() {
        if (!root.available || root.songsLoaded || root.songsLoading)
            return ;

        root.songsLoading = true;
        root.songsProcess.running = true;
    }

    // Fetch the song list from mpd again (after a download)
    function reloadSongs() {
        root.songsLoaded = false;
        root.loadSongs();
    }

    // "Mon Nov 23 15:23:20 2026" (mpc %mtime%, C locale) -> ms since epoch; 0 if unknown
    function parseMtime(text) {
        const m = /^\w{3} (\w{3}) +(\d+) (\d+):(\d+):(\d+) (\d{4})$/.exec(text.trim());
        if (!m)
            return 0;

        const month = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].indexOf(m[1]);
        return month < 0 ? 0 : new Date(+m[6], month, +m[2], +m[3], +m[4], +m[5]).getTime();
    }

    function parseSongs(rawText) {
        try {
            // Lines are "<mtime>\t<path>"
            const added = {
            };
            const lines = [];
            for (const raw of rawText.split('\n')) {
                if (!raw.trim())
                    continue;

                const tab = raw.indexOf("\t");
                const path = tab < 0 ? raw : raw.substring(tab + 1);
                if (!path)
                    continue;

                lines.push(path);
                if (tab > 0)
                    added[path] = root.parseMtime(raw.substring(0, tab));

            }
            root.songAdded = added;
            root.allSongs = lines.sort((a, b) => {
                return a.localeCompare(b);
            });
            root.songsLoaded = true;
            // Provide preview images of the whole library in the background (existing ones come right away).
            // Have songs without a cover checked again: a newly downloaded file may have one now
            root.requestCovers(root.allSongs, true);
        } catch (e) {
            console.error("Error parsing songs:", e);
        }
        root.songsLoading = false;
    }

    // ==== Play counts ====
    // 0 (never) to 1 (often and lately): as LauncherSearch.heat, halved every 30 days without playing
    function heat(path) {
        const u = plays[path];
        if (!u || !u.n)
            return 0;

        const days = Math.max(0, (Date.now() - (u.t || 0)) / 8.64e+07);
        return Math.min(1, Math.log2(1 + u.n) / 5) * Math.pow(0.5, days / 30);
    }

    // Heat of every played song right now (the picker takes it once per opening, so the grid does
    // not reorder under the mouse while a song is counted)
    function heatMap() {
        const out = {
        };
        for (const path in plays)
            out[path] = heat(path);
        return out;
    }

    function setSort(mode) {
        if (sortModes.indexOf(mode) === -1 || mode === sortMode)
            return ;

        sortMode = mode;
        savePlays();
    }

    function cycleSort(dir) {
        const n = sortModes.length;
        setSort(sortModes[(sortModes.indexOf(sortMode) + (dir || 1) + n) % n]);
    }

    // A new track started: it counts once it played 30 s
    function startPlayCount(path) {
        countPath = path;
        playCountTimer.restart();
    }

    function countPlay(path) {
        if (!path || path !== nowPlaying || !playsLoaded)
            return ;

        const u = plays[path] || {
            "n": 0,
            "t": 0
        };
        // A shell restart sees the same song start again: not a second play
        if (Date.now() - u.t < 120000)
            return ;

        const next = Object.assign({
        }, plays);
        next[path] = {
            "n": u.n + 1,
            "t": Date.now()
        };
        plays = next;
        savePlays();
    }

    function savePlays() {
        if (!playsLoaded)
            return ;

        playsView.setText(JSON.stringify({
            "sort": sortMode,
            "plays": plays
        }) + "\n");
    }

    function requestCover(songPath) {
        root.requestCovers([songPath]);
    }

    // Several songs at once (e.g. the whole library after loading), order = priority.
    // recheck: also ask for songs remembered as "no cover" (the script checks the file date)
    function requestCovers(paths, recheck) {
        const inFlight = Object.values(root.coverInFlight);
        let added = false;
        for (const p of paths) {
            if (!p || root.coverCache[p] || (root.noCover[p] && !recheck) || root.coverQueue.includes(p) || inFlight.includes(p))
                continue;

            root.coverQueue.push(p);
            added = true;
        }
        if (added)
            root.processCoverQueue();

    }

    // Starts the script with everything in the queue; whatever comes in
    // meanwhile runs in the next pass
    function processCoverQueue() {
        if (root.coverProcess.running || root.coverQueue.length === 0)
            return ;

        const flight = {
        };
        const args = ["bash", root.coverScript, root.musicDir, root.coverDir, String(root.coverSize)];
        for (const p of root.coverQueue) {
            const md5 = Qt.md5(p);
            flight[md5] = p;
            args.push(md5, p);
        }
        root.coverQueue = [];
        root.coverInFlight = flight;
        root.coverProcess.command = args;
        root.coverProcess.running = true;
    }

    function flushCovers() {
        const done = root.coverPending;
        root.coverPending = {
        };
        const got = {
        };
        const none = {
        };
        let nGot = 0, nNone = 0;
        for (const p in done) {
            if (done[p]) {
                got[p] = done[p];
                nGot++;
            } else {
                none[p] = true;
                nNone++;
            }
        }
        // Create a new map, so QML bindings notice the update
        if (nGot > 0) {
            root.coverCache = Object.assign({
            }, root.coverCache, got);
            // If a song now has a cover after all, forget the old "no cover" mark
            let stale = false;
            for (const p in got) {
                if (root.noCover[p])
                    stale = true;

            }
            if (stale) {
                const nc = Object.assign({
                }, root.noCover);
                for (const p in got)
                    delete nc[p];
                root.noCover = nc;
            }
        }

        if (nNone > 0)
            root.noCover = Object.assign({
        }, root.noCover, none);

        // The cover (or no cover) for the announced song is there
        const a = root.announcePath;
        if (a !== "" && a === root.nowPlaying && (a in done))
            root.announceNow(a);

    }

    function displayName(songPath) {
        if (!songPath)
            return "";

        const base = songPath.split("/").pop();
        return base.replace(/\.[^.]+$/, "");
    }

    // ==== Queue ====
    // All mpd changes run one after another (one job after the other),
    // so fast clicks do not shift each other's positions.
    function runQueueJob(args) {
        root.queueJobs.push(args);
        root.nextQueueJob();
    }

    function refreshQueue() {
        if (!root.available)
            return ;

        root.queueSyncing = true;
        root.runQueueJob(["snapshot"].concat(root.queue));
    }

    function nextQueueJob() {
        if (root.queueBusy || root.queueJobs.length === 0)
            return ;

        root.queueBusy = true;
        const args = root.queueJobs.shift();
        root.queueProcess.command = ["bash", root.queueScript].concat(args);
        root.queueProcess.running = true;
    }

    // Append a song to the end of the queue
    function addToQueue(songPath) {
        if (root.queueSyncing || !songPath || root.queue.indexOf(songPath) !== -1)
            return ;

        const k = root.queue.length;
        root.queue = root.queue.concat([songPath]);
        root.requestCover(songPath);
        root.runQueueJob(["add", songPath, String(k)]);
    }

    function removeFromQueue(index) {
        if (root.queueSyncing || index < 0 || index >= root.queue.length)
            return ;

        root.queue = root.queue.filter((p, i) => {
            return i !== index;
        });
        root.runQueueJob(["del", String(index), String(root.queue.length)]);
    }

    // Pull a song to the start of the queue ("Play next")
    function queueNext(index) {
        if (root.queueSyncing || index <= 0 || index >= root.queue.length)
            return ;

        const q = root.queue.slice();
        const song = q.splice(index, 1)[0];
        q.unshift(song);
        root.queue = q;
        root.runQueueJob(["next", String(index), String(root.queue.length)]);
    }

    function clearQueue() {
        if (root.queueSyncing || root.queue.length === 0)
            return ;

        const n = root.queue.length;
        root.queue = [];
        root.runQueueJob(["clear", String(n)]);
    }

    function playSong(songPath) {
        if (root.queueSyncing || !songPath)
            return;

        root.queue = root.queue.filter((path) => path !== songPath);
        root.announceSong(songPath);
        root.runQueueJob(["start", songPath].concat(root.queue));
    }

    // ==== "Now playing" notification (only for songs the picker starts) ====
    // Waits briefly for the cover, so the toast shows it right away
    function announceSong(path) {
        if (path === root.nowPlaying) {
            root.announceNow(path);
            return ;
        }
        root.announcePath = path;
        announceTimer.restart();
    }

    function announceNow(path) {
        root.announcePath = "";
        announceTimer.stop();
        NotificationState.send("Music", "Now playing", path.split("/").pop().replace(/\.[^.]+$/, ""), {
            "image": root.coverCache[path] || "",
            "timeout": 3500
        });
    }

    // Play a queue song right away (the queue moves up via nowPlaying)
    function playQueued(index) {
        if (root.queueSyncing || index < 0 || index >= root.queue.length)
            return ;

        root.announceSong(root.queue[index]);
        root.runQueueJob(["play", String(index)]);
    }

    function toggle() {
        PickerManager.toggle("music");
    }

    function close() {
        if (PickerManager.isOpen("music"))
            PickerManager.close();

    }

    function open() {
        PickerManager.open("music");
    }

    // MPD IDs tell two entries of the same file apart (e.g. a queued replay).
    function updateNowPlaying(songId, songPath) {
        const trackChanged = songId !== "" && songId !== queueState.lastPlayingId;
        if (!trackChanged && root.nowPlaying === songPath)
            return;

        root.nowPlaying = songPath;
        if (songId === "")
            return;

        queueState.lastPlayingId = songId;
        root.startPlayCount(songPath);
        root.requestCover(songPath);
        if (songPath === root.announcePath && root.coverCache[songPath])
            root.announceNow(songPath);

        const i = trackChanged ? root.queue.indexOf(songPath) : -1;
        if (i !== -1) {
            // MPD has 255 positive levels. With longer queues the rest moves up.
            const needsPriorities = root.queue.length > 255;
            root.queue = root.queue.slice(i + 1);
            if (needsPriorities && root.queue.length > 0)
                root.runQueueJob(["priorities", String(root.queue.length)]);
        }
    }

    // mpd client (mpc) installed? Without it the music picker stays empty instead of failing every 3 s
    property bool available: false
    property Process availableProcess: Process {
        command: ["sh", "-c", "command -v mpc >/dev/null"]
        onExited: (code) => {
            root.available = code === 0;
            if (root.available) {
                root.loadSongs();
                Qt.callLater(root.refreshQueue);
            }
        }
    }

    Component.onCompleted: availableProcess.running = true

    property Timer playCountTimer: Timer {
        interval: 30000
        onTriggered: root.countPlay(root.countPath)
    }

    property FileView playsView: FileView {
        path: root.playsFile
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const data = JSON.parse(text()) || {
                };
                root.plays = data.plays || {
                };
                if (root.sortModes.indexOf(data.sort) !== -1)
                    root.sortMode = data.sort;

            } catch (e) {
                root.plays = {
                };
            }
            root.playsLoaded = true;
        }
        // No file yet (first start): counting may begin
        onLoadFailed: root.playsLoaded = true
    }

    songsProcess: Process {
        // Quickshell starts before start.sh starts MPD: wait for it (max. 30 s), otherwise the empty
        // answer would stay as the song list until the next download
        command: ["sh", "-c", "for i in $(seq 30); do mpc status >/dev/null 2>&1 && exec env LC_ALL=C mpc listall -f \"%mtime%\t%file%\"; sleep 1; done"]

        stdout: StdioCollector {
            onStreamFinished: root.parseSongs(text)
        }

    }

    coverProcess: Process {
        onExited: (exitCode, exitStatus) => {
            root.flushCovers();
            root.coverInFlight = {
            };
            Qt.callLater(root.processCoverQueue);
        }

        // Zeilen "<md5> jpg|none"
        stdout: SplitParser {
            onRead: (data) => {
                const parts = data.trim().split(" ");
                const path = root.coverInFlight[parts[0]];
                if (path === undefined)
                    return ;

                root.coverPending[path] = parts[1] === "jpg" ? root.coverDir + "/" + parts[0] + ".jpg" : "";
                if (!root.coverFlushTimer.running)
                    root.coverFlushTimer.start();

            }
        }

    }

    queueProcess: Process {
        stdout: StdioCollector {
            id: queueOutput
        }
        stderr: StdioCollector {
            id: queueError
        }

        onExited: (exitCode, exitStatus) => {
            const action = command[2];
            const success = exitCode === 0 && exitStatus === 0;
            if (!success)
                console.warn("Music queue", action, "failed:", exitCode, queueError.text.trim());

            root.queueBusy = false;
            if (action === "snapshot") {
                if (success)
                    root.queue = queueOutput.text.split("\n").filter(path => path !== "");
                else if (root.queueRetries++ < 20)
                    root.queueRetryTimer.restart();
                root.queueSyncing = false;
            } else if (!success) {
                // Follow-up jobs refer to the presumably changed positions.
                root.queueJobs = [];
                NotificationState.send("Music", "Couldn't update the queue", "The queue will be refreshed.");
                root.refreshQueue();
                return;
            }
            root.nextQueueJob();
        }
    }

    // Watches mpd with `mpc idle player` (event driven, no polling).
    // Prints "NOW|<id> <file>" on every player event; if mpd is not running,
    // it tries again every 3 s. The space is a literal in the mpc format.
    nowProcess: Process {
        command: ["bash", "-c", 'while true; do echo "NOW|$(mpc -f "%id% %file%" current 2>/dev/null)"; mpc idle player >/dev/null 2>&1 || sleep 3; done']
        running: root.available

        stdout: SplitParser {
            onRead: (data) => {
                if (!data.startsWith("NOW|"))
                    return;

                const song = data.substring(4);
                const separator = song.indexOf(" ");
                if (separator < 0)
                    root.updateNowPlaying("", "");
                else
                    root.updateNowPlaying(song.substring(0, separator), song.substring(separator + 1));
            }
        }

    }

    dlProcess: Process {
        onExited: (exitCode, exitStatus) => {
            if (root._dlOk) {
                root.dlStage = 4;
                root.dlPhase = "done";
                root.dlDoneCounter++;
                root.reloadSongs();
                NotificationState.send("Music", "Download complete", root.dlName || "Added to library", {
                    "keep": true,
                    "success": true
                });
            } else {
                if (root.dlError === "")
                    root.dlError = "Download failed";

                root.dlPhase = "error";
                NotificationState.send("Music", "Download failed", root.dlError, {
                    "keep": true
                });
            }
            Qt.callLater(root._startNext);
        }

        stdout: SplitParser {
            onRead: (data) => {
                const idx = data.indexOf("|");
                if (idx === -1)
                    return ;

                const kind = data.substring(0, idx);
                const rest = data.substring(idx + 1).trim();
                if (kind === "STATUS") {
                    root.dlStatus = rest;
                    root.dlStage = Math.max(root.dlStage, root.stageOf(rest));
                } else if (kind === "PROG") {
                    const p = parseFloat(rest);
                    if (!isNaN(p)) {
                        root.dlProgress = Math.max(0, Math.min(1, p / 100));
                        root.dlStage = Math.max(root.dlStage, 1);
                    }
                } else if (kind === "DONE") {
                    root.dlName = rest;
                    root._dlOk = true;
                } else if (kind === "ERR") {
                    root.dlError = rest;
                }
            }
        }

    }

}
