import "./lock"
import "./services"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Lock screen as its OWN qs instance (not in shell.qml): a hot reload or crash of the
// main shell must never touch the lock. Started by ~/.config/hypr/scripts/lock.sh
// (`qs -n -p ~/.config/quickshell/lock.qml`); if this instance crashes, lock.sh starts it again.
ShellRoot {
    id: shell

    // No hot reload while locked (e.g. when a sync changes files)
    settings.watchFiles: false

    // From the power menu (QS_LOCK_DEFER=1): load already while the tiles sink away there, but only
    // lock once lock.sh has captured the screen (`qs ipc --pid <pid> call lockscreen engage`).
    // So there is no waiting time between the menu and the lock screen.
    readonly property bool deferred: Quickshell.env("QS_LOCK_DEFER") === "1"
    property bool engaged: !deferred
    // Monitor of the power menu (engage argument). Set = the lock comes from the menu: there and on
    // all other monitors (windows/LockTransition.qml) the finished lock screen is already shown
    property string preEnteredScreen: ""
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR")

    Component.onCompleted: Quickshell.execDetached(["touch", runDir + "/quickshell-lock.loaded"])

    IpcHandler {
        function engage(screen: string): void {
            console.log("time", Date.now(), "engage", screen);
            shell.preEnteredScreen = screen;
            shell.engaged = true;
        }

        target: "lockscreen"
    }

    // Current pywal wallpaper (the path is in ~/.cache/wal/wal without a newline)
    FileView {
        id: walFile

        path: Quickshell.env("HOME") + "/.cache/wal/wal"
        blockLoading: true
    }

    WlSessionLock {
        id: lock

        locked: shell.engaged
        // The lock really holds (the compositor confirmed) -> lock.sh waits for this file
        onSecureChanged: {
            if (secure)
                Quickshell.execDetached(["touch", shell.runDir + "/quickshell-lock.ready"]);

        }

        WlSessionLockSurface {
            id: surface

            color: WalColors.color0

            LockSurface {
                anchors.fill: parent
                // Exact wallpaper of this monitor (lock.sh: paused video frame or the awww image);
                // if it is missing, LockSurface uses the theme still image
                wallpaper: surface.screen ? shell.runDir + "/quickshell-lock-wall-" + surface.screen.name : ""
                fallbackWallpaper: walFile.text().trim()
                // Captured by lock.sh right before locking (if missing, the frost starts from the wallpaper)
                desktopShot: surface.screen ? shell.runDir + "/quickshell-lock-" + surface.screen.name + ".ppm" : ""
                // Target when unlocking: if the lock came from the power menu, the desktop without the menu
                thawShot: surface.screen ? shell.runDir + "/quickshell-lock-thaw-" + surface.screen.name + ".ppm" : ""
                primary: surface.screen && surface.screen.name === MachineConfig.activeBarScreen(Quickshell.screens).name
                preEntered: shell.preEnteredScreen !== ""
            }

        }

    }

    // After thawing (outro in LockSurface) release the session and quit
    Connections {
        function onUnlocked() {
            releaseTimer.start();
        }

        target: LockState
    }

    Timer {
        id: releaseTimer

        interval: LockState.thawTotal
        onTriggered: {
            lock.locked = false;
            quitTimer.start();
        }
    }

    Timer {
        id: quitTimer

        interval: 200
        onTriggered: Qt.quit()
    }

}
