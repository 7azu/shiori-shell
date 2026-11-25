// State of the screenshot editor (SUPER + SHIFT + S, UI: windows/ScreenshotEditor.qml).
// Everything stays non-destructive until saving: strokes and crop are in coordinates of the
// original image, the rotation (steps of 90) and the color values are only applied on export.
// So crop and strokes rotate along automatically when rotating.
// Opened from yazi (folder mode): all images of the folder can be browsed, each keeps its
// edits until closing. It saves as a copy next to the original or over the original.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/screenshot_edit.sh").toString().replace("file://", "")
    readonly property string tempDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-screenshot"
    property bool isOpen: false
    property bool capturing: false
    // Running capture: own name per capture, otherwise Image shows the old picture from the cache
    property string pendingPath: ""
    property string imagePath: "" // requested, may still be loading
    property string shownPath: "" // shown and edited right now
    property url shownUrl: "" // only swap with the fully loaded image, otherwise the dimensions briefly do not fit
    // Foreign file (e.g. from the clipboard cache): does not belong to us and is never deleted
    property bool externalImage: false
    property var closeCallback: null
    property int imageW: 0
    property int imageH: 0

    // ---- Folder mode ----
    property bool folderMode: false
    property string folderDir: ""
    property var gallery: [] // paths, naturally sorted
    readonly property int currentIndex: gallery.indexOf(imagePath)
    // Path -> { snapshot, undoStack, redoStack, savedDepth } of the images not shown right now
    property var sessions: ({})
    property var broken: [] // unreadable images: do not come back on a re-read either
    // Path -> counter: overwritten files get a new URL, otherwise the old picture would come from the cache
    property var versions: ({})
    property var unsaved: ({}) // paths of the images not shown right now with unsaved changes

    // ---- Editing ----
    property int rotation: 0 // 0, 90, 180, 270 clockwise
    property var crop: ({ "x": 0, "y": 0, "w": 0, "h": 0 }) // in the original image
    property real brightness: 0 // -1..1
    property real contrast: 0
    property real saturation: 0
    property var strokes: [] // { color, width, points: [{x, y}] } in the original image
    // Complete states (strokes themselves never change, a shallow copy is enough)
    property var undoStack: []
    property var redoStack: []
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0
    readonly property bool dirty: canUndo
    // State of the undo list at the last save (-1: this state can no longer be reached)
    property int savedDepth: 0
    readonly property bool currentUnsaved: undoStack.length !== savedDepth
    readonly property bool anyUnsaved: currentUnsaved || Object.keys(unsaved).some((p) => {
        return p !== shownPath;
    })
    readonly property int rotatedW: rotation % 180 === 0 ? imageW : imageH
    readonly property int rotatedH: rotation % 180 === 0 ? imageH : imageW

    // Animated GIFs would be lost when overwriting (the editor only knows the first frame)
    readonly property bool canOverwrite: folderMode && dirty && !/\.gif$/i.test(shownPath) && !saveProc.running

    // Right before opening: the window sets its monitor here
    signal aboutToOpen()
    signal trashFailed()
    // Saving in folder mode done (copy or original replaced): the editor confirms at the button
    signal saved(bool overwrite)

    // Rotates a rectangle (w, h = size of the image it lies in) by deg clockwise
    function rotateRect(r, w, h, deg) {
        switch ((deg % 360 + 360) % 360) {
        case 90:
            return { "x": h - r.y - r.h, "y": r.x, "w": r.h, "h": r.w };
        case 180:
            return { "x": w - r.x - r.w, "y": h - r.y - r.h, "w": r.w, "h": r.h };
        case 270:
            return { "x": r.y, "y": w - r.x - r.w, "w": r.h, "h": r.w };
        default:
            return { "x": r.x, "y": r.y, "w": r.w, "h": r.h };
        }
    }

    // Crop as it looks after the rotation (that is the image section that is exported)
    function rotatedCrop() {
        return rotateRect(crop, imageW, imageH, rotation);
    }

    // Inverse: put a rectangle from the rotated view back into the original image
    function setRotatedCrop(r) {
        crop = rotateRect(r, rotatedW, rotatedH, 360 - rotation);
    }

    function snapshot() {
        return {
            "rotation": rotation,
            "crop": crop,
            "brightness": brightness,
            "contrast": contrast,
            "saturation": saturation,
            "strokes": strokes
        };
    }

    function restore(s) {
        rotation = s.rotation;
        crop = s.crop;
        brightness = s.brightness;
        contrast = s.contrast;
        saturation = s.saturation;
        strokes = s.strokes;
    }

    // Call before every change (for sliders once on release with the state from when grabbed)
    function pushUndo(s) {
        if (savedDepth > undoStack.length)
            savedDepth = -1;

        undoStack = undoStack.concat([s || snapshot()]);
        redoStack = [];
    }

    function undo() {
        if (!canUndo)
            return ;

        const prev = undoStack[undoStack.length - 1];
        redoStack = redoStack.concat([snapshot()]);
        undoStack = undoStack.slice(0, -1);
        restore(prev);
    }

    function redo() {
        if (!canRedo)
            return ;

        const next = redoStack[redoStack.length - 1];
        undoStack = undoStack.concat([snapshot()]);
        redoStack = redoStack.slice(0, -1);
        restore(next);
    }

    function rotateBy(deg) {
        pushUndo();
        rotation = (rotation + deg + 360) % 360;
    }

    function addStroke(stroke) {
        pushUndo();
        strokes = strokes.concat([stroke]);
    }

    // Everything back to the state of the capture (can itself be undone again)
    function resetAll() {
        if (!dirty)
            return ;

        pushUndo();
        restore({
            "rotation": 0,
            "crop": { "x": 0, "y": 0, "w": imageW, "h": imageH },
            "brightness": 0,
            "contrast": 0,
            "saturation": 0,
            "strokes": []
        });
    }

    function startCapture() {
        // The key also works with the editor open: do not throw away the work by accident
        if (isOpen || capturing)
            return ;

        aboutToOpen();
        capturing = true;
        pendingPath = tempDir + "/capture-" + Date.now() + ".png";
        captureProc.command = ["bash", script, "capture", pendingPath];
        captureProc.running = true;
    }

    // Edit an existing image; the original stays untouched, "Save" creates a new file.
    // onClosed only runs if the editor was really open (not when falling back to swayimg)
    function openFile(path, onClosed) {
        if (isOpen || capturing)
            return ;

        aboutToOpen();
        closeCallback = onClosed || null;
        externalImage = true;
        imagePath = path;
    }

    // From yazi: like openFile, plus the image's folder becomes browsable
    function openFolderFile(path) {
        if (isOpen || capturing)
            return ;

        aboutToOpen();
        externalImage = true;
        folderMode = true;
        folderDir = path.substring(0, path.lastIndexOf("/")) || "/";
        gallery = [path];
        imagePath = path;
        refreshGallery();
    }

    // From the folder browser (windows/MediaBrowser): open an image also in another folder. The
    // edits of the previous images stay (sessions depend on the path), the strip shows the new folder
    function openInFolder(path) {
        const dir = path.substring(0, path.lastIndexOf("/")) || "/";
        if (!folderMode || dir === folderDir) {
            goTo(path);
            return ;
        }
        folderDir = dir;
        gallery = [path];
        goTo(path);
        refreshGallery();
    }

    // Folder sorted by date (MediaBrowserState): rewrite paths, so edits stay with their image
    // (another file now carries the old name); count versions up, otherwise the old picture would come
    // from the cache under a reused name. moved = { old: new }
    function applyRenames(moved) {
        if (!isOpen || !folderMode)
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
        // Store the current edit under the old name, rewrite it too and repeat on reload
        storeSession();
        sessions = remap(sessions);
        unsaved = remap(unsaved);
        const v = remap(versions);
        for (const to of Object.values(moved))
            v[to] = (v[to] || 0) + 1;
        versions = v;
        broken = broken.map(re);
        gallery = gallery.map(re);
        const now = re(imagePath);
        if (now !== imagePath) {
            shownPath = "";
            imagePath = "";
            imagePath = now;
        }
        refreshGallery();
    }

    function refreshGallery() {
        if (!folderMode)
            return ;

        listProc.command = ["bash", script, "list", folderDir];
        listProc.running = true;
    }

    // To the trash, not for good: an accidental double click should cost nothing
    function deleteCurrent() {
        if (!folderMode || trashProc.running || saveProc.running || shownPath === "")
            return ;

        trashProc.target = shownPath;
        trashProc.command = ["gio", "trash", "--", shownPath];
        trashProc.running = true;
    }

    function afterTrash(file, index) {
        const list = gallery.filter((p) => {
            return p !== file;
        });
        for (const name of ["sessions", "unsaved", "versions"]) {
            const copy = Object.assign({}, root[name]);
            delete copy[file];
            root[name] = copy;
        }
        NotificationState.send("Screenshot", "Moved to trash", file.substring(file.lastIndexOf("/") + 1), {});
        if (list.length === 0) {
            close();
            return ;
        }
        gallery = list;
        // Without shownPath, goTo remembers no edit for the deleted file
        shownPath = "";
        savedDepth = 0;
        undoStack = [];
        redoStack = [];
        // The next image moves to the same place, at the end the previous one
        goTo(list[Math.min(index, list.length - 1)]);
    }

    function isUnsaved(path) {
        return path === shownPath ? currentUnsaved : !!unsaved[path];
    }

    function storeSession() {
        if (shownPath === "")
            return ;

        const all = Object.assign({}, sessions);
        all[shownPath] = {
            "snapshot": snapshot(),
            "undoStack": undoStack,
            "redoStack": redoStack,
            "savedDepth": savedDepth
        };
        sessions = all;
        const marks = Object.assign({}, unsaved);
        if (currentUnsaved)
            marks[shownPath] = true;
        else
            delete marks[shownPath];
        unsaved = marks;
    }

    function goTo(path) {
        if (path === imagePath || !path)
            return ;

        storeSession();
        // Go via "": an image from the cache would otherwise report no status change
        imagePath = "";
        imagePath = path;
    }

    function step(delta) {
        const i = currentIndex + delta;
        if (i >= 0 && i < gallery.length)
            goTo(gallery[i]);

    }

    // A format Qt cannot read: at least show foreign images in the viewer instead of doing nothing
    function imageFailed() {
        // When browsing: take a broken image out of the strip and stay at the last good one
        if (folderMode && isOpen) {
            const bad = imagePath;
            broken = broken.concat([bad]);
            gallery = gallery.filter((p) => {
                return p !== bad;
            });
            imagePath = "";
            imagePath = shownPath;
            return ;
        }
        if (externalImage)
            Quickshell.execDetached(["swayimg", imagePath]);

        close();
    }

    // From the window as soon as the image is loaded: only then the dimensions are fixed
    function imageLoaded(w, h) {
        imageW = w;
        imageH = h;
        shownPath = imagePath;
        shownUrl = fileUrl(imagePath);
        const s = sessions[imagePath];
        if (s) {
            restore(s.snapshot);
            undoStack = s.undoStack;
            redoStack = s.redoStack;
            savedDepth = s.savedDepth;
        } else {
            restore({
                "rotation": 0,
                "crop": { "x": 0, "y": 0, "w": w, "h": h },
                "brightness": 0,
                "contrast": 0,
                "saturation": 0,
                "strokes": []
            });
            undoStack = [];
            redoStack = [];
            savedDepth = 0;
        }
        isOpen = true;
    }

    function prepareExport(callback) {
        if (prepareExportProc.running || saveProc.running)
            return false;

        prepareExportProc.callback = callback;
        prepareExportProc.running = true;
        return true;
    }

    // The finished image is already in path; the script runs detached (notify-send waits for clicks)
    function finish(action, path) {
        if (!folderMode) {
            Quickshell.execDetached(["bash", script, action, path]);
            close();
        } else if (action === "copy") {
            Quickshell.execDetached(["bash", script, "copy", path]);
        } else if (!saveProc.running) {
            saveProc.sourcePath = shownPath;
            saveProc.depth = undoStack.length;
            saveProc.overwrite = action === "overwrite";
            saveProc.command = ["bash", script, saveProc.overwrite ? "overwrite" : "save-next", path, shownPath];
            saveProc.running = true;
        }
    }

    // The original is now the new state: edits and undo belong to the old file, so reload
    function afterOverwrite(path) {
        const v = Object.assign({}, versions);
        v[path] = (v[path] || 0) + 1;
        versions = v;
        const all = Object.assign({}, sessions);
        delete all[path];
        sessions = all;
        const marks = Object.assign({}, unsaved);
        delete marks[path];
        unsaved = marks;
        if (path === shownPath) {
            imagePath = "";
            imagePath = path;
        }
    }

    function markSaved(path, depth) {
        if (path === shownPath) {
            savedDepth = depth;
        } else if (sessions[path]) {
            sessions[path].savedDepth = depth;
            const marks = Object.assign({}, unsaved);
            if (sessions[path].undoStack.length === depth)
                delete marks[path];

            unsaved = marks;
        }
    }

    function close() {
        const wasOpen = isOpen;
        const callback = closeCallback;
        closeCallback = null;
        isOpen = false;
        if (imagePath !== "" && !externalImage)
            Quickshell.execDetached(["rm", "-f", imagePath]);

        imagePath = "";
        shownPath = "";
        shownUrl = "";
        versions = {};
        externalImage = false;
        folderMode = false;
        gallery = [];
        broken = [];
        sessions = {};
        unsaved = {};
        savedDepth = 0;
        undoStack = [];
        redoStack = [];
        if (wasOpen && callback)
            callback();

    }

    // Paths can contain #, ? or %, which mean something else in a URL
    function fileUrl(path) {
        const v = versions[path];
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F") + (v ? "?v=" + v : "");
    }

    Process {
        id: captureProc

        onExited: (code) => {
            root.capturing = false;
            // Cancelled in slurp: simply do nothing
            if (code === 0)
                root.imagePath = root.pendingPath;

        }
    }

    Process {
        id: listProc

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.folderMode)
                    return ;

                const found = text.split("\n").filter((l) => {
                    return l !== "" && root.broken.indexOf(l) < 0;
                });
                // Opened directly but not in the list (e.g. SVG): show it anyway
                if (root.imagePath !== "" && found.indexOf(root.imagePath) < 0)
                    found.unshift(root.imagePath);

                root.gallery = found;
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
                NotificationState.send("Screenshot", "Could not move to trash", target.substring(target.lastIndexOf("/") + 1), {});
                root.trashFailed();
            }
        }
    }

    Process {
        id: prepareExportProc

        command: ["mkdir", "-p", "--", root.tempDir]
        property var callback: null

        onExited: (code) => {
            const done = callback;
            callback = null;
            done(code === 0 ? root.tempDir + "/export-" + Date.now() + ".png" : "");
        }
    }

    Process {
        id: saveProc

        property string sourcePath: ""
        property int depth: 0
        property bool overwrite: false

        onExited: (code) => {
            if (code !== 0)
                return ;

            if (overwrite)
                root.afterOverwrite(sourcePath);
            else
                root.markSaved(sourcePath, depth);
            root.refreshGallery();
            root.saved(overwrite);
        }
    }

}
