import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Backdrop of a modal window: dimming over the whole screen, Hyprland blurs behind it (blur rule with
// ignore_alpha for its namespace in hypr/modules/windows.lua, animation "fade"). A layer surface of its
// own below the card window: on closing it goes at once and Hyprland fades it while the card evaporates
// (common/Evaporate), so both leave together. It must be on a lower layer (Top) than the card
// (Overlay): Hyprland draws a closing layer's fade above the other surfaces of its layer (measured).
PanelWindow {
    id: bd

    // Namespace with the blur rule, e.g. "quickshell:settings"
    property string name: ""
    property bool shown: false
    property color dim: WalColors.withAlpha(WalColors.color0, 0.4)
    // false: clicks go through (the card window decides)
    property bool clickable: true
    // For windows that glide with Hyprland's workspace slide (common/WorkspaceSlide): the veil moves along
    property real shift: 0
    property real veilOpacity: 1

    signal clicked()

    visible: shown
    color: "transparent"
    WlrLayershell.namespace: bd.name
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: clickable ? null : emptyRegion

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Region {
        id: emptyRegion
    }

    Rectangle {
        anchors.fill: parent
        color: bd.dim
        opacity: bd.veilOpacity

        transform: Translate {
            x: bd.shift
        }

    }

    MouseArea {
        anchors.fill: parent
        enabled: bd.clickable
        onClicked: bd.clicked()
    }

}
