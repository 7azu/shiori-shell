import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// The first step while you are away (services/IdleState): a dark veil over every monitor that fades
// in slowly. It takes no clicks and no keys, so any input reaches the apps below and hypridle lifts it
// at once. Only mapped while it shows. Layer "quickshell:idle-dim" without Hyprland's own fade
// (rule in hypr/modules/windows.lua): the fade is drawn here.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData

            screen: modelData
            visible: IdleState.dimK > 0.002
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            color: "transparent"
            WlrLayershell.namespace: "quickshell:idle-dim"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region {
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: IdleState.dimK * IdleState.dimMax
            }

        }

    }

}
