import "../../common"
import "../../services"
import QtQuick
import QtQuick.Effects
import Quickshell.Io

// Assemble the background scaled down and fade it over the desktop as one surface.
Item {
    id: backdrop

    readonly property bool canBlur: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property string wallpaper: WallpaperPickerState.currentPath
    property var stills: ({})
    readonly property string source: {
        let best = "";
        let bestDiff = Infinity;
        const aspect = width / Math.max(1, height);
        for (const key of Object.keys(stills)) {
            const [w, h] = key.split("x").map(Number);
            const diff = Math.abs(w / h - aspect);
            if (diff < bestDiff) {
                bestDiff = diff;
                best = stills[key];
            }
        }
        return best;
    }

    function fetch() {
        if (wallpaper === "" || stillProc.running)
            return;

        stillProc.requestedPath = wallpaper;
        stillProc.command = ["bash", WallpaperTransition.stillScript, wallpaper].concat(WallpaperTransition.stillSizes);
        stillProc.running = true;
    }

    onWallpaperChanged: fetch()
    Component.onCompleted: fetch()

    Item {
        id: wash

        // Limit the longest edge, so the blur stays compact on portrait monitors too.
        readonly property real sampleScale: Math.max(1, Math.max(backdrop.width, backdrop.height) / 640)

        width: Math.max(1, Math.ceil(backdrop.width / sampleScale))
        height: Math.max(1, Math.ceil(backdrop.height / sampleScale))
        scale: sampleScale
        transformOrigin: Item.TopLeft
        layer.enabled: backdrop.canBlur
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            color: WalColors.color0
        }

        Image {
            id: wallpaperImage
            anchors.fill: parent
            source: backdrop.canBlur ? backdrop.source : ""
            sourceSize: Qt.size(wash.width * 2, wash.height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            retainWhileLoading: true
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            source: wallpaperImage
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 12
            saturation: -0.45
            opacity: wallpaperImage.status === Image.Ready ? 0.52 : 0
            visible: backdrop.canBlur && opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }

    // Thin starry sky over the blurred wallpaper (a recurring motif of the shell); fainter
    // than in the power menu, the tiles are the main thing here
    StarField {
        anchors.fill: parent
        strength: 0.8
        cellScale: 1.3
        sparkles: [[0.05, 0.08, 5, 0], [0.96, 0.92, 6, 2.3]]
        sparkleOpacity: 0.6
    }

    Process {
        id: stillProc
        property string requestedPath: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (stillProc.requestedPath !== backdrop.wallpaper)
                    return;

                const stills = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf(" ");
                    if (i > 0)
                        stills[line.slice(0, i)] = "file://" + line.slice(i + 1).split("/").map(encodeURIComponent).join("/");
                }
                if (Object.keys(stills).length > 0)
                    backdrop.stills = stills;
            }
        }

        onExited: {
            if (requestedPath !== backdrop.wallpaper)
                Qt.callLater(backdrop.fetch);
        }
    }
}
