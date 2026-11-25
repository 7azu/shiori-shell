// Content of the folder browser in the image and video editor (UI: windows/MediaBrowser.qml).
// Reads a folder with scripts/media_browse.py: subfolders (with count and up to 4 cover files)
// and images/videos. Video previews come one by one afterwards and stay remembered across
// folder changes (same cache as the strip in the video editor).

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/media_browse.py").toString().replace("file://", "")
    readonly property string sortScript: Qt.resolvedUrl("../scripts/media_sort.py").toString().replace("file://", "")
    readonly property string home: Quickshell.env("HOME") || ""
    property string dir: ""
    property string parentDir: ""
    property var folders: []
    property var files: []
    property var thumbs: ({}) // video path -> preview image
    property bool loading: false
    property string requested: ""
    // Cut (x), waiting for paste (p); stays across folder changes and closing
    property var cutPaths: []
    // A browser is open (VaultService only locks vaults nobody is in anymore)
    property bool active: false
    // The current folder is a locked vault -> password prompt; cipher = its ciphertext folder
    property bool locked: false
    property string cipher: ""
    // If the folder is in an unlocked vault: its root (lock button for locking)
    property string vaultMount: ""
    // Icon of the current folder (as in yazi, see media_browse.py load_dir_icons)
    property string dirIcon: ""
    // Fuzzy search over all subfolders (f or / in the browser): best hits first, each with "rel" = folder
    property var results: []
    property string resultsFor: ""
    readonly property bool searchBusy: searchProc.running
    property string searchDir: ""
    property string searchQuery: ""
    readonly property bool busy: opProc.running || sortProc.running
    property string lastError: ""
    // ---- Sort by date (scripts/media_sort.py; button in the browser, only in vaults) ----
    // sortPlan: result of "plan" (count, sources, renames, token) for sortDir; null = none yet
    property var sortPlan: null
    property string sortDir: ""
    // "new": only append files that do not follow the naming scheme yet (default); "all": everything new
    property string sortMode: "new"
    readonly property bool sortChecking: sortProc.running && sortProc.mode === "plan"
    readonly property bool sortApplying: sortProc.running && sortProc.mode === "apply"
    property real sortProgress: 0
    property string sortError: ""
    // Counts up on every sort: the same paths show other images afterwards (bypass the preview cache)
    property int sortGeneration: 0

    // New folder content is there (the browser then plays its entrance)
    signal loaded()
    // Sort done: renamed = count (0 = was already sorted)
    signal sorted(int renamed)
    // After moving/trashing: trashed = [path], moved = { old: new }. The editors use this to follow their
    // open file or notice that it is gone
    signal operationDone(var trashed, var moved)

    function checkSort(folder) {
        if (sortProc.running && sortProc.mode === "apply")
            return ;

        sortPlan = null;
        sortDir = folder;
        sortError = "";
        sortProgress = 0;
        // A preview is still running (mode switched): cancel it and restart with the new mode
        if (sortProc.running) {
            sortProc.again = true;
            sortProc.running = false;
            return ;
        }
        sortProc.mode = "plan";
        sortProc.command = ["python3", "-I", sortScript, "plan", folder, sortMode];
        sortProc.running = true;
    }

    function setSortMode(mode) {
        if (mode === sortMode || sortApplying)
            return ;

        sortMode = mode;
        if (sortDir !== "")
            checkSort(sortDir);

    }

    function applySort() {
        if (sortProc.running || !sortPlan || sortPlan.renameCount === 0)
            return ;

        sortError = "";
        sortProgress = 0;
        sortProc.mode = "apply";
        sortProc.command = ["python3", "-I", sortScript, "apply", sortDir, sortPlan.token, sortMode];
        sortProc.running = true;
    }

    function cancelSortCheck() {
        if (sortProc.running && sortProc.mode === "plan") {
            sortProc.again = false;
            sortProc.running = false;
        }
        sortPlan = null;
        sortMode = "new";
        sortError = "";
    }

    function trash(paths) {
        runOp(["trash"].concat(paths));
    }

    // Move what was cut here (paste)
    function paste(dest) {
        if (cutPaths.length > 0)
            runOp(["move", dest].concat(cutPaths));

    }

    function runOp(args) {
        if (opProc.running || args.length < 2)
            return ;

        opProc.trashed = [];
        opProc.moved = {};
        opProc.errors = [];
        lastError = "";
        opProc.command = ["python3", "-I", script].concat(args);
        opProc.running = true;
    }

    // A search is still running (you keep typing): cancel it and restart with the new text
    function search(dir, query) {
        searchDir = dir;
        searchQuery = query;
        if (searchProc.running) {
            searchProc.again = true;
            searchProc.running = false;
            return ;
        }
        searchProc.command = ["python3", "-I", script, "search", dir, query];
        searchProc.running = true;
    }

    function load(folder) {
        requested = folder;
        loading = true;
        if (listProc.running) {
            listProc.again = true;
            listProc.running = false;
            return ;
        }
        listProc.command = ["python3", "-I", script, "list", folder];
        listProc.running = true;
    }

    function fileUrl(path) {
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    // Image directly, video via the preview ("" = still coming). After a sort the same path shows a
    // different image: the number is part of the cache key (Qt loads local files without the query)
    function previewFor(path) {
        if (/\.(png|jpe?g|webp|bmp|gif|tiff?)$/i.test(path))
            return fileUrl(path) + (sortGeneration > 0 ? "?s=" + sortGeneration : "");

        return thumbs[path] ? fileUrl(thumbs[path]) : "";
    }

    function isVideo(path) {
        return !/\.(png|jpe?g|webp|bmp|gif|tiff?)$/i.test(path);
    }

    // ~ instead of /home/<name>, for the path bar and title
    function pretty(path) {
        return home !== "" && path.indexOf(home) === 0 ? "~" + path.substring(home.length) : path;
    }

    Process {
        id: opProc

        property var trashed: []
        property var moved: ({})
        property var errors: []

        onExited: {
            // Pasted items are no longer cut; failed ones stay for another try
            const done = opProc.moved;
            root.cutPaths = root.cutPaths.filter((p) => {
                return done[p] === undefined && opProc.trashed.indexOf(p) < 0;
            });
            if (opProc.errors.length > 0)
                root.lastError = opProc.errors.length === 1 ? opProc.errors[0] : opProc.errors[0] + " (+" + (opProc.errors.length - 1) + " more)";

            root.operationDone(opProc.trashed, opProc.moved);
            root.load(root.dir);
        }

        stdout: SplitParser {
            onRead: (line) => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return ;
                }
                if (msg.error !== undefined)
                    opProc.errors = opProc.errors.concat([msg.error]);
                else if (msg.op === "trash")
                    opProc.trashed = opProc.trashed.concat([msg.path]);
                else if (msg.op === "move")
                    opProc.moved[msg.from] = msg.to;
            }
        }

    }

    Process {
        id: sortProc

        property string mode: "plan"
        property var result: null
        property string error: ""
        property bool again: false

        onStarted: {
            result = null;
            error = "";
        }
        onExited: {
            if (again) {
                again = false;
                Qt.callLater(() => {
                    return root.checkSort(root.sortDir);
                });
                return ;
            }
            if (mode === "plan") {
                if (result)
                    root.sortPlan = result;
                else if (error !== "")
                    root.sortError = error;
                return ;
            }
            root.sortPlan = null;
            if (error !== "") {
                root.sortError = error;
                return ;
            }
            const renamed = result ? result.renamed : 0;
            const moved = result ? result.moved : {};
            if (renamed > 0) {
                root.sortGeneration++;
                // Previews depend on the path: fetch all of this folder again
                const map = Object.assign({}, root.thumbs);
                for (const k of Object.keys(map)) {
                    if (k.indexOf(root.sortDir + "/") === 0)
                        delete map[k];

                }
                root.thumbs = map;
                // Editors rewrite their paths (not operationDone: with chains a->b, b->c they would otherwise
                // jump to the wrong file)
                VideoEditorState.applyRenames(moved);
                ScreenshotEditorState.applyRenames(moved);
                CompressQueue.applyRenames(moved);
            }
            root.sorted(renamed);
            root.load(root.dir);
        }

        stdout: SplitParser {
            onRead: (line) => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return ;
                }
                if (msg.progress !== undefined)
                    root.sortProgress = msg.progress;
                else if (msg.plan !== undefined)
                    sortProc.result = msg.plan;
                else if (msg.ok)
                    sortProc.result = msg;
                else if (msg.error !== undefined)
                    sortProc.error = msg.error;
            }
        }

    }

    Process {
        id: searchProc

        property bool again: false

        onExited: {
            if (again) {
                again = false;
                searchProc.command = ["python3", "-I", root.script, "search", root.searchDir, root.searchQuery];
                searchProc.running = true;
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                if (searchProc.again)
                    return ;

                if (line.indexOf("T ") === 0) {
                    const cut = line.indexOf("\t");
                    const map = Object.assign({}, root.thumbs);
                    map[line.substring(cut + 1)] = line.substring(2, cut);
                    root.thumbs = map;
                    return ;
                }
                try {
                    const data = JSON.parse(line);
                    root.results = data.results;
                    root.resultsFor = data.query;
                } catch (e) {
                }
            }
        }

    }

    Process {
        id: listProc

        property bool again: false

        onExited: {
            if (again) {
                again = false;
                listProc.command = ["python3", "-I", root.script, "list", root.requested];
                listProc.running = true;
            } else {
                root.loading = false;
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                if (listProc.again)
                    return ;

                if (line.indexOf("T ") === 0) {
                    const cut = line.indexOf("\t");
                    const map = Object.assign({}, root.thumbs);
                    map[line.substring(cut + 1)] = line.substring(2, cut);
                    root.thumbs = map;
                    return ;
                }
                let data;
                try {
                    data = JSON.parse(line);
                } catch (e) {
                    return ;
                }
                root.dir = data.dir;
                root.parentDir = data.parent;
                root.locked = data.locked === true;
                root.cipher = data.cipher || "";
                root.vaultMount = data.vaultMount || "";
                root.dirIcon = data.icon || "";
                root.folders = data.folders;
                root.files = data.files;
                root.loaded();
            }
        }

    }

}
