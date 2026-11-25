pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Optional private add-ons in addons/ (ignored by git, usually a link to a private repo).
// The shell runs without them; whatever they provide simply does not show up.
// addons/addons.json says what is there, paths relative to addons/:
//
//   { "media": "media/MediaPicker.qml",            full-screen picker "media" (bar icon, toggle_media)
//     "editorAction": "resolve/EditorAction.qml" }  one extra action row in the image and video editors
//
// An editor action is a QtObject with: available, busy, button (Component with signal requested()),
// send(job), cancel(), refresh() and signal finished(mode, path). job = { path, kind: "image"|"video",
// start, end (seconds, -1 = whole), rotation, width, height }. mode "fresh" closes the editor.
Singleton {
    id: root

    readonly property string dir: Quickshell.shellPath("addons")
    property var manifest: ({})
    readonly property bool media: typeof manifest.media === "string"
    property var editorAction: null

    // Through Quickshell's own scheme (qs:@/qs/...) like every other shell file, not file://: with
    // file:// the add-on's import "../../services" is a different module to Qt, and it gets its own
    // second copy of every singleton (PickerManager, NotificationState ...)
    function url(rel) {
        return Qt.resolvedUrl("../addons/" + rel);
    }

    function createEditorAction(rel) {
        const comp = Qt.createComponent(url(rel));
        if (comp.status === Component.Ready)
            editorAction = comp.createObject(root);
        else
            console.warn("Addons: could not load", rel, comp.errorString());
    }

    Component.onCompleted: {
        const text = manifestFile.text();
        if (text === "")
            return ;

        try {
            manifest = JSON.parse(text);
        } catch (e) {
            console.warn("Addons: addons.json is not valid JSON:", e);
            return ;
        }
        if (typeof manifest.editorAction === "string")
            createEditorAction(manifest.editorAction);

        console.info("Addons: loaded", Object.keys(manifest).join(", "));    }

    FileView {
        id: manifestFile

        path: root.dir + "/addons.json"
        blockLoading: true
        printErrors: false
    }

}
