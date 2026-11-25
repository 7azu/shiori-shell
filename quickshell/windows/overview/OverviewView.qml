import "../../common"
import "../../services"
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Content of the workspace overview: state, layout, opening/closing, keys, drag and drop.
// Deliberately separate from the PanelWindow (windows/WorkspaceOverview.qml), so tools/overview-shot can render
// the same view in an invisible test instance and check it frame by frame.
//
Item {
    id: view

    // Monitor the overview lies on (aspect ratio of the cards, monitor name on foreign cards)
    property var monitor: null
    // Screen captures only run while the view is really visible (otherwise the DMA buffers are free)
    property bool capturing: false
    property int previewSlots: 0
    readonly property string moveScript: Qt.resolvedUrl("../../scripts/hypr_move_window.sh").toString().replace("file://", "")
    // closed -> opening -> open -> switching/closing -> closed
    property string phase: "closed"
    readonly property bool shown: phase !== "closed"
    readonly property bool interactive: phase === "opening" || phase === "open"
    readonly property var slotIds: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    readonly property int columns: board.columns
    // The card with the workspaces and the desktop cover fade independently.
    property real reveal: 0
    property real dim: 0
    property real slowMo: 1
    property int originWorkspaceId: -1
    readonly property bool targetWorkspaceFocused: pendingWs > 0 && workspaceHasFocus(pendingWs)
    property int focusReleaseFrames: 0

    signal workspaceHandoff()
    // ==== Selection / drag ====
    property int selectedId: -1
    property int dropTargetId: -1
    property var dragWin: null
    property int dragFromId: -1
    property point dragPos: Qt.point(0, 0)
    property string dragAddress: ""
    property real dragAspect: 1
    property string dragIcon: ""
    property int dragGeneration: 0
    property var pendingDrop: null
    property real dropProgress: 0
    readonly property bool dropArrived: !!pendingDrop
        && windowsOn(pendingDrop.to).some(win => String(win.address) === dragAddress)
    readonly property var dragSnapshot: snapshots[dragAddress] ?? null
    // Hover = selection, but only on a real mouse move (>= 3 px), as in the pickers: a resting pointer
    // should not overwrite the keyboard selection when opening. x < 0 = only remember the next move.
    property point lastPointer: Qt.point(-1, -1)
    // Address -> still image (ItemGrabResult) of the preview at the start of a drag. The preview in the target card
    // shows it until the new capture delivers frames (see WindowThumb), otherwise it would be empty at first
    property var snapshots: ({
    })
    // Run after closing (focus the window / switch the workspace)
    property var pendingWin: null
    property int pendingWs: -1

    // ================= Data =================
    function workspaceById(id) {
        return Hyprland.workspaces.values.find((w) => {
            return w.id === id;
        }) ?? null;
    }

    // Real, visible windows of a workspace. Without IPC data (just created) it counts too.
    readonly property var ignoredClasses: ["xwaylandvideobridge", "ueberzug"]

    function windowsOn(id) {
        return Hyprland.toplevels.values.filter((t) => {
            if (!t.workspace || t.workspace.id !== id)
                return false;

            const o = t.lastIpcObject;
            if (o && (o.mapped === false || o.hidden === true))
                return false;

            const cls = String((t.wayland ? t.wayland.appId : "") || (o ? o["class"] || "" : "")).toLowerCase();
            return !ignoredClasses.some((c) => {
                return cls.indexOf(c) >= 0;
            });
        });
    }

    // Logical rectangle of a monitor in the Hyprland layout (rotated + scaled), null without data
    function monitorGeom(m) {
        const o = m ? m.lastIpcObject : null;
        if (!o || !(o.width > 0) || !(o.height > 0))
            return null;

        const sc = o.scale > 0 ? o.scale : 1;
        const rotated = (o.transform ?? 0) % 2 === 1;
        return {
            "id": o.id,
            "x": o.x ?? 0,
            "y": o.y ?? 0,
            "w": (rotated ? o.height : o.width) / sc,
            "h": (rotated ? o.width : o.height) / sc
        };
    }

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    // ================= Opening / closing =================
    function toggle() {
        if (interactive)
            dismiss();
        else
            show();
    }

    function show(m) {
        if (interactive || phase === "switching" || pendingWs > 0)
            return;

        closeAnim.stop();
        focusAfterClose.stop();
        if (!shown) {
            const mon = m ?? Hyprland.focusedMonitor;
            const ws = mon?.activeWorkspace ?? Hyprland.focusedWorkspace;
            originWorkspaceId = ws?.id ?? -1;
            selectedId = slotIds.includes(originWorkspaceId) ? originWorkspaceId : slotIds[0];
            reveal = 0;
            dim = 0;
            previewSlots = 1;
        }
        pendingWin = null;
        lastPointer = Qt.point(-1, -1);
        phase = "opening";
        openAnim.start();
    }

    function dismiss() {
        if (!interactive)
            return;

        resetDrag();
        openAnim.stop();
        phase = "closing";
        closeAnim.start();
    }

    function go(wsId, win) {
        if (phase !== "open" || wsId < 1 || dragAddress)
            return;

        pendingWin = win ?? null;
        selectedId = wsId;
        if (wsId === originWorkspaceId) {
            dismiss();
            return;
        }

        pendingWs = wsId;
        resetDrag();
        openAnim.stop();
        phase = "switching";
        workspaceHandoff();
        focusReleaseFrames = 2;
        focusReleaseTimeout.restart();
        coverAnim.start();
    }

    function switchWorkspace() {
        if (focusReleaseFrames === 0)
            return;

        focusReleaseFrames = 0;
        focusReleaseTimeout.stop();
        switchTimeout.start();
        if (pendingWin)
            focusWindow(pendingWin);
        else
            focusWorkspace(pendingWs);
        if (targetWorkspaceFocused && switchTimeout.running)
            revealWorkspace();
    }

    function revealWorkspace() {
        switchTimeout.stop();
        phase = "closing";
        uncoverAnim.start();
    }

    function finishClose() {
        const win = pendingWin && !windowHasFocus(pendingWin) ? pendingWin : null;
        const ws = pendingWs > 0 && !targetWorkspaceFocused ? pendingWs : -1;
        pendingWin = null;
        pendingWs = -1;
        phase = "closed";
        if (win || ws > 0) {
            focusAfterClose.targetWindow = win;
            focusAfterClose.targetWorkspace = ws;
            focusAfterClose.restart();
        }
    }

    onTargetWorkspaceFocusedChanged: {
        if (targetWorkspaceFocused && switchTimeout.running)
            revealWorkspace();
    }

    // First hand the layer surface to Hyprland without exclusive keyboard focus.
    Connections {
        target: view.Window.window
        enabled: view.focusReleaseFrames > 0
        function onFrameSwapped() {
            if (view.focusReleaseFrames === 1)
                view.switchWorkspace();
            else if (view.focusReleaseFrames > 1)
                view.focusReleaseFrames--;
        }
    }

    Timer {
        id: focusReleaseTimeout
        interval: 65
        onTriggered: view.switchWorkspace()
    }

    // In case the compositor only releases the focus after hiding, set it once more.
    Timer {
        id: focusAfterClose
        property var targetWindow: null
        property int targetWorkspace: -1
        interval: 34
        onTriggered: {
            if (targetWindow && !view.windowHasFocus(targetWindow))
                view.focusWindow(targetWindow);
            else if (targetWorkspace > 0 && !view.workspaceHasFocus(targetWorkspace))
                view.focusWorkspace(targetWorkspace);
            targetWindow = null;
            targetWorkspace = -1;
        }
    }

    ParallelAnimation {
        id: openAnim
        onFinished: {
            view.phase = "open";
            view.refresh();
        }

        NumberAnimation {
            target: view
            property: "reveal"
            to: 1
            duration: 370 * view.slowMo
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.24, 0.77, 0.28, 1, 1, 1]
        }

        NumberAnimation {
            target: view
            property: "dim"
            to: 1
            duration: 300 * view.slowMo
            easing.type: Easing.OutCubic
        }
    }

    // When fading in, start at most one more occupied card per frame.
    Timer {
        interval: 16
        running: view.interactive && view.previewSlots < view.slotIds.length
        repeat: true
        onTriggered: {
            let next = view.previewSlots;
            do {
                next++;
            } while (next < view.slotIds.length && !board.cardFor(board.previewOrder[next - 1])?.wins.length);
            view.previewSlots = next;
        }
    }

    NumberAnimation {
        id: coverAnim

        target: view
        property: "reveal"
        to: 0
        duration: 195 * view.slowMo
        easing.type: Easing.InOutCubic
    }

    NumberAnimation {
        id: uncoverAnim

        target: view
        property: "dim"
        to: 0
        duration: 220 * view.slowMo
        easing.type: Easing.InOutCubic
        onFinished: view.finishClose()
    }

    ParallelAnimation {
        id: closeAnim
        onFinished: view.finishClose()

        NumberAnimation {
            target: view
            property: "reveal"
            to: 0
            duration: 235 * view.slowMo
            easing.type: Easing.InOutCubic
        }

        NumberAnimation {
            target: view
            property: "dim"
            to: 0
            duration: 280 * view.slowMo
            easing.type: Easing.InOutCubic
        }
    }

    Timer {
        id: switchTimeout
        interval: 300
        onTriggered: view.revealWorkspace()
    }

    // ================= Hyprland actions =================
    function workspaceHasFocus(id) {
        return Hyprland.focusedWorkspace?.id === id;
    }

    function windowHasFocus(win) {
        return Hyprland.activeToplevel === win;
    }

    // Hyprland with the Lua config no longer understands `hyprctl dispatch workspace N` (it is read as Lua);
    // the new form is hl.dsp.focus({ workspace = "N" }). If Hyprland does not answer "ok" (old hyprlang config),
    // the old syntax is used.
    function focusWorkspace(id) {
        const n = String(parseInt(id));
        if (n === "NaN")
            return ;

        Quickshell.execDetached(["bash", "-c", "out=$(hyprctl dispatch \"hl.dsp.focus({ workspace = \\\"$1\\\" })\" 2>&1); " + "[ \"$out\" = ok ] || hyprctl dispatch workspace \"$1\"", "_", n]);
    }

    function addressOf(win) {
        const raw = String(win.address);
        return raw.startsWith("0x") ? raw : "0x" + raw;
    }

    // foreign-toplevel first (also focuses on other workspaces), otherwise by address
    function focusWindow(win) {
        if (!win)
            return ;

        if (win.wayland)
            win.wayland.activate();
        else
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + addressOf(win) + "\" })"]);
    }

    function closeWindow(win) {
        if (!win)
            return ;

        if (win.wayland)
            win.wayland.close();
        else
            Quickshell.execDetached(["bash", "-c", "out=$(hyprctl dispatch \"$1\" 2>&1); [ \"$out\" = ok ] || hyprctl dispatch closewindow \"$2\"", "_", "hl.dsp.window.close({ window = \"address:" + addressOf(win) + "\" })", "address:" + addressOf(win)]);
        refreshTimer.restart();
    }

    function moveWindow(win, wsId) {
        if (!win || !win.address)
            return ;

        Quickshell.execDetached(["bash", moveScript, String(win.address), String(wsId)]);
        refreshTimer.restart();
    }

    // Window sizes are only in lastIpcObject and are only fetched again on request.
    // On events that change the layout, check again bundled (also when closed: then
    // the previews are already right in the first frame of the next opening).
    readonly property var layoutEvents: /^(openwindow|closewindow|movewindow|changefloatingmode|fullscreen|togglegroup|moveintogroup|moveoutofgroup|createworkspace|destroyworkspace|moveworkspace|monitoradded|monitorremoved|configreloaded)/

    Connections {
        function onRawEvent(event) {
            if (view.layoutEvents.test(event.name))
                refreshTimer.restart();

        }

        target: Hyprland
    }

    Timer {
        id: refreshTimer

        interval: 120
        onTriggered: view.refresh()
    }

    // ================= Selection, keys, drag =================
    function pointerMoved(p, wsId) {
        if (lastPointer.x < 0) {
            lastPointer = p;
            return ;
        }
        if (Math.abs(p.x - lastPointer.x) < 3 && Math.abs(p.y - lastPointer.y) < 3)
            return ;

        lastPointer = p;
        if (wsId > 0 && interactive && !dragWin)
            selectedId = wsId;

    }

    function moveSelection(step) {
        const i = Math.max(0, slotIds.indexOf(selectedId));
        const n = i + step;
        if (n >= 0 && n < slotIds.length)
            selectedId = slotIds[n];

        lastPointer = Qt.point(-1, -1);
    }

    function handleKey(event) {
        const key = PickerManager.navKey(event);
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        event.accepted = true;
        if (key === Qt.Key_Escape) {
            if (dragWin)
                resetDrag();
            else
                dismiss();
        } else if (key === Qt.Key_Left || (ctrl && event.key === Qt.Key_H)) {
            moveSelection(-1);
        } else if (key === Qt.Key_Right || (ctrl && event.key === Qt.Key_L)) {
            moveSelection(1);
        } else if (key === Qt.Key_Up) {
            moveSelection(-columns);
        } else if (key === Qt.Key_Down) {
            moveSelection(columns);
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            go(selectedId, null);
        } else if (key >= Qt.Key_0 && key <= Qt.Key_9) {
            // 1..9 and 0 = 10, like the workspace keys
            go(key === Qt.Key_0 ? 10 : key - Qt.Key_0, null);
        } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
            // No tabs: just swallow
        } else {
            event.accepted = false;
        }
    }

    function beginDrag(win, fromId, p, shot, appId) {
        if (phase !== "open" || dragAddress || !win)
            return false;

        const generation = ++dragGeneration;
        const addr = String(win.address);
        const size = win.lastIpcObject?.size;
        if (shot && shot.hasContent) {
            shot.grabToImage((result) => {
                if (!view.shown || view.dragGeneration !== generation)
                    return;
                const next = Object.assign({}, view.snapshots);
                next[addr] = result;
                view.snapshots = next;
            });
        }

        dragAspect = size && size[0] > 0 && size[1] > 0 ? size[0] / size[1] : 16 / 10;
        dragIcon = appId;
        dragAddress = addr;
        dragWin = win;
        dragFromId = fromId;
        updateDrag(p);
        return true;
    }

    function updateDrag(p) {
        if (!dragAddress || pendingDrop)
            return;

        dragPos = p;
        const id = board.workspaceAt(p);
        dropTargetId = id === dragFromId ? -1 : id;
        selectedId = id > 0 ? id : dragFromId;
    }

    function endDrag(p) {
        if (!dragAddress || pendingDrop)
            return;

        updateDrag(p);
        if (dropTargetId <= 0) {
            resetDrag();
            return;
        }

        const target = board.cardFor(dropTargetId);
        pendingDrop = {
            to: dropTargetId,
            center: target.mapToItem(view, target.width / 2, target.previewHeight / 2)
        };
        dropProgress = 0;
        dropTimeout.restart();
        dropAnim.start();
        moveWindow(dragWin, pendingDrop.to);
        moveLayoutTimer.restart();
    }

    function resetDrag() {
        dropAnim.stop();
        dropTimeout.stop();
        ++dragGeneration;
        pendingDrop = null;
        dragWin = null;
        dragAddress = "";
        dragFromId = -1;
        dropTargetId = -1;
        dropProgress = 0;
    }

    onDropArrivedChanged: {
        if (dropArrived && !dropAnim.running)
            resetDrag();
    }

    NumberAnimation {
        id: dropAnim
        target: view
        property: "dropProgress"
        to: 1
        duration: 245
        easing.type: Easing.OutCubic
        onFinished: {
            if (view.dropArrived)
                view.resetDrag();
        }
    }

    Timer {
        id: dropTimeout
        interval: 750
        onTriggered: view.resetDrag()
    }

    Timer {
        id: moveLayoutTimer
        interval: 720
        onTriggered: view.refresh()
    }

    onShownChanged: {
        if (!shown) {
            previewSlots = 0;
            snapshots = {};
        }
    }
    focus: true
    Keys.onPressed: (event) => {
        return view.handleKey(event);
    }

    // Fade the background over the desktop as one single surface.
    OverviewBackdrop {
        anchors.fill: parent
        opacity: view.dim
        visible: opacity > 0.001
    }

    // A click outside the workspace area = close
    MouseArea {
        anchors.fill: parent
        enabled: view.interactive
        hoverEnabled: true
        onClicked: view.dismiss()
        onPositionChanged: (mouse) => {
            return view.pointerMoved(Qt.point(mouse.x, mouse.y), -1);
        }
    }

    OverviewBoard {
        id: board
        view: parent
    }

    // A still image with a fixed aspect ratio follows the pointer into the target card.
    Item {
        id: ghost

        readonly property real maxEdge: Math.min(board.cardWidth * 0.7, MachineConfig.px(235))
        readonly property real targetScale: 1 - 0.44 * view.dropProgress
        readonly property point center: view.pendingDrop
            ? Qt.point(view.dragPos.x + (view.pendingDrop.center.x - view.dragPos.x) * view.dropProgress,
                       view.dragPos.y + (view.pendingDrop.center.y - view.dragPos.y) * view.dropProgress)
            : view.dragPos

        visible: view.dragAddress !== ""
        width: Math.round(maxEdge * Math.min(1, view.dragAspect))
        height: Math.round(maxEdge / Math.max(1, view.dragAspect))
        scale: targetScale
        x: center.x - width / 2
        y: center.y - height / 2
        opacity: view.pendingDrop ? 1 - view.dropProgress : 1
        z: 100

        SoftShadow {
            radius: Theme.radiusXS
            raised: true
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXS
            color: WalColors.color0
        }

        Image {
            anchors.fill: parent
            anchors.margins: 3
            source: view.dragSnapshot?.url ?? ""
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        AppIcon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.35
            height: width
            visible: !view.dragSnapshot
            icon: view.dragIcon.toLowerCase()
            name: view.dragIcon
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXS
            color: "transparent"
            border.width: 2
            border.color: view.dropTargetId > 0 ? WalColors.color2 : WalColors.color4
        }
    }
}
