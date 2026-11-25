// Queue for compressing with HandBrake (video editor, "Compress" page). Not tied to the
// editor window: you can browse on, queue more videos and close the editor, the work goes on
// in the shell. Always only one video at a time (HandBrake uses all cores anyway).
// The work is done by scripts/video_edit.py compress; the result as a notification and the signal finished.

import "../common/Format.js" as Fmt
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/video_edit.py").toString().replace("file://", "")
    // On machines without HandBrake the feature disappears from the editor
    property bool available: false
    // { id, path, name, level, start, end, rotation, mute, replace }; the first one runs while busy
    property var jobs: []
    readonly property bool busy: proc.running
    readonly property var current: busy && jobs.length > 0 ? jobs[0] : null
    property real progress: 0
    // File -> result of the last run (text for the editor), stored under source and target
    property var notes: ({})
    property int nextId: 1
    // Paths needed right now (VaultService does not lock a vault meanwhile)
    readonly property var paths: jobs.map((j) => {
        return j.path;
    })

    // how: "copy" | "replaced" | "kept" (replacing failed, kept as a copy)
    signal finished(string source, string how, string target)

    // Folder sorted by date: results stick to the file, not to the old name. Queued files
    // are not renamed (the browser then does not sort)
    function applyRenames(moved) {
        const out = {};
        for (const k of Object.keys(notes))
            out[moved[k] !== undefined ? moved[k] : k] = notes[k];
        notes = out;
    }

    function indexOf(path) {
        return jobs.findIndex((j) => {
            return j.path === path;
        });
    }

    function percentSaved(before, after) {
        return Math.round((1 - after / Math.max(1, before)) * 100);
    }

    // job without id; the same file only enters the queue once
    function add(job) {
        if (!available || indexOf(job.path) >= 0)
            return ;

        const j = Object.assign({
            "id": nextId,
            "name": job.path.substring(job.path.lastIndexOf("/") + 1)
        }, job);
        nextId++;
        jobs = jobs.concat([j]);
        const n = Object.assign({}, notes);
        delete n[job.path];
        notes = n;
        startNext();
    }

    // Waiting: take it out of the queue. Running: cancel (the script removes the half-written file)
    function remove(path) {
        const i = indexOf(path);
        if (i < 0)
            return ;

        if (i === 0 && busy) {
            proc.cancelled = true;
            proc.running = false;
            return ;
        }
        jobs = jobs.filter((j, k) => {
            return k !== i;
        });
    }

    function startNext() {
        if (busy || jobs.length === 0)
            return ;

        const j = jobs[0];
        progress = 0;
        proc.cancelled = false;
        proc.lastResult = "";
        proc.command = ["python3", "-I", script, "compress", j.path, j.level, j.start.toFixed(3), j.end.toFixed(3), String(j.rotation), j.mute ? "1" : "0", j.replace ? "1" : "0"];
        proc.running = true;
    }

    function setNote(paths, text) {
        const n = Object.assign({}, notes);
        for (const p of paths)
            n[p] = text;
        notes = n;
    }

    Component.onCompleted: check.running = true

    Process {
        id: check

        command: ["sh", "-c", "command -v HandBrakeCLI"]
        onExited: (code) => {
            root.available = code === 0;
        }
    }

    Process {
        id: proc

        property string lastResult: ""
        property bool cancelled: false

        onExited: (code) => {
            const job = root.jobs[0];
            root.jobs = root.jobs.slice(1);
            root.progress = 0;
            const parts = lastResult.split(" ");
            if (cancelled) {
                // Cancelled: nothing to report
            } else if (parts[0] === "OK") {
                // "OK <copy|replaced|kept> <before> <after> <path>" - the path may contain spaces
                const how = parts[1];
                const before = Number(parts[2]);
                const after = Number(parts[3]);
                const target = parts.slice(4).join(" ");
                const name = target.substring(target.lastIndexOf("/") + 1);
                const sizes = Fmt.bytes(before) + " → " + Fmt.bytes(after) + " (−" + root.percentSaved(before, after) + " %)";
                if (how === "replaced") {
                    root.setNote([job.path, target], "Compressed " + sizes);
                    NotificationState.send("Video", "Video compressed", name + " · " + sizes, {
                        "success": true
                    });
                } else {
                    root.setNote([job.path], how === "kept" ? "Original couldn't go to the trash, saved as copy" : "Saved copy " + sizes);
                    NotificationState.send("Video", "Compressed copy saved", name + " · " + sizes, {
                        "success": true
                    });
                }
                root.finished(job.path, how, target);
            } else if (parts[0] === "BIGGER") {
                root.setNote([job.path], "Already compact, nothing changed");
                NotificationState.send("Video", "Not compressed", job.name + " is already compact, nothing changed", {});
            } else {
                const message = lastResult.indexOf("ERR ") === 0 ? lastResult.substring(4) : "HandBrake stopped (code " + code + ")";
                root.setNote([job.path], "Failed: " + message);
                NotificationState.send("Video", "Compression failed", job.name + " · " + message, {});
            }
            // Not directly: from its own onExited the same Process does not restart (measured)
            Qt.callLater(root.startNext);
        }

        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("P ") === 0)
                    root.progress = Number(line.substring(2));
                else
                    proc.lastResult = line;
            }
        }

    }

}
