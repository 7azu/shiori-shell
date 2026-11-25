import "../common"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Settings of the shell: a card in the middle of the screen over a dimmed, blurred background, like
// the pickers and the calculator (layer "quickshell:settings", blur rule in hypr/modules/windows.lua).
// Opened by Super + , (toggle_settings), the gear in the bar (bar/SettingsButton), the gear in a
// dropdown header and `qs ipc call settings open <page>`; state and the description of the pages:
// services/SettingsState. A click next to the card closes it.
// The content only exists while the window is open.
PanelWindow {
    id: win

    // 0 -> 1 while opening
    property real reveal: 0

    screen: anchor.screen
    visible: SettingsState.open && anchor.here
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    WlrLayershell.namespace: "quickshell:settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible && anchor.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onVisibleChanged: {
        opening.stop();
        if (visible) {
            // Do not pop up again on a workspace change; only on a real opening
            if (anchor.isReturn())
                reveal = 1;
            else
                opening.restart();
        } else {
            reveal = 0;
        }
    }

    // Stays on the monitor and workspace where it was opened
    WindowAnchor {
        id: anchor

        open: SettingsState.open
        onClosedWhileAway: SettingsState.open = true
    }

    NumberAnimation {
        id: opening

        target: win
        property: "reveal"
        from: 0
        to: 1
        duration: Appearance.anim.durations.slow
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    // As in the pickers: alpha via ignore_alpha on the whole screen, so Hyprland blurs the background
    // outside the card too
    Rectangle {
        anchors.fill: parent
        color: WalColors.withAlpha(WalColors.color0, 0.4)

        MouseArea {
            anchors.fill: parent
            onClicked: SettingsState.close()
        }

    }

    Item {
        id: card

        anchors.centerIn: parent
        anchors.verticalCenterOffset: Theme.px(20) * (1 - win.reveal)
        width: Math.min(Theme.px(1060), parent.width - Theme.px(48))
        height: Math.min(Theme.px(720), parent.height - Theme.px(96))
        scale: 0.95 + 0.05 * win.reveal
        opacity: win.reveal

        // Clicks on the card do not reach the background (which closes)
        MouseArea {
            anchors.fill: parent
        }

        // Round corners that also cut the rail and the folder browser
        RoundedClip {
            anchors.fill: parent
            radius: Theme.radiusXL
            color: WalColors.withAlpha(WalColors.color0, 0.92)

            Loader {
                anchors.fill: parent
                active: SettingsState.open
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
