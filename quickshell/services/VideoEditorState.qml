// State of the video editor (from yazi: scripts/open_video.sh, UI: windows/VideoEditor.qml).
// Everything stays non-destructive until export; the preview computes live, ffmpeg only on save
// (scripts/video_edit.py). The color formulas there are matched to the preview's MultiEffect.
// As in the image editor: all videos of the folder can be browsed, each keeps its edits.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/video_edit.py").toString().replace("file://", "")
    readonly property string screenshotScript: Qt.resolvedUrl("../scripts/screenshot_edit.sh").toString().replace("file://", "")
    readonly property string tempRoot: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-video"
    readonly property int thumbCount: 40
    property bool isOpen: false
    property string path: ""
    readonly property string fileName: path.substring(path.lastIndexOf("/") + 1)
    readonly property string fileUrl: path === "" ? "" : "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F")
    property string sessionDir: "" // RAM folder of this session, deleted when closing
    property var thumbs: [] // timeline: index -> path, fills up bit by bit

    // ---- Folder ----
    property string folderDir: ""
    property var gallery: []
    readonly property int currentIndex: gallery.indexOf(path)
    property var galleryThumbs: ({}) // path -> preview image (permanent cache)
    property var galleryPending: []
    property var broken: [] // unreadable videos do not come back on a re-read either
    property string lastGood: ""
    // Path -> { edits, savedKey, thumbDir } of the videos not shown right now
    property var sessions: ({})
    property var thumbDirs: ({})
    property var unsavedMarks: ({})
    // Path -> counter: overwritten files get fresh timeline images. Do not append it to the
    // player's URL: ffmpeg takes a "?v=1" as part of the file name and finds nothing anymore
    property var versions: ({})

    // ---- File (ffprobe) ----
    property real duration: 0 // Sekunden
    property int videoW: 0 // already with the rotation from the metadata
    property int videoH: 0
    property bool hasAudio: false
    property real fileSize: 0 // Bytes
    property string error: ""

    // ---- Editing ----
    property real trimStart: 0
    property real trimEnd: 0
    property int rotation: 0
    property real speed: 1
    property real brightness: 0
    property real contrast: 0
    property real saturation: 0
    property bool removeAudio: false
    readonly property string editKey: JSON.stringify([trimStart, trimEnd, rotation, speed, brightness, contrast, saturation, removeAudio])
    readonly property string neutralKey: JSON.stringify([0, duration, 0, 1, 0, 0, 0, false])
    property string savedKey: ""
    readonly property bool dirty: editKey !== neutralKey
    readonly property bool unsaved: editKey !== (savedKey || neutralKey)
    readonly property bool anyUnsaved: unsaved || Object.keys(unsavedMarks).some((p) => {
        return p !== path;
    })
    readonly property string extension: path.substring(path.lastIndexOf(".")).toLowerCase()
    // Not while HandBrake reads exactly this file (otherwise the old version would come back on replace)
    readonly property bool canOverwrite: dirty && !exporting && queuePos !== 0 && [".mp4", ".m4v", ".mov", ".mkv", ".webm"].indexOf(extension) >= 0

    // ---- Export ----
    readonly property bool exporting: exportProc.running
    property real progress: 0

    // ---- Compress (queue: services/CompressQueue.qml, keeps running without the editor) ----
    readonly property var compressLevels: ["low", "medium", "high"]
    property int compressLevel: 1
    property bool compressReplace: false
    // This file: -1 = not in the queue, 0 = being compressed right now, n = n videos before it
    readonly property int queuePos: CompressQueue.jobs.length >= 0 ? CompressQueue.indexOf(path) : -1
    readonly property string compressNote: CompressQueue.notes[path] || ""
    // Queued: the page shows the settings of the job, not the current ones
    readonly property var queuedJob: queuePos >= 0 ? CompressQueue.jobs[queuePos] : null
    readonly property int shownLevel: queuedJob ? compressLevels.indexOf(queuedJob.level) : compressLevel
    readonly property bool shownReplace: queuedJob ? queuedJob.replace : compressReplace
    // Applies when compressing: trim, rotation, remove audio. Not speed and colors
    readonly property bool compressEdits: trimStart > 0.01 || (trimEnd > 0 && trimEnd < duration - 0.01) || rotation !== 0 || removeAudio
    readonly property bool compressSkips: speed !== 1 || brightness !== 0 || contrast !== 0 || saturation !== 0
    property int frameCounter: 0 // two captures must never share a temporary file

    // From the window: release the player before swapping the file, or restart it
    signal reloaded()
    // The open file was renamed (folder sorted by date): same file, new path
    signal pathRenamed()
    signal trashFailed()
    // Saving done (copy or original replaced): the editor confirms at the button
    signal saved(bool overwrite)

    function open(file) {
        if (isOpen)
            return ;

        path = file;
        folderDir = file.substring(0, file.lastIndexOf("/")) || "/";
        gallery = [file];
        sessionDir = tempRoot + "/" + Date.now();
        loadFile();
        refreshGallery();
        isOpen = true;
    }

    // From the folder browser (windows/MediaBrowser): open a video also in another folder. The
    // edits of the previous videos stay (sessions depend on the path), the strip shows the new folder
    function openInFolder(file) {
        if (exporting || !file)
            return ;

        const dir = file.substring(0, file.lastIndexOf("/")) || "/";
        const moved = dir !== folderDir;
        if (moved) {
            folderDir = dir;
            gallery = [file];
        }
        goTo(file);
        if (moved)
            refreshGallery();

    }

    // Folder sorted by date (MediaBrowserState): rewrite all remembered paths, so edits,
    // timeline images and markers stay with their file - after sorting another file carries
    // the old name. moved = { old: new }; whoever is not in it keeps its name
    function applyRenames(moved) {
        if (!isOpen)
            return ;

        const re = (p) => {
            return moved[p] !== undefined ? moved[p] : p;
        };
        const remap = (obj) => {
            const out = {};
            for (const k of Object.keys(obj))
                out[re(k)] = obj[k];
            return out;
        };
        sessions = remap(sessions);
        thumbDirs = remap(thumbDirs);
        unsavedMarks = remap(unsavedMarks);
        versions = remap(versions);
        galleryThumbs = remap(galleryThumbs);
        broken = broken.map(re);
        gallery = gallery.map(re);
        lastGood = re(lastGood);
        const now = re(path);
        if (now !== path) {
            path = now;
            pathRenamed();
        }
        refreshGallery();
    }

    function refreshGallery() {
        if (galleryProc.running) {
            galleryProc.again = true;
            galleryProc.running = false;
            return ;
        }
        galleryPending = [];
        galleryProc.command = ["python3", "-I", script, "gallery", folderDir, path];
        galleryProc.running = true;
    }

    function isUnsaved(file) {
        return file === path ? unsaved : !!unsavedMarks[file];
    }

    function storeSession() {
        if (duration <= 0)
            return ;

        const all = Object.assign({}, sessions);
        all[path] = {
            "edits": [trimStart, trimEnd, rotation, speed, brightness, contrast, saturation, removeAudio],
            "savedKey": savedKey
        };
        sessions = all;
        const marks = Object.assign({}, unsavedMarks);
        if (unsaved)
            marks[path] = true;
        else
            delete marks[path];
        unsavedMarks = marks;
    }

    function goTo(file) {
        if (exporting || !file || file === path)
            return ;

        storeSession();
        path = file;
        loadFile();
        reloaded();
    }

    function step(delta) {
        const i = currentIndex + delta;
        if (i >= 0 && i < gallery.length)
            goTo(gallery[i]);

    }

    function loadFile() {
        error = "";
        duration = 0;
        resetEdits();
        savedKey = "";
        thumbs = [];
        thumbProc.running = false;
        startInfo();
    }

    // When browsing fast the predecessor may still be running: end it first, then restart
    function startInfo() {
        if (infoProc.running) {
            infoProc.again = true;
            infoProc.running = false;
            return ;
        }
        infoProc.forPath = path;
        infoProc.command = ["python3", "-I", script, "info", path];
        infoProc.running = true;
    }

    function startThumbs() {
        if (thumbProc.running) {
            thumbProc.again = true;
            thumbProc.running = false;
            return ;
        }
        const dirs = Object.assign({}, thumbDirs);
        if (!dirs[path])
            dirs[path] = sessionDir + "/" + Object.keys(dirs).length + "-" + (versions[path] || 0);

        thumbDirs = dirs;
        thumbProc.forPath = path;
        thumbProc.command = ["python3", "-I", script, "thumbs", path, dirs[path], String(thumbCount), String(duration)];
        thumbProc.running = true;
    }

    // Unreadable: take it out of the column when browsing and stay at the last good video
    function fileFailed() {
        if (lastGood !== "" && lastGood !== path) {
            const bad = path;
            broken = broken.concat([bad]);
            gallery = gallery.filter((p) => {
                return p !== bad;
            });
            path = lastGood;
            loadFile();
            reloaded();
        } else {
            error = "Could not read this video";
        }
    }

    function resetEdits() {
        trimStart = 0;
        trimEnd = duration;
        rotation = 0;
        speed = 1;
        brightness = 0;
        contrast = 0;
        saturation = 0;
        removeAudio = false;
    }

    function setTrimStart(t) {
        trimStart = Math.max(0, Math.min(t, trimEnd - 0.1));
    }

    function setTrimEnd(t) {
        trimEnd = Math.min(duration, Math.max(t, trimStart + 0.1));
    }

    function exportAs(mode) {
        if (exporting || !dirty || (mode === "overwrite" && !canOverwrite))
            return ;

        error = "";
        progress = 0;
        exportProc.mode = mode;
        exportProc.lastResult = "";
        exportProc.command = ["python3", "-I", script, "export", path, mode, trimStart.toFixed(3), trimEnd.toFixed(3), String(rotation), String(speed), brightness.toFixed(4), contrast.toFixed(4), saturation.toFixed(4), removeAudio ? "1" : "0"];
        exportProc.running = true;
    }

    // To the trash, not for good: an accidental double click should cost nothing
    function deleteCurrent() {
        if (exporting || trashProc.running || path === "")
            return ;

        error = "";
        trashProc.target = path;
        trashProc.command = ["gio", "trash", "--", path];
        trashProc.running = true;
    }

    function afterTrash(file, index) {
        const list = gallery.filter((p) => {
            return p !== file;
        });
        for (const name of ["sessions", "thumbDirs", "unsavedMarks", "versions"]) {
            const copy = Object.assign({}, root[name]);
            delete copy[file];
            root[name] = copy;
        }
        NotificationState.send("Video", "Moved to trash", file.substring(file.lastIndexOf("/") + 1), {});
        if (list.length === 0) {
            close();
            return ;
        }
        gallery = list;
        lastGood = "";
        // The next video moves to the same place, at the end the previous one
        path = list[Math.min(index, list.length - 1)];
        loadFile();
        reloaded();
    }

    // Lives in RAM until the screenshot script moves the image to the screenshots folder
    function newFrameFile() {
        frameCounter++;
        return (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-video-frame-" + Date.now() + "-" + frameCounter + ".png";
    }

    // As in the screenshot editor: folder, clipboard, notification. The script waits for a click
    // on the notification, so it is detached
    function storeFrame(file) {
        Quickshell.execDetached(["bash", screenshotScript, "save", file]);
    }

    function frameFailed() {
        NotificationState.send("Video", "Could not save frame", fileName, {});
    }

    // Queue with the current settings; later changes to the video do not count for this run
    function queueCompress() {
        if (duration <= 0 || path === "")
            return ;

        CompressQueue.add({
            "path": path,
            "level": compressLevels[compressLevel],
            "start": trimStart,
            "end": trimEnd,
            "rotation": rotation,
            "mute": removeAudio,
            "replace": compressReplace
        });
    }

    function cancelExport() {
        exportProc.running = false;
    }

    // Original replaced (maybe with another name, mkv -> mp4): edits and timeline images belong to the
    // old file. If the editor shows it right now, it loads the new one (trim/rotation are already applied)
    function compressReplaced(source, target) {
        const v = Object.assign({}, versions);
        v[target] = (v[target] || 0) + 1;
        versions = v;
        for (const key of ["sessions", "thumbDirs", "unsavedMarks"]) {
            const copy = Object.assign({}, root[key]);
            delete copy[source];
            delete copy[target];
            root[key] = copy;
        }
        if ((path === source || path === target) && !exporting) {
            path = target;
            loadFile();
            reloaded();
        }
    }

    function close() {
        if (exporting)
            return ;

        isOpen = false;
        thumbProc.again = false;
        thumbProc.running = false;
        infoProc.again = false;
        infoProc.running = false;
        galleryProc.again = false;
        galleryProc.running = false;
        if (sessionDir !== "")
            Quickshell.execDetached(["rm", "-rf", sessionDir]);

        sessionDir = "";
        thumbs = [];
        path = "";
        duration = 0;
        gallery = [];
        galleryThumbs = {};
        broken = [];
        lastGood = "";
        sessions = {};
        thumbDirs = {};
        unsavedMarks = {};
        versions = {};
    }

    Process {
        id: infoProc

        property string forPath: ""
        property bool again: false

        onExited: {
            if (again) {
                again = false;
                root.startInfo();
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                // Superseded query of another video
                if (infoProc.again || infoProc.forPath !== root.path)
                    return ;

                if (text.indexOf("ERR ") === 0 || text === "") {
                    root.fileFailed();
                    return ;
                }
                const d = JSON.parse(text);
                const turned = d.rotation % 180 !== 0;
                root.videoW = turned ? d.height : d.width;
                root.videoH = turned ? d.width : d.height;
                root.hasAudio = d.hasAudio;
                root.fileSize = d.size || 0;
                root.duration = d.duration;
                root.lastGood = root.path;
                const s = root.sessions[root.path];
                if (s) {
                    root.trimStart = s.edits[0];
                    root.trimEnd = s.edits[1];
                    root.rotation = s.edits[2];
                    root.speed = s.edits[3];
                    root.brightness = s.edits[4];
                    root.contrast = s.edits[5];
                    root.saturation = s.edits[6];
                    root.removeAudio = s.edits[7];
                    root.savedKey = s.savedKey;
                } else {
                    root.trimStart = 0;
                    root.trimEnd = d.duration;
                }
                root.startThumbs();
            }
        }

    }

    Process {
        id: thumbProc

        property string forPath: ""
        property bool again: false

        onExited: {
            if (again) {
                again = false;
                root.startThumbs();
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                const cut = line.indexOf(" ");
                if (cut < 0 || thumbProc.again || thumbProc.forPath !== root.path)
                    return ;

                const list = root.thumbs.slice();
                list[Number(line.substring(0, cut))] = line.substring(cut + 1);
                root.thumbs = list;
            }
        }

    }

    Process {
        id: galleryProc

        property bool again: false

        onExited: {
            if (again) {
                again = false;
                root.refreshGallery();
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                if (galleryProc.again)
                    return ;

                if (line.indexOf("F ") === 0) {
                    root.galleryPending.push(line.substring(2));
                } else if (line === "E") {
                    const found = root.galleryPending.filter((p) => {
                        return root.broken.indexOf(p) < 0;
                    });
                    // Opened directly but not in the list (hidden file, rare extension)
                    if (found.indexOf(root.path) < 0)
                        found.unshift(root.path);

                    root.gallery = found;
                } else if (line.indexOf("T ") === 0) {
                    const cut = line.indexOf("\t");
                    const map = Object.assign({}, root.galleryThumbs);
                    map[line.substring(cut + 1)] = line.substring(2, cut);
                    root.galleryThumbs = map;
                }
            }
        }

    }

    Process {
        id: trashProc

        property string target: ""

        onExited: (code) => {
            if (code === 0)
                root.afterTrash(target, root.gallery.indexOf(target));
            else {
                root.error = "Could not move this file to the trash";
                root.trashFailed();
            }
        }
    }

    // Once at start: is HandBrake there? (optional, see install.sh)
    // Compression done (even if the editor was closed in between): read the strip again, swap the replaced file
    Connections {
        function onFinished(source, how, target) {
            if (!root.isOpen)
                return ;

            if (how === "replaced")
                root.compressReplaced(source, target);

            if (target.substring(0, target.lastIndexOf("/")) === root.folderDir)
                root.refreshGallery();

        }

        target: CompressQueue
    }

    Process {
        id: exportProc

        property string mode: "copy"
        property string lastResult: ""

        onExited: (code) => {
            if (lastResult.indexOf("OK ") === 0) {
                const saved = lastResult.substring(3);
                const name = saved.substring(saved.lastIndexOf("/") + 1);
                if (mode === "overwrite") {
                    NotificationState.send("Video", "Original overwritten", name, {
                        "success": true
                    });
                    const v = Object.assign({}, root.versions);
                    v[root.path] = (v[root.path] || 0) + 1;
                    root.versions = v;
                    // Edits and timeline images belong to the old file
                    const all = Object.assign({}, root.sessions);
                    delete all[root.path];
                    root.sessions = all;
                    const dirs = Object.assign({}, root.thumbDirs);
                    delete dirs[root.path];
                    root.thumbDirs = dirs;
                    root.loadFile();
                    root.reloaded();
                } else {
                    root.savedKey = root.editKey;
                    NotificationState.send("Video", "Video saved", name, {
                        "success": true
                    });
                }
                root.refreshGallery();
                root.saved(mode === "overwrite");
            } else if (lastResult.indexOf("ERR ") === 0) {
                root.error = lastResult.substring(4);
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("P ") === 0)
                    root.progress = Number(line.substring(2));
                else
                    exportProc.lastResult = line;
            }
        }

    }

}
