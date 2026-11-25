import "../services"
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

// Decode the original video directly, without GIF conversion or a reduced color palette.
Variants {
    // Only on the bar monitor (the others show a still image with awww, WallpaperPickerState.paintStatic)
    // (during a soft bar move briefly the old and new monitor, videoScreens)
    model: WallpaperPickerState.animationUrl ? WallpaperPickerState.videoScreens : []

    PanelWindow {
        id: wallpaper
        required property var modelData
        // Logically the wallpaper (original path) ...
        readonly property string path: WallpaperPickerState.shownAnimation
        // ... but what plays is the copy scaled down to this monitor, if there is one
        // (scripts/wallpaper_video_variant.sh: 4K cost ~225 MB of RAM per player)
        readonly property string url: WallpaperPickerState.videoUrlFor(path, modelData)

        // New source: append an extra player, the old one keeps running until the new one shows its
        // first frame (promote). So there is no black gap during the change.
        // Compare by path: if a copy gets finished during playback, the player keeps running.
        function addPlayer() {
            if (path && (players.count === 0 || players.get(players.count - 1).path !== path))
                players.append({"src": url, "path": path});
        }
        // Player i shows a frame -> remove all older ones. During an ink transition the old ones
        // keep running (the new one spreads masked above them) and only go on finished.
        function promote(i) {
            if (WallpaperTransition.maskMode !== "newSlot")
                dropOlder(i);
            WallpaperPickerState.animationReady(path);
            WallpaperPickerState.moveVideoReady(modelData.name);
        }
        function dropOlder(i) {
            for (let k = i - 1; k >= 0; --k)
                players.remove(k);
        }

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: -1
        // Transparent until the first frame: the previous wallpaper (awww image or
        // the old scene) stays underneath instead of flashing black
        color: "transparent"
        // Bottom layer: above awww and the scenes (background). So a video can stay live during a change to a
        // scene and reveal it in the ink shape (maskMode "reveal"). The transition's overlay
        // (InkBloom) also lies on bottom, but is created later -> above.
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:animated-wallpaper"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        onPathChanged: addPlayer()
        Component.onCompleted: addPlayer()

        // Transition done: only now remove the old players
        Connections {
            target: WallpaperTransition
            function onFinished() {
                wallpaper.dropOlder(players.count - 1);
            }
        }

        // ListModel instead of an array: append/remove leaves the other players untouched.
        // A fresh player per source: if you only change the source of a running MediaPlayer
        // (video -> video, GIF -> video), Qt 6.12 does not restart playback (stays black).
        ListModel {
            id: players
        }

        // Same ink shape as the overlay (windows/shaders/inkmask.frag)
        component InkMask: ShaderEffect {
            property bool invertMask: false
            property real cover: WallpaperTransition.cover
            property real invert: invertMask ? 1 : 0
            property real maxR: WallpaperTransition.maxR
            property real time: WallpaperTransition.time
            property point origin: Qt.point(WallpaperTransition.origin.x - wallpaper.modelData.x, WallpaperTransition.origin.y - wallpaper.modelData.y)
            property size size: Qt.size(width, height)
            property color glowColor: WalColors.color4
            fragmentShader: Qt.resolvedUrl("shaders/inkmask.frag.qsb")
        }

        // Video -> scene: the new scene draws underneath; the video becomes transparent in the shape
        Item {
            id: stage
            anchors.fill: parent
            // Bar move: fade in on the new monitor over the same still image
            opacity: WallpaperPickerState.videoOpacityFor(wallpaper.modelData.name)
            layer.enabled: WallpaperTransition.maskMode === "reveal"
            layer.effect: InkMask {
                invertMask: true
            }

            Repeater {
                model: players

                Item {
                    id: slot
                    required property string src
                    required property string path
                    required property int index
                    property bool ready: false
                    anchors.fill: parent
                    // The new player lies on top, but is invisible until it has a frame
                    opacity: ready ? 1 : 0
                    z: index
                    // Target video: the target's player spreads over the old one in the ink shape.
                    // Check by source, not "the topmost": until the new one is created (~0.1 s), that would
                    // still be the old one -> fully transparent with cover = 0, awww flashed through
                    layer.enabled: WallpaperTransition.maskMode === "newSlot" && path === WallpaperTransition.target
                    layer.effect: InkMask {}

                    VideoOutput {
                        id: output
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                    }
                    Connections {
                        target: output.videoSink
                        enabled: !slot.ready
                        function onVideoFrameChanged() {
                            slot.ready = true;
                            wallpaper.promote(slot.index);
                        }
                    }
                    // Lock screen: pause on the current frame, afterwards continue playing exactly there
                    Connections {
                        target: WallpaperPickerState
                        function onAnimationFrozenChanged() {
                            if (WallpaperPickerState.animationFrozen) {
                                player.pause();
                                // Only the topmost player (the visible one) saves its frame
                                if (slot.index === players.count - 1)
                                    frameGrab.restart();
                            } else {
                                frameGrab.stop();
                                player.play();
                            }
                        }
                    }
                    // Wait briefly until the paused frame is surely drawn, then save.
                    // Write to .tmp first and rename: lock.sh should never read a half-written file.
                    Timer {
                        id: frameGrab
                        interval: 60
                        onTriggered: {
                            const out = WallpaperPickerState.frozenFramePrefix + "-" + wallpaper.modelData.name + ".bmp";
                            stage.grabToImage((r) => {
                                if (!WallpaperPickerState.animationFrozen)
                                    return;
                                if (r.saveToFile(out + ".tmp.bmp"))
                                    Quickshell.execDetached(["mv", "-f", out + ".tmp.bmp", out]);
                            });
                        }
                    }
                    MediaPlayer {
                        id: player
                        property bool playbackReported: false
                        source: slot.src
                        videoOutput: output
                        audioOutput: AudioOutput { muted: true }
                        loops: MediaPlayer.Infinite
                        autoPlay: true
                        onPositionChanged: {
                            if (!playbackReported && player.position > 500) {
                                playbackReported = true;
                                console.log("Animated wallpaper playing:", wallpaper.screen.name, source, player.position);
                            }
                        }
                        onErrorOccurred: (error, message) => {
                            console.warn("Animated wallpaper:", message);
                            NotificationState.send("Wallpaper", "Video playback failed", message, {"timeout": 7000});
                        }
                    }
                }
            }
        }
    }
}
