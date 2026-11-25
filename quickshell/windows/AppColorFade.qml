import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Color change of apps on a wallpaper change as a real crossfade (Vesktop, OBS; flow and why:
// services/SnapshotColorFade.qml). One window per app that is fading right now: freezes the
// monitor section above it, reports the still image, the app changes colors underneath in one step,
// then the still image fades out. Only exists during the change; click-through.
// Top layer (above windows, below pickers/overlay), without a Hyprland layer animation (windows.lua).
Variants {
    model: TerminalColorFade.snapshotFades.filter(f => f.active && f.screen)

    PanelWindow {
        id: win

        // the SnapshotColorFade instance
        required property var modelData
        readonly property rect area: modelData.rect

        screen: modelData.screen
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:app-color-fade"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Only the app's section of the monitor image: everything else (wallpaper wave, terminals) stays live
        Item {
            id: cut

            x: win.area.x
            y: win.area.y
            width: win.area.width
            height: win.area.height
            clip: true
            // only show when the image is there (before, the surface would be empty = no difference)
            opacity: shot.hasContent ? win.modelData.opacity : 0

            ScreencopyView {
                id: shot

                x: -cut.x
                y: -cut.y
                width: win.screen.width
                height: win.screen.height
                // one single frame; our own window is still transparent meanwhile
                live: false
                captureSource: win.screen
                onHasContentChanged: {
                    if (hasContent)
                        shownDelay.start();
                }
            }
        }

        // a few frames until the still image is surely on screen, only then change colors underneath
        Timer {
            id: shownDelay

            interval: 50
            onTriggered: win.modelData.captured()
        }

        mask: Region {
        }

    }

}
