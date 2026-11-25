// Trash: data and actions for pickers/TrashPicker.qml (the work is done by scripts/trash.py).
// Only the trash in the home folder: the one in a vault (.Trash-1000) should not reveal its names here.
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/trash.py").toString().replace("file://", "")
    readonly property string home: Quickshell.env("HOME")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")
    readonly property string filesDir: dataHome + "/Trash/files"
    readonly property bool pickerVisible: PickerManager.isOpen("trash")
    readonly property bool busy: opProc.running || queue.length > 0
    property var entries: []
    property bool loaded: false
    property bool emptying: false
    property string message: ""
    property bool messageIsError: false
    property var queue: []
    property bool refreshAgain: false
    property string lastOutput: ""

    function toggle() {
        PickerManager.toggle("trash");
    }

    function refresh() {
        if (listProc.running)
            refreshAgain = true;
        else
            listProc.running = true;
    }

    function prettyPath(path) {
        return path.indexOf(home) === 0 ? "~" + path.slice(home.length) : path;
    }

    function showMessage(text, isError) {
        message = text;
        messageIsError = isError;
        messageTimer.restart();
    }

    function drop(entry) {
        entries = entries.filter((e) => {
            return e.id !== entry.id;
        });
    }

    function enqueue(args) {
        queue = queue.concat([args]);
        startNext();
    }

    function startNext() {
        if (opProc.running || queue.length === 0)
            return ;

        const next = queue[0];
        queue = queue.slice(1);
        opProc.action = next[0];
        opProc.command = ["python3", script].concat(next);
        opProc.running = true;
    }

    // The list is adjusted right away (the row animates out), the script follows behind.
    // If it fails, the refresh after processing brings the entry back.
    function restore(entry) {
        drop(entry);
        enqueue(["restore", entry.id]);
    }

    function remove(entry) {
        drop(entry);
        enqueue(["delete", entry.id]);
    }

    function empty() {
        if (entries.length === 0 || emptying)
            return ;

        emptying = true;
        entries = [];
        enqueue(["empty"]);
    }

    function parseList(text) {
        if (text === lastOutput)
            return ;

        lastOutput = text;
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (err) {
            console.warn("[TrashState] list not readable:", err);
            return ;
        }
        // Unchanged entries keep their object: otherwise every refresh rebuilds all rows
        const known = {
        };
        for (const e of entries) known[e.id] = e
        entries = parsed.map((e) => {
            const old = known[e.id];
            if (old && old.size === e.size && old.ts === e.ts)
                return old;

            e.lname = e.name.toLowerCase();
            e.hay = (e.name + " " + e.origin).toLowerCase();
            e.place = e.origin === "" ? "Unknown origin" : prettyPath(e.origin);
            return e;
        });
    }

    Process {
        id: listProc

        command: ["python3", root.script, "list"]
        onRunningChanged: {
            if (!running && root.refreshAgain) {
                root.refreshAgain = false;
                running = true;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                // While actions are running the list is already outdated and would bring deleted items back
                if (root.busy || root.refreshAgain)
                    return ;

                root.parseList(text);
                root.loaded = true;
            }
        }

    }

    Process {
        id: opProc

        property string action: ""
        property string output: ""

        onRunningChanged: {
            if (running)
                return ;

            let result = {
                "ok": false,
                "error": "Script failed"
            };
            try {
                result = JSON.parse(output);
            } catch (err) {
            }
            if (!result.ok)
                root.showMessage(result.error, true);
            else if (action === "restore")
                root.showMessage("Restored to " + root.prettyPath(result.restoredTo), false);
            if (action === "empty")
                root.emptying = false;

            output = "";
            root.startNext();
            if (!root.busy) {
                root.lastOutput = "";
                root.refresh();
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                opProc.output += line;
            }
        }

    }

    Timer {
        id: messageTimer

        interval: 4500
        onTriggered: root.message = ""
    }

    // Whatever lands in the trash while the window is open should show up too
    Timer {
        interval: 5000
        running: root.pickerVisible && !root.busy
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        function onActivePickerChanged() {
            if (PickerManager.activePicker === "trash")
                root.refresh();

        }

        target: PickerManager
    }

}
