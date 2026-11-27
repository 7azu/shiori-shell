import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Settings of the shell: a card in the middle of the screen over a dimmed, blurred background, like
// the pickers and the calculator. Two layer surfaces: the backdrop (dimming + Hyprland blur, layer
// "quickshell:settings" on Top, blur rule in hypr/modules/windows.lua) and above it this window with
// the card ("quickshell:settings-card" on Overlay, no Hyprland animation). On closing the backdrop
// (common/ModalBackdrop) goes at once while the card evaporates (common/Evaporate).
// Opened by Super + , (toggle_settings), the gear in the bar (bar/SettingsButton), the gear in a
// dropdown header and `qs ipc call settings open <page>`; state and the description of the pages:
// services/SettingsState. A click next to the card closes it.
// The content only exists while the window is open (and during the closing).
PanelWindow {
    id: win

    // 0 -> 1 while opening
    property real reveal: 0
    // Spring scale on top of reveal (same pop as the pickers), overshoots briefly
    property real pop: 1
    screen: anchor.screen
    visible: ev.held && anchor.here
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    WlrLayershell.namespace: "quickshell:settings-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible && anchor.focused && !ev.closing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onVisibleChanged: {
        opening.stop();
        if (visible) {
            // Do not pop up again on a workspace change; only on a real opening
            if (anchor.isReturn()) {
                reveal = 1;
                pop = 1;
            } else {
                opening.restart();
            }
        } else {
            reveal = 0;
        }
    }

    // While a shortcut row waits for its keys, Hyprland holds its own shortcuts back: Super + M then
    // reaches this window instead of opening the music picker. Ends by itself if the window goes away.
    ShortcutInhibitor {
        window: win
        enabled: Keybinds.captureId !== ""
    }

    // Stays on the monitor and workspace where it was opened
    WindowAnchor {
        id: anchor

        open: SettingsState.open
        onClosedWhileAway: SettingsState.open = true
    }

    Evaporate {
        id: ev

        window: win
        open: SettingsState.open
        // Opened again during the closing: play the opening from here
        onReopened: opening.restart()
    }

    ParallelAnimation {
        id: opening

        NumberAnimation {
            target: win
            property: "reveal"
            from: 0
            to: 1
            duration: Appearance.anim.durations.slow
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.outQuint
        }

        NumberAnimation {
            target: win
            property: "pop"
            from: 0.88
            to: 1
            duration: Appearance.anim.durations.spring
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.spring
        }

    }

    // Clicks only on the card; next to it they go through to the backdrop (which closes)
    mask: Region {
        item: card
    }

    ModalBackdrop {
        screen: anchor.screen
        name: "quickshell:settings"
        shown: SettingsState.open && anchor.here
        onClicked: SettingsState.close()
    }

    Item {
        id: card

        anchors.centerIn: parent
        anchors.verticalCenterOffset: Theme.px(20) * (1 - win.reveal)
        width: Math.min(Theme.px(1060), parent.width - Theme.px(48))
        height: Math.min(Theme.px(720), parent.height - Theme.px(96))
        scale: (0.95 + 0.05 * win.reveal) * win.pop * ev.scale
        opacity: win.reveal * ev.opacity
        // Blur only while closing (costs nothing while open)
        layer.enabled: ev.closing

        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: true
            blur: ev.blur
            blurMax: 64
            blurMultiplier: 0.6
        }

        // Clicks on the card do not reach the background (which closes)
        MouseArea {
            anchors.fill: parent
        }

        // Round corners that also cut the rail and the folder browser
        RoundedClip {
            anchors.fill: parent
            radius: Theme.radiusXL
            // Opaque: the blurred desktop behind the card stays around it, not in it
            color: WalColors.color0

            Loader {
                anchors.fill: parent
                active: ev.held
                enabled: !ev.closing
                focus: true

                sourceComponent: SettingsView {
                    focus: true
                }

            }

        }

        // Fine edge like the calculator card
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXL
            color: "transparent"
            border.width: 1
            border.color: Theme.glass
        }

    }

}
