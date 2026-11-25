import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Soft change when the bar (and with it the wallpaper animation) moves to another monitor
// (flow: WallpaperPickerState, "moveState"). Shows the still image of the current wallpaper:
//   monitor left behind: fades in over the still running animation, then the animation goes
//   new monitor (scene only): covers until the scene draws, then fades out
// (AnimatedWallpaper fades videos in on the new monitor itself.)
// Bottom layer, created later than the video windows -> above them; scenes lie on background.
Variants {
    model: WallpaperPickerState.moveState ? Quickshell.screens.filter((s) => {
        return s.name === WallpaperPickerState.moveOld || (WallpaperPickerState.moveScene && s.name === WallpaperPickerState.moveNew);
    }) : []

    PanelWindow {
        id: win

        required property var modelData
        readonly property bool leaving: modelData.name === WallpaperPickerState.moveOld

        screen: modelData
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:anim-move-fade"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Image {
            id: still

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            source: WallpaperPickerState.moveStills[WallpaperTransition.sizeFor(win.modelData)] || ""
            opacity: win.leaving ? WallpaperPickerState.moveOldFade : WallpaperPickerState.moveNewFade
            onStatusChanged: {
                if (status === Image.Ready)
                    WallpaperPickerState.moveStillLoaded(win.modelData.name);
                else if (status === Image.Error)
                    WallpaperPickerState.moveAbort();
            }
        }

        mask: Region {
        }

    }

}
