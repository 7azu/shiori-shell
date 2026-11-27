import "../common"
import "../common/Format.js" as Fmt
import "../services"
import QtMultimedia
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Video player and editor (from yazi), logic in VideoEditorState. Like the image tool: opens with the
// editor (settings on the right, the timeline with handles for trimming at the bottom), on the left the other
// videos of the folder. The big view (F) lets the editor glide out = a plain player.
// Everything works live in the preview, computing only happens on save.
PanelWindow {
    id: win

    readonly property var st: VideoEditorState
    property bool confirmDiscard: false
    // Overwriting cannot be undone: the first click only asks
    property bool confirmOverwrite: false
    property bool confirmDelete: false
    // Big view as in the image tool: the card grows, but stays smaller than the screen,
    // and the editor glides out. Normal view = always with the editor
    property bool enlarged: false
    readonly property bool editing: !enlarged
    // Runs along softly: image, columns and timeline morph between player and editor
    property real editK: editing ? 1 : 0
    property real enlargeK: enlarged ? 1 : 0
    property bool snapView: false
    readonly property bool browsing: st.gallery.length > 1
    readonly property int arrowGutter: 44
    property bool muted: false
    // The slider works with perceived volume; starts at 50 % on every opening of the window
    property real volume: 0.5
    readonly property bool audioUsable: st.hasAudio && !st.removeAudio
    readonly property real shownVolume: muted ? 0 : volume
    readonly property int rotatedW: st.rotation % 180 === 0 ? st.videoW : st.videoH
    readonly property int rotatedH: st.rotation % 180 === 0 ? st.videoH : st.videoW
    readonly property real fit: rotatedW > 0 ? Math.min(viewport.width / rotatedW, viewport.height / rotatedH) : 1
    readonly property real positionSec: player.position / 1000
    // "Compress" page (HandBrake) in the sidebar, slides over the tools as on iOS
    property bool compressOpen: false
    // Queue entry that flies out on the next click (confirmation as when deleting)
    property int confirmCancelId: -1
    property real compressK: compressOpen ? 1 : 0

    Behavior on compressK {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }

    }

    function formatTime(sec) {
        const s = Math.max(0, sec);
        const h = Math.floor(s / 3600);
        const m = Math.floor(s / 60) % 60;
        const rest = s % 60;
        const body = String(m).padStart(h > 0 ? 2 : 1, "0") + ":" + rest.toFixed(1).padStart(4, "0");
        return h > 0 ? h + ":" + body : body;
    }

    // While dragging many positions come per second; the player should only seek to the last one
    function seekTo(sec) {
        pendingSeek = Math.max(0, Math.min(sec, st.duration));
        seekTimer.start();
    }

    property real pendingSeek: -1
    // After renaming the open file: position (ms) where it continues after reopening
    property real resumeAt: -1
    property real frameStepPos: 0
    // From the metadata; some containers have no value -> 30 fps as an assumption
    readonly property real fps: {
        const r = player.metaData.value(MediaMetaData.VideoFrameRate);
        return r > 0 ? r : 30;
    }
    // When deleting, the old video keeps playing until the swap: only then the frames count
    property bool awaitingFrame: false
    property bool frameSeen: false

    function setVolume(v) {
        volume = Math.max(0, Math.min(1, v));
        muted = false;
    }

    function togglePlay() {
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause();
        else
            player.play();
    }

    function startPlayback() {
        player.stop();
        player.source = "";
        player.source = st.fileUrl;
        player.play();
    }

    function stepVideo(delta) {
        const i = st.currentIndex + delta;
        if (i >= 0 && i < st.gallery.length)
            showVideo(st.gallery[i]);

    }

    function showVideo(file) {
        if (st.exporting || file === st.path)
            return ;

        confirmDiscard = false;
        // The snapshot for the slide does not know the zoom transform -> reset it first
        zoomer.reset();
        slide.begin(st.gallery.indexOf(file) > st.currentIndex ? 1 : -1, () => {
            st.goTo(file);
        });
    }

    // The new video only slides in when its first frame and its dimensions are there: before, the
    // surface would be empty or the image would still have the size of the previous video
    function revealWhenReady() {
        if (!frameSeen || st.duration <= 0)
            return ;

        awaitingFrame = false;
        frameSeen = false;
        slide.reveal();
    }

    // During the export the editor stays: progress and "Cancel" run there
    function toggleEnlarged() {
        if (!st.exporting)
            enlarged = !enlarged;

    }

    function escapePressed() {
        if (st.exporting)
            return ;

        // Open page: Esc first leads back to the tools (like "Back")
        if (compressOpen && editing) {
            compressOpen = false;
            return ;
        }
        // Big view = player: Esc closes directly. With unsaved changes first back to the
        // editor, the confirmation to discard is there
        if (enlarged && st.anyUnsaved)
            enlarged = false;
        else
            requestClose();
    }

    // Optional editor action from a private add-on (services/Addons): trim and rotation go along,
    // the file itself stays the original (colors, speed and audio removal are done in the other app)
    function sendToAction() {
        const action = Addons.editorAction;
        if (st.exporting || !action || !action.available)
            return ;

        if (action.busy) {
            action.cancel();
            return ;
        }
        player.pause();
        const trimmed = st.trimStart > 0.01 || (st.trimEnd > 0 && st.trimEnd < st.duration - 0.01);
        action.send({
            "path": st.path,
            "kind": "video",
            "start": trimmed ? st.trimStart : -1,
            "end": trimmed ? st.trimEnd : -1,
            "rotation": st.rotation,
            "width": st.videoW,
            "height": st.videoH
        });
    }

    // ---------- Folder browser ----------
    // The video pauses underneath and continues after closing, if it was playing
    property bool resumeAfterBrowser: false
    // Open video moved to the trash in the browser (see closeBrowser)
    property bool currentGone: false

    // levelUp: Ctrl+H in the editor -> one level above the open file's folder
    function openBrowser(levelUp) {
        if (browser.open || st.exporting)
            return ;

        resumeAfterBrowser = player.playbackState === MediaPlayer.PlayingState;
        player.pause();
        browser.show(levelUp === true);
    }

    function closeBrowser(resume) {
        // The open video was moved to the trash in the browser: without a new choice there is nothing left to show
        if (currentGone) {
            currentGone = false;
            browser.open = false;
            player.stop();
            player.source = "";
            st.close();
            return ;
        }
        browser.open = false;
        keyScope.forceActiveFocus();
        if (resume && resumeAfterBrowser)
            player.play();

    }

    // Video: open here (also from another folder). Image: hand over to the image editor
    function openFromBrowser(file, kind) {
        currentGone = false;
        if (kind === "video") {
            closeBrowser(file === st.path);
            if (file !== st.path)
                st.openInFolder(file);

            return ;
        }
        if (st.anyUnsaved && pendingSwitch !== file) {
            pendingSwitch = file;
            browser.hint = "Unsaved changes will be lost. Open again to continue.";
            switchTimer.restart();
            return ;
        }
        pendingSwitch = "";
        browser.hint = "";
        // Open the image editor first, then close this one: so there is no gap in between
        ScreenshotEditorState.openFolderFile(file);
        player.stop();
        player.source = "";
        st.close();
    }

    // Opened from yazi while the editor is already open (maybe on another workspace): move it here
    // and show the video
    function adopt(file) {
        anchor.pin();
        if (browser.open)
            browser.open = false;

        if (file !== st.path)
            st.openInFolder(file);

        keyScope.forceActiveFocus();
    }

    function requestClose() {
        if (st.exporting)
            return ;

        if (!st.anyUnsaved || confirmDiscard) {
            player.stop();
            player.source = "";
            st.close();
        } else {
            confirmDiscard = true;
            discardTimer.restart();
        }
    }

    function requestDelete() {
        if (st.exporting)
            return ;

        if (confirmDelete) {
            confirmDelete = false;
            // The next video moves up, only for the last one the previous one comes
            slide.begin(st.currentIndex < st.gallery.length - 1 ? 1 : -1, () => {
                st.deleteCurrent();
            });
        } else {
            confirmDelete = true;
            deleteTimer.restart();
        }
    }

    // Relative seeking (a/d): with the key held down keep computing from the still pending target,
    // player.position lags behind and would otherwise swallow jumps
    function seekBy(sec) {
        seekTo((seekTimer.running ? pendingSeek : positionSec) + sec);
    }

    // One frame forward/back (. and ,), pauses meanwhile. Snaps to the frame grid. Fast
    // tapping computes from the last frame sought to: player.position only follows with a delay
    // and would otherwise swallow steps.
    function stepFrame(dir) {
        if (st.duration <= 0 || slide.active)
            return ;

        player.pause();
        const base = frameStepTimer.running ? frameStepPos : (seekTimer.running ? pendingSeek : positionSec);
        const frame = Math.round(base * fps) + dir;
        frameStepPos = Math.max(0, Math.min(st.duration, frame / fps));
        frameStepTimer.restart();
        seekTo(frameStepPos);
    }

    // Grabs the shown image instead of fetching it again with ffmpeg: player.position is up to one
    // frame off (measured). The frame has the video's dimensions, so full resolution including rotation and colors
    function captureFrame() {
        if (st.duration <= 0 || slide.active)
            return ;

        const file = st.newFrameFile();
        const started = frameBox.grabToImage((result) => {
            if (result.saveToFile(file))
                win.st.storeFrame(file);
            else
                win.st.frameFailed();
        }, Qt.size(rotatedW, rotatedH));
        if (!started)
            st.frameFailed();

    }

    function requestOverwrite() {
        if (!st.canOverwrite)
            return ;

        if (confirmOverwrite) {
            confirmOverwrite = false;
            player.pause();
            st.exportAs("overwrite");
        } else {
            confirmOverwrite = true;
            overwriteTimer.restart();
        }
    }

    function saveCopy() {
        if (!st.dirty || st.exporting)
            return ;

        player.pause();
        st.exportAs("copy");
    }

    // Stays on the monitor + workspace where it was opened (common/WindowAnchor): other workspaces are free,
    // and the keyboard only belongs to it while its monitor is focused - otherwise windows on the
    // other screen would not be usable (e.g. browser extensions)
    screen: anchor.screen
    // Leave it mapped on foreign workspaces (transparent, click-through): see common/WorkspaceSlide
    // Card surface ("-card", no Hyprland animation); dimming + blur in the backdrop below, so on
    // closing the card evaporates while the backdrop fades (common/ModalBackdrop, common/Evaporate)
    visible: ev.held
    mask: anchor.here ? null : passThrough
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.namespace: "quickshell:video-editor-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: st.isOpen && !ev.closing && anchor.here && anchor.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    Connections {
        function onPathChanged() {
            win.confirmDelete = false;
            zoomer.reset();
        }

        function onIsOpenChanged() {
            // Every opening starts fitted, even if the new video has the same size
            zoomer.reset();
            // Even if the state closes itself (last video deleted): the sound must be off
            if (!win.st.isOpen) {
                slide.cancel();
                player.stop();
                player.source = "";
                return ;
            }

            win.confirmDiscard = false;
            win.confirmOverwrite = false;
            win.compressOpen = false;
            win.muted = false;
            win.volume = 0.5;
            // Videos open as a player (big view), F expands the editor
            win.snapView = true;
            win.enlarged = true;
            Qt.callLater(() => {
                win.snapView = false;
            });
            keyScope.forceActiveFocus();
            if (Addons.editorAction)
                Addons.editorAction.refresh();

            // Only open the card with the first video frame, otherwise an empty surface zooms in
            intro.reset();
            introTimer.restart();
            win.startPlayback();
        }

        function onReloaded() {
            win.awaitingFrame = true;
            win.frameSeen = false;
            win.startPlayback();
        }

        // Folder sorted by date: the same file under a new name. The player still holds the old path,
        // under which another file lies now -> reopen and continue at the same place
        function onPathRenamed() {
            win.resumeAt = player.position;
            player.source = win.st.fileUrl;
        }

        function onDurationChanged() {
            win.revealWhenReady();
        }

        function onTrashFailed() {
            slide.cancel();
        }

        target: win.st
    }

    // File operations in the browser: if the open video was moved, the editor follows it (paused, the
    // browser still lies above it); if it is in the trash, it closes with the browser. Read the strip again
    Connections {
        function onOperationDone(trashed, moved) {
            if (!win.st.isOpen)
                return ;

            const to = moved[win.st.path];
            if (to !== undefined) {
                win.st.openInFolder(to);
                player.pause();
            } else if (trashed.indexOf(win.st.path) >= 0) {
                win.currentGone = true;
            }
            win.st.refreshGallery();
        }

        target: MediaBrowserState
    }

    // The editor action opened the file in its app ("fresh"): the editor would cover it -> close.
    // Other modes (only added to a library): stay open, you can keep browsing and send more
    Connections {
        function onFinished(mode, path) {
            if (mode !== "fresh" || !win.st.isOpen || path !== win.st.path)
                return ;

            player.stop();
            player.source = "";
            win.st.close();
        }

        target: Addons.editorAction
        ignoreUnknownSignals: true
    }

    Connections {
        function onVideoFrameChanged() {
            if (win.st.isOpen)
                intro.play();

            // While loading the next video a last frame of the previous one may still arrive
            if (!win.awaitingFrame || player.mediaStatus === MediaPlayer.LoadingMedia)
                return ;

            win.frameSeen = true;
            win.revealWhenReady();
        }

        target: videoView.videoSink
    }

    MediaPlayer {
        id: player

        videoOutput: videoView
        onErrorOccurred: (code, message) => {
            win.st.error = "Could not play this video";
            slide.cancel();
        }
        playbackRate: win.st.speed
        onPositionChanged: {
            // Only show the trimmed part in a loop
            if (win.st.isOpen && !timeline.dragging && win.st.trimEnd > 0 && player.position / 1000 >= win.st.trimEnd)
                player.position = win.st.trimStart * 1000;

        }
        onMediaStatusChanged: {
            if (win.resumeAt >= 0 && (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)) {
                player.position = win.resumeAt;
                win.resumeAt = -1;
            }
            if (mediaStatus === MediaPlayer.EndOfMedia && win.st.isOpen) {
                player.position = win.st.trimStart * 1000;
                player.play();
            }
        }

        audioOutput: AudioOutput {
            muted: win.muted || win.st.removeAudio
            // The ear hears logarithmically: linear, the slider would only work in its lower part
            volume: Math.pow(win.volume, 3)
        }

    }

    Behavior on editK {
        enabled: !win.snapView

        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }

    }

    // When opening the view jumps into the big view without animation (snapView), otherwise the
    // card and sidebar would visibly open first
    Behavior on enlargeK {
        enabled: !win.snapView

        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }

    }

    OpenMotion {
        id: intro
    }

    Evaporate {
        id: ev

        window: win
        open: win.st.isOpen
    }

    // Stays mapped on foreign workspaces like the editor itself (transparent there), glides along
    ModalBackdrop {
        screen: anchor.screen
        name: "quickshell:video-editor"
        shown: win.st.isOpen
        clickable: false
        shift: wsSlide.shift
        veilOpacity: wsSlide.hidden ? 0 : 1
    }

    WindowAnchor {
        id: anchor

        open: win.st.isOpen
    }

    // Glides in/out with Hyprland's slide on a workspace change
    WorkspaceSlide {
        id: wsSlide

        windowAnchor: anchor
        active: win.st.isOpen
        distance: win.width
    }

    Region {
        id: passThrough
    }

    // If the first frame does not come soon (slow container, error), the card opens anyway
    Timer {
        id: introTimer

        interval: 400
        onTriggered: intro.play()
    }

    // Switching to the other editor with unsaved changes: a second opening within 4 s confirms
    property string pendingSwitch: ""

    Timer {
        id: switchTimer

        interval: 4000
        onTriggered: {
            win.pendingSwitch = "";
            browser.hint = "";
        }
    }

    Timer {
        id: seekTimer

        interval: 60
        onTriggered: player.position = win.pendingSeek * 1000
    }

    // Window in which further frame steps compute from the last target (see stepFrame)
    Timer {
        id: frameStepTimer

        interval: 1000
    }

    Timer {
        id: deleteTimer

        interval: 4000
        onTriggered: win.confirmDelete = false
    }

    Timer {
        id: cancelConfirmTimer

        interval: 4000
        onTriggered: win.confirmCancelId = -1
    }

    Timer {
        id: discardTimer

        interval: 2500
        onTriggered: win.confirmDiscard = false
    }

    Timer {
        id: overwriteTimer

        interval: 4000
        onTriggered: win.confirmOverwrite = false
    }

    Item {
        id: keyScope

        // For tools/ui-shot (finds the content for screenshots by name)
        objectName: "editorRoot"
        anchors.fill: parent
        opacity: wsSlide.hidden ? 0 : 1
        transform: Translate {
            x: wsSlide.shift
        }
        focus: true
        Keys.onPressed: (event) => {
            // Folder browser open: it gets all keys (Esc closes it)
            if (browser.open) {
                browser.handleKey(event);
                event.accepted = true;
                return ;
            }
            const ctrl = event.modifiers & Qt.ControlModifier;
            const shift = event.modifiers & Qt.ShiftModifier;
            // Arrows switch the video as in the image editor; within the video Shift (5 s) and Ctrl (1 s) jump.
            // Without other videos in the folder the plain arrows jump too
            const stepSec = ctrl ? 1 : 5;
            const seeking = ctrl || shift || !win.browsing;
            // h/l (vim) behave like the arrows in all combinations
            const left = event.key === Qt.Key_Left || event.key === Qt.Key_H;
            const right = event.key === Qt.Key_Right || event.key === Qt.Key_L;
            // Ctrl+H: folder browser one level up (like Ctrl+H in the browser); 1 s back stays Ctrl+arrow
            if (ctrl && event.key === Qt.Key_H)
                win.openBrowser(true);
            else if (event.key === Qt.Key_Escape)
                win.escapePressed();
            else if (event.key === Qt.Key_Space)
                win.togglePlay();
            else if (event.key === Qt.Key_A && event.modifiers === Qt.NoModifier)
                win.seekBy(-5);
            else if (event.key === Qt.Key_D && event.modifiers === Qt.NoModifier)
                win.seekBy(5);
            else if (event.key === Qt.Key_Period)
                win.stepFrame(1);
            else if (event.key === Qt.Key_Comma)
                win.stepFrame(-1);
            else if (left && seeking)
                win.seekTo(win.positionSec - stepSec);
            else if (right && seeking)
                win.seekTo(win.positionSec + stepSec);
            else if (left)
                win.stepVideo(-1);
            else if (right)
                win.stepVideo(1);
            else if (ctrl && event.key === Qt.Key_E)
                win.sendToAction();
            else if (event.key === Qt.Key_E)
                win.toggleEnlarged();
            else if (event.key === Qt.Key_Delete)
                win.requestDelete();
            else if (event.key === Qt.Key_Up)
                win.setVolume(win.volume + 0.05);
            else if (event.key === Qt.Key_Down)
                win.setVolume(win.volume - 0.05);
            else if (event.key === Qt.Key_M)
                win.muted = !win.muted;
            else if (event.key === Qt.Key_S && event.modifiers === Qt.NoModifier && !event.isAutoRepeat)
                win.captureFrame();
            else if (event.key === Qt.Key_F && event.modifiers === Qt.NoModifier)
                win.toggleEnlarged();
            else if (event.key === Qt.Key_B && event.modifiers === Qt.NoModifier)
                win.openBrowser();
            else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)
                zoomer.zoomCenter(1.5);
            else if (event.key === Qt.Key_Minus)
                zoomer.zoomCenter(1 / 1.5);
            else if (event.key === Qt.Key_0)
                zoomer.zoomOut();
            else if (!win.editing)
                return ;
            else if (event.key === Qt.Key_I)
                win.st.setTrimStart(win.positionSec);
            else if (event.key === Qt.Key_O)
                win.st.setTrimEnd(win.positionSec);
            else if (event.key === Qt.Key_R)
                win.st.rotation = (win.st.rotation + (shift ? 270 : 90)) % 360;
            else if (ctrl && shift && event.key === Qt.Key_S)
                win.requestOverwrite();
            else if (ctrl && event.key === Qt.Key_S)
                win.saveCopy();
            else
                return ;
            event.accepted = true;
        }

        // Copy of the card for the closing: the state empties the image/video right after isOpen goes
        // false, so the card itself would evaporate empty. This copy follows the card while open
        // (live, almost invisible so it keeps being drawn) and freezes in the same moment the closing
        // starts (live is bound to it), so the last real frame evaporates (common/Evaporate).
        ShaderEffectSource {
            id: cardShot

            anchors.fill: card
            sourceItem: card
            live: !ev.closing
            hideSource: false
            smooth: true
            scale: ev.scale
            opacity: ev.closing ? ev.opacity : 0.001
            layer.enabled: ev.closing
            layer.effect: MultiEffect {
                autoPaddingEnabled: true
                blurEnabled: true
                blur: ev.blur
                blurMax: 64
                blurMultiplier: 0.6
            }
        }

        Rectangle {
            id: card

            readonly property real normalW: Math.min(parent.width - 80, 1500)
            readonly property real normalH: Math.min(parent.height - 80, 960)
            readonly property real bigW: Math.max(normalW, parent.width * 0.94)
            readonly property real bigH: Math.max(normalH, parent.height * 0.94)

            anchors.centerIn: parent
            // Opening animation (common/OpenMotion)
            scale: intro.cardScale
            // While closing the frozen copy (cardShot) evaporates in its place
            opacity: ev.closing ? 0 : intro.cardOpacity
            enabled: !ev.closing
            transform: Translate {
                y: intro.rise
            }
            width: normalW + (bigW - normalW) * win.enlargeK
            height: normalH + (bigH - normalH) * win.enlargeK
            radius: Theme.radiusXL
            color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.04))
            border.width: 1
            border.color: Theme.stroke
            // The settings glide out of the card to the right
            clip: true

            MouseArea {
                anchors.fill: parent
                onPressed: keyScope.forceActiveFocus()
            }

            // ---------- Folder browser (B / folder button) ----------
            MediaBrowser {
                id: browser

                objectName: "mediaBrowser"
                anchors.fill: parent
                currentPath: win.st.path
                onPicked: (path, kind) => {
                    return win.openFromBrowser(path, kind);
                }
                onDismissed: win.closeBrowser(true)
                // After unlocking (or leaving) a vault: keys back to the editor
                onWantsKeys: keyScope.forceActiveFocus()

                Connections {
                    function onIsOpenChanged() {
                        if (!win.st.isOpen)
                            browser.open = false;

                    }

                    target: win.st
                }

            }

            // ---------- Other videos in the folder ----------
            MediaStrip {
                id: strip

                x: 20
                y: 20
                height: parent.height - 40
                targetHeight: (win.enlarged ? card.bigH : card.normalH) - 40
                visible: win.browsing
                paths: win.st.gallery
                currentIndex: win.st.currentIndex
                currentPath: win.st.path
                sourceFor: (path) => {
                    const file = win.st.galleryThumbs[path];
                    return file ? "file://" + encodeURI(file) : "";
                }
                unsavedFor: (path) => {
                    return win.st.isUnsaved(path);
                }
                onPicked: (path) => {
                    win.showVideo(path);
                }
            }

            GlassButton {
                x: viewport.x - win.arrowGutter + (win.arrowGutter - width) / 2
                y: viewport.y + (viewport.height - height) / 2
                visible: win.browsing
                glyph: "\uf053"
                dimmed: win.st.currentIndex <= 0
                onClicked: win.stepVideo(-1)
            }

            GlassButton {
                x: viewport.x + viewport.width + (win.arrowGutter - width) / 2
                y: viewport.y + (viewport.height - height) / 2
                visible: win.browsing
                glyph: "\uf054"
                dimmed: win.st.currentIndex >= win.st.gallery.length - 1
                onClicked: win.stepVideo(1)
            }

            // ---------- Image ----------
            Item {
                id: viewport

                x: win.browsing ? strip.x + strip.width + 14 + win.arrowGutter : 20
                y: 20
                width: parent.width - x - 20 - (win.browsing ? win.arrowGutter : 0) - (side.width + 20) * win.editK
                height: parent.height - 40 - controls.height - timeline.height - 16
                // Only during the slide or when zoomed: the images should end at the edge of the surface
                clip: slide.active || zoomer.zoomed

                // Zoom/pan of the view (see common/PanZoom). Content = the video frame (frameBox)
                PanZoom {
                    id: zoomer

                    viewW: viewport.width
                    viewH: viewport.height
                    contentW: frameBox.width
                    contentH: frameBox.height
                }

                // Mouse wheel: zoom to the pointer
                WheelHandler {
                    id: zoomWheel

                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const p = zoomWheel.point.position;
                        zoomer.zoomAt(p.x, p.y, Math.pow(1.0015, event.angleDelta.y));
                    }
                }

                // Own shell, because the snapshot does not take along the rotation of the source itself
                Item {
                    id: videoBox

                    anchors.fill: parent
                    opacity: slide.contentOpacity

                    // Lies exactly around the rotated image: captureFrame should not take a margin along
                    Item {
                        id: frameBox

                        anchors.centerIn: parent
                        width: win.rotatedW * win.fit
                        height: win.rotatedH * win.fit

                        VideoOutput {
                            id: videoView

                            readonly property bool adjusted: win.st.brightness !== 0 || win.st.contrast !== 0 || win.st.saturation !== 0

                            anchors.centerIn: parent
                            // Rounded middle: rotated, the snapshot would otherwise miss a strip at the edge
                            anchors.alignWhenCentered: false
                            // At 90/270 degrees width and height of the unrotated surface are swapped.
                            // Rounded up and stretched: the surface otherwise rounds down and leaves an empty
                            // pixel column in the rotated snapshot
                            width: Math.ceil(win.st.videoW * win.fit)
                            height: Math.ceil(win.st.videoH * win.fit)
                            fillMode: VideoOutput.Stretch
                            rotation: win.st.rotation
                            layer.enabled: adjusted
                            // Otherwise a snapshot with a color slider would only have the size of the preview
                            layer.textureSize: Qt.size(win.st.videoW, win.st.videoH)
                            layer.effect: MultiEffect {
                                brightness: win.st.brightness
                                contrast: win.st.contrast
                                saturation: win.st.saturation
                            }
                        }

                    }

                    // Zoom sits here instead of on frameBox: frameBox is captured for "Save Frame"
                    // and should stay unzoomed. Math as in PanZoom, only offset by frameBox.x/y
                    // (videoBox fills the viewport, frameBox lies centered in it).
                    transform: [
                        Scale {
                            origin.x: frameBox.x + zoomer.anchorX
                            origin.y: frameBox.y + zoomer.anchorY
                            xScale: zoomer.zoom
                            yScale: zoomer.zoom
                        },
                        Translate {
                            x: zoomer.screenX - frameBox.x - zoomer.anchorX + slide.contentOffset
                            y: zoomer.screenY - frameBox.y - zoomer.anchorY
                        }
                    ]

                }

                MediaSlide {
                    id: slide

                    anchors.fill: parent
                    source: videoBox
                }

                // Click = play/pause. When zoomed, dragging (any button) pans the image; a drag then does not
                // count as a click, otherwise every pan would pause the video
                MouseArea {
                    property point pressPos
                    property point last
                    property bool panned: false

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: panned ? Qt.ClosedHandCursor : (zoomer.zoomed ? Qt.OpenHandCursor : Qt.PointingHandCursor)
                    onPressed: (mouse) => {
                        keyScope.forceActiveFocus();
                        pressPos = Qt.point(mouse.x, mouse.y);
                        last = pressPos;
                        panned = false;
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed || !zoomer.zoomed)
                            return ;

                        if (!panned && Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) < 4)
                            return ;

                        panned = true;
                        zoomer.panBy(mouse.x - last.x, mouse.y - last.y);
                        last = Qt.point(mouse.x, mouse.y);
                    }
                    onReleased: Qt.callLater(() => {
                        panned = false;
                    })
                    onClicked: (mouse) => {
                        if (!panned && mouse.button === Qt.LeftButton)
                            win.togglePlay();

                    }
                }

                // Zoom level (video pixels per screen pixel), only while zoomed
                ZoomBadge {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    shown: zoomer.zoomed
                    percent: win.fit * zoomer.zoom * 100
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 80
                    visible: win.st.error !== "" && (win.st.duration === 0 || !win.editing)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: win.st.error
                    color: Theme.bad
                    font.family: Theme.font
                    font.pixelSize: Theme.sizeBody
                }

            }

            // ---------- Playback ----------
            // Like the iOS player: transport in the middle (5 s back, play big and bright, 5 s forward), on the left the
            // volume (the slider expands on hover), on the right time and fullscreen
            Item {
                id: controls

                x: viewport.x
                y: viewport.y + viewport.height + 8
                width: viewport.width
                height: Theme.px(46)

                // The slider expands on hover. The item covers symbol and slider, so it
                // does not collapse on the way from the symbol to the slider
                Item {
                    id: volumeBox

                    property bool expanded: (volumeHover.hovered || volumeDrag.pressed) && win.audioUsable

                    anchors.verticalCenter: parent.verticalCenter
                    width: volumeIcon.width + (expanded ? Theme.px(118) : 0)
                    height: volumeIcon.height
                    clip: true

                    HoverHandler {
                        id: volumeHover
                    }

                    // Mouse wheel over the symbol or slider, in 5 % steps
                    WheelHandler {
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            if (win.audioUsable)
                                win.setVolume(win.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05));

                        }
                    }

                    GlassButton {
                        id: volumeIcon

                        glyph: {
                            if (win.muted || win.st.removeAudio || win.volume === 0)
                                return "";

                            return win.volume < 0.5 ? "" : "";
                        }
                        dimmed: !win.audioUsable
                        onClicked: win.muted = !win.muted
                    }

                    Item {
                        x: volumeIcon.width + Theme.px(12)
                        width: Theme.px(96)
                        height: parent.height
                        opacity: volumeBox.expanded ? 1 : 0

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: Theme.px(4)
                            radius: height / 2
                            color: Theme.tint(Theme.text, 0.14)

                            Rectangle {
                                width: parent.width * win.shownVolume
                                height: parent.height
                                radius: height / 2
                                color: Theme.text
                            }

                            Rectangle {
                                x: parent.width * win.shownVolume - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.px(14)
                                height: width
                                radius: width / 2
                                color: Theme.knob
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

                Row {
                    id: transport

                    anchors.centerIn: parent
                    spacing: Theme.px(14)

                    GlassButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: ""
                        onClicked: win.seekBy(-5)
                    }

                    GlassButton {
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.px(44)
                        prominent: true
                        glyph: player.playbackState === MediaPlayer.PlayingState ? "" : ""
                        onClicked: win.togglePlay()
                    }

                    GlassButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: ""
                        onClicked: win.seekBy(5)
                    }

                }

                Row {
                    id: rightControls

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.px(12)

                    // Digits of equal width: otherwise the running time wobbles on every tenth
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.px(6)

                        Text {
                            text: win.formatTime(win.positionSec)
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.features: Theme.tabular
                            font.pixelSize: Theme.sizeBody
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: "/  " + win.formatTime(win.st.duration)
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.features: Theme.tabular
                            font.pixelSize: Theme.sizeBody
                        }

                    }

                    GlassButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: win.enlarged ? "" : ""
                        active: win.enlarged
                        dimmed: win.st.exporting
                        onClicked: win.toggleEnlarged()
                    }

                }

                // As in the image tool: in the big view the sidebar is missing, shortcuts ask
                // anyway
                Text {
                    anchors.right: rightControls.left
                    anchors.rightMargin: Theme.px(12)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, (parent.width - transport.width) / 2 - rightControls.width - Theme.px(24))
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    visible: win.enlarged
                    text: win.confirmDelete ? "Press Del again to move to trash" : ""
                    color: Theme.warn
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                }

            }

            // ---------- Timeline ----------
            Item {
                id: timeline

                readonly property real pxPerSec: win.st.duration > 0 ? width / win.st.duration : 0
                readonly property real startX: win.st.trimStart * pxPerSec
                readonly property real endX: win.st.trimEnd * pxPerSec
                readonly property bool dragging: seekArea.pressed || startGrip.pressed || endGrip.pressed
                // Count from the narrow editor width, not the current one: otherwise it changes
                // in the middle of the switch and the strip visibly rebuilds
                // (that is also why the card's target width, not the one being animated)
                readonly property int cells: Math.max(1, Math.ceil(((win.enlarged ? card.bigW : card.normalW) - viewport.x - 40 - (win.browsing ? win.arrowGutter : 0) - side.width) / 96))
                readonly property int fullHeight: 64

                x: viewport.x
                y: controls.y + controls.height + 8
                width: viewport.width
                // In the player only a narrow progress bar, in the editor the frame strip
                height: 8 + (fullHeight - 8) * win.editK

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: Theme.track
                    opacity: 1 - win.editK

                    Rectangle {
                        width: Math.max(0, win.positionSec * timeline.pxPerSec)
                        height: parent.height
                        radius: 4
                        color: Theme.accent
                    }

                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.card
                    opacity: win.editK
                    visible: win.editK > 0.01

                    // Fixed image height, centered: on the switch the strip is only uncovered. If the
                    // image grew along, PreserveAspectCrop would crop it anew every frame and it looks distorted
                    Row {
                        y: (timeline.height - timeline.fullHeight) / 2

                        Repeater {
                            model: timeline.cells

                            delegate: Image {
                                required property int index
                                readonly property string file: win.st.thumbs[Math.floor((index + 0.5) / timeline.cells * win.st.thumbCount)] || ""

                                width: timeline.width / timeline.cells
                                height: timeline.fullHeight
                                source: file !== "" ? "file://" + encodeURI(file) : ""
                                sourceSize.height: 180
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                        }

                    }

                }

                // Darken the trimmed-away parts
                Rectangle {
                    width: timeline.startX
                    height: parent.height
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.65)
                }

                Rectangle {
                    x: timeline.endX
                    width: parent.width - x
                    height: parent.height
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.65)
                }

                // Frame around the part that stays
                Rectangle {
                    x: timeline.startX
                    width: timeline.endX - timeline.startX
                    height: parent.height
                    opacity: win.editK
                    visible: win.editK > 0.01
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.accent
                    radius: 4
                }

                MouseArea {
                    id: seekArea

                    function seek(mouse) {
                        win.seekTo(mouse.x / timeline.pxPerSec);
                    }

                    anchors.fill: parent
                    // The narrow bar in the player should still be easy to hit
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: (mouse) => {
                        keyScope.forceActiveFocus();
                        seek(mouse);
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed)
                            seek(mouse);

                    }
                }

                TrimGrip {
                    id: startGrip

                    visible: win.editK > 0.01
                    enabled: win.editing
                    opacity: win.editK
                    gripX: timeline.startX
                    onDragged: (x) => {
                        win.st.setTrimStart(x / timeline.pxPerSec);
                        win.seekTo(win.st.trimStart);
                    }
                }

                TrimGrip {
                    id: endGrip

                    visible: win.editK > 0.01
                    enabled: win.editing
                    opacity: win.editK
                    gripX: timeline.endX
                    onDragged: (x) => {
                        win.st.setTrimEnd(x / timeline.pxPerSec);
                        win.seekTo(win.st.trimEnd - 0.05);
                    }
                }

                // Abspielposition
                Rectangle {
                    x: win.positionSec * timeline.pxPerSec - width / 2
                    y: -3
                    width: 2
                    height: parent.height + 6
                    radius: 1
                    opacity: win.editK
                    color: "white"
                }

                // Preview above the timeline on hover
                Rectangle {
                    id: hoverPreview

                    readonly property real hoverSec: seekArea.mouseX / Math.max(0.001, timeline.pxPerSec)
                    readonly property string file: win.st.thumbs[Math.min(win.st.thumbCount - 1, Math.floor(hoverSec / Math.max(0.001, win.st.duration) * win.st.thumbCount))] || ""

                    x: Math.max(0, Math.min(timeline.width - width, seekArea.mouseX - width / 2))
                    y: -height - 10
                    width: 216
                    height: 142
                    radius: 10
                    visible: seekArea.containsMouse && win.st.duration > 0
                    color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.08))
                    border.width: 1
                    border.color: Theme.stroke

                    ClippingRectangle {
                        x: 4
                        y: 4
                        width: parent.width - 8
                        height: parent.height - 28
                        radius: 7
                        color: Theme.card

                        Image {
                            anchors.fill: parent
                            source: hoverPreview.file !== "" ? "file://" + encodeURI(hoverPreview.file) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.formatTime(hoverPreview.hoverSec)
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.sizeSmall
                    }

                }

            }

            // ---------- Sidebar (iOS style, built the same as in the image editor) ----------
            // Header (file, close), tools in grouped cards (scroll if there is not enough
            // room), fixed at the bottom: main action "Save Copy" and the side actions as a list.
            EditorSidePanel {
                id: side

                shownK: win.editK
                enabled: win.editing
                backColor: card.color
                header.kind: "Video"
                header.glyph: ""
                header.fileName: win.st.fileName
                header.index: win.st.currentIndex
                header.count: win.st.gallery.length
                header.mediaW: win.st.videoW
                header.mediaH: win.st.videoH
                header.duration: win.st.duration
                headerActions: [
                    // Folder browser: other folders, subfolders, images and videos mixed (key B)
                    GlassButton {
                        size: Theme.px(30)
                        glyph: "\uf07c"
                        visible: true
                        onClicked: win.openBrowser()
                    },
                    // Close like Esc: with unsaved changes the first click asks
                    GlassButton {
                        size: Theme.px(30)
                        glyph: ""
                        active: win.confirmDiscard
                        onClicked: win.escapePressed()
                    }
                ]
                tools: [
                    // Trimming happens at the bottom on the timeline; here the values and setting at the playback position
                    IosGroup {
                        width: parent.width
                        title: "Trim"

                        IosRow {
                            divider: false
                            glyph: ""
                            title: "Start"
                            subtitle: "Click to set at playhead · I"
                            trailing: win.formatTime(win.st.trimStart)
                            onClicked: win.st.setTrimStart(win.positionSec)
                        }

                        IosRow {
                            glyph: ""
                            title: "End"
                            subtitle: "Click to set at playhead · O"
                            trailing: win.formatTime(win.st.trimEnd)
                            onClicked: win.st.setTrimEnd(win.positionSec)
                        }

                    },
                    IosGroup {
                        width: parent.width
                        title: "Speed"
                        plain: true

                        IosSegmented {
                            width: parent.width
                            items: [{
                                "text": "0.5×"
                            }, {
                                "text": "1×"
                            }, {
                                "text": "1.5×"
                            }, {
                                "text": "2×"
                            }]
                            currentIndex: [0.5, 1, 1.5, 2].indexOf(win.st.speed)
                            onActivated: (i) => {
                                win.st.speed = [0.5, 1, 1.5, 2][i];
                            }
                        }

                    },
                    IosGroup {
                        width: parent.width
                        title: "Audio"

                        IosRow {
                            divider: false
                            glyph: ""
                            title: "Remove Audio"
                            subtitle: win.st.hasAudio ? "" : "This video has no sound"
                            dimmed: !win.st.hasAudio
                            onClicked: win.st.removeAudio = !win.st.removeAudio

                            IosSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: win.st.removeAudio
                                onToggled: {
                                    if (win.st.hasAudio)
                                        win.st.removeAudio = !win.st.removeAudio;

                                }
                            }

                        }

                    },
                    IosGroup {
                        width: parent.width
                        title: "Rotate"

                        RotatePair {
                            width: parent.width
                            onRotateLeft: win.st.rotation = (win.st.rotation + 270) % 360
                            onRotateRight: win.st.rotation = (win.st.rotation + 90) % 360
                        }

                    },
                    IosGroup {
                        width: parent.width
                        title: "Adjust"
                        inset: Theme.px(12)
                        // Like "Revert" in iOS Photos: everything back to the original
                        actionText: "Revert"
                        actionTone: Theme.bad
                        actionEnabled: win.st.dirty
                        onActionClicked: win.st.resetEdits()

                        AdjustSlider {
                            width: parent.width
                            label: "Brightness"
                            prop: "brightness"
                        }

                        AdjustSlider {
                            width: parent.width
                            label: "Contrast"
                            prop: "contrast"
                        }

                        AdjustSlider {
                            width: parent.width
                            label: "Saturation"
                            prop: "saturation"
                        }

                    }
                ]
                footer: [
                    Text {
                        width: parent.width
                        visible: text !== ""
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: {
                            if (win.st.error !== "" && win.st.duration > 0)
                                return win.st.error;

                            if (win.confirmDiscard)
                                return "Close again to discard all changes";

                            if (win.confirmOverwrite)
                                return "Replaces the original file. This can't be undone.";

                            return "";
                        }
                        color: win.st.error !== "" && win.st.duration > 0 ? Theme.bad : Theme.warn
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    },
                    // During the export: progress fills the row, below it cancel
                    IosGroup {
                        width: parent.width
                        visible: win.st.exporting

                        IosRow {
                            divider: false
                            glyph: ""
                            title: "Exporting"
                            trailing: Math.round(win.st.progress * 100) + " %"
                            progress: win.st.progress
                        }

                        IosRow {
                            centered: true
                            title: "Cancel Export"
                            tone: Theme.bad
                            onClicked: win.st.cancelExport()
                        }

                    },
                    IosButton {
                        id: saveButton

                        width: parent.width
                        visible: !win.st.exporting && !win.compressOpen
                        glyph: ""
                        text: "Save Copy"
                        dimmed: !win.st.dirty
                        onClicked: win.saveCopy()

                        // Saved: star at the button (during the export the button is hidden and comes back afterwards
                        // with the confirmation)
                        Connections {
                            target: win.st

                            function onSaved(overwrite) {
                                saveButton.confirm(overwrite ? "Original replaced" : "Saved");
                            }
                        }
                    },
                    // On the "Compress" page this is the main action
                    IosButton {
                        width: parent.width
                        // This file is already in the queue: the button takes it out again or cancels
                        readonly property bool queued: win.st.queuePos >= 0

                        visible: !win.st.exporting && win.compressOpen
                        kind: queued ? "tinted" : "filled"
                        tone: queued ? Theme.bad : Theme.accent
                        glyph: queued ? "\uf00d" : (CompressQueue.busy ? "\uf067" : "\uf066")
                        text: {
                            if (win.st.queuePos === 0)
                                return "Cancel Compression";

                            if (queued)
                                return "Remove from Queue";

                            if (CompressQueue.busy)
                                return "Add to Queue";

                            return win.st.compressReplace ? "Compress & Replace" : "Compress";
                        }
                        onClicked: {
                            if (queued)
                                CompressQueue.remove(win.st.path);
                            else
                                win.st.queueCompress();
                        }
                    },
                    IosGroup {
                        width: parent.width
                        visible: !win.st.exporting

                        EditorActionSlot {
                            onRequested: win.sendToAction()
                        }

                        // Opens the page with the levels (click again = back)
                        IosRow {
                            readonly property string appIcon: Quickshell.iconPath("fr.handbrake.ghb", true)

                            visible: CompressQueue.available
                            divider: Addons.editorAction !== null && Addons.editorAction.available
                            iconSource: appIcon
                            glyph: appIcon === "" ? "" : ""
                            title: "Compress with HandBrake"
                            subtitle: {
                                if (win.st.queuePos === 0)
                                    return "Compressing " + Math.round(CompressQueue.progress * 100) + " %";

                                if (win.st.queuePos > 0)
                                    return "Waiting in queue";

                                if (CompressQueue.busy)
                                    return CompressQueue.jobs.length + " in queue · " + Math.round(CompressQueue.progress * 100) + " %";

                                if (win.st.compressNote !== "")
                                    return win.st.compressNote;

                                return win.st.fileSize > 0 ? "Now " + Fmt.bytes(win.st.fileSize) : "Make the file smaller";
                            }
                            // Fills up while the queue works (also for other videos)
                            progress: CompressQueue.busy ? CompressQueue.progress : -1
                            trailingGlyph: win.compressOpen ? "" : ""
                            chevron: !win.compressOpen
                            onClicked: win.compressOpen = !win.compressOpen
                        }

                        // Counterpart of "Copy to Clipboard" in the image tool: the current frame as a file (key S)
                        IosRow {
                            divider: (Addons.editorAction !== null && Addons.editorAction.available) || CompressQueue.available
                            glyph: ""
                            title: "Save Frame"
                            trailing: "S"
                            onClicked: win.captureFrame()
                        }

                        IosRow {
                            glyph: ""
                            title: win.confirmOverwrite ? "Click Again to Overwrite" : "Overwrite Original"
                            tone: Theme.bad
                            dimmed: !win.st.canOverwrite
                            onClicked: win.requestOverwrite()
                        }

                        IosRow {
                            glyph: ""
                            title: win.confirmDelete ? "Click Again to Move to Trash" : "Delete"
                            tone: Theme.bad
                            onClicked: win.requestDelete()
                        }

                    }
                ]
                pushK: win.compressK

                // ---------- "Compress" page (HandBrake) ----------
                // Lies exactly above the tool list and slides in from the right; header and end
                // stay, the main button at the bottom becomes "Compress" meanwhile
                Flickable {
                    x: side.width * 0.3 * (1 - win.compressK)
                    y: side.toolsArea.y
                    width: side.width
                    height: side.toolsArea.height
                    opacity: win.compressK
                    visible: win.compressK > 0.01
                    enabled: win.compressOpen
                    contentHeight: compressPage.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    Column {
                        id: compressPage

                        width: parent.width
                        spacing: Theme.px(16)

                        // Navigation row as on iOS: back on the left, the title in the middle
                        Item {
                            width: parent.width
                            height: Theme.px(28)

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.px(2)
                                text: "\uf053  Edit"
                                color: Theme.accent
                                opacity: backMouse.containsMouse ? 0.7 : 1
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeBody
                                font.weight: Font.DemiBold

                                MouseArea {
                                    id: backMouse

                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.compressOpen = false
                                }

                            }

                            Text {
                                anchors.centerIn: parent
                                text: "Compress"
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeLead
                                font.weight: Font.DemiBold
                            }

                        }

                        // Selection list with check marks instead of a segmented control: this way each level fits an explanation
                        IosGroup {
                            width: parent.width
                            title: "Quality"
                            footer: {
                                if (win.st.compressEdits)
                                    return "Trim, rotation and audio removal are applied" + (win.st.compressSkips ? ", speed and colors are not." : ".");

                                return win.st.compressSkips ? "Speed and color changes are not applied." : "";
                            }

                            Repeater {
                                model: [{
                                    "title": "Low",
                                    "subtitle": "Up to 720p · smallest file"
                                }, {
                                    "title": "Medium",
                                    "subtitle": "Up to 1080p · good balance"
                                }, {
                                    "title": "High",
                                    "subtitle": "Full resolution · best quality"
                                }]

                                IosRow {
                                    id: levelRow

                                    required property var modelData
                                    required property int index

                                    divider: index > 0
                                    title: modelData.title
                                    subtitle: modelData.subtitle
                                    // Already queued: the settings from back then apply, nothing more to choose here
                                    dimmed: win.st.queuePos >= 0
                                    onClicked: win.st.compressLevel = index

                                    // Check mark in the accent color as in iOS selection lists
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: win.st.shownLevel === levelRow.index
                                        text: "\uf00c"
                                        color: Theme.accent
                                        font.family: Theme.font
                                        font.pixelSize: Theme.sizeBody
                                    }

                                }

                            }

                        }

                        IosGroup {
                            width: parent.width
                            title: "Save"
                            footer: win.st.shownReplace ? "The original goes to the trash, so you can still get it back." : "Saved next to the original as " + win.st.fileName.replace(/\.[^.]*$/, "") + "-compressed.mp4."

                            IosRow {
                                divider: false
                                glyph: "\uf1f8"
                                title: "Replace Original"
                                dimmed: win.st.queuePos >= 0
                                onClicked: win.st.compressReplace = !win.st.compressReplace

                                IosSwitch {
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: win.st.shownReplace
                                    onToggled: {
                                        if (win.st.queuePos < 0)
                                            win.st.compressReplace = !win.st.compressReplace;

                                    }
                                }

                            }

                        }

                        IosGroup {
                            width: parent.width
                            title: "File"

                            IosRow {
                                divider: false
                                glyph: "\uf0a0"
                                title: "Current Size"
                                trailing: win.st.fileSize > 0 ? Fmt.bytes(win.st.fileSize) : ""
                            }

                            // Result of the last run for this video
                            IosRow {
                                visible: win.st.compressNote !== "" && win.st.queuePos < 0
                                glyph: "\uf00c"
                                title: "Last Result"
                                subtitle: win.st.compressNote
                            }

                        }

                        // All queued videos (also from other folders); keeps running when the editor closes.
                        // Click = take out or cancel, for the running one only after a confirmation
                        IosGroup {
                            width: parent.width
                            visible: CompressQueue.jobs.length > 0
                            title: "Queue"
                            footer: "Keeps running when you close the editor."

                            Repeater {
                                model: CompressQueue.jobs

                                IosRow {
                                    required property var modelData
                                    required property int index
                                    readonly property bool running: index === 0 && CompressQueue.busy
                                    readonly property string levelName: ({
                                        "low": "Low",
                                        "medium": "Medium",
                                        "high": "High"
                                    })[modelData.level] + (modelData.replace ? " · replaces" : "")

                                    divider: index > 0
                                    glyph: running ? "\uf021" : "\uf017"
                                    tone: modelData.path === win.st.path ? Theme.accent : Theme.text
                                    title: modelData.name
                                    subtitle: {
                                        if (win.confirmCancelId === modelData.id)
                                            return running ? "Click again to cancel" : "Click again to remove";

                                        return running ? "Compressing " + Math.round(CompressQueue.progress * 100) + " % · " + levelName : "Waiting · " + levelName;
                                    }
                                    progress: running ? CompressQueue.progress : -1
                                    trailingGlyph: "\uf00d"
                                    onClicked: {
                                        if (win.confirmCancelId === modelData.id) {
                                            win.confirmCancelId = -1;
                                            CompressQueue.remove(modelData.path);
                                        } else {
                                            win.confirmCancelId = modelData.id;
                                            cancelConfirmTimer.restart();
                                        }
                                    }
                                }

                            }

                        }

                    }

                }

            }

        }

    }

    // Handle at one end of the cut
    component TrimGrip: Item {
        id: grip

        property real gripX: 0
        readonly property alias pressed: gripMouse.pressed

        signal dragged(real x)

        x: gripX - width / 2
        y: -4
        width: 18
        height: parent.height + 8

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: parent.height
            radius: 4
            color: Theme.accent
        }

        MouseArea {
            id: gripMouse

            anchors.fill: parent
            cursorShape: Qt.SizeHorCursor
            onPositionChanged: (mouse) => {
                if (pressed)
                    grip.dragged(mapToItem(grip.parent, mouse.x, 0).x);

            }
        }

    }

    // Image slider (-100..100 %, double click = back to 0)
    component AdjustSlider: ValueSlider {
        property string prop: ""

        from: -1
        to: 1
        zeroAt: 0
        value: VideoEditorState[prop]
        valueText: (value > 0 ? "+" : "") + Math.round(value * 100)
        onMoved: (v) => {
            // Snap at 0: otherwise the neutral position is hard to hit with the mouse
            VideoEditorState[prop] = Math.abs(v) < 0.03 ? 0 : v;
        }
        onDoubleClicked: VideoEditorState[prop] = 0
    }

}
