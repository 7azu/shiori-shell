import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Overlay of the wallpaper transition (flow: services/WallpaperTransition.qml), two kinds:
//   newStill:  in the growing shape the still image of the new image, transparent outside
//   freezeOld: outside the old wallpaper frozen, transparent in the shape (the new scene live underneath)
// Bottom layer, created anew for the transition -> above all wallpapers (awww/scenes: background,
// AnimatedWallpaper: bottom, older), but below the windows.
Variants {
    // Per monitor as needed: the bar monitor by overlayMode, monitors without animation always "freezeOld"
    model: WallpaperTransition.active ? Quickshell.screens.filter((s) => {
        return WallpaperTransition.modeFor(s.name) !== "none";
    }) : []

    PanelWindow {
        id: win

        required property var modelData
        readonly property bool freeze: WallpaperTransition.modeFor(modelData.name) === "freezeOld"
        readonly property Image texture: freeze ? oldImage : newImage
        readonly property bool textureReady: texture.status === Image.Ready

        screen: modelData
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:ink-bloom"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        onTextureReadyChanged: {
            if (textureReady)
                WallpaperTransition.stillLoaded(win.modelData.name);

        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Only textures for the shader. Asynchronous: a big image would otherwise stall everything briefly
        Image {
            id: oldImage

            visible: false
            asynchronous: true
            cache: false
            source: win.freeze ? (WallpaperTransition.oldStills[win.modelData.name] || "") : ""
            onStatusChanged: {
                if (status === Image.Error)
                    WallpaperTransition.abort();

            }
        }

        Image {
            id: newImage

            visible: false
            asynchronous: true
            cache: false
            source: win.freeze ? "" : (WallpaperTransition.newStills[WallpaperTransition.sizeFor(win.modelData)] || "")
            onStatusChanged: {
                if (status === Image.Error)
                    WallpaperTransition.abort();

            }
        }

        ShaderEffect {
            property real cover: WallpaperTransition.cover
            property real live: win.freeze ? 1 : 0
            property real oldA: win.freeze ? 1 : 0
            property real maxR: WallpaperTransition.maxR
            property real time: WallpaperTransition.time
            property point origin: Qt.point(WallpaperTransition.origin.x - win.modelData.x, WallpaperTransition.origin.y - win.modelData.y)
            property size size: Qt.size(width, height)
            property size oldSize: Qt.size(Math.max(1, win.texture.implicitWidth), Math.max(1, win.texture.implicitHeight))
            property size newSize: oldSize
            property color glowColor: WalColors.color4
            property var oldTex: win.texture
            property var newTex: win.texture

            anchors.fill: parent
            visible: win.textureReady
            // On a transition into a scene the still image fades out at the end (WallpaperTransition.sceneFade)
            opacity: WallpaperTransition.overlayFade
            fragmentShader: Qt.resolvedUrl("shaders/inkbloom.frag.qsb")
        }

        mask: Region {
        }

    }

}
