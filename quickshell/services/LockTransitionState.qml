import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Transition power menu -> lock screen on the OTHER monitors (windows/LockTransition.qml).
// The menu only shows the transition on its own monitor; without this the other monitors would
// only start at the handover to lock.qml (~1 s later). On a click on Lock the other
// monitors are captured, then the same image freezes there as in the lock screen and the clock falls
// in. At the handover every monitor already shows the finished lock screen.
Singleton {
    id: root

    property bool active: false
    // Monitor of the power menu (there the transition runs in the menu itself)
    property string menuScreen: ""
    // Captures of the other monitors are ready -> the transition starts
    property bool shotsReady: false
    // Same name as the menu's desktop capture: lock.sh takes these images as the target image when
    // unlocking (desktop without the lock screen)
    readonly property string shotPrefix: Quickshell.env("XDG_RUNTIME_DIR") + "/powermenu-desktop"
    // Duration of the freeze; must be done before the handover to lock.qml (power menu, ~0.94 s)
    readonly property int frostMs: 780

    function begin(screenName) {
        menuScreen = screenName;
        shotsReady = false;
        const others = Quickshell.screens.filter((s) => {
            return s.name !== screenName;
        }).map((s) => {
            return s.name;
        });
        if (others.length === 0)
            return ;

        active = true;
        shotProc.command = [Qt.resolvedUrl("../scripts/desktop_shot.sh").toString().replace("file://", ""), shotPrefix].concat(others);
        shotProc.running = true;
    }

    function end() {
        shotProc.running = false;
        active = false;
        shotsReady = false;
    }

    Process {
        id: shotProc

        onExited: {
            if (root.active)
                root.shotsReady = true;

        }
    }

}
