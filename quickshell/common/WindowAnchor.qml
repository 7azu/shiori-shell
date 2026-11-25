import QtQuick
import Quickshell
import Quickshell.Hyprland

// Keeps an overlay window where it was opened: monitor + workspace are held
// when opening. It no longer moves to other monitors with the cursor and is hidden
// while its monitor shows another workspace (when switching back it is there again).
//
//   WindowAnchor { id: anchor; open: <window open> ; onClosedWhileAway: <open again> }
//   screen: anchor.screen
//   visible: <as before> && anchor.here
//
// If a hidden window is "closed" by keybind/click, what was really meant is:
// bring it here -> closedWhileAway, the window then opens again (on the current workspace).
QtObject {
    id: anchor

    // The window is (logically) open
    property bool open: false
    readonly property var focusedScreen: {
        const focused = Hyprland.focusedMonitor;
        if (focused) {
            const match = Quickshell.screens.find((s) => {
                return s.name === focused.name;
            });
            if (match)
                return match;

        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }
    // Held when opening; stays after closing (for closing animations)
    property var pinnedScreen: null
    property int workspaceId: -1
    readonly property var screen: pinnedScreen ?? focusedScreen
    readonly property var monitor: {
        const name = screen ? screen.name : "";
        return Hyprland.monitors.values.find((m) => {
            return m.name === name;
        }) ?? null;
    }
    // Does the monitor show the workspace the window was opened on right now?
    readonly property bool here: workspaceId < 0 || !monitor || !monitor.activeWorkspace || monitor.activeWorkspace.id === workspaceId
    readonly property bool away: open && !here
    // Is the window's monitor focused right now (cursor there)? Only then may it take the keyboard
    // exclusively, otherwise windows on the other monitors would no longer be usable
    readonly property bool focused: !!Hyprland.focusedMonitor && !!screen && Hyprland.focusedMonitor.name === screen.name
    // Since when the monitor shows another workspace (0 = here right now)
    property double _leftAt: 0
    // When the window was opened (0 = closed)
    property double _openedAt: 0

    signal closedWhileAway()

    // Is the window only becoming visible again because you returned to its workspace
    // (instead of freshly opened)? For onVisibleChanged: then e.g. do not clear the search
    function isReturn() {
        return open && _openedAt > 0 && Date.now() - _openedAt > 300;
    }

    // Set to the focused monitor + its workspace
    function pin() {
        const m = Hyprland.focusedMonitor;
        pinnedScreen = focusedScreen;
        workspaceId = m && m.activeWorkspace ? m.activeWorkspace.id : -1;
    }

    // Set to a specific workspace (the monitor stays), e.g. when the media picker moves with the player to
    // its own workspace. -1 = bound to no workspace (always "here")
    function pinTo(id) {
        workspaceId = id;
    }

    onHereChanged: _leftAt = here ? 0 : Date.now()
    onOpenChanged: {
        if (open) {
            pin();
            _leftAt = 0;
            _openedAt = Date.now();
            return ;
        }
        _openedAt = 0;
        if (_leftAt > 0 && Date.now() - _leftAt > 400) {
            // Only if it was gone for a while: if a window closes itself because it just
            // switched the workspace (e.g. the workspace overview), it should not open again
            Qt.callLater(anchor.closedWhileAway);
        }
    }
}
