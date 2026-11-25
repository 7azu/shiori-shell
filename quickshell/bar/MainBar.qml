import "../services"
import "../common/Format.js" as Fmt
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: panelWindow

    // For EditBadge (bar/EditBadge.qml): commit a still pending order before a new drag
    property alias commitTimer: commitTimer
    property bool calendarOpen: false
    property bool monitorsOpen: false
    // Target of the morph ("calendar" | "monitors"); stays while collapsing,
    // so the shape does not jump in the middle of the animation.
    property string panelKind: "calendar"
    // Notification center: the state lives in NotificationState (toasts/shortcut also open it)
    readonly property bool notifOpen: NotificationState.centerOpen
    // true = the bar was hidden and was only shown for the center
    property bool notifShowedBar: false
    // The same for the calendar by shortcut (SUPER+K)
    property bool calShowedBar: false
    readonly property bool panelOpen: calendarOpen || monitorsOpen || notifOpen
    property bool startupDone: false
    // Sliding the bar in/out: 0 = above out of the picture, 1 = there. Only moved, not faded. The surface
    // stays meanwhile (before margins.top was animated = a layer reconfigure per frame), the content glides
    // inside it and is clipped at the top window edge. Only after startupFix: during the redraw trick
    // the bar stands almost invisible at its place, afterwards it slides in from the top.
    property real barSlide: (BarState.barVisible && startupDone) ? 1 : 0
    // + 28: the shadow below the shape (offset 3 + blur 19) should go out of the picture too
    readonly property real barSlideY: startupDone ? -(1 - barSlide) * (shapeH + 28) : 0
    property real morph: panelOpen ? 1 : 0
    property bool drawerOpen: false
    // Edit mode (right-click the logo): all icons visible, click = on/off
    property bool editMode: false
    property real editReveal: editMode ? 1 : 0
    property bool drawerWasOpen: false
    property real revealT: drawerOpen ? 1 : 0
    property date now: new Date()
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property date selectedDate: new Date()
    property string selectedKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property string todayKey: Qt.formatDate(now, "yyyy-MM-dd")
    readonly property real barHeight: 40
    readonly property real cornerR: 20
    // Bar width as a fixed share of the monitor width (1920 of 2560 = 75%),
    // so it looks equally proportioned on every monitor.
    // barMinWidth prevents the content from being squeezed on narrow (portrait) monitors.
    readonly property real barRatio: 0.75
    readonly property real barMinWidth: 1000
    readonly property real screenW: panelWindow.width > 0 ? panelWindow.width : screen.width
    readonly property real barWidth: Math.min(screenW, Math.max(barMinWidth, Math.round(screenW * barRatio)))
    readonly property real calBodyWidth: 500
    readonly property real calWidth: calBodyWidth + 2 * cornerR
    readonly property real calHeight: calClip.contentHeight + 24
    readonly property real calPad: 16
    // Week column as a narrow margin on the left; the same free on the right, so the 7 days sit exactly centered
    readonly property real wkW: 30
    readonly property real calCardPad: 10
    readonly property real cellW: (calBodyWidth - 2 * calPad - 2 * calCardPad - 2 * wkW) / 7
    readonly property real cellH: 34
    readonly property real barContentOpacity: 1 - clamp01(morph / 0.12)
    readonly property real wT: smooth((morph - 0.05) / 0.55)
    readonly property real hT: smooth((morph - 0.25) / 0.6)
    readonly property real monBodyWidth: 520
    readonly property real monWidth: monBodyWidth + 2 * cornerR
    readonly property real monHeight: monClip.contentHeight + 24
    readonly property real notifBodyWidth: 480
    readonly property real notifWidth: notifBodyWidth + 2 * cornerR
    readonly property real notifHeight: notifPanel.implicitHeight + 34
    // Height of the layer surface: as high as the biggest possible panel (notification center with a full
    // list) plus room for the shadow, from the start. Afterwards it no longer changes
    // (only grows if a panel does get bigger, e.g. one more monitor). The mask handles clicks,
    // so the transparent rest does not disturb.
    // Before, the surface only grew when opening and shrank again 700 ms after every height change:
    // every resize made the morph stutter (first opening after the start, swiping away notifications,
    // calendar after new notifications), and at rest (only 40 px) the bar's shadow was
    // cut off at the bottom or jumped while growing/shrinking. "Wallpaper changed" also made
    // the invisible center grow before -> the bar squashed for one frame; with a fixed height that is gone.
    // Shadow (RectangularShadow below): blur 19 + offset 3 -> ~22 px below the shape, with some reserve
    readonly property real shadowPad: 28
    readonly property real surfaceNeed: Math.max(barHeight, calHeight, monHeight, notifPanel.maxHeight + 34) + shadowPad
    property real surfaceH: Math.ceil(surfaceNeed)
    onSurfaceNeedChanged: {
        // Only grow, never shrink; the assignment also breaks the binding
        surfaceH = Math.max(surfaceH, Math.ceil(surfaceNeed));
    }
    // ==== Switching between panels with the shape open (calendar <-> notification center <-> monitors) ====
    // morph stays at 1 meanwhile, only panelKind changes -> own transition kindT 0..1: the shape glides
    // from its current size (kindFromW/H) to the size of the new panel, the old content fades
    // out at the start, the new one in toward the end. kindFrom = previous panel ("" = no switch active).
    property string kindFrom: ""
    // Deliberately no binding to panelKind: onPanelKindChanged still needs the old value here
    property string lastKind: "calendar"
    property real kindT: 1
    property real kindFromW: 0
    property real kindFromH: 0
    readonly property real kindSizeT: smooth((kindT - 0.08) / 0.77)
    readonly property real panelWidth: kindFrom === "" ? kindWidth(panelKind) : kindFromW + (kindWidth(panelKind) - kindFromW) * kindSizeT
    readonly property real panelHeight: kindFrom === "" ? kindHeight(panelKind) : kindFromH + (kindHeight(panelKind) - kindFromH) * kindSizeT
    readonly property real panelContentOpacity: clamp01((morph - 0.8) / 0.2)
    readonly property real calContentOpacity: panelContentOpacity * kindVisible("calendar")
    readonly property real monContentOpacity: panelContentOpacity * kindVisible("monitors")
    readonly property real notifContentOpacity: panelContentOpacity * kindVisible("notifications")
    // Monitor panel: chosen monitor (while the mini bar glides there), keyboard/hover index
    property string pendingBarScreen: ""
    property int monKbIndex: -1
    readonly property var monScreens: MachineConfig.sortedScreens(Quickshell.screens)
    readonly property string monBarName: pendingBarScreen !== "" ? pendingBarScreen : (screen ? screen.name : "")
    readonly property var monInfoScreen: (monKbIndex >= 0 && monKbIndex < monScreens.length) ? monScreens[monKbIndex] : screen
    property real nudge: 0
    readonly property real shapeW: barWidth + (panelWidth - barWidth) * wT + nudge
    readonly property real shapeH: barHeight + (panelHeight - barHeight) * hT
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var weekdayLong: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var weekdayShort: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property var cells: buildCells(viewYear, viewMonth)
    readonly property var weekNumbers: buildWeekNumbers(viewYear, viewMonth)
    // ==== Month change as a slide ====
    // The last shown month stays as a second grid during the animation and glides out,
    // the new one glides in from the other side. slideDir: +1 = forward (the new month comes from the right)
    property int prevYear: viewYear
    property int prevMonth: viewMonth
    readonly property var prevCells: buildCells(prevYear, prevMonth)
    readonly property var prevWeekNumbers: buildWeekNumbers(prevYear, prevMonth)
    property int slideDir: 1
    property real slideT: 1
    // ==== Dragging in edit mode ====
    // While dragging only a preview (neighbors glide to their new places by offset),
    // the real order is only applied after release -> the mouse grab is kept.
    property var editBadges: ({
    })
    property var dragOrder: []
    property string dragGroup: ""
    // true while the order is applied: offsets jump to 0 without animation
    property bool reorderSnap: false

    function clamp01(x) {
        return Math.max(0, Math.min(1, x));
    }

    function smooth(x) {
        const t = clamp01(x);
        return t * t * (3 - 2 * t);
    }

    function fmtTime(s) {
        return Fmt.clock(s);
    }

    function kindWidth(k) {
        return k === "monitors" ? monWidth : (k === "notifications" ? notifWidth : calWidth);
    }

    function kindHeight(k) {
        return k === "monitors" ? monHeight : (k === "notifications" ? notifHeight : calHeight);
    }

    // Visibility of a panel content during a switch (without a switch: only the active one)
    function kindVisible(k) {
        if (k === panelKind)
            return kindFrom === "" ? 1 : smooth((kindT - 0.55) / 0.45);

        if (k === kindFrom)
            return 1 - smooth(kindT / 0.3);

        return 0;
    }

    function redrawShape() {
        // No longer set it to "transparent" first: the shape follows the color binding by
        // itself now, and the empty intermediate state was visible for one frame (the bar flickered on every
        // pywal color change). Only renew the binding.
        forceRedrawTimer.restart();
    }

    function toggleCalendar() {
        if (!BarState.barVisible)
            return ;

        monitorsOpen = false;
        NotificationState.close();
        panelKind = "calendar";
        calendarOpen = !calendarOpen;
    }

    function toggleMonitors() {
        if (!BarState.barVisible)
            return ;

        calendarOpen = false;
        NotificationState.close();
        panelKind = "monitors";
        monitorsOpen = !monitorsOpen;
    }

    function closePanels() {
        calendarOpen = false;
        monitorsOpen = false;
        NotificationState.close();
    }

    // When entering, open the drawer; when leaving, restore the previous state
    function setEditMode(on) {
        if (on === editMode)
            return ;

        if (on) {
            closePanels();
            if (DropdownState.hoveredIcon !== "")
                DropdownState.leave(DropdownState.hoveredIcon);

            drawerWasOpen = drawerOpen;
            drawerOpen = true;
        } else {
            drawerOpen = drawerWasOpen;
        }
        editMode = on;
    }

    // In edit mode all icons are visible (hidden ones dimmed)
    function iconShown(id) {
        return editMode || BarIcons.shown(id);
    }

    // ==== Order of the icons (edit mode: changeable by dragging, see BarIcons) ====
    function groupIds(group) {
        return group === "left" ? ["clipboard", "trash", "bluetooth", "wifi", "apps", "media", "monitor", "ja"] : ["sync", "claude", "vpn", "audio", "stats", "battery"];
    }

    function groupItems(group) {
        return group === "left" ? {
            "clipboard": drawer.cbSlot,
            "trash": drawer.trashSlot,
            "bluetooth": drawer.btSlot,
            "wifi": drawer.wifiSlot,
            "apps": drawer.appsSlot,
            "media": drawer.mediaSlot,
            "monitor": drawer.monitorSlot,
            "ja": drawer.jaGroup
        } : {
            "sync": iconGroup.syBtn,
            "claude": iconGroup.clBtn,
            "vpn": iconGroup.vpnBtn,
            "audio": iconGroup.atBtn,
            "stats": iconGroup.stBtn,
            "battery": iconGroup.batBtn
        };
    }

    // Row arranges by the order of its children. There is no stackBefore/After in QML,
    // so the icons are re-attached in the wanted order.
    function applyOrder(group) {
        const ids = BarIcons.orderOf(group, groupIds(group));
        const items = groupItems(group);
        const row = items[ids[0]].parent === reorderHolder ? null : items[ids[0]].parent;
        if (!row)
            return ;

        const kids = Array.from(row.children);
        const current = ids.slice().sort((a, b) => {
            return kids.indexOf(items[a]) - kids.indexOf(items[b]);
        });
        if (current.join(",") === ids.join(","))
            return ;

        for (let i = 0; i < ids.length; i++) items[ids[i]].parent = reorderHolder
        for (let i = 0; i < ids.length; i++) items[ids[i]].parent = row
    }

    function dragTo(group, id, px) {
        const ids = dragOrder.length > 0 ? dragOrder : BarIcons.orderOf(group, groupIds(group));
        const items = groupItems(group);
        const others = ids.filter((o) => {
            return o !== id;
        });
        // Sort in before the first visible neighbor whose (preview) center lies to the right of the pointer
        let at = others.length;
        for (let i = 0; i < others.length; i++) {
            const it = items[others[i]];
            const b = editBadges[others[i]];
            const cx = it.x + (b ? b.previewDx : 0) + it.width / 2;
            if (it.visible && px < cx) {
                at = i;
                break;
            }
        }
        const next = others.slice(0, at).concat([id], others.slice(at));
        dragGroup = group;
        dragOrder = next;
        // Target positions as the Row would lay them out
        const row = items[id].parent;
        let x = row.leftPadding || 0;
        for (let i = 0; i < next.length; i++) {
            const it = items[next[i]];
            const b = editBadges[next[i]];
            if (!it.visible)
                continue;

            if (b)
                b.previewDx = x - it.x;

            x += it.width + row.spacing;
        }
    }

    function finishDrag() {
        commitTimer.restart();
    }

    // The drawer fades its icons in staggered, in the current order
    function revealDelay(id) {
        const i = BarIcons.orderOf("left", groupIds("left")).indexOf(id);
        return [0, 0.25, 0.35, 0.45, 0.5, 0.6, 0.7, 0.75][i] || 0;
    }

    // The mini bar glides to the chosen monitor, the panel collapses, then the bar moves
    function pickBarScreen(name) {
        if (pendingBarScreen !== "")
            return ;

        pendingBarScreen = name;
        monCloseTimer.restart();
    }

    function monInfo(s) {
        const m = s ? Hyprland.monitorFor(s) : null;
        const o = (m && m.lastIpcObject) ? m.lastIpcObject : ({
        });
        const sc = (m && m.scale > 0) ? m.scale : 1;
        return {
            "desc": o.description || (s ? s.model : ""),
            "model": o.model || (s ? s.model : ""),
            "hz": o.refreshRate ? Math.round(o.refreshRate) : 0,
            "res": s ? Math.round(s.width * sc) + "×" + Math.round(s.height * sc) : "",
            "scale": sc
        };
    }

    // Bounding box of all monitors (logical coordinates, rotation already included)
    function monBounds(list) {
        if (list.length === 0)
            return {
            "x": 0,
            "y": 0,
            "w": 1,
            "h": 1
        };

        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (let i = 0; i < list.length; i++) {
            const s = list[i];
            x0 = Math.min(x0, s.x);
            y0 = Math.min(y0, s.y);
            x1 = Math.max(x1, s.x + s.width);
            y1 = Math.max(y1, s.y + s.height);
        }
        return {
            "x": x0,
            "y": y0,
            "w": Math.max(1, x1 - x0),
            "h": Math.max(1, y1 - y0)
        };
    }

    // All month changes go through here, so every path (arrows, mouse wheel, keys, click on a neighbor day) slides
    function setView(year, month) {
        const oldIdx = viewYear * 12 + viewMonth;
        const newIdx = year * 12 + month;
        if (oldIdx === newIdx)
            return ;

        // Only animate with the calendar visible, not while it morphs open (goToday when opening)
        if (calendarOpen && calContentOpacity > 0.99) {
            // slideT to 0 first: turns off the cells' color behaviors before the days change
            monthSlide.stop();
            slideT = 0;
            prevYear = viewYear;
            prevMonth = viewMonth;
            slideDir = newIdx > oldIdx ? 1 : -1;
            viewYear = year;
            viewMonth = month;
            monthSlide.restart();
        } else {
            monthSlide.stop();
            slideT = 1;
            viewYear = year;
            viewMonth = month;
        }
    }

    function goToday() {
        now = new Date();
        setView(now.getFullYear(), now.getMonth());
        selectedDate = now;
        selectedKey = Qt.formatDate(now, "yyyy-MM-dd");
    }

    function shiftMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1);
        setView(d.getFullYear(), d.getMonth());
    }

    function selectCell(c) {
        selectedKey = c.key;
        selectedDate = new Date(c.year, c.month, c.day);
        if (!c.inMonth)
            setView(c.year, c.month);

    }

    function buildCells(year, month) {
        const offset = (new Date(year, month, 1).getDay() + 6) % 7;
        const list = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(year, month, 1 - offset + i);
            list.push({
                "day": d.getDate(),
                "month": d.getMonth(),
                "year": d.getFullYear(),
                "inMonth": d.getMonth() === month,
                "key": Qt.formatDate(d, "yyyy-MM-dd")
            });
        }
        return list;
    }

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const dayNum = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - dayNum);
        const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - yearStart) / 8.64e+07 + 1) / 7);
    }

    function buildWeekNumbers(year, month) {
        const offset = (new Date(year, month, 1).getDay() + 6) % 7;
        const list = [];
        for (let r = 0; r < 6; r++) {
            list.push(isoWeek(new Date(year, month, 1 - offset + r * 7 + 3)));
        }
        return list;
    }

    function describe(d) {
        return weekdayLong[d.getDay()] + ", " + monthNames[d.getMonth()] + " " + d.getDate() + "  ·  Week " + isoWeek(d);
    }

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: surfaceH
    color: "transparent"
    exclusiveZone: BarState.barVisible ? barHeight : 0
    WlrLayershell.keyboardFocus: (panelOpen || editMode) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onCalendarOpenChanged: {
        if (calendarOpen) {
            if (PickerManager.isOpen("apps"))
                PickerManager.close();

            goToday();
        } else if (calShowedBar) {
            // Shown only for the calendar -> gone again after morphing back
            calShowedBar = false;
            notifHideTimer.restart();
        }
    }
    // Panel switched while the shape is open -> transition instead of a jump (see kindT)
    onPanelKindChanged: {
        const old = lastKind;
        lastKind = panelKind;
        if (old === panelKind)
            return ;

        if (morph < 0.5) {
            // The shape is closed or only just opening: the normal morph takes over
            kindAnim.stop();
            kindFrom = "";
            kindT = 1;
            return ;
        }
        // Start = current size (also in the middle of a previous switch), not the old panel's
        kindFromW = kindFrom === "" ? kindWidth(old) : kindFromW + (kindWidth(old) - kindFromW) * kindSizeT;
        kindFromH = kindFrom === "" ? kindHeight(old) : kindFromH + (kindHeight(old) - kindFromH) * kindSizeT;
        kindFrom = old;
        kindT = 0;
        kindAnim.restart();
    }
    onMonitorsOpenChanged: {
        if (monitorsOpen) {
            if (PickerManager.isOpen("apps"))
                PickerManager.close();

            Hyprland.refreshMonitors();
            pendingBarScreen = "";
            monKbIndex = -1;
            for (let i = 0; i < monScreens.length; i++) {
                if (monScreens[i].name === screen.name)
                    monKbIndex = i;

            }
        }
    }
    onDrawerOpenChanged: {
        if (!drawerOpen && PickerManager.isOpen("apps"))
            PickerManager.close();

    }

    // Month slide: fast start, long and soft ending (MD3 emphasized decelerate)
    NumberAnimation {
        id: monthSlide

        target: panelWindow
        property: "slideT"
        from: 0
        to: 1
        duration: 480
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.emphasizedDecelerate
    }

    // Density of the icons by monitor width (2560px = 1, lower limit 0.65)
    Binding {
        target: BarState
        property: "density"
        value: Math.max(0.65, Math.min(1, panelWindow.screenW / 2560))
    }

    // Paused while yazi is open for the profile picture: the focus moves there, the center should stay
    HyprlandFocusGrab {
        windows: [panelWindow]
        active: panelWindow.panelOpen && !NotificationState.avatarPicking
        onCleared: panelWindow.closePanels()
    }

    // A click outside the bar ends edit mode
    HyprlandFocusGrab {
        windows: [panelWindow]
        active: panelWindow.editMode
        onCleared: panelWindow.setEditMode(false)
    }

    Timer {
        id: monCloseTimer

        interval: 380
        onTriggered: {
            panelWindow.monitorsOpen = false;
            monCommitTimer.restart();
        }
    }

    // Only move after collapsing: the bar is recreated on the new monitor meanwhile
    Timer {
        id: monCommitTimer

        interval: 660
        onTriggered: {
            const name = panelWindow.pendingBarScreen;
            if (name !== "" && name !== panelWindow.screen.name)
                MachineConfig.setBarScreen(name);
            else
                panelWindow.pendingBarScreen = "";
        }
    }

    // Notification center: the whole bar morphs into it. If the bar is hidden (e.g. SUPER+N),
    // it slides in briefly for it and away again after morphing back.
    Connections {
        function onCenterOpenChanged() {
            if (NotificationState.centerOpen) {
                notifHideTimer.stop();
                panelWindow.calendarOpen = false;
                panelWindow.monitorsOpen = false;
                panelWindow.setEditMode(false);
                panelWindow.panelKind = "notifications";
                if (PickerManager.isOpen("apps"))
                    PickerManager.close();

                if (!BarState.barVisible) {
                    panelWindow.notifShowedBar = true;
                    BarState.barVisible = true;
                }
            } else if (panelWindow.notifShowedBar) {
                panelWindow.notifShowedBar = false;
                notifHideTimer.restart();
            }
        }

        target: NotificationState
    }

    // Calendar by shortcut: like the notification center, a hidden bar slides in briefly for it
    Connections {
        function onCalendarToggleRequested() {
            if (panelWindow.calendarOpen) {
                panelWindow.calendarOpen = false;
                return ;
            }
            notifHideTimer.stop();
            if (!BarState.barVisible || panelWindow.notifShowedBar) {
                panelWindow.calShowedBar = true;
                panelWindow.notifShowedBar = false;
                BarState.barVisible = true;
            }
            panelWindow.toggleCalendar();
        }

        target: BarState
    }

    Timer {
        id: notifHideTimer

        interval: 640
        onTriggered: {
            if (!panelWindow.panelOpen)
                BarState.barVisible = false;

        }
    }

    Connections {
        function onOrderChanged() {
            panelWindow.applyOrder("left");
            panelWindow.applyOrder("right");
        }

        target: BarIcons
    }

    // After snapping in (animation of the released icon) apply the order.
    // Re-attaching and resetting the offsets happen in the same frame -> no jump.
    Timer {
        id: commitTimer

        interval: 270
        onTriggered: {
            if (panelWindow.dragGroup === "")
                return ;

            panelWindow.reorderSnap = true;
            BarIcons.setOrder(panelWindow.dragGroup, panelWindow.dragOrder, true);
            for (const id in panelWindow.editBadges) panelWindow.editBadges[id].previewDx = 0
            panelWindow.dragOrder = [];
            panelWindow.dragGroup = "";
            Qt.callLater(() => {
                panelWindow.reorderSnap = false;
            });
        }
    }

    Connections {
        function onBarVisibleChanged() {
            if (!BarState.barVisible) {
                panelWindow.closePanels();
                panelWindow.setEditMode(false);
                if (PickerManager.isOpen("apps"))
                    PickerManager.close();

            }
        }

        target: BarState
    }

    Timer {
        interval: 1000
        running: panelWindow.morph > 0
        repeat: true
        onTriggered: panelWindow.now = new Date()
    }

    // Temporary holder while re-attaching the icons (applyOrder)
    Item {
        id: reorderHolder

        visible: false
    }

    Item {
        id: rootContainer

        anchors.fill: parent
        opacity: panelWindow.startupDone ? 1 : 0.004

        transform: Translate {
            y: panelWindow.barSlideY
        }

        // Soft shadow below the shape (as in Caelestia), also follows the morph.
        // Before, a layer + MultiEffect on the shape: during the morph (calendar, notification center, monitors)
        // the texture was created at a new size and blurred in every frame. RectangularShadow
        // is a single shader without an intermediate texture (as with the dropdown, same values).
        // Extended by cornerR at the top, so no round shadow corners become visible there.
        RectangularShadow {
            x: shapeItem.x + panelWindow.cornerR
            y: -panelWindow.cornerR
            width: shapeItem.width - 2 * panelWindow.cornerR
            height: shapeItem.height + panelWindow.cornerR
            radius: panelWindow.cornerR
            offset: Qt.vector2d(0, 3)
            blur: 19
            color: Qt.rgba(0, 0, 0, 0.5)
        }

        Shape {
            id: shapeItem

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: panelWindow.shapeW
            height: panelWindow.shapeH
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: barShape

                fillColor: WalColors.withAlpha(WalColors.color0, 1)
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0
                startY: 0

                PathArc {
                    x: panelWindow.cornerR
                    y: panelWindow.cornerR
                    radiusX: panelWindow.cornerR
                    radiusY: panelWindow.cornerR
                }

                PathLine {
                    x: panelWindow.cornerR
                    y: shapeItem.height - panelWindow.cornerR
                }

                PathArc {
                    x: 2 * panelWindow.cornerR
                    y: shapeItem.height
                    radiusX: panelWindow.cornerR
                    radiusY: panelWindow.cornerR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: shapeItem.width - 2 * panelWindow.cornerR
                    y: shapeItem.height
                }

                PathArc {
                    x: shapeItem.width - panelWindow.cornerR
                    y: shapeItem.height - panelWindow.cornerR
                    radiusX: panelWindow.cornerR
                    radiusY: panelWindow.cornerR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: shapeItem.width - panelWindow.cornerR
                    y: panelWindow.cornerR
                }

                PathArc {
                    x: shapeItem.width
                    y: 0
                    radiusX: panelWindow.cornerR
                    radiusY: panelWindow.cornerR
                }

                PathLine {
                    x: 0
                    y: 0
                }

            }

        }

        Connections {
            function onColorsUpdated() {
                panelWindow.redrawShape();
            }

            target: WalColors
        }

        Timer {
            id: forceRedrawTimer

            interval: 10
            onTriggered: barShape.fillColor = Qt.binding(() => {
                return WalColors.withAlpha(WalColors.color0, 1);
            })
        }

        Timer {
            id: startupFix

            property int ticks: 0

            interval: 150
            running: true
            repeat: true
            onTriggered: {
                ticks++;
                panelWindow.nudge = (ticks % 2 === 1) ? 0.1 : 0;
                if (ticks >= 4) {
                    stop();
                    panelWindow.startupDone = true;
                }
            }
        }

        Item {
            id: barClip

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: panelWindow.shapeW
            height: panelWindow.barHeight
            clip: true
            opacity: panelWindow.barContentOpacity
            visible: opacity > 0.01
            enabled: !panelWindow.panelOpen

            Item {
                anchors.centerIn: parent
                width: panelWindow.barWidth
                height: panelWindow.barHeight

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 35
                    anchors.rightMargin: 35

                    Row {
                        id: leftRow

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Item {
                            id: archBtn

                            width: 24 + 16
                            height: 32

                            Text {
                                id: archGlyph

                                // The glyph is wider than its advance width (20 instead of 14.4 px),
                                // so centering by alignment puts it next to the box center and it
                                // wobbles when rotating. That is why the box is placed exactly so that its
                                // center (= pivot) lies on the center of the glyph (measured).
                                x: 4.8
                                y: 0
                                width: 20
                                height: 31.62
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignTop
                                text: "󰣇"
                                font.pixelSize: 24
                                color: (archHover.hovered || panelWindow.drawerOpen || panelWindow.editMode) ? WalColors.color4 : WalColors.color2
                                rotation: panelWindow.editMode ? 180 : (panelWindow.drawerOpen ? 90 : 0)
                                scale: archHover.hovered ? 1.1 : 1
                                transformOrigin: Item.Center

                                Behavior on rotation {
                                    NumberAnimation {
                                        duration: 460
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.5
                                    }

                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Appearance.anim.durations.fast
                                        easing.type: Easing.OutCubic
                                    }

                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 180
                                    }

                                }

                            }

                            Rectangle {
                                x: 19
                                y: 5
                                width: 6
                                height: 6
                                radius: height / 2
                                color: WalColors.color4
                                visible: scale > 0.01
                                scale: (LanguageAudioState.isPlaying && !panelWindow.drawerOpen) ? 1 : 0

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 260
                                        easing.type: Easing.OutBack
                                    }

                                }

                            }

                            HoverHandler {
                                id: archHover
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.rightMargin: 10
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton)
                                        panelWindow.setEditMode(!panelWindow.editMode);
                                    else if (panelWindow.editMode)
                                        panelWindow.setEditMode(false);
                                    else
                                        panelWindow.drawerOpen = !panelWindow.drawerOpen;
                                }
                            }

                        }

                        BarDrawer {
                            id: drawer

                            mainBar: panelWindow
                        }

                        // When open, the drawer gets a smaller gap to the next button.
                        Item {
                            id: drawerGap

                            width: Theme.px(2) + panelWindow.revealT * Theme.gapSmall
                            height: 1
                        }

                        BarIcon {
                            id: shortcutsButton

                            readonly property real room: workspacesModule.x - x
                            readonly property bool showLabel: panelWindow.barWidth >= Theme.px(1250)
                                && room >= Theme.px(320)
                            readonly property bool active: PickerManager.isOpen("shortcuts")

                            objectName: "shortcutsBarButton"
                            height: Theme.px(32)
                            itemGap: 2 * Theme.gapSmall
                            contentWidth: shortcutsContent.implicitWidth
                            reveal: room >= contentWidth + Math.round(padding * BarState.density)
                                + itemGap + Theme.gapSmall ? 1 : 0
                            enabled: !panelWindow.editMode
                            Accessible.role: Accessible.Button
                            Accessible.name: "Search shortcuts"
                            Accessible.onPressAction: PickerManager.toggle("shortcuts")
                            Controls.ToolTip.text: "Search shortcuts"
                            Controls.ToolTip.visible: hovered && enabled
                            Controls.ToolTip.delay: Appearance.anim.durations.slow
                            onClicked: PickerManager.toggle("shortcuts")

                            Rectangle {
                                anchors.centerIn: parent
                                width: shortcutsButton.buttonWidth
                                height: shortcutsButton.height
                                radius: Theme.radiusS
                                color: shortcutsButton.active || shortcutsButton.hovered
                                    ? Theme.accentSoft : Theme.card
                                border.color: Theme.stroke

                                Behavior on color {
                                    ColorAnimation { duration: Appearance.anim.durations.fast }
                                }
                            }

                            Row {
                                id: shortcutsContent

                                anchors.centerIn: parent
                                spacing: Theme.px(5)

                                BarGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰌌"
                                    font.pixelSize: Theme.px(16)
                                    hot: shortcutsButton.hovered
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: shortcutsButton.showLabel
                                    text: "Shortcuts"
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.sizeLabel
                                    color: Theme.text
                                }
                            }
                        }

                        Item {
                            // The empty margin of the logo button also belongs to the visible spacing.
                            width: shortcutsButton.reveal * (drawerGap.width + (1 - panelWindow.revealT)
                                * (archBtn.width - archGlyph.x - archGlyph.width))
                            height: 1
                        }

                        ActiveWindow {
                            width: Math.max(0, Math.min(implicitWidth, 200, workspacesModule.x - x - Theme.gapSmall))
                        }

                    }

                    // Centered, but positioned by hand: while a workspace fades in/out the module grows.
                    // anchors.centerIn rounds every frame to whole pixels then, the module (and the kanji in it)
                    // jumped back and forth. At rest still on whole pixels (sharp)
                    Workspaces {
                        id: workspacesModule

                        readonly property real centerX: (parent.width - width) / 2

                        // The tray icon can be hidden in edit mode (see Workspaces.tabletShown)
                        editMode: panelWindow.editMode

                        x: appearing > 0 ? centerX : Math.round(centerX)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Row {
                        // The spacing to the power icon fades in/out with it (hidden: the clock at the far right)
                        anchors.right: powerBtn.left
                        anchors.rightMargin: Math.round(40 * BarState.density) * powerBtn.reveal
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        spacing: Math.round(40 * BarState.density)

                        BarIconGroup {
                            id: iconGroup

                            mainBar: panelWindow
                        }

                        Clock {
                            onClicked: panelWindow.toggleCalendar()
                        }

                    }

                    // Power menu at the far right, counterpart of the logo on the left: no dropdown like the
                    // icons of the group, so not in it (see PowerMenuButton)
                    PowerMenuButton {
                        id: powerBtn

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: panelWindow.iconShown("power")
                        reveal: BarIcons.shown("power") ? 1 : panelWindow.editReveal

                        // Only on/off (group empty = not movable)
                        EditBadge {
                            mainBar: panelWindow
                            iconId: "power"
                        }

                    }

                }

            }

        }

        CalendarPanel {
            id: calClip

            mainBar: panelWindow
            shapeHeight: shapeItem.height
        }

        // ═══ Notification-Center ═══
        Item {
            id: notifClip

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: panelWindow.notifBodyWidth
            height: shapeItem.height
            clip: true
            opacity: panelWindow.notifContentOpacity
            visible: opacity > 0.01
            enabled: panelWindow.notifOpen
            focus: panelWindow.notifOpen
            Keys.onEscapePressed: NotificationState.close()

            NotificationPanel {
                id: notifPanel

                anchors.horizontalCenter: parent.horizontalCenter
                y: 18
                width: panelWindow.notifBodyWidth - 2 * panelWindow.calPad
                maxListH: Math.min(460, (panelWindow.screen ? panelWindow.screen.height : 1080) * 0.5)
                shown: panelWindow.notifOpen && panelWindow.notifContentOpacity > 0.01
                screenName: panelWindow.screen ? panelWindow.screen.name : ""
                // Bottom edge of the center (the bar lies at the top of the monitor) -> the yazi window starts there
                bottomY: panelWindow.notifHeight
            }

        }

        // ═══ Monitor panel: choose the bar monitor ═══
        MonitorPanel {
            id: monClip

            mainBar: panelWindow
            shapeHeight: shapeItem.height
        }

    }

    // Follows the glide (the translate does not move shapeItem itself): only the visible part of the shape
    // takes clicks, fully retracted the bar is click-through
    mask: Region {
        x: shapeItem.x
        y: 0
        width: shapeItem.width
        height: (panelWindow.startupDone || BarState.barVisible) ? Math.max(0, shapeItem.height + panelWindow.barSlideY) : 0
    }

    // Open and close with the same curve: reacts right away and eases out softly. No curve that depends on barVisible:
    // Qt started the animation before switching the curve (opening then ran with InCubic =
    // ~300 ms of nothing visible). InCubic when closing also feels sluggish (~100 ms of hardly any movement).
    Behavior on barSlide {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }

    }

    Behavior on morph {
        NumberAnimation {
            duration: 620
            easing.type: Easing.Linear
        }

    }

    // Panel switch with the shape open; the curves are in kindSizeT / kindVisible
    NumberAnimation {
        id: kindAnim

        target: panelWindow
        property: "kindT"
        from: 0
        to: 1
        duration: 560
        easing.type: Easing.Linear
        onFinished: panelWindow.kindFrom = ""
    }

    Behavior on editReveal {
        NumberAnimation {
            duration: Appearance.anim.durations.slow
            easing.type: Easing.OutCubic
        }
    }

    Behavior on revealT {
        NumberAnimation {
            duration: 480
            easing.type: Easing.OutCubic
        }

    }

}
