import "../lock"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Transition power menu -> lock screen on the other monitors (state: LockTransitionState).
// First image = capture of the monitor, then it freezes exactly as in the lock screen (same building blocks
// LockBackdrop/LockForeground) and the clock falls in from the top. lock.qml then takes over this
// finished image without its own intro.
Variants {
    model: LockTransitionState.active ? Quickshell.screens.filter((s) => {
        return s.name !== LockTransitionState.menuScreen;
    }) : []

    PanelWindow {
        id: win

        required property var modelData
        readonly property string shot: LockTransitionState.shotPrefix + "-" + modelData.name + ".ppm"
        property real frost: 0
        property real enter: 0

        screen: modelData
        visible: LockTransitionState.shotsReady
        color: "transparent"
        exclusiveZone: -1
        // Without a Hyprland fade-in (rule in hypr/modules/windows.lua), not clickable
        WlrLayershell.namespace: "quickshell:lock-transition"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}
        onVisibleChanged: {
            if (visible)
                anim.restart();

        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        ParallelAnimation {
            id: anim

            NumberAnimation {
                target: win
                property: "frost"
                from: 0
                to: 1
                duration: LockTransitionState.frostMs
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.outQuint
            }

            NumberAnimation {
                target: win
                property: "enter"
                from: 0
                to: 1
                duration: LockTransitionState.frostMs
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.outQuint
            }

        }

        LockBackdrop {
            anchors.fill: parent
            wallpaper: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-lock-wall-" + win.modelData.name
            frost: win.frost
            drifting: false
            overlay: [
                Image {
                    anchors.fill: parent
                    source: LockTransitionState.shotsReady ? "file://" + win.shot : ""
                    fillMode: Image.Stretch
                    asynchronous: false
                    cache: false
                    opacity: Math.max(0, 1 - win.frost / 0.85)
                }
            ]
        }

        LockForeground {
            anchors.fill: parent
            enter: win.enter
            primary: win.modelData.name === MachineConfig.activeBarScreen(Quickshell.screens).name
        }

    }

}
