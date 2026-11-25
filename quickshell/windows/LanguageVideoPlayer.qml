import "../common"
import "../dropdowns"
import "../services"
import "../common/Format.js" as Fmt
import QtMultimedia
import QtQuick
import Quickshell
import Quickshell.Wayland

// Video player of the language tool, built like the video tool (card over a dimmed desktop):
// on top back (to the language picker, the audio keeps playing) and fullscreen, below the image, the
// playback bar and its own subtitle box (common/LanguageSubtitleBox: clickable words).
// Playback belongs to LanguageAudioState: commands come via videoCommand, position/pause go
// back. Even with the window closed (list mode) the MediaPlayer keeps playing here.
// Keys: space pause, F fullscreen, Esc back, ←/→ 5 s, ↑/↓ volume, M mute,
// R repeat the line, T translate.
PanelWindow {
    id: win

    readonly property var st: LanguageAudioState
    readonly property bool open: st.videoOpen && st.videoLoaded
    property bool fullscreen: false
    property real fullK: fullscreen ? 1 : 0
    // Showing/hiding the card (without a morph: fade + slight growth)
    property real shownK: 0
    // Morph out of/into the language panel: 0 = the card lies exactly on the panel, 1 = player
    property real morphK: 1
    readonly property rect fromRect: st.pickerPanel
    readonly property bool canMorph: fromRect.width > 0 && fromRect.height > 0
    property bool leaving: false
    // Dimming of the player; when switching with the picker opposite to its dimming (250 ms in the
    // PickerWindow), so both never lie on top of each other (dark flash)
    property real backdropK: 1
    // Morph back done, the picker fades in above the card: only then the window goes
    property bool handingOff: false
    property real resumeAt: 0
    // Content only when the card is big enough (it is laid out for the target size)
    // Morph after the pattern bar -> calendar (MainBar): one linear progress 0..1 in 620 ms, from it
    //   0.00-0.12 panel content out, card in over the panel (same surface -> crossfade)
    //   0.06-0.86 shape (width and height AT THE SAME TIME, S-curve; staggered it looked angular here)
    //   0.80-1.00 player content in
    // Back runs the same way in reverse.
    readonly property real mk: canMorph ? morphK : 1
    readonly property real wT: smooth((mk - 0.06) / 0.8)
    readonly property real hT: wT
    readonly property real coverK: clamp01(mk / 0.12)
    readonly property real contentK: clamp01((mk - 0.8) / 0.2)
    readonly property bool hasSubs: LanguageSubtitleState.cues.length > 0
    readonly property real pad: Theme.px(20) * (1 - fullK) + Theme.px(14) * fullK
    property bool muted: false
    readonly property real shownVolume: muted ? 0 : st.videoVolume

    function formatTime(sec) {
        return Fmt.clock(sec);
    }

    function togglePlay() {
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause();
        else
            player.play();
    }

    // Only save after a short rest: while dragging many values come per second
    function setVolume(v) {
        st.videoVolume = Math.max(0, Math.min(1, v));
        muted = false;
        volumeSave.restart();
    }

    function lerp(a, b, k) {
        return a + (b - a) * k;
    }

    function clamp01(x) {
        return Math.max(0, Math.min(1, x));
    }

    function smooth(x) {
        const t = clamp01(x);
        return t * t * (3 - 2 * t);
    }

    // Report the progress to the picker: it fades its panel content out/in with it
    onMkChanged: st.videoMorph = open || leaving ? mk : 0

    // Back: content out, the card shrinks into the panel, then the picker takes over at the same place
    function goBack() {
        if (leaving)
            return ;

        subs.close();
        if (!canMorph) {
            st.backToPicker();
            return ;
        }
        leaving = true;
        morphAnim.stop();
        morphAnim.to = 0;
        morphAnim.duration = 620 * morphK;
        morphAnim.start();
    }

    function seekBy(sec) {
        player.position = Math.max(0, Math.min(player.duration, player.position + sec * 1000));
    }

    onOpenChanged: {
        if (open) {
            // Hold the monitor when opening (otherwise the window jumps after the mouse)
            screen = MachineConfig.focusedScreen();
            keyScope.forceActiveFocus();
            leaving = false;
            hideAnim.stop();
            handingOff = false;
            if (canMorph) {
                // Grow out of the panel: the card is there right away, only the shape changes
                shownK = 1;
                morphK = 0;
                backdropK = 1;
                morphAnim.stop();
                morphAnim.to = 1;
                morphAnim.duration = 620;
                morphAnim.start();
            } else {
                morphK = 1;
                backdropK = 1;
                showAnim.restart();
            }
        } else {
            subs.close();
            showAnim.stop();
            if (handingOff) {
                // The card is already invisible at the end of the morph back (coverK = 0): simply gone
                handingOff = false;
                shownK = 0;
            } else {
                hideAnim.restart();
            }
        }
    }
    visible: open || shownK > 0.01
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell:language-video"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Connections {
        function onVideoCommand(cmd, arg) {
            if (cmd === "load") {
                player.stop();
                win.resumeAt = arg.at || 0;
                player.source = "file://" + encodeURI(arg.path).replace(/\?/g, "%3F").replace(/#/g, "%23");
                player.play();
            } else if (cmd === "toggle") {
                win.togglePlay();
            } else if (cmd === "pause") {
                if (arg)
                    player.pause();
                else
                    player.play();
            } else if (cmd === "seek") {
                player.position = arg * 1000;
            } else if (cmd === "stop") {
                player.stop();
                player.source = "";
            }
        }

        target: win.st
    }

    MediaPlayer {
        id: player

        videoOutput: videoView
        onPositionChanged: win.st.videoPosition(player.position / 1000)
        onDurationChanged: win.st.currentDuration = player.duration / 1000
        onPlaybackStateChanged: win.st.isPlaying = playbackState === MediaPlayer.PlayingState
        onErrorOccurred: (code, message) => {
            console.warn("[LanguageVideo] " + message);
        }
        // Continue watching: jump to the remembered position as soon as the video is ready
        onMediaStatusChanged: {
            if (win.resumeAt > 0 && (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)) {
                player.position = win.resumeAt * 1000;
                win.resumeAt = 0;
            }
            if (mediaStatus === MediaPlayer.EndOfMedia)
                win.st.rememberPosition();

        }

        audioOutput: AudioOutput {
            muted: win.muted
            // The ear hears logarithmically: linear, the slider would only work in its lower part
            volume: Math.pow(win.st.videoVolume, 3)
        }

    }

    Timer {
        id: volumeSave

        interval: 600
        onTriggered: win.st.savePrefs()
    }

    // Dimmed desktop (fullscreen: fully dark); a click beside only closes the word explanation
    Rectangle {
        anchors.fill: parent
        // No veil of its own: the open language window underneath dims and blurs.
        // Without a morph (picker closed) dim as before
        color: WalColors.withAlpha(WalColors.color0, win.canMorph ? 0 : 0.4)
        opacity: win.shownK * win.backdropK

        MouseArea {
            anchors.fill: parent
            onClicked: subs.close()
        }

    }

    FocusScope {
        id: keyScope

        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => {
            const k = event.key;
            if (k === Qt.Key_Escape) {
                if (subs.popupOpen)
                    subs.close();
                else if (win.fullscreen)
                    win.fullscreen = false;
                else
                    win.goBack();
            } else if (k === Qt.Key_Space) {
                win.togglePlay();
            } else if (k === Qt.Key_F && event.modifiers === Qt.NoModifier) {
                win.fullscreen = !win.fullscreen;
            } else if (k === Qt.Key_Left) {
                win.seekBy(-5);
            } else if (k === Qt.Key_Right) {
                win.seekBy(5);
            } else if (k === Qt.Key_Up) {
                win.setVolume(win.st.videoVolume + 0.05);
            } else if (k === Qt.Key_Down) {
                win.setVolume(win.st.videoVolume - 0.05);
            } else if (k === Qt.Key_M && event.modifiers === Qt.NoModifier) {
                win.muted = !win.muted;
            } else if (k === Qt.Key_R && event.modifiers === Qt.NoModifier) {
                subs.replay();
            } else if (k === Qt.Key_T && event.modifiers === Qt.NoModifier) {
                subs.translate();
            } else {
                return ;
            }
            event.accepted = true;
        }

        Rectangle {
            id: card

            readonly property real normalW: Math.min(parent.width - 80, 1500)
            // Height by the aspect ratio of the video (otherwise wide black bars, especially on a
            // portrait monitor); 16:9 until the first frame is there
            readonly property real aspect: videoView.sourceRect.width > 0 ? videoView.sourceRect.height / videoView.sourceRect.width : 9 / 16
            readonly property real chromeH: 2 * win.pad + header.height + controls.height + subsArea.height + 3 * Theme.gapSmall
            readonly property real normalH: Math.min(parent.height - 80, chromeH + (normalW - 2 * win.pad) * aspect)

            readonly property real targetW: normalW + (parent.width - normalW) * win.fullK
            readonly property real targetH: normalH + (parent.height - normalH) * win.fullK
            // Without a known panel position simply out of the middle
            readonly property real k: win.canMorph ? win.morphK : 1

            // Width and height staggered like the bar's calendar morph (wT before hT)
            x: win.lerp(win.fromRect.x, (parent.width - targetW) / 2, win.wT)
            y: win.lerp(win.fromRect.y, (parent.height - targetH) / 2, win.hT)
            width: win.lerp(win.fromRect.width, targetW, win.wT)
            height: win.lerp(win.fromRect.height, targetH, win.hT)
            // Start shape = the language panel (radius 28, same surface)
            radius: win.lerp(28, 20 * (1 - win.fullK), win.wT)
            color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.04 * (1 - win.fullK) * win.wT))
            border.width: 1 - win.fullK
            border.color: Theme.stroke
            // Crossfaded over the panel at the start/end (coverK), full in between
            opacity: win.shownK * win.coverK
            scale: win.canMorph ? 1 : 0.97 + 0.03 * win.shownK
            clip: k < 1

            Item {
                id: inner

                x: (card.width - width) / 2
                y: (card.height - height) / 2
                width: card.targetW
                height: card.targetH
                opacity: win.canMorph ? win.contentK : 1
                visible: opacity > 0.01

            // A click on a free area of the card: focus back (keys) and close the explanation
            MouseArea {
                anchors.fill: parent
                onPressed: {
                    keyScope.forceActiveFocus();
                    subs.close();
                }
            }

            // ---------- Header: back, title, subtitles, fullscreen ----------
            Item {
                id: header

                x: win.pad
                y: win.pad
                width: parent.width - 2 * win.pad
                height: Theme.controlHeight

                CardButton {
                    id: backBtn

                    width: Theme.px(122)
                    glyph: ""
                    text: "Library"
                    onClicked: win.goBack()
                }

                Text {
                    anchors.left: backBtn.right
                    anchors.leftMargin: Theme.gapSmall * 2
                    anchors.right: rightButtons.left
                    anchors.rightMargin: Theme.gapSmall * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.st.stemOf(win.st.currentFile)
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeTitle
                    color: Theme.text
                }

                Row {
                    id: rightButtons

                    anchors.right: parent.right
                    spacing: Theme.gapSmall

                    CardButton {
                        visible: win.hasSubs
                        width: Theme.px(44)
                        glyph: "字"
                        active: LanguageSubtitleState.subsShown
                        onClicked: LanguageSubtitleState.setSubsShown(!LanguageSubtitleState.subsShown)
                    }

                    CardButton {
                        width: Theme.px(44)
                        glyph: win.fullscreen ? "" : ""
                        active: win.fullscreen
                        onClicked: win.fullscreen = !win.fullscreen
                    }

                }

            }

            // ---------- Image ----------
            Item {
                id: viewport

                x: win.pad
                y: header.y + header.height + Theme.gapSmall
                width: parent.width - 2 * win.pad
                height: controls.y - y - Theme.gapSmall

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusM * (1 - win.fullK)
                    color: "black"
                }

                VideoOutput {
                    id: videoView

                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                // Click = pause/resume, double click = fullscreen (as usual in video players)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        keyScope.forceActiveFocus();
                        if (subs.popupOpen)
                            subs.close();
                        else
                            win.togglePlay();
                    }
                    onDoubleClicked: {
                        win.fullscreen = !win.fullscreen;
                        win.togglePlay(); // the first click already toggled
                    }
                }

                // Big pause symbol in the middle while paused
                Rectangle {
                    anchors.centerIn: parent
                    width: Theme.px(72)
                    height: width
                    radius: width / 2
                    color: WalColors.withAlpha(WalColors.color0, 0.6)
                    opacity: player.playbackState === MediaPlayer.PausedState && !subs.popupOpen ? 1 : 0
                    visible: opacity > 0.01

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: Theme.px(2)
                        text: ""
                        font.family: Theme.font
                        font.pixelSize: Theme.px(26)
                        color: Theme.text
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

            }

            // ---------- Playback ----------
            Item {
                id: controls

                x: win.pad
                y: subsArea.y - height - Theme.gapSmall
                width: parent.width - 2 * win.pad
                height: Theme.controlHeight

                Row {
                    id: leftControls

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.gapSmall

                    CardButton {
                        width: Theme.px(44)
                        glyph: player.playbackState === MediaPlayer.PlayingState ? "" : ""
                        active: true
                        onClicked: win.togglePlay()
                    }

                    CardButton {
                        width: Theme.px(44)
                        text: "‹10"
                        onClicked: win.seekBy(-10)
                    }

                    CardButton {
                        width: Theme.px(44)
                        text: "10›"
                        onClicked: win.seekBy(10)
                    }

                    // Volume as in the video tool: the slider expands on hover. The item covers
                    // icon and slider, so it does not collapse on the way from the icon to the slider
                    Item {
                        id: volumeBox

                        property bool expanded: volumeHover.hovered || volumeDrag.pressed

                        width: volumeIcon.width + (expanded ? 118 : 0)
                        height: volumeIcon.height
                        clip: true

                        HoverHandler {
                            id: volumeHover
                        }

                        // Mouse wheel over the icon or slider, in 5 % steps
                        WheelHandler {
                            target: null
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (event) => {
                                win.setVolume(win.st.videoVolume + (event.angleDelta.y > 0 ? 0.05 : -0.05));
                            }
                        }

                        CardButton {
                            id: volumeIcon

                            width: Theme.px(44)
                            glyph: {
                                if (win.muted || win.st.videoVolume === 0)
                                    return "\uf026";

                                return win.st.videoVolume < 0.5 ? "\uf027" : "\uf028";
                            }
                            onClicked: {
                                win.muted = !win.muted;
                                keyScope.forceActiveFocus();
                            }
                        }

                        Item {
                            x: volumeIcon.width + 12
                            width: 96
                            height: parent.height
                            opacity: volumeBox.expanded ? 1 : 0

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Theme.track

                                Rectangle {
                                    width: parent.width * win.shownVolume
                                    height: parent.height
                                    radius: 2
                                    color: Theme.accent
                                }

                                Rectangle {
                                    x: parent.width * win.shownVolume - width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 12
                                    height: 12
                                    radius: height / 2
                                    color: Theme.accent
                                }

                            }

                            MouseArea {
                                id: volumeDrag

                                function apply(mx) {
                                    win.setVolume(mx / width);
                                }

                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (mouse) => {
                                    keyScope.forceActiveFocus();
                                    apply(mouse.x);
                                }
                                onPositionChanged: (mouse) => {
                                    if (pressed)
                                        apply(mouse.x);

                                }
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.anim.durations.fast
                                }

                            }

                        }

                        Behavior on width {
                            NumberAnimation {
                                duration: Appearance.anim.durations.fast
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                }

                Text {
                    id: timeText

                    anchors.left: leftControls.right
                    anchors.leftMargin: Theme.gapSmall * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.formatTime((seek.dragging ? seek.dragFrac * player.duration : player.position) / 1000) + " / " + win.formatTime(player.duration / 1000)
                    font.family: Theme.fontUi
                    font.features: Theme.tabular
                    font.pixelSize: Theme.sizeBody
                    color: Theme.textDim
                }

                // Timeline: drag/click jumps
                Item {
                    id: seek

                    readonly property bool hovered: seekMouse.containsMouse
                    readonly property bool dragging: seekMouse.pressed
                    property real dragFrac: 0
                    readonly property real frac: dragging ? dragFrac : (player.duration > 0 ? player.position / player.duration : 0)

                    anchors.left: timeText.right
                    anchors.leftMargin: Theme.gapSmall * 2
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.px(16)

                    Rectangle {
                        id: track

                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: seek.hovered || seek.dragging ? 6 : 4
                        radius: height / 2
                        color: Theme.track

                        Rectangle {
                            width: parent.width * seek.frac
                            height: parent.height
                            radius: height / 2
                            color: Theme.accent
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 120
                            }

                        }

                    }

                    Rectangle {
                        x: seek.width * seek.frac - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: seek.dragging ? 16 : (seek.hovered ? 13 : 10)
                        height: width
                        radius: width / 2
                        color: Theme.accent
                        border.width: 2
                        border.color: WalColors.withAlpha(WalColors.color0, 0.9)

                        Behavior on width {
                            Springy {
                            }

                        }

                    }

                    MouseArea {
                        id: seekMouse

                        anchors.fill: parent
                        anchors.topMargin: -6
                        anchors.bottomMargin: -6
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: (mouse) => {
                            seek.dragFrac = Math.max(0, Math.min(1, mouse.x / width));
                        }
                        onPositionChanged: (mouse) => {
                            if (pressed)
                                seek.dragFrac = Math.max(0, Math.min(1, mouse.x / width));

                        }
                        onReleased: {
                            player.position = seek.dragFrac * player.duration;
                            keyScope.forceActiveFocus();
                        }
                    }

                }

            }

            // ---------- Subtitle box (own surface below the image) ----------
            Item {
                id: subsArea

                readonly property bool on: win.hasSubs && LanguageSubtitleState.subsShown

                // Clipped while expanding/collapsing: the box disappears with its surface instead of
                // the text below still fading out. Only then - when open, the word explanation sticks up
                // out of this area and would otherwise be cut off
                clip: height < subs.height - 0.5
                x: win.pad
                width: parent.width - 2 * win.pad
                height: on ? subs.height : 0
                y: parent.height - win.pad - height

                LanguageSubtitleBox {
                    id: subs

                    shown: subsArea.on && win.open
                    fillWidth: true
                    maxWidth: subsArea.width
                    boxColor: WalColors.withAlpha(WalColors.color7, 0.045)
                    textSize: Theme.px(26) + Theme.px(4) * win.fullK
                }

                Behavior on height {
                    NumberAnimation {
                        duration: Appearance.anim.durations.normal
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.standard
                    }

                }

            }

            // Short help at the bottom right of the image, only in the normal view
            Text {
                anchors.right: viewport.right
                anchors.rightMargin: Theme.px(10)
                anchors.bottom: viewport.bottom
                anchors.bottomMargin: Theme.px(8)
                text: "space pause · f fullscreen · ←/→ 5 s · ↑/↓ volume · m mute · r repeat · t translate · esc back"
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                color: WalColors.withAlpha(WalColors.color7, 0.45)
                opacity: 1 - win.fullK
                visible: opacity > 0.01
            }

            }

        }

    }

    Behavior on fullK {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecelerate
        }

    }

    NumberAnimation {
        id: showAnim

        target: win
        property: "shownK"
        to: 1
        duration: Appearance.anim.durations.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.standard
    }

    // After the morph back the card fades out over the already visible panel (crossfade)
    NumberAnimation {
        id: hideAnim

        target: win
        property: "shownK"
        to: 0
        duration: Appearance.anim.durations.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.standard
    }

    NumberAnimation {
        id: backdropAnim

        target: win
        property: "backdropK"
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: morphAnim

        target: win
        property: "morphK"
        easing.type: Easing.Linear
        onFinished: {
            if (win.leaving && win.morphK === 0) {
                win.leaving = false;
                win.fullscreen = false;
                win.handingOff = true;
                win.st.backToPicker();
            }
        }
    }

}
