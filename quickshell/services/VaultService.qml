// Vaults (gocryptfs) in the folder browser of the image/video editors: unlock with a password and lock again.
// Same behavior as the yazi plugin (~/.config/yazi/plugins/vault.yazi): password only via stdin,
// gocryptfs locks itself after 3 min of inactivity, no preview images from the vault on the disk.
// Only what Quickshell unlocked itself is locked (a vault opened by yazi stays yazi's business),
// and only when neither the browser nor an editor is in it. If a file is still open: again later.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/media_browse.py").toString().replace("file://", "")
    // Unlocked by us -> we lock them again too
    property var ourMounts: []
    readonly property bool unlocking: unlockProc.running
    property string error: "" // "wrong" or the message of the last unlock
    // Paths needed right now: folder of the open browser, files of the open editors and of the
    // compress queue (it keeps running with the editor closed)
    readonly property var usedPaths: [MediaBrowserState.active ? MediaBrowserState.dir : "", VideoEditorState.isOpen ? VideoEditorState.path : "", ScreenshotEditorState.isOpen ? ScreenshotEditorState.shownPath : ""].concat(CompressQueue.paths)
    readonly property var idleMounts: ourMounts.filter((m) => {
        return !usedPaths.some((p) => {
            return p !== "" && inside(p, m);
        });
    })

    signal unlocked(string mount)
    signal wrongPassword()
    signal locked(string mount)

    function inside(path, mount) {
        return path === mount || path.indexOf(mount + "/") === 0;
    }

    function unlock(cipher, mount, password) {
        if (unlockProc.running)
            return ;

        error = "";
        unlockProc.mount = mount;
        unlockProc.result = "";
        unlockProc.command = ["python3", "-I", script, "unlock", cipher, mount];
        unlockProc.pending = password;
        unlockProc.running = true;
    }

    // Lock right away (lock button in the browser); if an open file holds it, lockTimer keeps trying
    function lockNow(mount) {
        if (ourMounts.indexOf(mount) < 0)
            ourMounts = ourMounts.concat([mount]);

        lockTimer.interval = 300;
        lockTimer.restart();
    }

    onIdleMountsChanged: {
        if (idleMounts.length > 0) {
            lockTimer.interval = 300;
            lockTimer.restart();
        }
    }

    // Wait briefly: when switching folders you are "outside" for a moment
    Timer {
        id: lockTimer

        interval: 300
        onTriggered: {
            if (lockProc.running || root.idleMounts.length === 0)
                return ;

            lockProc.mount = root.idleMounts[0];
            lockProc.command = ["python3", "-I", root.script, "lock", lockProc.mount];
            lockProc.running = true;
        }
    }

    Process {
        id: unlockProc

        property string mount: ""
        property string result: ""
        // Hold the password only until the start, then pass it via stdin and forget it
        property string pending: ""

        stdinEnabled: true
        onStarted: {
            write(pending + "\n");
            pending = "";
        }
        onExited: {
            pending = "";
            if (result === "ok") {
                if (root.ourMounts.indexOf(mount) < 0)
                    root.ourMounts = root.ourMounts.concat([mount]);

                root.unlocked(mount);
            } else if (result === "wrong") {
                root.error = "wrong";
                root.wrongPassword();
            } else {
                root.error = result || "Could not unlock";
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const msg = JSON.parse(line);
                    unlockProc.result = msg.ok ? "ok" : (msg.error || "");
                } catch (e) {
                }
            }
        }

    }

    Process {
        id: lockProc

        property string mount: ""
        property string result: ""

        onStarted: result = ""
        onExited: {
            if (result === "ok") {
                root.ourMounts = root.ourMounts.filter((m) => {
                    return m !== mount;
                });
                root.locked(mount);
            }
            // Still busy (file open): again in 5 s, as long as it stays unused
            if (root.idleMounts.length > 0) {
                lockTimer.interval = result === "ok" ? 300 : 5000;
                lockTimer.restart();
            }
        }

        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const msg = JSON.parse(line);
                    lockProc.result = msg.ok ? "ok" : (msg.error || "");
                } catch (e) {
                }
            }
        }

    }

}
