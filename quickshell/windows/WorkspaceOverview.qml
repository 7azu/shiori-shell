import "../common"
import "overview"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Workspace overview (right-click on the workspaces in the bar, `qs ipc call workspaceoverview toggle`).
// Only the window: state, layout, motion and controls are in overview/OverviewView.qml,
// cards in overview/WorkspaceCard.qml, window previews in overview/WindowThumb.qml.
// The view itself fades in and out. The layer surface stays mapped across the change.
PanelWindow {
    id: overview

    // Stays on the monitor + workspace where it was opened
    WindowAnchor {
        id: anchor

        open: view.shown
        onClosedWhileAway: view.show()
    }

    WlrLayershell.namespace: "quickshell:workspaceoverview"
    WlrLayershell.layer: WlrLayer.Overlay
    // Keyboard only while it is usable and its monitor is focused
    WlrLayershell.keyboardFocus: view.interactive && anchor.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    screen: anchor.screen
    visible: view.shown && anchor.here
    color: "transparent"
    onVisibleChanged: {
        if (visible)
            view.forceActiveFocus();

    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            view.toggle();
        }

        // Not "show": "qs ipc call <target> show" collides with Quickshell's own "qs ipc show"
        // and only prints the help
        function open() {
            view.show();
        }

        function hide() {
            view.dismiss();
        }

        target: "workspaceoverview"
    }

    OverviewView {
        id: view

        // The monitor reports the right size before the layer surface was configured.
        width: overview.screen ? overview.screen.width : overview.width
        height: overview.screen ? overview.screen.height : overview.height
        monitor: anchor.monitor
        capturing: overview.visible
        onWorkspaceHandoff: anchor.pinTo(-1)
    }

}
