import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Screenshot editor (SUPER + SHIFT + S), logic in ScreenshotEditorState. Crop, paint, rotate,
// brightness/contrast/saturation. "stage" is saved with grabToImage at the original resolution:
// Preview and export are the same scene, so the file looks exactly like the view.
// Opened from yazi: on the left a column with the other images of the folder, arrows next to the image
// and the arrow keys or h/l switch.
PanelWindow {
    id: win

    readonly property var st: ScreenshotEditorState
    property string tool: "draw" // "draw" | "crop"
    property color penColor: "#e5484d"
    property real penSize: 5 // in pixels of the view, so the pen feels the same regardless of the zoom
    // Crop in progress, in coordinates of the rotated image
    property var draft: ({ "x": 0, "y": 0, "w": 0, "h": 0 })
    // The first Esc only warns, so edits are not lost by accident
    property bool confirmDiscard: false
    // Overwriting cannot be undone: the first click only asks
    property bool confirmOverwrite: false
    property bool confirmDelete: false
    property bool exporting: false
    // Visible section: while cropping the whole rotated image, otherwise the crop
    readonly property bool cropping: tool === "crop" && st.isOpen
    readonly property var frame: cropping ? ({ "x": 0, "y": 0, "w": st.rotatedW, "h": st.rotatedH }) : st.rotatedCrop()
    // Several images in the folder: column on the left, arrows left and right of the image
    readonly property bool browsing: st.folderMode && st.gallery.length > 1
    readonly property int arrowGutter: 44
    // Big view: the card grows, the tools glide out. Stays deliberately smaller than the screen
    property bool enlarged: false
    // Runs along softly, so card, column and image morph together
    property real enlargeK: enlarged ? 1 : 0
    property bool snapView: false
    // Open image moved to the trash in the browser (see closeBrowser)
    property bool currentGone: false
    // Small images should grow along too: normally the limit stops them at double size
    readonly property real fit: frame.w > 0 ? Math.min(viewport.width / frame.w, viewport.height / frame.h, 2 + 2 * enlargeK) : 1

    function setTool(t) {
        if (t === tool)
            return ;

        if (tool === "crop")
            commitCrop();

        if (t === "crop")
            draft = st.rotatedCrop();

        tool = t;
    }

    function commitCrop() {
        const c = st.rotatedCrop();
        if (draft.x === c.x && draft.y === c.y && draft.w === c.w && draft.h === c.h)
            return ;

        st.pushUndo();
        st.setRotatedCrop(draft);
    }

    function rotate(deg) {
        zoomer.reset();
        if (cropping)
            commitCrop();

        st.rotateBy(deg);
        if (cropping)
            draft = st.rotatedCrop();

    }

    function undo() {
        st.undo();
        if (cropping)
            draft = st.rotatedCrop();

    }

    function redo() {
        st.redo();
        if (cropping)
            draft = st.rotatedCrop();

    }

    function escapePressed() {
        if (cropping) {
            // Discard the crop, the image stays open
            tool = "draw";
        } else if (enlarged) {
            // Big view = viewer: Esc closes directly. With unsaved changes first back
            // to the editor, the confirmation to discard is there
            if (st.anyUnsaved)
                enlarged = false;
            else
                st.close();
        } else if (!st.anyUnsaved || confirmDiscard) {
            st.close();
        } else {
            confirmDiscard = true;
            discardTimer.restart();
        }
    }

    function stepImage(delta) {
        const i = st.currentIndex + delta;
        if (i >= 0 && i < st.gallery.length)
            showImage(st.gallery[i]);

    }

    function showImage(path) {
        if (path === st.imagePath)
            return ;

        // A running crop belongs to the old image, so apply it before switching
        if (cropping)
            setTool("draw");

        confirmDiscard = false;
        // The snapshot for the slide does not know the zoom transform -> reset it first
        zoomer.reset();
        slide.begin(st.gallery.indexOf(path) > st.currentIndex ? 1 : -1, () => {
            st.goTo(path);
        });
    }

    function requestDelete() {
        if (!st.folderMode)
            return ;

        if (confirmDelete) {
            confirmDelete = false;
            tool = "draw";
            // The next image moves up, only for the last one the previous one comes
            slide.begin(st.currentIndex < st.gallery.length - 1 ? 1 : -1, () => {
                st.deleteCurrent();
            });
        } else {
            confirmDelete = true;
            deleteTimer.restart();
        }
    }

    // dd (vim): the fast double tap is already the confirmation, and it only lands in the trash
    function pressDeleteKey() {
        if (!ddTimer.running) {
            ddTimer.restart();
            return ;
        }
        ddTimer.stop();
        if (!confirmDelete)
            requestDelete();

        requestDelete();
    }

    function requestOverwrite() {
        if (cropping)
            setTool("draw");

        if (!st.canOverwrite)
            return ;

        if (confirmOverwrite) {
            confirmOverwrite = false;
            exportAs("overwrite");
        } else {
            confirmOverwrite = true;
            overwriteTimer.restart();
        }
    }

    function exportAs(action) {
        if (exporting || !st.isOpen || st.shownPath !== st.imagePath)
            return;

        if (cropping)
            setTool("draw");

        const source = st.shownPath;
        exporting = st.prepareExport((path) => {
            if (!st.isOpen || source !== st.shownPath || source !== st.imagePath) {
                exporting = false;
                return;
            }
            if (!path) {
                exportFailed("Could not create the temporary export folder.");
                return;
            }
            const started = stage.grabToImage((result) => {
                exporting = false;
                if (!st.isOpen || source !== st.shownPath || source !== st.imagePath)
                    return;

                if (result.saveToFile(path))
                    st.finish(action, path);
                else
                    exportFailed("Could not write the temporary image.");
            }, Qt.size(frame.w, frame.h));
            if (!started)
                exportFailed("Could not render the image.");
        });
    }

    function exportFailed(message) {
        exporting = false;
        NotificationState.send("Screenshot", "Could not export image", message, {});
    }

    // Optional editor action from a private add-on (services/Addons). Unedited folder images go as the
    // original; otherwise the current view is rendered (a screenshot only lives in a RAM folder and is gone
    // after closing). Own name with a timestamp: external apps may cache imported files by name
    function sendToAction() {
        const action = Addons.editorAction;
        if (!action || !action.available)
            return ;

        if (action.busy) {
            action.cancel();
            return ;
        }
        if (cropping)
            setTool("draw");

        const job = {
            "kind": "image",
            "start": -1,
            "end": -1,
            "rotation": 0,
            "width": frame.w,
            "height": frame.h
        };
        if (st.folderMode && !st.dirty) {
            job.path = st.shownPath;
            action.send(job);
            return ;
        }
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
        let path;
        if (st.folderMode) {
            const p = st.shownPath;
            const dot = p.lastIndexOf(".");
            path = (dot > p.lastIndexOf("/") ? p.substring(0, dot) : p) + "_edit_" + stamp + ".png";
        } else {
            path = Settings.folder("screenshots") + "/Screenshot_" + stamp + "_edit.png";
        }
        stage.grabToImage((result) => {
            if (result.saveToFile(path)) {
                job.path = path;
                action.send(job);
            } else {
                NotificationState.send("Screenshot", "Could not export image", "Could not write " + path, {});
            }
        }, Qt.size(frame.w, frame.h));
    }

    // ---------- Folder browser (only for images from a folder; a screenshot has none) ----------
    // levelUp: Ctrl+H in the editor -> one level above the open file's folder
    function openBrowser(levelUp) {
        if (browser.open || !st.folderMode)
            return ;

        if (cropping)
            setTool("draw");

        browser.show(levelUp === true);
    }

    function closeBrowser() {
        // The open image was moved to the trash in the browser: without a new choice there is nothing left to show
        if (currentGone) {
            currentGone = false;
            browser.open = false;
            st.close();
            return ;
        }
        browser.open = false;
        keyScope.forceActiveFocus();
    }

    // Image: open here (also from another folder). Video: hand over to the video editor
    function openFromBrowser(path, kind) {
        currentGone = false;
        if (kind === "image") {
            closeBrowser();
            if (path === st.shownPath)
                return ;

            const dir = path.substring(0, path.lastIndexOf("/")) || "/";
            if (dir === st.folderDir && st.gallery.indexOf(path) >= 0)
                showImage(path);
            else
                st.openInFolder(path);
            return ;
        }
        if (st.anyUnsaved && pendingSwitch !== path) {
            pendingSwitch = path;
            browser.hint = "Unsaved changes will be lost. Open again to continue.";
            switchTimer.restart();
            return ;
        }
        pendingSwitch = "";
        browser.hint = "";
        // Open the video editor first, then close this one: so there is no gap in between
        VideoEditorState.open(path);
        st.close();
    }

    // Opened from yazi while the editor is already open (maybe on another workspace): move it here
    // and show the image. A screenshot has no folder -> then the old behavior stays (shell.qml)
    function adopt(path) {
        anchor.pin();
        browser.open = false;
        if (path !== st.shownPath)
            st.openInFolder(path);

        keyScope.forceActiveFocus();
    }

    function clampDraft(r) {
        const minSize = 8;
        const w = Math.max(minSize, Math.min(r.w, st.rotatedW));
        const h = Math.max(minSize, Math.min(r.h, st.rotatedH));
        return {
            "x": Math.round(Math.max(0, Math.min(r.x, st.rotatedW - w))),
            "y": Math.round(Math.max(0, Math.min(r.y, st.rotatedH - h))),
            "w": Math.round(w),
            "h": Math.round(h)
        };
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
    WlrLayershell.namespace: "quickshell:screenshot-editor-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: st.isOpen && !ev.closing && anchor.here && anchor.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    Connections {
        function onIsOpenChanged() {
            if (!win.st.isOpen) {
                slide.cancel();
                return ;
            }

            win.tool = "draw";
            // Images from a folder open as a viewer (big view, F = editor). A fresh
            // screenshot on the other hand right in the editor: you mostly want to paint on or crop it right away
            win.snapView = true;
            win.enlarged = win.st.folderMode;
            Qt.callLater(() => {
                win.snapView = false;
            });
            win.confirmDiscard = false;
            keyScope.forceActiveFocus();
            if (Addons.editorAction)
                Addons.editorAction.refresh();

            // The image is already loaded when opening: open the card right away
            intro.reset();
            intro.play();
        }

        function onShownPathChanged() {
            win.confirmOverwrite = false;
            win.confirmDelete = false;
        }

        function onTrashFailed() {
            slide.cancel();
        }

        target: win.st
    }

    // File operations in the browser: if the open image was moved, the editor follows it; if it is in the
    // trash, it closes with the browser. Read the strip again
    Connections {
        function onOperationDone(trashed, moved) {
            if (!win.st.isOpen || !win.st.folderMode)
                return ;

            const to = moved[win.st.shownPath];
            if (to !== undefined)
                win.st.openInFolder(to);
            else if (trashed.indexOf(win.st.shownPath) >= 0)
                win.currentGone = true;
            win.st.refreshGallery();
        }

        target: MediaBrowserState
    }

    // The editor action opened the file in its app ("fresh"): the editor would cover it -> close.
    // The edits are in the sent image. Other modes (only added to a library): stay open
    Connections {
        function onFinished(mode, path) {
            if (mode === "fresh" && win.st.isOpen)
                win.st.close();

        }

        target: Addons.editorAction
        ignoreUnknownSignals: true
    }

    // Loads the fresh capture already before opening, the state needs the dimensions
    Image {
        id: loader

        visible: false
        source: win.st.imagePath !== "" ? win.st.fileUrl(win.st.imagePath) : ""
        // Does not block when browsing; the visible image then gets the result from the cache
        asynchronous: true
        autoTransform: true
        onStatusChanged: {
            if (status === Image.Ready) {
                win.st.imageLoaded(implicitWidth, implicitHeight);
                slide.reveal();
            } else if (status === Image.Error)
                win.st.imageFailed();

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
        name: "quickshell:screenshot-editor"
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
        id: ddTimer

        interval: 400
    }

    Timer {
        id: deleteTimer

        interval: 4000
        onTriggered: win.confirmDelete = false
    }

    Timer {
        id: overwriteTimer

        interval: 4000
        onTriggered: win.confirmOverwrite = false
    }

    Timer {
        id: discardTimer

        interval: 2500
        onTriggered: win.confirmDiscard = false
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
            // Holding down must not delete anything; any other key cancels dd (d, l, d would otherwise hit the next image)
            if (event.key === Qt.Key_D && event.modifiers === Qt.NoModifier) {
                if (!event.isAutoRepeat)
                    win.pressDeleteKey();

                event.accepted = true;
                return ;
            }
            ddTimer.stop();
            // Ctrl+H: folder browser one level above the image's folder (like Ctrl+H in the browser)
            if (ctrl && event.key === Qt.Key_H && win.st.folderMode)
                win.openBrowser(true);
            else if (event.key === Qt.Key_Escape)
                win.escapePressed();
            else if (ctrl && event.key === Qt.Key_Z && shift)
                win.redo();
            else if (ctrl && event.key === Qt.Key_Z)
                win.undo();
            else if (event.key === Qt.Key_Delete && win.st.folderMode)
                win.requestDelete();
            else if (ctrl && shift && event.key === Qt.Key_S && win.st.folderMode)
                win.requestOverwrite();
            else if (ctrl && event.key === Qt.Key_S)
                win.exportAs("save");
            else if (ctrl && event.key === Qt.Key_C)
                win.exportAs("copy");
            else if (ctrl && event.key === Qt.Key_E)
                win.sendToAction();
            else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_H) && win.browsing)
                win.stepImage(-1);
            else if ((event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_L) && win.browsing)
                win.stepImage(1);
            else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && win.cropping)
                win.setTool("draw");
            else if (event.key === Qt.Key_C)
                win.setTool(win.cropping ? "draw" : "crop");
            else if (event.key === Qt.Key_F && event.modifiers === Qt.NoModifier)
                win.enlarged = !win.enlarged;
            else if (event.key === Qt.Key_B && event.modifiers === Qt.NoModifier && win.st.folderMode)
                win.openBrowser();
            else if (event.key === Qt.Key_R)
                win.rotate(shift ? -90 : 90);
            else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)
                zoomer.zoomCenter(1.5);
            else if (event.key === Qt.Key_Minus)
                zoomer.zoomCenter(1 / 1.5);
            else if (event.key === Qt.Key_0)
                zoomer.zoomOut();
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
            // The tools glide out of the card to the right
            clip: true
            color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.04))
            border.width: 1
            border.color: Theme.stroke

            // Clicks on the card should not trigger the pen or lose the focus
            MouseArea {
                anchors.fill: parent
                onPressed: keyScope.forceActiveFocus()
            }

            // ---------- Image ----------
            Item {
                id: viewport

                // The arrows get their own margins: above the image they would disturb painting.
                // Always on the right: there also sits the button for the big view next to the image
                readonly property real leftSpace: win.browsing ? strip.width + 14 + win.arrowGutter : win.arrowGutter * win.enlargeK
                readonly property real rightSpace: (side.width + 20) * (1 - win.enlargeK) + win.arrowGutter

                x: 20 + leftSpace
                y: 20
                width: parent.width - 40 - leftSpace - rightSpace
                height: parent.height - 40
                // Only during the slide or when zoomed: otherwise the crop handles may stick out over the edge
                clip: slide.active || zoomer.zoomed

                // Zoom/pan of the view (see common/PanZoom)
                PanZoom {
                    id: zoomer

                    viewW: viewport.width
                    viewH: viewport.height
                    contentW: holder.width
                    contentH: holder.height
                }

                // Every opening starts fitted, even if the new image has the same size
                Connections {
                    function onIsOpenChanged() {
                        zoomer.reset();
                    }

                    target: win.st
                }

                // Mouse wheel: zoom to the pointer. The MouseAreas in the image take no wheel, it arrives here
                WheelHandler {
                    id: zoomWheel

                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const p = zoomWheel.point.position;
                        zoomer.zoomAt(p.x, p.y, Math.pow(1.0015, event.angleDelta.y));
                    }
                }

                // Pan with the middle or right button (left is the pen)
                DragHandler {
                    id: panDrag

                    property point last

                    target: null
                    acceptedButtons: Qt.MiddleButton | Qt.RightButton
                    enabled: zoomer.zoomed
                    cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onActiveChanged: last = Qt.point(0, 0)
                    onTranslationChanged: {
                        if (!active)
                            return ;

                        zoomer.panBy(translation.x - last.x, translation.y - last.y);
                        last = Qt.point(translation.x, translation.y);
                    }
                }

                Item {
                    id: holder

                    anchors.centerIn: parent
                    width: win.frame.w * win.fit
                    height: win.frame.h * win.fit
                    opacity: slide.contentOpacity
                    // A stroke during the slide would otherwise land on the wrong image
                    enabled: !slide.active
                    // Zoom around the anchor, then move the anchor to its screen position (+ switch slide)
                    transform: [
                        Scale {
                            origin.x: zoomer.anchorX
                            origin.y: zoomer.anchorY
                            xScale: zoomer.zoom
                            yScale: zoomer.zoom
                        },
                        Translate {
                            x: zoomer.screenX - holder.x - zoomer.anchorX + slide.contentOffset
                            y: zoomer.screenY - holder.y - zoomer.anchorY
                        }
                    ]

                    // Exported scene at the original size, the view only scales it
                    Item {
                        id: stage

                        width: win.frame.w
                        height: win.frame.h
                        clip: true
                        transformOrigin: Item.TopLeft
                        scale: win.fit
                        // Strong scaling down needs mipmaps, otherwise text flickers in the preview
                        layer.enabled: win.fit < 0.75
                        layer.mipmap: true
                        layer.smooth: win.fit * zoomer.zoom < 3

                        // Original image + strokes; order of the transforms: rotate, then
                        // move back into the positive range, then set to the section
                        Item {
                            id: content

                            width: win.st.imageW
                            height: win.st.imageH
                            transform: [
                                Rotation {
                                    angle: win.st.rotation
                                },
                                Translate {
                                    x: (win.st.rotation === 90 ? win.st.imageH : (win.st.rotation === 180 ? win.st.imageW : 0)) - win.frame.x
                                    y: (win.st.rotation === 180 ? win.st.imageH : (win.st.rotation === 270 ? win.st.imageW : 0)) - win.frame.y
                                }
                            ]

                            Image {
                                id: photo

                                // Without sliders no effect layer: this way the pixels stay exactly the original
                                readonly property bool adjusted: win.st.brightness !== 0 || win.st.contrast !== 0 || win.st.saturation !== 0

                                anchors.fill: parent
                                // Only swap when the new image is ready: otherwise it flashes empty when browsing
                                source: win.st.shownUrl
                                autoTransform: true
                                // From 300 % on real pixels instead of washed out (for a close look)
                                smooth: win.fit * zoomer.zoom < 3
                                layer.enabled: adjusted
                                layer.effect: MultiEffect {
                                    brightness: win.st.brightness
                                    contrast: win.st.contrast
                                    saturation: win.st.saturation
                                }
                            }

                            Canvas {
                                id: paint

                                // New points of the running stroke are only appended: a complete
                                // redraw pass per mouse move would be too expensive on big images
                                property var live: null
                                property int liveDrawn: 0
                                property bool fullRepaint: true

                                function drawPiece(ctx, s, i) {
                                    const p = s.points;
                                    if (i === 0) {
                                        ctx.fillStyle = s.color;
                                        ctx.beginPath();
                                        ctx.arc(p[0].x, p[0].y, s.width / 2, 0, Math.PI * 2);
                                        ctx.fill();
                                        return ;
                                    }
                                    ctx.strokeStyle = s.color;
                                    ctx.lineWidth = s.width;
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";
                                    const midX = (p[i].x + p[i - 1].x) / 2;
                                    const midY = (p[i].y + p[i - 1].y) / 2;
                                    ctx.beginPath();
                                    if (i === 1) {
                                        ctx.moveTo(p[0].x, p[0].y);
                                        ctx.lineTo(midX, midY);
                                    } else {
                                        ctx.moveTo((p[i - 1].x + p[i - 2].x) / 2, (p[i - 1].y + p[i - 2].y) / 2);
                                        ctx.quadraticCurveTo(p[i - 1].x, p[i - 1].y, midX, midY);
                                    }
                                    ctx.stroke();
                                }

                                // Last half piece up to the end point (the curves end on the midpoints)
                                function drawTail(ctx, s) {
                                    const p = s.points;
                                    const n = p.length;
                                    if (n < 2)
                                        return ;

                                    ctx.strokeStyle = s.color;
                                    ctx.lineWidth = s.width;
                                    ctx.lineCap = "round";
                                    ctx.beginPath();
                                    ctx.moveTo((p[n - 1].x + p[n - 2].x) / 2, (p[n - 1].y + p[n - 2].y) / 2);
                                    ctx.lineTo(p[n - 1].x, p[n - 1].y);
                                    ctx.stroke();
                                }

                                function repaintAll() {
                                    fullRepaint = true;
                                    requestPaint();
                                }

                                anchors.fill: parent
                                onPaint: {
                                    const ctx = getContext("2d");
                                    if (fullRepaint) {
                                        ctx.clearRect(0, 0, width, height);
                                        const all = win.st.strokes;
                                        for (let k = 0; k < all.length; k++) {
                                            for (let i = 0; i < all[k].points.length; i++) drawPiece(ctx, all[k], i)
                                            drawTail(ctx, all[k]);
                                        }
                                        fullRepaint = false;
                                        liveDrawn = 0;
                                    }
                                    if (live) {
                                        for (let i = liveDrawn; i < live.points.length; i++) drawPiece(ctx, live, i)
                                        liveDrawn = live.points.length;
                                    }
                                }

                                Connections {
                                    function onStrokesChanged() {
                                        paint.repaintAll();
                                    }

                                    target: win.st
                                }

                            }

                            // Lies in the image: so the coordinates are automatically those of the original,
                            // no matter how it is rotated and scaled right now
                            MouseArea {
                                id: penArea

                                readonly property point viewPos: {
                                    // Dependencies, so the preview follows zooming/panning
                                    zoomer.zoom;
                                    zoomer.screenX;
                                    zoomer.screenY;
                                    return mapToItem(viewport, mouseX, mouseY);
                                }

                                anchors.fill: parent
                                enabled: win.tool === "draw"
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.BlankCursor : Qt.ArrowCursor
                                onPressed: (mouse) => {
                                    keyScope.forceActiveFocus();
                                    paint.live = {
                                        "color": win.penColor.toString(),
                                        "width": win.penSize / (win.fit * zoomer.zoom),
                                        "points": [{ "x": mouse.x, "y": mouse.y }]
                                    };
                                    paint.liveDrawn = 0;
                                    paint.requestPaint();
                                }
                                onPositionChanged: (mouse) => {
                                    if (!paint.live)
                                        return ;

                                    paint.live.points.push({ "x": mouse.x, "y": mouse.y });
                                    paint.requestPaint();
                                }
                                onReleased: {
                                    if (!paint.live)
                                        return ;

                                    const s = paint.live;
                                    paint.live = null;
                                    win.st.addStroke(s);
                                }
                            }

                        }

                    }

                    // ---------- Crop: darkened rest, frame, handles ----------
                    Item {
                        id: cropLayer

                        readonly property real px: win.draft.x * win.fit
                        readonly property real py: win.draft.y * win.fit
                        readonly property real pw: win.draft.w * win.fit
                        readonly property real ph: win.draft.h * win.fit

                        anchors.fill: parent
                        visible: win.cropping

                        Shade {
                            width: parent.width
                            height: cropLayer.py
                        }

                        Shade {
                            y: cropLayer.py + cropLayer.ph
                            width: parent.width
                            height: parent.height - y
                        }

                        Shade {
                            y: cropLayer.py
                            width: cropLayer.px
                            height: cropLayer.ph
                        }

                        Shade {
                            x: cropLayer.px + cropLayer.pw
                            y: cropLayer.py
                            width: parent.width - x
                            height: cropLayer.ph
                        }

                        // Dragging beside = a new frame
                        MouseArea {
                            property point start

                            anchors.fill: parent
                            cursorShape: Qt.CrossCursor
                            onPressed: (mouse) => {
                                start = Qt.point(mouse.x / win.fit, mouse.y / win.fit);
                            }
                            onPositionChanged: (mouse) => {
                                const cx = Math.max(0, Math.min(mouse.x / win.fit, win.st.rotatedW));
                                const cy = Math.max(0, Math.min(mouse.y / win.fit, win.st.rotatedH));
                                win.draft = win.clampDraft({
                                    "x": Math.min(start.x, cx),
                                    "y": Math.min(start.y, cy),
                                    "w": Math.abs(cx - start.x),
                                    "h": Math.abs(cy - start.y)
                                });
                            }
                        }

                        Rectangle {
                            x: cropLayer.px
                            y: cropLayer.py
                            width: cropLayer.pw
                            height: cropLayer.ph
                            color: "transparent"
                            border.width: 1
                            border.color: "white"

                            // Lines of thirds help with aligning
                            Repeater {
                                model: 4

                                delegate: Rectangle {
                                    required property int index
                                    readonly property bool vertical: index < 2
                                    readonly property real k: (index % 2 + 1) / 3

                                    x: vertical ? parent.width * k : 0
                                    y: vertical ? 0 : parent.height * k
                                    width: vertical ? 1 : parent.width
                                    height: vertical ? parent.height : 1
                                    color: Qt.rgba(1, 1, 1, 0.25)
                                }

                            }

                            // Move the frame
                            MouseArea {
                                property point grab
                                property var from

                                anchors.fill: parent
                                cursorShape: Qt.SizeAllCursor
                                onPressed: (mouse) => {
                                    grab = mapToItem(cropLayer, mouse.x, mouse.y);
                                    from = win.draft;
                                }
                                onPositionChanged: (mouse) => {
                                    const p = mapToItem(cropLayer, mouse.x, mouse.y);
                                    win.draft = win.clampDraft({
                                        "x": from.x + (p.x - grab.x) / win.fit,
                                        "y": from.y + (p.y - grab.y) / win.fit,
                                        "w": from.w,
                                        "h": from.h
                                    });
                                }
                            }

                            // dx/dy: which edge the handle moves (-1 left/top, 1 right/bottom, 0 none)
                            Repeater {
                                model: [
                                    { "dx": -1, "dy": -1, "c": Qt.SizeFDiagCursor },
                                    { "dx": 0, "dy": -1, "c": Qt.SizeVerCursor },
                                    { "dx": 1, "dy": -1, "c": Qt.SizeBDiagCursor },
                                    { "dx": -1, "dy": 0, "c": Qt.SizeHorCursor },
                                    { "dx": 1, "dy": 0, "c": Qt.SizeHorCursor },
                                    { "dx": -1, "dy": 1, "c": Qt.SizeBDiagCursor },
                                    { "dx": 0, "dy": 1, "c": Qt.SizeVerCursor },
                                    { "dx": 1, "dy": 1, "c": Qt.SizeFDiagCursor }
                                ]

                                delegate: Item {
                                    required property var modelData

                                    x: (modelData.dx + 1) / 2 * parent.width - width / 2
                                    y: (modelData.dy + 1) / 2 * parent.height - height / 2
                                    width: 22
                                    height: 22

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 10
                                        height: 10
                                        radius: height / 2
                                        color: "white"
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.5)
                                    }

                                    MouseArea {
                                        property point grab
                                        property var from

                                        anchors.fill: parent
                                        cursorShape: parent.modelData.c
                                        onPressed: (mouse) => {
                                            grab = mapToItem(cropLayer, mouse.x, mouse.y);
                                            from = win.draft;
                                        }
                                        onPositionChanged: (mouse) => {
                                            const p = mapToItem(cropLayer, mouse.x, mouse.y);
                                            const mx = (p.x - grab.x) / win.fit;
                                            const my = (p.y - grab.y) / win.fit;
                                            const dx = parent.modelData.dx;
                                            const dy = parent.modelData.dy;
                                            let left = from.x;
                                            let top = from.y;
                                            let right = from.x + from.w;
                                            let bottom = from.y + from.h;
                                            // The handle stays in the image and cannot overtake the opposite edge
                                            if (dx < 0)
                                                left = Math.max(0, Math.min(left + mx, right - 8));

                                            if (dx > 0)
                                                right = Math.min(win.st.rotatedW, Math.max(right + mx, left + 8));

                                            if (dy < 0)
                                                top = Math.max(0, Math.min(top + my, bottom - 8));

                                            if (dy > 0)
                                                bottom = Math.min(win.st.rotatedH, Math.max(bottom + my, top + 8));

                                            win.draft = win.clampDraft({
                                                "x": left,
                                                "y": top,
                                                "w": right - left,
                                                "h": bottom - top
                                            });
                                        }
                                    }

                                }

                            }

                        }

                    }

                }

                MediaSlide {
                    id: slide

                    anchors.fill: parent
                    source: holder
                }

                // Pen preview: outside of stage, so it is never exported
                Rectangle {
                    visible: penArea.containsMouse && win.tool === "draw"
                    x: penArea.viewPos.x - width / 2
                    y: penArea.viewPos.y - height / 2
                    width: Math.max(4, win.penSize)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: win.penColor
                }

                // Zoom level (pixels of the original per screen pixel), only while zoomed
                ZoomBadge {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    shown: zoomer.zoomed
                    percent: win.fit * zoomer.zoom * 100
                }

            }

            // ---------- Folder browser (B / folder button) ----------
            MediaBrowser {
                id: browser

                objectName: "mediaBrowser"
                anchors.fill: parent
                currentPath: win.st.shownPath
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

            // ---------- Other images in the folder ----------
            MediaStrip {
                id: strip

                x: 20
                y: 20
                height: parent.height - 40
                targetHeight: (win.enlarged ? card.bigH : card.normalH) - 40
                visible: win.browsing
                paths: win.st.gallery
                currentIndex: win.st.currentIndex
                currentPath: win.st.imagePath
                sourceFor: (path) => {
                    return win.st.fileUrl(path);
                }
                unsavedFor: (path) => {
                    return win.st.isUnsaved(path);
                }
                onPicked: (path) => {
                    win.showImage(path);
                }
            }

            GlassButton {
                id: prevArrow

                x: viewport.x - win.arrowGutter + (win.arrowGutter - width) / 2
                y: viewport.y + (viewport.height - height) / 2
                visible: win.browsing
                glyph: "\uf053"
                dimmed: win.st.currentIndex <= 0
                onClicked: win.stepImage(-1)
            }

            GlassButton {
                x: viewport.x + viewport.width + (win.arrowGutter - width) / 2
                y: viewport.y + (viewport.height - height) / 2
                visible: win.browsing
                glyph: "\uf054"
                dimmed: win.st.currentIndex >= win.st.gallery.length - 1
                onClicked: win.stepImage(1)
            }

            // ---------- Sidebar (iOS style, built the same as in the video editor) ----------
            // Header (file, undo, close), tools in grouped cards (scroll if there is not
            // enough room), fixed at the bottom: main action "Save" and the side actions as a list.
            EditorSidePanel {
                id: side

                shownK: 1 - win.enlargeK
                enabled: !win.enlarged
                backColor: card.color
                header.kind: win.st.folderMode ? "Image" : "Screenshot"
                header.glyph: win.st.folderMode ? "" : ""
                header.fileName: win.st.folderMode ? win.st.shownPath.substring(win.st.shownPath.lastIndexOf("/") + 1) : ""
                header.index: win.st.currentIndex
                header.count: win.st.gallery.length
                header.mediaW: win.st.imageW
                header.mediaH: win.st.imageH
                headerActions: [
                    GlassButton {
                        size: Theme.px(30)
                        glyph: ""
                        dimmed: !win.st.canUndo
                        onClicked: win.undo()
                    },
                    GlassButton {
                        size: Theme.px(30)
                        glyph: ""
                        dimmed: !win.st.canRedo
                        onClicked: win.redo()
                    },
                    // Folder browser: other folders, subfolders, images and videos mixed (key B)
                    GlassButton {
                        size: Theme.px(30)
                        glyph: "\uf07c"
                        visible: win.st.folderMode
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
                    IosGroup {
                        width: parent.width
                        title: "Tool"
                        plain: true

                        IosSegmented {
                            width: parent.width
                            items: [{
                                "glyph": "",
                                "text": "Draw"
                            }, {
                                "glyph": "",
                                "text": "Crop"
                            }]
                            currentIndex: win.tool === "crop" ? 1 : 0
                            onActivated: (i) => {
                                return win.setTool(i === 1 ? "crop" : "draw");
                            }
                        }

                    },
                    IosGroup {
                        width: parent.width
                        title: "Pen"
                        inset: Theme.px(12)
                        visible: win.tool === "draw"

                        Row {
                            spacing: Theme.px(10)

                            Repeater {
                                // Paint colors are content, not UI: deliberately fixed and not from pywal
                                model: ["#e5484d", "#f5a524", "#46a758", "#3e8ed0", "#a56de2", "#ffffff", "#111111"]

                                delegate: Item {
                                    required property string modelData
                                    readonly property bool selected: Qt.colorEqual(win.penColor, modelData)

                                    width: Theme.px(26)
                                    height: width

                                    // Selection as a ring with a gap, like the color picker on iOS
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Theme.text
                                        opacity: parent.selected ? 1 : 0

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: Appearance.anim.durations.fast
                                            }

                                        }

                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.selected ? parent.width - 8 : parent.width - 2
                                        height: width
                                        radius: width / 2
                                        color: parent.modelData
                                        border.width: 1
                                        border.color: Theme.separator

                                        Behavior on width {
                                            NumberAnimation {
                                                duration: Appearance.anim.durations.fast
                                            }

                                        }

                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.penColor = parent.modelData
                                    }

                                }

                            }

                        }

                        ValueSlider {
                            width: parent.width
                            label: "Size"
                            from: 2
                            to: 30
                            value: win.penSize
                            valueText: Math.round(win.penSize) + " px"
                            onMoved: (v) => {
                                win.penSize = v;
                            }
                        }

                    },
                    IosGroup {
                        width: parent.width
                        title: "Crop"
                        visible: win.cropping
                        footer: "Drag the frame or its corners. Enter applies, Esc cancels."

                        IosRow {
                            divider: false
                            glyph: ""
                            title: "Size"
                            trailing: Math.round(win.draft.w) + " × " + Math.round(win.draft.h) + " px"
                        }

                    },
                    IosGroup {
                        width: parent.width
                        title: "Rotate"

                        RotatePair {
                            width: parent.width
                            onRotateLeft: win.rotate(-90)
                            onRotateRight: win.rotate(90)
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
                        onActionClicked: {
                            win.st.resetAll();
                            if (win.cropping)
                                win.draft = win.st.rotatedCrop();

                        }

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
                            if (win.confirmDiscard)
                                return "Close again to discard all changes";

                            if (win.confirmOverwrite)
                                return "Replaces the original file. This can't be undone.";

                            return "";
                        }
                        color: Theme.warn
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    },
                    // File from the folder: copy next to it. Screenshot: to ~/Pictures/Screenshots
                    IosButton {
                        id: saveButton

                        width: parent.width
                        glyph: ""
                        text: win.st.folderMode ? "Save Copy" : "Save"
                        onClicked: win.exportAs("save")

                        // Saved (folder mode; a fresh screenshot closes the editor, there the notification
                        // confirms): star at the button
                        Connections {
                            target: win.st

                            function onSaved(overwrite) {
                                saveButton.confirm(overwrite ? "Original replaced" : "Saved");
                            }
                        }
                    },
                    IosGroup {
                        width: parent.width

                        EditorActionSlot {
                            onRequested: win.sendToAction()
                        }

                        IosRow {
                            divider: Addons.editorAction !== null && Addons.editorAction.available
                            glyph: ""
                            title: "Copy to Clipboard"
                            onClicked: win.exportAs("copy")
                        }

                        IosRow {
                            visible: win.st.folderMode
                            glyph: ""
                            title: win.confirmOverwrite ? "Click Again to Overwrite" : "Overwrite Original"
                            tone: Theme.bad
                            dimmed: !win.st.canOverwrite
                            onClicked: win.requestOverwrite()
                        }

                        IosRow {
                            visible: win.st.folderMode
                            glyph: ""
                            title: win.confirmDelete ? "Click Again to Move to Trash" : "Delete"
                            tone: Theme.bad
                            onClicked: win.requestDelete()
                        }

                    }
                ]
            }

            // Right next to the top right image corner: on the image it disturbed painting and cropping.
            // With very flat images it keeps a distance to the arrow sitting next to it at half height
            GlassButton {
                x: viewport.x + holder.x + holder.width + 8
                y: Math.min(viewport.y + holder.y, viewport.y + viewport.height / 2 - prevArrow.height / 2 - 8 - height)
                size: Theme.px(30)
                glyph: win.enlarged ? "\uf066" : "\uf065"
                active: win.enlarged
                onClicked: win.enlarged = !win.enlarged
            }

            // The hints from the tool column: shortcuts ask in the big view too
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                x: viewport.x
                width: viewport.width
                visible: win.enlarged && text !== ""
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: {
                    if (win.confirmDelete)
                        return "Press Del again to move to trash";

                    if (win.confirmOverwrite)
                        return "Press again to replace the original. This can't be undone.";

                    if (win.cropping)
                        return Math.round(win.draft.w) + " × " + Math.round(win.draft.h) + " px · Enter applies, Esc cancels";

                    return "";
                }
                color: win.cropping && !win.confirmDelete && !win.confirmOverwrite ? Theme.textDim : Theme.warn
                font.family: Theme.font
                font.pixelSize: Theme.sizeSmall
            }

        }

    }

    component Shade: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.6)
    }

    // Image slider (-100..100 %, double click = back to 0). Undo: one step per drag
    component AdjustSlider: ValueSlider {
        id: adj

        property string prop: ""
        property var before: null

        from: -1
        to: 1
        zeroAt: 0
        value: ScreenshotEditorState[prop]
        valueText: (value > 0 ? "+" : "") + Math.round(value * 100)
        onMoved: (v) => {
            // Snap at 0: otherwise the neutral position is hard to hit with the mouse
            ScreenshotEditorState[prop] = Math.abs(v) < 0.03 ? 0 : v;
        }
        onGrabbed: before = ScreenshotEditorState.snapshot()
        onReleased: {
            if (before && before[prop] !== ScreenshotEditorState[prop])
                ScreenshotEditorState.pushUndo(before);

            before = null;
        }
        onDoubleClicked: {
            ScreenshotEditorState.pushUndo();
            ScreenshotEditorState[prop] = 0;
        }
    }

}
