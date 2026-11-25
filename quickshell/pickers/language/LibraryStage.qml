import "../../common"
import "../../services"
import QtQuick
import QtQuick.Effects

// Listen tab: the stage on top. The playing video, otherwise the one to continue or the newest one: blurred
// preview image as a glow, the sharp image, title, seek line and controls; while listening the spoken subtitle
// sentence below (LibraryCue). Which video it shows is decided by the tab (view.stageFile).
// Part of LanguageLibrary.qml (view = the Listen tab, picker = core).
Item {
    id: stage

    required property var picker
    required property var view

    readonly property string file: stage.view.stageFile
    readonly property var m: stage.view.info(file)
    readonly property real dur: stage.view.live && LanguageAudioState.currentDuration > 0 ? LanguageAudioState.currentDuration : (m.duration || 0)
    readonly property real frac: stage.view.live ? (dur > 0 ? Math.min(1, LanguageAudioState.currentPosition / dur) : 0) : stage.view.resumeFrac(file)
    readonly property real shownFrac: seek.pressed ? seek.dragFrac : frac
    readonly property bool playing: stage.view.live && LanguageAudioState.isPlaying

    width: parent.width
    height: stage.view.stageH
    clip: true
    opacity: file !== "" ? 1 : 0
    visible: height > 0.5

    RoundedClip {
        id: stageCard

        width: parent.width
        height: stage.view.stageFull
        radius: 20
        color: Theme.groupFill

        // Glow: the same image heavily blurred and enlarged (no hard edges), breathes softly
        // while playing (opacity only)
        Image {
            id: ambient

            property real glow: 0.42

            anchors.centerIn: parent
            width: parent.width * 1.25
            height: parent.height * 1.6
            source: LanguageAudioState.fileUrl(stage.m.thumb)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 320
            opacity: status === Image.Ready ? glow : 0
            layer.enabled: true

            SequentialAnimation on glow {
                running: stage.playing && stage.visible
                loops: Animation.Infinite
                onRunningChanged: {
                    if (!running)
                        ambient.glow = 0.42;

                }

                NumberAnimation {
                    to: 0.55
                    duration: 2600
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    to: 0.36
                    duration: 2600
                    easing.type: Easing.InOutSine
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 400
                }

            }

            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1
                blurMax: 64
                saturation: 0.15
            }

        }

        // Darken toward the panel color: right (text) calmer than left (image)
        Rectangle {
            anchors.fill: parent

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: WalColors.withAlpha(WalColors.color0, 0.35)
                }

                GradientStop {
                    position: 1
                    color: WalColors.withAlpha(WalColors.color0, 0.72)
                }

            }

        }

        // ── Image ──
        RoundedClip {
            id: stageThumb

            x: 16
            y: Math.round((stage.view.stageBase - height) / 2)
            height: stage.view.stageBase - 32
            width: Math.round(height * 16 / 9)
            radius: 12
            color: WalColors.withAlpha(WalColors.color0, 0.5)

            Text {
                anchors.centerIn: parent
                visible: stageImg.status !== Image.Ready
                text: stage.view.gVideo
                color: Theme.textFaint
                font.family: Theme.font
                font.pixelSize: 22
            }

            Image {
                id: stageImg

                anchors.fill: parent
                source: LanguageAudioState.fileUrl(stage.m.thumb)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 480
            }

            // Watch hint on hover
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
                opacity: thumbMouse.containsMouse ? 1 : 0

                Text {
                    anchors.centerIn: parent
                    text: stage.view.gExpand
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: 18
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                    }

                }

            }

            MouseArea {
                id: thumbMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: LanguageAudioState.watchVideo(stage.file)
            }

        }

        // ── Title, seek line, controls ──
        Item {
            anchors.left: stageThumb.right
            anchors.leftMargin: 20
            anchors.right: parent.right
            anchors.rightMargin: 18
            height: stage.view.stageBase

            Row {
                id: stageStatus

                y: 20
                spacing: 8

                // Small level meter: only moves while playing
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: stage.view.live
                    spacing: 2

                    Repeater {
                        model: 3

                        Rectangle {
                            id: lvl

                            required property int index
                            property real level: 0.4

                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: Math.round(3 + 7 * level)
                            radius: 1
                            color: Theme.accent

                            SequentialAnimation on level {
                                running: stage.playing && stage.visible
                                loops: Animation.Infinite

                                NumberAnimation {
                                    to: [0.9, 0.5, 1][lvl.index]
                                    duration: 300 + lvl.index * 70
                                    easing.type: Easing.InOutSine
                                }

                                NumberAnimation {
                                    to: [0.2, 0.95, 0.35][lvl.index]
                                    duration: 340 + lvl.index * 50
                                    easing.type: Easing.InOutSine
                                }

                            }

                        }

                    }

                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: !stage.view.live ? (stage.view.resumeFile !== "" ? "CONTINUE WATCHING" : "START WATCHING") : LanguageAudioState.isPlaying ? (LanguageAudioState.watching ? "NOW WATCHING" : "LISTENING IN THE BACKGROUND") : "PAUSED"
                    color: stage.playing ? Theme.accent : Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.microSpacing
                }

            }

            Text {
                anchors.top: stageStatus.bottom
                anchors.topMargin: 8
                width: parent.width
                text: LanguageAudioState.stemOf(stage.file)
                color: Theme.text
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.1
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeTitle
                font.weight: Font.Medium
            }

            // Seek line (drag = jump, only for the playing video)
            Item {
                id: seekLine

                anchors.bottom: controls.top
                anchors.bottomMargin: 8
                width: parent.width
                height: 12

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: seek.containsMouse || seek.pressed ? 5 : 3
                    radius: height / 2
                    color: WalColors.withAlpha(WalColors.color7, 0.16)

                    Rectangle {
                        width: Math.round(parent.width * stage.shownFrac)
                        height: parent.height
                        radius: height / 2
                        color: Theme.accent
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                MouseArea {
                    id: seek

                    property real dragFrac: 0

                    anchors.fill: parent
                    anchors.topMargin: -4
                    anchors.bottomMargin: -4
                    enabled: stage.view.live && stage.dur > 0
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: (mouse) => {
                        dragFrac = Math.max(0, Math.min(1, mouse.x / width));
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed)
                            dragFrac = Math.max(0, Math.min(1, mouse.x / width));

                    }
                    onReleased: LanguageAudioState.seekToFraction(dragFrac)
                }

            }

            Row {
                id: controls

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                spacing: 6

                CircleButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 36
                    primary: true
                    glyph: stage.playing ? stage.view.gPause : stage.view.gPlay
                    glyphShift: stage.playing ? 0 : 1.5
                    // Play = audio in the background (watch via the image or the button on the right)
                    onClicked: LanguageAudioState.play(stage.file)
                }

                CircleButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: stage.view.live
                    flat: true
                    glyph: stage.view.gBack
                    onClicked: LanguageAudioState.seekRelative(-10)
                }

                CircleButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: stage.view.live
                    flat: true
                    glyph: stage.view.gFwd
                    onClicked: LanguageAudioState.seekRelative(10)
                }

                CircleButton {
                    anchors.verticalCenter: parent.verticalCenter
                    flat: true
                    glyph: stage.view.gExpand
                    onClicked: LanguageAudioState.watchVideo(stage.file)
                }

            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: controls.verticalCenter
                text: stage.picker.formatTime(stage.shownFrac * stage.dur) + "  /  " + stage.picker.formatTime(stage.dur)
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                font.features: Theme.tabular
            }

        }

        // ── Spoken sentence: subtitle of the current position, what was already said bright, the rest faint ──
        LibraryCue {
            picker: stage.picker
            view: stage.view
            file: stage.file
        }

    }

    Behavior on opacity {
        NumberAnimation {
            duration: 220
        }

    }

}
