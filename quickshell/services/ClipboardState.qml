import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Clipboard history (cliphist) for pickers/ClipboardPicker, plus pinned entries.
// Pinned entries are kept apart from cliphist, so "Clear all" (cliphist wipe) leaves them: their content
// is copied to <stateDir>/clip-pins/<pid>.<ext> (txt for text) and listed in <stateDir>/clipboard-pins.json.
// `shown` = pinned ones first, then the history (a text that is also pinned is not listed twice).
// Their ids start with "pin:", so they never mix with cliphist ids.
Singleton {
    id: root

    readonly property string tempDir: "/tmp/qs-clip-images"
    readonly property int imageLimit: 40
    readonly property int textLimit: 300
    readonly property bool pickerVisible: PickerManager.isOpen("clipboard")
    property var entries: []
    // Pinned entries, newest first (see the top)
    property var pins: []
    readonly property string pinDir: Quickshell.stateDir + "/clip-pins"
    readonly property string pinFile: Quickshell.stateDir + "/clipboard-pins.json"
    // What the picker lists: pinned first, then the history without the texts that are pinned
    readonly property var shown: {
        const pinnedText = {};
        for (const p of pins) {
            if (!p.isImage)
                pinnedText[p.label] = true;

        }
        return pins.concat(entries.filter((e) => {
            return e.isImage || !pinnedText[e.label];
        }));
    }
    // Pid of the entry that was pinned last (the picker selects it again after it moved to the top)
    property string lastPinned: ""
    property bool loaded: false
    property string signature: ""
    property var readyIds: ({
    })
    property var attempted: ({
    })
    property bool decodeQueued: false
    // Image the picker selects again after the editor ("" = none)
    property string returnToId: ""
    readonly property string decodeScript: 'dir="$1"; shift; mkdir -p "$dir"; for spec in "$@"; do id="${spec%%:*}"; ext="${spec##*:}"; f="$dir/$id.$ext"; if [ -s "$f" ] || { cliphist decode "$id" > "$f" 2>/dev/null && [ -s "$f" ]; }; then echo "$id"; else rm -f "$f"; fi; done'

    function refresh() {
        if (!listProc.running)
            listProc.running = true;

    }

    // Copying from the picker: create qs-clip-from-picker first. clip_store.sh (wl-paste --watch) then does not store
    // this copy again: otherwise cliphist would have created the entry anew at the top with a NEW id - the list
    // jumped, the confirmation (flashId) vanished with the old id and images were briefly empty (decoded again).
    // This way the entry keeps its place and id; the picker shows the confirmation itself (no double toast).
    function copyEntry(e) {
        if (e.pinned) {
            // From its own file; the marker keeps clip_store.sh from storing it again
            Quickshell.execDetached(["bash", "-c", 'touch "${XDG_RUNTIME_DIR:-/tmp}/qs-clip-from-picker"; if [ -n "$2" ]; then wl-copy -t "$2" < "$1"; else wl-copy < "$1"; fi', "qs-clip", e.path, e.mime || ""]);
            return ;
        }
        Quickshell.execDetached(["bash", "-c", 'touch "${XDG_RUNTIME_DIR:-/tmp}/qs-clip-from-picker"; if [ -n "$2" ]; then cliphist decode "$1" | wl-copy -t "$2"; else cliphist decode "$1" | wl-copy; fi', "qs-clip", String(e.id), e.mime || ""]);
    }

    // After the editor the clipboard opens again, with the same search and the same image
    function openImage(e) {
        const search = PickerManager.searchText;
        ScreenshotEditorState.openFile(e.path, () => {
            returnToId = e.id;
            open();
            PickerManager.searchText = search;
        });
    }

    // Images can be shown once their file is there; pinned ones always have it
    function isReady(e) {
        return !!e && (e.pinned === true || readyIds[e.id] === true);
    }

    // Pin or unpin. Pinning copies the full content out of cliphist (the list only has a preview).
    function togglePin(e) {
        if (!e)
            return ;

        if (e.pinned) {
            unpin(e.pid);
            return ;
        }
        if (pinProc.running)
            return ;

        const pid = String(Date.now());
        const ext = e.isImage ? e.ext : "txt";
        pinProc.pending = {
            "id": "pin:" + pid,
            "pid": pid,
            "pinned": true,
            "isImage": e.isImage,
            "ext": e.isImage ? e.ext : "",
            "mime": e.mime || "",
            "path": pinDir + "/" + pid + "." + ext,
            "preview": e.preview,
            "hay": e.hay,
            "label": e.label,
            "kind": e.kind,
            "meta": e.meta || ""
        };
        pinProc.command = ["bash", "-c", 'mkdir -p "$1" && cliphist decode "$2" > "$3" && [ -s "$3" ] || { rm -f "$3"; exit 1; }', "qs-clip", pinDir, String(e.id), pinProc.pending.path];
        pinProc.running = true;
    }

    function unpin(pid) {
        const p = pins.find((x) => {
            return x.pid === pid;
        });
        pins = pins.filter((x) => {
            return x.pid !== pid;
        });
        savePins();
        if (p)
            Quickshell.execDetached(["rm", "-f", p.path]);

    }

    function savePins() {
        pinView.setText(JSON.stringify(pins));
    }

    function deleteEntry(id) {
        if (String(id).startsWith("pin:")) {
            unpin(String(id).slice(4));
            return ;
        }
        entries = entries.filter((e) => {
            return e.id !== id;
        });
        signature = entries.map((e) => {
            return e.id;
        }).join(",");
        const r = Object.assign({
        }, readyIds);
        delete r[id];
        readyIds = r;
        Quickshell.execDetached(["bash", "-c", 'printf "%s\\tx\\n" "$1" | cliphist delete; rm -f "$2"/"$1".*', "qs-clip", String(id), tempDir]);
    }

    // The history only: pinned entries stay
    function wipe() {
        entries = [];
        signature = "";
        readyIds = ({
        });
        attempted = ({
        });
        Quickshell.execDetached(["bash", "-c", 'cliphist wipe; rm -rf "$1"', "qs-clip", tempDir]);
    }

    function detectExt(preview) {
        if (!preview.startsWith("[[ binary data"))
            return "";

        const m = preview.toLowerCase().match(/\b(png|jpe?g|gif|webp|bmp)\b/);
        if (!m)
            return "";

        return m[1] === "jpeg" ? "jpg" : m[1];
    }

    function mimeFor(ext) {
        switch (ext) {
        case "png":
            return "image/png";
        case "jpg":
            return "image/jpeg";
        case "gif":
            return "image/gif";
        case "webp":
            return "image/webp";
        case "bmp":
            return "image/bmp";
        }
        return "";
    }

    function imageMeta(preview) {
        const m = preview.match(/binary data\s+([\d.]+\s*\S+)\s+\S+\s+(\d+)x(\d+)/i);
        return m ? (m[2] + "×" + m[3] + "  ·  " + m[1]) : "";
    }

    function textKind(t) {
        if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(t))
            return "color";

        if (/^(https?|ftp):\/\/\S+$/i.test(t) || /^www\.\S+$/i.test(t))
            return "url";

        return "text";
    }

    function parseList(text) {
        const parsed = [];
        for (const line of text.split("\n")) {
            const m = line.match(/^(\d+)\s+(.*)$/);
            if (!m)
                continue;

            const id = m[1];
            const preview = m[2].replace(/\r$/, "");
            const ext = detectExt(preview);
            if (ext !== "") {
                parsed.push({
                    "id": id,
                    "preview": preview,
                    "hay": preview.toLowerCase(),
                    "label": preview,
                    "isImage": true,
                    "ext": ext,
                    "mime": mimeFor(ext),
                    "path": tempDir + "/" + id + "." + ext,
                    "kind": "image",
                    "meta": imageMeta(preview)
                });
            } else {
                const label = preview.replace(/\s+/g, " ").trim();
                if (label === "")
                    continue;

                parsed.push({
                    "id": id,
                    "preview": preview,
                    "hay": label.toLowerCase(),
                    "label": label,
                    "isImage": false,
                    "ext": "",
                    "mime": "",
                    "path": "",
                    "kind": textKind(label),
                    "meta": ""
                });
            }
        }
        const sig = parsed.map((e) => {
            return e.id;
        }).join(",");
        if (sig !== signature) {
            entries = parsed;
            signature = sig;
        }
        loaded = true;
        startDecode();
    }

    function startDecode() {
        const specs = [];
        let seen = 0;
        for (const e of entries) {
            if (!e.isImage)
                continue;

            if (++seen > imageLimit)
                break;

            if (readyIds[e.id] || attempted[e.id])
                continue;

            specs.push(e.id + ":" + e.ext);
        }
        if (specs.length === 0)
            return ;

        if (decodeProc.running) {
            decodeQueued = true;
            return ;
        }
        for (const s of specs) attempted[s.split(":")[0]] = true
        decodeProc.command = ["bash", "-c", decodeScript, "qs-clip", tempDir].concat(specs);
        decodeProc.running = true;
    }

    function markReady(id) {
        if (id === "" || readyIds[id])
            return ;

        const c = Object.assign({
        }, readyIds);
        c[id] = true;
        readyIds = c;
    }

    function toggle() {
        PickerManager.toggle("clipboard");
    }

    function open() {
        PickerManager.open("clipboard");
    }

    function close() {
        if (PickerManager.isOpen("clipboard"))
            PickerManager.close();

    }

    Process {
        id: pinProc

        property var pending: null

        onExited: (code) => {
            if (code === 0 && pending) {
                root.pins = [pending].concat(root.pins);
                root.lastPinned = pending.pid;
                root.savePins();
            }
            pending = null;
        }
    }

    FileView {
        id: pinView

        path: root.pinFile
        printErrors: false
        onLoaded: {
            try {
                const list = JSON.parse(text()) || [];
                root.pins = list.filter((p) => {
                    return p && p.pid && p.path;
                });
            } catch (e) {
                root.pins = [];
            }
        }
    }

    Process {
        id: listProc

        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseList(text);
            }
        }

    }

    Process {
        id: decodeProc

        onRunningChanged: {
            if (!running && root.decodeQueued) {
                root.decodeQueued = false;
                root.startDecode();
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                return root.markReady(line.trim());
            }
        }

    }

    // Refresh once when opening
    Connections {
        function onActivePickerChanged() {
            if (PickerManager.activePicker === "clipboard")
                root.refresh();

        }

        target: PickerManager
    }

    // Refresh continuously every 500ms while the picker is open.
    // cliphist has no watch mechanism, so we poll.
    Timer {
        id: liveRefreshTimer

        interval: 500
        running: root.pickerVisible
        repeat: true
        onTriggered: root.refresh()
    }

}
