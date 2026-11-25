import "../common"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string terminalCommand: "kitty"
    property var allApps: AppLauncherState.allApps
    // State for hidden apps
    property var hiddenApps: ({
    })
    property bool showHidden: false
    readonly property string hiddenFile: Quickshell.stateDir + "/app-launcher-hidden.json"
    property var filteredApps: allApps.filter((app) => {
        const isHidden = hiddenApps[app.exec] === true;
        if (isHidden && !showHidden)
            return false;

        return app.name.toLowerCase().includes(PickerManager.searchText.toLowerCase());
    })
    // ==== Calculator: "= 12 * (3 + 4)" in the search computes, Enter copies the result ====
    readonly property bool calcMode: PickerManager.searchText.trim().startsWith("=")
    readonly property string calcResult: calcMode ? calculate(PickerManager.searchText.trim().slice(1)) : ""
    readonly property var calcNames: ({
        "sqrt": "Math.sqrt",
        "sin": "Math.sin",
        "cos": "Math.cos",
        "tan": "Math.tan",
        "abs": "Math.abs",
        "ln": "Math.log",
        "log": "Math.log10",
        "exp": "Math.exp",
        "round": "Math.round",
        "floor": "Math.floor",
        "ceil": "Math.ceil",
        "min": "Math.min",
        "max": "Math.max",
        "pi": "Math.PI",
        "e": "Math.E"
    })
    property real lastMouseX: -1
    property real lastMouseY: -1
    // Same tiles and cells as in the music picker (Theme), the icon grows in the old ratio
    // (60 px icon in an 88 px tile)
    readonly property real cellW: Theme.pickerCellW
    readonly property real cellH: Theme.pickerCellH
    readonly property real tileSize: Theme.pickerTile
    readonly property real iconSize: Math.round(tileSize * 60 / 88)
    // Up to 5 columns, fewer if the monitor is too narrow
    readonly property int gridColumns: Math.max(2, Math.min(5, Math.floor((width - 96) / cellW)))
    // ==== Tab switch: only the content animates, the search bar always stays ====
    // tabIn: 0 = content hidden, 1 = fully there. The search bar on the other hand switches
    // right away, so it never flickers or moves during the switch.
    // Also active during the closing animation, so everything fades out together
    readonly property bool tabActive: PickerManager.activePicker === "app" || PickerManager.closingPicker === "app"
    property real tabIn: tabActive ? 1 : 0
    // Slide in tab direction: incoming from the switch direction, outgoing in the opposite direction
    // ==== Elements fade in one after another when showing (as in the clipboard) ====
    // intro: short time window in which newly created elements play the animation.
    // introRun: counted up, so elements that already exist play it too.
    property bool intro: false
    property int introRun: 0
    // After fading in: make every tile whose fade-in animation is not (or no longer) running fully visible.
    // Safety net: "launcher open but empty" happened now and then, and a stuck animation
    // would have left the tiles invisible
    signal settleTiles()

    function playIntro() {
        intro = true;
        introTimer.restart();
        settleTimer.restart();
        // Start at the top: an old scroll position could otherwise be past the end of the list
        grid.positionViewAtBeginning();
        grid.currentIndex = 0;
        introRun++;
    }

    // Diagnosis: if the launcher is still empty shortly after opening, write the state to the log
    // (qs log), so the cause can be found
    function checkEmpty() {
        // Only without search text: a search without hits is empty on purpose
        if (!root.tabActive || root.calcMode || PickerManager.searchText !== "")
            return;
        let shown = 0;
        for (const c of grid.contentItem.children) {
            if (c.enter !== undefined && c.enter > 0.5)
                shown++;
        }
        if (grid.count > 0 && shown > 0 && gridArea.opacity > 0.5)
            return;
        console.warn("AppLauncher empty after opening:", JSON.stringify({
            "allApps": root.allApps.length,
            "entries": AppLauncherState.entries.length,
            "appsLoaded": AppLauncherState.appsLoaded,
            "search": PickerManager.searchText,
            "filtered": root.filteredApps.length,
            "gridCount": grid.count,
            "tilesShown": shown,
            "tabIn": root.tabIn,
            "gridAreaOpacity": gridArea.opacity,
            "contentY": grid.contentY,
            "visible": root.visible,
            "picker": PickerManager.activePicker
        }));
    }

    function focusSearch() {
        searchInput.forceActiveFocus();
    }

    // Only numbers, operators and the names from calcNames are evaluated; everything else gives "".
    // A comma counts as the decimal point (except between function arguments: there a semicolon), ^ as power.
    function calculate(input) {
        const expr = input.toLowerCase().replace(/,/g, ".").replace(/;/g, ",").replace(/\^/g, "**").trim();
        if (expr === "" || !/^[0-9a-z+\-*\/%().,\s]+$/.test(expr))
            return "";

        let unknown = false;
        const js = expr.replace(/[a-z]+/g, (name) => {
            if (!calcNames[name])
                unknown = true;

            return calcNames[name] || "";
        });
        if (unknown)
            return "";

        try {
            const v = Function("return (" + js + ");")();
            if (typeof v !== "number" || !isFinite(v))
                return "";

            return String(Number(v.toPrecision(12)));
        } catch (e) {
            return "";
        }
    }

    function copyResult() {
        Quickshell.execDetached(["wl-copy", "--", calcResult]);
        NotificationState.send("Calculator", calcResult, "Copied to clipboard", {
            "timeout": 2000,
            "success": true
        });
        AppLauncherState.close();
    }

    function launchApp(app) {
        if (!app)
            return ;

        try {
            let command = [];
            if (app.terminal)
                command = [terminalCommand, "-e", "sh", "-c", app.exec + "; exec sh"];
            else
                command = ["sh", "-c", app.exec];
            Quickshell.execDetached(command);
            NotificationState.send("Launcher", app.name, "Launching …", {
                "icon": app.icon || "",
                "timeout": 2500
            });
        } catch (e) {
            console.error("Error starting", app.name, ":", e);
        }
        AppLauncherState.close();
    }

    function toggleHide(app) {
        let h = Object.assign({
        }, hiddenApps);
        if (h[app.exec])
            delete h[app.exec];
        else
            h[app.exec] = true;
        hiddenApps = h;
        saveHidden();
    }

    function saveHidden() {
        const jsonStr = JSON.stringify(root.hiddenApps);
        hiddenWriter.command = ["bash", "-c", "mkdir -p $(dirname \"" + root.hiddenFile + "\") && echo '" + jsonStr.replace(/'/g, "'\\''") + "' > \"" + root.hiddenFile + "\""];
        hiddenWriter.running = false;
        hiddenWriter.running = true;
    }

    function loadHidden() {
        hiddenReader.running = false;
        hiddenReader.running = true;
    }

    onTabActiveChanged: {
        if (tabActive)
            playIntro();

    }
    Component.onCompleted: {
        AppLauncherState.loadApps();
        loadHidden();
        if (tabActive)
            playIntro();

    }
    onFilteredAppsChanged: grid.currentIndex = 0
    Keys.onEscapePressed: AppLauncherState.close()
    Keys.onReturnPressed: {
        if (root.calcMode) {
            if (root.calcResult !== "")
                root.copyResult();

            return ;
        }
        if (root.filteredApps.length > 0)
            root.launchApp(root.filteredApps[grid.currentIndex]);

    }

    Timer {
        id: introTimer

        interval: 700
        onTriggered: root.intro = false
    }

    // Longest staggered fade-in: 4 rows * 70 + 4 columns * 35 + 20 + 460 ms ~ 900 ms
    Timer {
        id: settleTimer

        interval: 1500
        onTriggered: {
            root.settleTiles();
            root.checkEmpty();
        }
    }

    // Process for loading the hidden apps
    Process {
        id: hiddenReader

        command: ["bash", "-c", "cat \"" + root.hiddenFile + "\" 2>/dev/null || echo '{}'"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.hiddenApps = JSON.parse(text.trim() || "{}");
                } catch (e) {
                    root.hiddenApps = {
                    };
                }
            }
        }

    }

    // Process for saving the hidden apps
    Process {
        id: hiddenWriter
    }

    // Search bar, top center
    Rectangle {
        id: searchBar

        visible: root.tabActive
        // Width set back to the original
        width: Math.min(root.width * 0.4, 400)
        height: 56
        radius: height / 2
        anchors.top: parent.top
        anchors.topMargin: Math.max(root.height * 0.08, 48)
        anchors.horizontalCenter: parent.horizontalCenter
        color: WalColors.withAlpha(WalColors.color7, 0.12)
        border.width: 2
        // Always in the accent color (not depending on focus): otherwise the border flashes briefly on a tab switch
        border.color: WalColors.withAlpha(WalColors.color4, 0.6)

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            font.family: Theme.font
            font.pixelSize: 18
            color: WalColors.withAlpha(WalColors.color7, 0.5)
        }

        TextInput {
            id: searchInput

            anchors.fill: parent
            anchors.leftMargin: 54
            anchors.rightMargin: 156 // room for the switcher
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.font
            font.pixelSize: 16
            color: WalColors.color7
            text: PickerManager.searchText
            onTextChanged: PickerManager.searchText = text
            Component.onCompleted: forceActiveFocus()
            Keys.onPressed: (event) => {
                // Ctrl+J/K = arrow down/up, the same in all pickers (PickerManager.navKey)
                const key = PickerManager.navKey(event);
                if (key === Qt.Key_Tab) {
                    if (event.modifiers & Qt.ShiftModifier)
                        PickerManager.cycleBackward();
                    else
                        PickerManager.cycle();
                    event.accepted = true;
                    return ;
                }
                // Arrow keys: stop a running mouse wheel animation, so it does not work against them
                if (key >= Qt.Key_Left && key <= Qt.Key_Down)
                    scrollAnim.stop();

                switch (key) {
                case Qt.Key_Down:
                    grid.moveCurrentIndexDown();
                    event.accepted = true;
                    break;
                case Qt.Key_Up:
                    grid.moveCurrentIndexUp();
                    event.accepted = true;
                    break;
                case Qt.Key_Left:
                    grid.moveCurrentIndexLeft();
                    event.accepted = true;
                    break;
                case Qt.Key_Right:
                    grid.moveCurrentIndexRight();
                    event.accepted = true;
                    break;
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 54
            anchors.verticalCenter: parent.verticalCenter
            text: "Search"
            color: WalColors.withAlpha(WalColors.color7, 0.35)
            font.family: Theme.font
            font.pixelSize: 14
            visible: searchInput.text === ""
        }

        PickerSwitcher {
            id: pickerSwitcher

            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            focusTarget: searchInput
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 120
            }

        }

    }

    // ==== Button next to the search: show/hide hidden apps ====
    // Deliberately smaller/subtler than the search bar (40 instead of 56): a side feature, should not compete
    Rectangle {
        id: eyeButton

        // Active (hidden apps visible) in the accent color, so you do not forget the mode
        readonly property bool hot: eyeMouse.containsMouse || root.showHidden

        visible: root.tabActive
        anchors.left: searchBar.right
        anchors.leftMargin: 10
        anchors.verticalCenter: searchBar.verticalCenter
        width: 40
        height: 40
        radius: width / 2
        color: hot ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.06)
        border.width: 1
        border.color: hot ? WalColors.withAlpha(WalColors.color4, 0.6) : WalColors.withAlpha(WalColors.color2, 0.15)
        scale: eyeMouse.pressed ? 0.92 : (eyeMouse.containsMouse ? 1.06 : 1)

        Text {
            anchors.centerIn: parent
            // Open eye = hidden apps visible, crossed out = hidden
            text: root.showHidden ? "󰈈" : "󰈉"
            font.family: Theme.font
            font.pixelSize: 17
            color: eyeButton.hot ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.5)

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        MouseArea {
            id: eyeMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.showHidden = !root.showHidden
        }

        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
                easing.overshoot: 1.5
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

        Behavior on border.color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    // App-Grid
    Item {
        id: gridArea

        width: root.gridColumns * root.cellW
        anchors.top: searchBar.bottom
        anchors.topMargin: 48
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: root.tabIn
        visible: opacity > 0.01


        // Calculator result (search starts with "=")
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            spacing: 10
            visible: root.calcMode

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.calcResult !== "" ? root.calcResult : "…"
                color: root.calcResult !== "" ? Theme.text : Theme.textFaint
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: 44
                font.weight: Font.DemiBold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.calcResult !== "" ? "Enter copies the result" : "Type a calculation, e.g. = 12 * (3 + 4) or = sqrt(2)"
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLabel
            }

        }

        // Loading indicator, in case the scan is still running
        Text {
            anchors.centerIn: parent
            text: "Loading apps…"
            color: WalColors.withAlpha(WalColors.color7, 0.45)
            font.family: Theme.font
            font.pixelSize: 14
            visible: !AppLauncherState.appsLoaded && grid.count === 0
        }

        GridView {
            id: grid

            // Only whole rows: round the height down to a multiple of the row height, otherwise
            // a strip of the next row sticks into view at the bottom
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(1, Math.floor(parent.height / root.cellH)) * root.cellH
            cellWidth: root.cellW
            cellHeight: root.cellH
            currentIndex: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onMovementStarted: scrollAnim.stop()

            // ScriptModel syncs the list instead of replacing it: while typing the
            // tiles (with icon and shadow) stay, only the filtered-out ones disappear
            model: ScriptModel {
                values: root.filteredApps
                objectProp: "name"
            }

            // Smooth scrolling: the target position is animated
            NumberAnimation {
                id: scrollAnim

                target: grid
                property: "contentY"
                duration: 260
                easing.type: Easing.OutCubic
            }

            // Mouse wheel: one notch = one row (touchpad: proportional)
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    const d = event.angleDelta.y;
                    if (d === 0)
                        return ;

                    const minY = grid.originY;
                    const maxY = Math.max(minY, grid.originY + grid.contentHeight - grid.height);
                    const base = scrollAnim.running ? scrollAnim.to : grid.contentY;
                    let to;
                    if (Math.abs(d) >= 120) {
                        // Mouse wheel: snap to the row border, exactly one row per notch
                        const rows = Math.max(1, Math.round(Math.abs(d) / 120));
                        to = (Math.round((base - minY) / root.cellH) - (d > 0 ? rows : -rows)) * root.cellH + minY;
                    } else {
                        // Touchpad: kleine Deltas weich mitnehmen
                        to = base - d / 120 * root.cellH;
                    }
                    to = Math.max(minY, Math.min(to, maxY));
                    scrollAnim.stop();
                    scrollAnim.to = to;
                    scrollAnim.start();
                    event.accepted = true;
                }
            }

            Text {
                anchors.centerIn: parent
                text: "No apps found"
                color: WalColors.withAlpha(WalColors.color7, 0.4)
                font.family: Theme.font
                visible: grid.count === 0 && AppLauncherState.appsLoaded && !root.calcMode
            }

            delegate: Item {
                id: delegateItem

                required property var modelData
                required property int index
                readonly property bool isCurrent: GridView.isCurrentItem
                readonly property bool isHidden: root.hiddenApps[modelData.exec] === true
                // Fade-in animation (staggered, as in the clipboard)
                property real enter: 1
                readonly property int gridCol: index % root.gridColumns
                readonly property int gridRow: Math.floor(index / root.gridColumns)

                function playEnter() {
                    enterAnim.stop();
                    enter = 0;
                    enterAnim.start();
                }

                width: grid.cellWidth
                height: grid.cellHeight
                opacity: (isHidden ? 0.5 : 1) * enter
                Component.onCompleted: {
                    if (root.intro)
                        playEnter();

                }

                Connections {
                    function onIntroRunChanged() {
                        delegateItem.playEnter();
                    }

                    function onSettleTiles() {
                        if (!enterAnim.running)
                            delegateItem.enter = 1;

                    }

                    target: root
                }

                SequentialAnimation {
                    id: enterAnim

                    PauseAnimation {
                        duration: Math.max(0, Math.min(delegateItem.gridRow, 4) * 70 + delegateItem.gridCol * 35 + 20)
                    }

                    NumberAnimation {
                        target: delegateItem
                        property: "enter"
                        to: 1
                        duration: 460
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.outQuint
                    }

                }

                // Click and hover logic for the tile
                MouseArea {
                    id: mArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPositionChanged: (mouse) => {
                        const p = mArea.mapToItem(null, mouse.x, mouse.y);
                        if (Math.abs(p.x - root.lastMouseX) < 3 && Math.abs(p.y - root.lastMouseY) < 3)
                            return ;

                        root.lastMouseX = p.x;
                        root.lastMouseY = p.y;
                        grid.currentIndex = index;
                    }
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            root.toggleHide(delegateItem.modelData);
                        } else {
                            grid.currentIndex = index;
                            root.launchApp(delegateItem.modelData);
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Rectangle {
                        id: iconBg

                        width: root.tileSize
                        height: root.tileSize
                        radius: Theme.pickerTileRadius
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: isCurrent ? WalColors.withAlpha(WalColors.color2, 0.3) : WalColors.withAlpha(WalColors.color2, 0.08)
                        border.width: isCurrent ? 2 : 0
                        border.color: WalColors.withAlpha(WalColors.color4, 0.6)
                        scale: isCurrent ? 1.08 : 1

                        SoftShadow {
                            radius: iconBg.radius
                            raised: isCurrent
                            // The tile is transparent: shadow only outside
                            hollow: true
                        }

                        AppIcon {
                            anchors.centerIn: parent
                            width: root.iconSize
                            height: root.iconSize
                            icon: modelData.icon || ""
                            name: modelData.name
                            highlighted: isCurrent
                        }

                        // Small hide/unhide button (appears on hover)
                        Rectangle {
                            width: 22
                            height: 22
                            radius: height / 2
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 4
                            color: hideMouse.containsMouse ? WalColors.withAlpha(WalColors.color1, 0.9) : WalColors.withAlpha(WalColors.color0, 0.8)
                            visible: (mArea.containsMouse || delegateItem.isCurrent) && (root.showHidden || !delegateItem.isHidden)

                            Text {
                                anchors.centerIn: parent
                                text: delegateItem.isHidden ? "+" : "✕"
                                color: hideMouse.containsMouse ? WalColors.color0 : WalColors.color7
                                font.pixelSize: 12
                                font.bold: true
                            }

                            MouseArea {
                                id: hideMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleHide(delegateItem.modelData)
                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutCubic
                            }

                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }

                        }

                    }

                    Text {
                        width: grid.cellWidth - 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: delegateItem.modelData.name + (delegateItem.isHidden ? " (hidden)" : "")
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: delegateItem.isHidden ? WalColors.withAlpha(WalColors.color7, 0.5) : WalColors.color7
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }

                }

                transform: Translate {
                    y: (1 - delegateItem.enter) * 18
                }

            }

        }

    }

    // Fade out fast; fade in only briefly, because the elements animate in one by one afterwards
    Behavior on tabIn {
        NumberAnimation {
            duration: root.tabActive ? 160 : 120
            easing.type: root.tabActive ? Easing.OutCubic : Easing.InCubic
        }

    }

}
