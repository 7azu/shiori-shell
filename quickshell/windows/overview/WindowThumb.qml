import "../../common"
import "../../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// A window in its workspace card, at its real position and size (from lastIpcObject).
// Click = focus the window, middle = close, drag = put it on another workspace.
Item {
    id: thumb

    required property var card
    required property var modelData
    required property int index
    readonly property var view: card.view
    readonly property var win: modelData
    readonly property var ipc: win ? win.lastIpcObject : null
    readonly property string address: win ? String(win.address) : ""
    readonly property bool geometryReady: (!ipc?.workspace || ipc.workspace.id === card.wsId)
        && (ipc?.monitor === undefined || card.geom?.id === undefined || ipc.monitor === card.geom.id)
    readonly property var r: card.normRect(geometryReady ? ipc : null, index, card.wins.length)
    readonly property bool landing: address !== "" && address === view.dragAddress && view.pendingDrop?.to === card.wsId
    readonly property bool floating: !!ipc && ipc.floating === true
    readonly property bool fullscreen: !!ipc && (ipc.fullscreen ?? 0) > 0
    readonly property bool dragging: address !== "" && address === view.dragAddress && card.wsId === view.dragFromId
    readonly property bool hot: view.interactive && pointer.containsMouse && view.dragAddress === ""
    readonly property string appId: String((win && win.wayland ? win.wayland.appId : "") || (ipc ? ipc["class"] || "" : ""))
    readonly property var entry: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
    // Window rounding from Hyprland, scaled down with the card
    readonly property real radius: Math.max(2, Theme.radiusS * width / Math.max(1, card.geom ? card.geom.w * r.w : width))
    property bool recapturing: false
    readonly property bool canCapture: view.capturing && card.previewsEnabled && geometryReady
    readonly property var snap: view.snapshots[address] ?? null
    readonly property bool captureReady: canCapture && shot.hasContent && !recapturing && matchesWindowAspect()
    // Only animate the normalized window geometry, so the preview stays in the card.
    property real nx: r.x
    property real ny: r.y
    property real nw: r.w
    property real nh: r.h

    x: nx * parent.width
    y: ny * parent.height
    width: Math.max(4, nw * parent.width)
    height: Math.max(4, nh * parent.height)
    // Fullscreen above floating above tiled, as in Hyprland
    z: fullscreen ? 3 : (floating ? 2 : 1)
    opacity: landing ? Math.max(0, Math.min(1, (view.dropProgress - 0.45) / 0.55)) : 1

    function matchesWindowAspect() {
        const size = ipc?.size;
        const capture = shot.sourceSize;
        if (!snap || !size || size[0] <= 0 || size[1] <= 0 || capture.width <= 0 || capture.height <= 0)
            return true;

        return Math.abs(Math.log(capture.width * size[1] / (capture.height * size[0]))) < 0.25;
    }
    // New capture session (captureFrame() is not enough: a hanging session delivers nothing even then)
    function restartCapture() {
        recapturing = true;
        Qt.callLater(() => {
            thumb.recapturing = false;
        });
    }

    // If the window is closed or moved during the drag, cancel the drag
    Component.onDestruction: {
        if (thumb.dragging && !thumb.view.pendingDrop)
            thumb.view.resetDrag();

    }

    Rectangle {
        anchors.fill: parent
        radius: thumb.radius
        color: Qt.tint(thumb.card.surfaceColor, WalColors.withAlpha(WalColors.color7, 0.035))
    }

    // The still image stays visible until the preview really delivers a frame.
    Image {
        anchors.fill: parent
        source: thumb.snap ? thumb.snap.url : ""
        fillMode: Image.PreserveAspectFit
        visible: !!thumb.snap && !thumb.dragging && (!thumb.captureReady || captureLayer.opacity < 0.99)
    }

    Item {
        id: captureLayer
        anchors.fill: parent
        opacity: thumb.captureReady ? (thumb.dragging ? 0.28 : 1) : 0

        ScreencopyView {
            id: shot
            anchors.fill: parent
            live: thumb.canCapture
            captureSource: thumb.canCapture && !thumb.recapturing ? (thumb.win?.wayland ?? null) : null
        }

        Behavior on opacity {
            NumberAnimation { duration: thumb.snap ? 160 : 115; easing.type: Easing.OutCubic }
        }
    }

    Timer {
        id: captureRetry
        property int tries: 0

        interval: 550
        repeat: true
        running: thumb.canCapture && !!thumb.win?.wayland && !thumb.captureReady && !thumb.recapturing && tries < 3
        onTriggered: {
            tries++;
            thumb.restartCapture();
        }

    }

    Connections {
        target: thumb.view
        function onCapturingChanged() {
            if (!thumb.view.capturing)
                captureRetry.tries = 0;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: thumb.radius
        color: thumb.hot ? WalColors.withAlpha("#ffffff", 0.06) : "transparent"
        border.width: thumb.hot ? 2 : 1
        border.color: thumb.hot ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.09)

        Behavior on border.color {
            ColorAnimation {
                duration: 120
            }

        }

    }

    // App icon: with small previews you hardly recognize the window otherwise
    AppIcon {
        readonly property real size: Math.min(MachineConfig.px(34), Math.min(thumb.width, thumb.height) * 0.34)

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.min(MachineConfig.px(8), thumb.height * 0.1)
        width: size
        height: size
        visible: size >= MachineConfig.px(12) && opacity > 0
        icon: thumb.entry && thumb.entry.icon ? thumb.entry.icon : thumb.appId.toLowerCase()
        name: thumb.entry ? thumb.entry.name : thumb.appId
        opacity: thumb.hot ? 0 : (thumb.dragging ? 0.3 : 0.92)
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Title on hover
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Math.min(MachineConfig.px(4), thumb.width * 0.04)
        height: titleText.implicitHeight + MachineConfig.px(6)
        radius: Theme.radiusXS
        color: WalColors.withAlpha(WalColors.color0, 0.85)
        visible: opacity > 0
        opacity: thumb.hot && thumb.height > MachineConfig.px(34) ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
        }

        Text {
            id: titleText

            anchors.fill: parent
            anchors.leftMargin: MachineConfig.px(6)
            anchors.rightMargin: MachineConfig.px(6)
            text: thumb.win && thumb.win.title ? thumb.win.title : (thumb.appId || "Untitled")
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
            elide: Text.ElideRight
            maximumLineCount: 1
            verticalAlignment: Text.AlignVCenter
        }

    }

    MouseArea {
        id: pointer

        property bool moved: false
        property point pressPos: Qt.point(0, 0)

        anchors.fill: parent
        enabled: thumb.view.phase === "open"
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: thumb.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        onPressed: (ev) => {
            pressPos = mapToItem(thumb.view, ev.x, ev.y);
            moved = false;
        }
        onPositionChanged: (ev) => {
            const p = mapToItem(thumb.view, ev.x, ev.y);
            if (!pressed || !(pressedButtons & Qt.LeftButton)) {
                thumb.view.pointerMoved(p, thumb.card.wsId);
                return ;
            }
            // Only from 8 px on it is a drag, below that a click
            if (!moved && Math.hypot(p.x - pressPos.x, p.y - pressPos.y) > 8)
                moved = thumb.view.beginDrag(thumb.win, thumb.card.wsId, p, shot, thumb.appId);
            if (moved)
                thumb.view.updateDrag(p);

        }
        onReleased: (ev) => {
            if (moved) {
                thumb.view.endDrag(mapToItem(thumb.view, ev.x, ev.y));
            } else if (ev.button === Qt.MiddleButton) {
                thumb.view.closeWindow(thumb.win);
            } else if (ev.button === Qt.LeftButton) {
                thumb.view.go(thumb.card.wsId, thumb.win);
            }
            moved = false;
        }
        onCanceled: {
            if (moved && !thumb.view.pendingDrop)
                thumb.view.resetDrag();
            moved = false;
        }
    }

    // Close button at the top right on hover
    Rectangle {
        id: closeBtn

        readonly property bool hotBtn: thumb.view.interactive && closeMouse.containsMouse

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: MachineConfig.px(5)
        width: MachineConfig.px(22)
        height: width
        radius: height / 2
        color: hotBtn ? Theme.bad : WalColors.withAlpha(WalColors.color0, 0.85)
        border.width: 1
        border.color: hotBtn ? Theme.bad : WalColors.withAlpha(WalColors.color7, 0.25)
        opacity: (thumb.hot || hotBtn) && thumb.width > MachineConfig.px(48) ? 1 : 0
        visible: opacity > 0.01
        scale: hotBtn ? 1.12 : 1

        Text {
            anchors.centerIn: parent
            text: "󰅖"
            font.family: Theme.font
            font.pixelSize: MachineConfig.px(12)
            color: closeBtn.hotBtn ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.85)
        }

        MouseArea {
            id: closeMouse

            anchors.fill: parent
            enabled: thumb.view.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: thumb.view.closeWindow(thumb.win)
        }

        Behavior on opacity {
            Anim {
                duration: 140
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }

        }

    }

    Behavior on nx {
        enabled: thumb.view.phase === "open"

        Smooth {
        }

    }

    Behavior on ny {
        enabled: thumb.view.phase === "open"

        Smooth {
        }

    }

    Behavior on nw {
        enabled: thumb.view.phase === "open"

        Smooth {
        }

    }

    Behavior on nh {
        enabled: thumb.view.phase === "open"

        Smooth {
        }

    }

}
