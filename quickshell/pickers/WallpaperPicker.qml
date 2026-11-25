import "../common"
import "../services"
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Item {
    id: root

    property var allWallpapers: WallpaperPickerState.allWallpapers
    property var filteredWallpapers: allWallpapers.filter((w) => {
        return w.name.toLowerCase().includes(PickerManager.searchText.toLowerCase());
    })
    property real lastMouseX: -1
    property real lastMouseY: -1
    readonly property string wallpaperDir: WallpaperPickerState.wallpaperDir
    // Cells adapt to the monitor: max. 630x350 and always 3 rows. If there is not enough room,
    // the cells get smaller instead of sticking out over the edge.
    readonly property int visibleCols: 2
    readonly property int maxRows: 3
    readonly property real cellAspect: 350 / 630
    readonly property real gridTop: Math.max(height * 0.08, 48) + 56 + 40
    readonly property real availW: width - 96
    readonly property real availH: height - gridTop - 40
    // floor(availH / maxRows) as an integer, so cellH never gets bigger after rounding and 3 rows surely fit
    readonly property real cellW: Math.floor(Math.max(240, Math.min(630, availW / visibleCols, Math.floor(availH / maxRows) / cellAspect)))
    readonly property real cellH: Math.round(cellW * cellAspect)
    readonly property int visibleRows: Math.max(1, Math.min(maxRows, Math.floor(availH / cellH)))
    // The image sits in the cell with a 15px margin (before a fixed 600x320 in 630x350)
    readonly property real imgW: cellW - 30
    readonly property real imgH: cellH - 30
    // ==== Tab switch: only the content animates, the search bar always stays ====
    // tabIn: 0 = content hidden, 1 = fully there. The search bar on the other hand switches
    // right away, so it never flickers or moves during the switch.
    // Also active during the closing animation, so everything fades out together
    readonly property bool tabActive: PickerManager.activePicker === "wallpaper" || PickerManager.closingPicker === "wallpaper"
    property real tabIn: tabActive ? 1 : 0
    // Slide in tab direction: incoming from the switch direction, outgoing in the opposite direction
    // ==== Elements fade in one after another when showing (as in the clipboard) ====
    // intro: short time window in which newly created elements play the animation.
    // introRun: counted up, so elements that already exist play it too.
    property bool intro: false
    property int introRun: 0
    // ==== Wallhaven: the plus button switches to search hits from wallhaven.cc (like the file list in VPN) ====
    readonly property bool browsing: WallhavenState.browsing
    // 0 = own wallpapers, 1 = wallhaven
    property real browseT: browsing ? 1 : 0
    // Arrow keys control the view that is visible right now
    readonly property GridView activeGrid: browsing ? whGrid : grid

    // One mouse wheel notch = one row (touchpad: proportional); for both grids
    function wheelScroll(view, anim, event) {
        const d = event.angleDelta.y;
        if (d === 0)
            return ;

        const minY = view.originY;
        const maxY = Math.max(minY, view.originY + view.contentHeight - view.height);
        const base = anim.running ? anim.to : view.contentY;
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
        anim.stop();
        anim.to = to;
        anim.start();
        event.accepted = true;
    }

    // Not downloaded yet -> download; already in the folder -> set it as the wallpaper directly
    function activateRemote(item) {
        if (!item)
            return ;

        if (WallhavenState.isDownloaded(item))
            setWallpaper("file://" + root.wallpaperDir + item.file);
        else
            WallhavenState.download(item);
    }

    function playIntro() {
        intro = true;
        introTimer.restart();
        introRun++;
    }

    function focusSearch() {
        searchInput.forceActiveFocus();
    }

    // After deleting stay at the same place instead of jumping to the top
    property int keepIndex: -1

    function deleteAt(i) {
        const entry = root.filteredWallpapers[i];
        if (!entry)
            return;
        grid.currentIndex = i;
        root.keepIndex = i;
        if (!WallpaperPickerState.requestDelete(entry))
            root.keepIndex = -1;
    }

    function setWallpaper(url) {
        let path = url.toString().replace(/^file:\/\//, "");
        path = decodeURIComponent(path);
        // The ink transition always starts in the middle of the picker's monitor (desktop coordinates);
        // starting from the tile, the start point felt random
        let origin = null;
        const win = QsWindow.window;
        if (win && win.screen)
            origin = Qt.point(win.screen.x + win.screen.width / 2, win.screen.y + win.screen.height / 2);
        // Runs in the singleton: the picker is unloaded shortly after closing and would otherwise
        // abort apply-wallpaper.sh in the middle of wal (colors stayed old)
        WallpaperPickerState.apply(path, origin);
        PickerManager.close();
    }

    onTabActiveChanged: {
        if (tabActive)
            playIntro();

    }
    Component.onCompleted: {
        WallpaperPickerState.loadWallpapers();
        if (tabActive)
            playIntro();

    }
    onFilteredWallpapersChanged: {
        if (keepIndex < 0) {
            grid.currentIndex = 0;
            return;
        }
        // A new model resets the view -> restore selection and scroll position
        const i = Math.min(keepIndex, filteredWallpapers.length - 1);
        keepIndex = -1;
        Qt.callLater(() => {
            grid.currentIndex = i;
            grid.positionViewAtIndex(i, GridView.Contain);
        });
    }
    // Switch: clear the search (the term belongs to the other view) and start at the top
    onBrowsingChanged: {
        PickerManager.searchText = "";
        whGrid.currentIndex = 0;
        whGrid.contentY = whGrid.originY;
    }
    Keys.onEscapePressed: {
        // Esc first cancels a marked deletion
        if (WallpaperPickerState.deleteArmed !== "")
            WallpaperPickerState.deleteArmed = "";
        else if (root.browsing)
            WallhavenState.close();
        else
            PickerManager.close();
    }
    Keys.onReturnPressed: {
        if (root.browsing)
            root.activateRemote(whGrid.count > 0 ? WallhavenState.results.get(whGrid.currentIndex) : null);
        else if (root.filteredWallpapers.length > 0)
            root.setWallpaper(root.filteredWallpapers[grid.currentIndex].url);
    }

    Behavior on browseT {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.standard
        }

    }

    // Segment group of the filter bar: pill with a symbol in front and the options after it.
    // multi: false = one choice with a gliding marker (like tabs), true = several on/off
    component SegmentGroup: Rectangle {
        id: seg

        property string glyph: ""
        property var options: []
        property var active: [] // keys of the active options
        property bool multi: false
        readonly property int activeIndex: {
            for (let i = 0; i < options.length; ++i) {
                if (active.includes(options[i].key))
                    return i;

            }
            return -1;
        }

        signal picked(var key)

        width: segRow.implicitWidth + 6
        height: 30
        radius: height / 2
        color: WalColors.withAlpha(WalColors.color7, 0.08)
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color2, 0.22)

        // Gliding marker (single choice only); the width follows, because the labels differ in length
        Rectangle {
            id: segMarker

            // count in the condition: itemAt reports no change, the binding has to run again
            // as soon as the Repeater has created its options
            readonly property Item target: seg.activeIndex >= 0 && segRepeater.count > seg.activeIndex ? segRepeater.itemAt(seg.activeIndex) : null
            // Only animate after the build, otherwise the marker glides in from the left when opening
            property bool ready: false

            Component.onCompleted: Qt.callLater(() => {
                ready = true;
            })

            visible: !seg.multi && target !== null
            x: target ? segRow.x + target.x : 0
            y: 3
            width: target ? target.width : 0
            height: seg.height - 6
            radius: height / 2
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.tint(Theme.accent, 0.3)

            Behavior on x {
                enabled: segMarker.ready

                NumberAnimation {
                    duration: 320
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.1
                }

            }

            Behavior on width {
                enabled: segMarker.ready

                NumberAnimation {
                    duration: 320
                    easing.type: Easing.OutCubic
                }

            }

        }

        Row {
            id: segRow

            x: 3
            height: seg.height

            Text {
                width: 30
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: seg.glyph
                font.family: Theme.font
                font.pixelSize: 14
                color: WalColors.withAlpha(WalColors.color7, 0.45)
            }

            Repeater {
                id: segRepeater

                model: seg.options

                delegate: Item {
                    id: opt

                    required property var modelData
                    readonly property bool on: seg.active.includes(modelData.key)

                    width: optText.implicitWidth + 24
                    height: seg.height

                    // Multiple choice: every active option has its own marker
                    Rectangle {
                        visible: seg.multi
                        anchors.fill: parent
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        anchors.leftMargin: 1
                        anchors.rightMargin: 1
                        radius: height / 2
                        color: Theme.accentSoft
                        border.width: 1
                        border.color: Theme.tint(Theme.accent, 0.3)
                        opacity: opt.on ? 1 : 0
                        scale: opt.on ? 1 : 0.85

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 180
                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 240
                                easing.type: Easing.OutBack
                            }

                        }

                    }

                    Text {
                        id: optText

                        anchors.centerIn: parent
                        text: opt.modelData.label
                        font.family: Theme.font
                        font.pixelSize: Theme.sizeBody
                        font.bold: opt.on
                        color: opt.on ? Theme.accent : (optMouse.containsMouse ? Theme.text : Theme.textDim)

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                    }

                    MouseArea {
                        id: optMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(opt.modelData.key)
                    }

                }

            }

        }

    }

    // New search/filter: start at the top again
    Connections {
        function onReset() {
            whGrid.currentIndex = 0;
            whGrid.contentY = whGrid.originY;
        }

        target: WallhavenState
    }

    Timer {
        id: introTimer

        interval: 700
        onTriggered: root.intro = false
    }

    // ==== Search bar with switcher ====
    Rectangle {
        id: searchBar

        visible: root.tabActive
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
            anchors.rightMargin: 156
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.font
            font.pixelSize: 16
            color: WalColors.color7
            text: PickerManager.searchText
            onTextChanged: {
                PickerManager.searchText = text;
                WallhavenState.setQuery(text);
            }
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
                if (key >= Qt.Key_Left && key <= Qt.Key_Down) {
                    scrollAnim.stop();
                    whScrollAnim.stop();
                }
                // Delete (to the trash, press twice): Del only with an empty search,
                // otherwise Del deletes characters; Ctrl+D always works
                const ctrl = event.modifiers & Qt.ControlModifier;
                if (!root.browsing && ((key === Qt.Key_Delete && text === "") || (key === Qt.Key_D && ctrl))) {
                    root.deleteAt(grid.currentIndex);
                    event.accepted = true;
                    return ;
                }
                switch (key) {
                case Qt.Key_Down:
                    root.activeGrid.moveCurrentIndexDown();
                    event.accepted = true;
                    break;
                case Qt.Key_Up:
                    root.activeGrid.moveCurrentIndexUp();
                    event.accepted = true;
                    break;
                case Qt.Key_Left:
                    root.activeGrid.moveCurrentIndexLeft();
                    event.accepted = true;
                    break;
                case Qt.Key_Right:
                    root.activeGrid.moveCurrentIndexRight();
                    event.accepted = true;
                    break;
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 54
            anchors.verticalCenter: parent.verticalCenter
            text: root.browsing ? "Search wallhaven.cc" : "Search"
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

    // ==== Button next to the search: browse wallhaven.cc (as in VPN and music) ====
    // Shared building block (PickerAddButton): in the wallhaven view it becomes the X, the number shows
    // running downloads; if some run with the view closed, a ring spins
    PickerAddButton {
        id: addButton

        visible: root.tabActive
        anchors.left: searchBar.right
        anchors.leftMargin: 10
        anchors.verticalCenter: searchBar.verticalCenter
        progress: root.browseT
        count: Object.keys(WallhavenState.downloading).length
        busy: count > 0 && !root.browsing
        onClicked: {
            if (root.browsing)
                WallhavenState.close();
            else
                WallhavenState.open();
            searchInput.forceActiveFocus();
        }
    }

    // ==== Filter bar below the search (wallhaven only) ====
    // Glides out from under the search bar when switching; the groups come one after another slightly offset.
    Row {
        id: filterBar

        // Offset per group: 0 = still invisible, 1 = there
        function stagger(i) {
            return Math.max(0, Math.min(1, root.browseT * 1.8 - i * 0.3));
        }

        visible: root.tabActive && root.browseT > 0.01
        enabled: root.browsing
        anchors.top: searchBar.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        opacity: root.tabIn

        SegmentGroup {
            glyph: "󰋩"
            multi: true
            options: [{
                "key": "catGeneral",
                "label": "General"
            }, {
                "key": "catAnime",
                "label": "Anime"
            }, {
                "key": "catPeople",
                "label": "People"
            }]
            active: ["catGeneral", "catAnime", "catPeople"].filter((k) => {
                return WallhavenState[k];
            })
            onPicked: (key) => {
                return WallhavenState.setFilter(key, !WallhavenState[key]);
            }
            opacity: filterBar.stagger(0)
            transform: Translate {
                y: (1 - filterBar.stagger(0)) * -10
            }
        }

        SegmentGroup {
            glyph: "󰒺"
            options: [{
                "key": "toplist",
                "label": "Top"
            }, {
                "key": "hot",
                "label": "Hot"
            }, {
                "key": "date_added",
                "label": "New"
            }, {
                "key": "random",
                "label": "Random"
            }]
            active: [WallhavenState.sorting]
            onPicked: (key) => {
                return WallhavenState.setFilter("sorting", key);
            }
            opacity: filterBar.stagger(1)
            transform: Translate {
                y: (1 - filterBar.stagger(1)) * -10
            }
        }

        SegmentGroup {
            glyph: "󰍹"
            options: [{
                "key": "1920x1080",
                "label": "1080p"
            }, {
                "key": "2560x1440",
                "label": "1440p"
            }, {
                "key": "3840x2160",
                "label": "4K"
            }]
            active: [WallhavenState.minResolution]
            onPicked: (key) => {
                return WallhavenState.setFilter("minResolution", key);
            }
            opacity: filterBar.stagger(2)
            transform: Translate {
                y: (1 - filterBar.stagger(2)) * -10
            }
        }

        // Reset: only grows out when something differs from the default
        Rectangle {
            id: resetFilters

            // grow animates expanding/collapsing, stagger(3) the fly-in with the bar
            property real grow: WallhavenState.filtersChanged ? 1 : 0
            readonly property real shown: grow * filterBar.stagger(3)

            width: 30 * shown
            height: 30
            radius: height / 2
            visible: shown > 0.01
            opacity: shown
            color: resetMouse.containsMouse ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.08)
            border.width: 1
            border.color: resetMouse.containsMouse ? WalColors.withAlpha(WalColors.color4, 0.6) : WalColors.withAlpha(WalColors.color2, 0.22)

            Text {
                anchors.centerIn: parent
                text: "󰑓"
                font.family: Theme.font
                font.pixelSize: 14
                color: resetMouse.containsMouse ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.6)
                rotation: resetMouse.containsMouse ? -90 : 0

                Behavior on rotation {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }

                }

            }

            MouseArea {
                id: resetMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: WallhavenState.resetFilters()
            }

            Behavior on grow {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    // ==== Wallpaper-Grid ====
    Item {
        id: gridArea

        width: root.cellW * root.visibleCols
        height: root.cellH * root.visibleRows
        anchors.top: searchBar.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        // When switching to wallhaven the own collection shrinks away slightly
        opacity: root.tabIn * (1 - root.browseT)
        visible: opacity > 0.01
        enabled: !root.browsing
        scale: 1 - 0.04 * root.browseT
        transformOrigin: Item.Top

        Text {
            anchors.centerIn: parent
            text: "Loading wallpapers…"
            color: WalColors.withAlpha(WalColors.color7, 0.45)
            font.family: Theme.font
            font.pixelSize: 14
            visible: !WallpaperPickerState.wallpapersLoaded && grid.count === 0
        }

        GridView {
            id: grid

            anchors.fill: parent
            flow: GridView.FlowLeftToRight
            model: root.filteredWallpapers
            cellWidth: root.cellW
            cellHeight: root.cellH
            currentIndex: 0
            clip: true
            focus: true
            // one row ahead, so the next images already load while scrolling
            cacheBuffer: root.cellH
            boundsBehavior: Flickable.StopAtBounds
            onMovementStarted: scrollAnim.stop()

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
                    return root.wheelScroll(grid, scrollAnim, event);
                }
            }

            Text {
                anchors.centerIn: parent
                text: "No wallpapers found"
                color: WalColors.withAlpha(WalColors.color7, 0.4)
                font.family: Theme.font
                visible: grid.count === 0 && WallpaperPickerState.wallpapersLoaded
            }

            delegate: Item {
                id: delegateItem

                readonly property bool isCurrent: GridView.isCurrentItem
                // Preview image from the cache; if no preview works, the original
                readonly property string thumbUrl: WallpaperPickerState.thumbCache[modelData.key] || (WallpaperPickerState.thumbFailed[modelData.key] ? modelData.url : "")
                // The preview only came when the tile was already standing -> fade it in softly. Already known ones
                // (searching, reopening) show right away: the small preview loads directly without a gap.
                property bool thumbArrived: false
                // Fade-in animation (staggered, as in the clipboard)
                property real enter: 1

                function playEnter() {
                    enterAnim.stop();
                    enter = 0;
                    enterAnim.start();
                }

                width: grid.cellWidth
                height: grid.cellHeight
                z: isCurrent ? 10 : 0
                // Always full opacity: the selection is shown by size + frame, not by transparency
                scale: isCurrent ? 0.99 : 0.96
                opacity: enter
                onThumbUrlChanged: thumbArrived = true
                Component.onCompleted: {
                    if (root.intro)
                        playEnter();

                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.setWallpaper(modelData.url);
                        event.accepted = true;
                    }
                }

                Connections {
                    function onIntroRunChanged() {
                        delegateItem.playEnter();
                    }

                    target: root
                }

                SequentialAnimation {
                    id: enterAnim

                    PauseAnimation {
                        duration: Math.min(Math.max(0, index), 7) * 55 + 20
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

                // Opaque placeholder while the image is still loading
                Rectangle {
                    width: root.imgW
                    height: root.imgH
                    anchors.centerIn: parent
                    radius: 20
                    color: Qt.lighter(WalColors.color0, 1.5)

                    SoftShadow {
                        radius: 20
                        raised: delegateItem.isCurrent
                        spread: 3
                        offsetY: 1
                        opacityScale: 2.65
                    }

                }

                // ClippingRectangle rounds with a shader; OpacityMask needed two intermediate
                // textures per tile (expensive on weak GPUs)
                ClippingRectangle {
                    width: root.imgW
                    height: root.imgH
                    anchors.centerIn: parent
                    radius: 20
                    color: "transparent"
                    opacity: img.status === Image.Ready ? 1 : 0

                    Image {
                        id: img

                        anchors.fill: parent
                        source: delegateItem.thumbUrl
                        fillMode: Image.PreserveAspectCrop
                        // The original (fallback) is big -> then always load in the background
                        asynchronous: delegateItem.thumbArrived || source.toString() === modelData.url
                        sourceSize: WallpaperPickerState.thumbSize
                    }

                    Behavior on opacity {
                        enabled: delegateItem.thumbArrived

                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: (parent.height - root.imgH) / 2 + 10
                    anchors.rightMargin: (parent.width - root.imgW) / 2 + 10
                    width: modelData.workshop ? 68 : (modelData.video ? 48 : 36)
                    height: 21
                    radius: 7
                    visible: modelData.animated === true
                    color: WalColors.withAlpha(WalColors.color0, 0.8)

                    Text {
                        anchors.centerIn: parent
                        text: modelData.scene ? "SCENE" : modelData.workshop ? "WORKSHOP" : (modelData.video ? "VIDEO" : "GIF")
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.bold: true
                        color: WalColors.color7
                    }
                }

                // Marked for deletion: darkened red with a hint, a second press deletes
                Rectangle {
                    readonly property bool armed: WallpaperPickerState.deleteArmed === modelData.key

                    width: root.imgW
                    height: root.imgH
                    anchors.centerIn: parent
                    radius: 20
                    color: Qt.rgba(0, 0, 0, 0.62)
                    border.width: 2
                    border.color: Theme.bad
                    opacity: armed ? 1 : 0
                    visible: opacity > 0

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰆴"
                            font.family: Theme.font
                            font.pixelSize: 34
                            color: Theme.bad
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.workshop ? "Press again to move to trash · unsubscribe in Steam" : "Press again to move to trash"
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            color: WalColors.color7
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Selection frame in a neutral color (lies above the image)
                Rectangle {
                    width: root.imgW
                    height: root.imgH
                    anchors.centerIn: parent
                    radius: 20
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.selectionFrame
                    opacity: delegateItem.isCurrent && WallpaperPickerState.deleteArmed !== modelData.key ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                MouseArea {
                    id: imageMouseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPositionChanged: (mouse) => {
                        const p = imageMouseArea.mapToItem(null, mouse.x, mouse.y);
                        if (Math.abs(p.x - root.lastMouseX) < 3 && Math.abs(p.y - root.lastMouseY) < 3)
                            return ;

                        root.lastMouseX = p.x;
                        root.lastMouseY = p.y;
                        grid.currentIndex = index;
                    }
                    onClicked: (mouse) => {
                        // Right-click = mark/confirm deletion (like Del)
                        if (mouse.button === Qt.RightButton) {
                            root.deleteAt(index);
                            return ;
                        }
                        // A left click on a marked tile only cancels instead of setting it
                        if (WallpaperPickerState.deleteArmed === modelData.key) {
                            WallpaperPickerState.deleteArmed = "";
                            return ;
                        }
                        grid.currentIndex = index;
                        root.setWallpaper(modelData.url);
                    }
                }

                transform: Translate {
                    y: (1 - delegateItem.enter) * 18
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

    }

    // ==== wallhaven.cc: search hits, click/Enter downloads into the wallpaper folder ====
    // Same tiles as the own collection; already downloaded ones carry a check mark and are set
    // directly with a click. At the end of the list the next page is loaded.
    Item {
        id: whArea

        width: root.cellW * root.visibleCols
        height: root.cellH * root.visibleRows
        anchors.top: searchBar.bottom
        // Room for the filter bar; taken from the bottom margin (there is enough air there)
        anchors.topMargin: 60
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: root.tabIn * root.browseT
        visible: opacity > 0.01
        enabled: root.browsing

        Text {
            anchors.centerIn: parent
            visible: whGrid.count === 0
            text: WallhavenState.loading ? "Searching wallhaven…" : (WallhavenState.failed ? "wallhaven.cc not reachable" : "No wallpapers found")
            color: WalColors.withAlpha(WalColors.color7, 0.45)
            font.family: Theme.font
            font.pixelSize: 14
        }

        GridView {
            id: whGrid

            anchors.fill: parent
            flow: GridView.FlowLeftToRight
            model: WallhavenState.results
            cellWidth: root.cellW
            cellHeight: root.cellH
            currentIndex: 0
            clip: true
            cacheBuffer: root.cellH
            boundsBehavior: Flickable.StopAtBounds
            onMovementStarted: whScrollAnim.stop()
            // Fetch the next page already two rows before the end
            onContentYChanged: {
                if (count > 0 && contentY + height >= originY + contentHeight - 2 * root.cellH)
                    WallhavenState.fetch(false);

            }
            // Also by keyboard: selection in the last row -> load more
            onCurrentIndexChanged: {
                if (count > 0 && currentIndex >= count - root.visibleCols * 2)
                    WallhavenState.fetch(false);

            }

            NumberAnimation {
                id: whScrollAnim

                target: whGrid
                property: "contentY"
                duration: 260
                easing.type: Easing.OutCubic
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    return root.wheelScroll(whGrid, whScrollAnim, event);
                }
            }

            delegate: Item {
                id: whItem

                required property var model
                required property int index
                readonly property bool isCurrent: GridView.isCurrentItem
                readonly property bool isLoading: WallhavenState.downloading[model.wid] === true
                readonly property bool isSaved: WallhavenState.isDownloaded(model)
                property real enter: 1

                width: whGrid.cellWidth
                height: whGrid.cellHeight
                z: isCurrent ? 10 : 0
                scale: isCurrent ? 0.99 : 0.96
                opacity: enter
                // Only freshly loaded tiles fade in staggered; tiles created again when scrolling back
                // are there right away (otherwise every row flickers while scrolling)
                Component.onCompleted: {
                    if (index >= WallhavenState.animFrom && Date.now() - WallhavenState.appendedAt < 1500) {
                        enter = 0;
                        whEnterAnim.start();
                    }
                }

                SequentialAnimation {
                    id: whEnterAnim

                    PauseAnimation {
                        duration: Math.min(Math.max(0, whItem.index - WallhavenState.animFrom), 7) * 55 + 20
                    }

                    NumberAnimation {
                        target: whItem
                        property: "enter"
                        to: 1
                        duration: 460
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.outQuint
                    }

                }

                Rectangle {
                    width: root.imgW
                    height: root.imgH
                    anchors.centerIn: parent
                    radius: 20
                    color: Qt.lighter(WalColors.color0, 1.5)

                    SoftShadow {
                        radius: 20
                        raised: whItem.isCurrent
                        spread: 3
                        offsetY: 1
                        opacityScale: 2.65
                    }

                }

                ClippingRectangle {
                    id: whClip

                    width: root.imgW
                    height: root.imgH
                    anchors.centerIn: parent
                    radius: 20
                    color: "transparent"

                    Image {
                        id: whImg

                        anchors.fill: parent
                        source: whItem.model.thumb
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    // Darken during the download, so the state is clear even without looking at the badge
                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        opacity: whItem.isLoading ? 0.45 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                            }

                        }

                    }

                    // Resolution at the bottom left
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        width: resText.implicitWidth + 16
                        height: 24
                        radius: height / 2
                        color: WalColors.withAlpha(WalColors.color0, 0.7)
                        opacity: whItem.isCurrent ? 1 : 0.75

                        Text {
                            id: resText

                            anchors.centerIn: parent
                            text: whItem.model.resolution
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: WalColors.color7
                        }

                    }

                    // State at the top right: download arrow (on selection), loading, already in the folder
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12
                        width: 34
                        height: 34
                        radius: height / 2
                        visible: opacity > 0.01
                        opacity: whItem.isSaved || whItem.isLoading || whItem.isCurrent ? 1 : 0
                        color: whItem.isSaved ? WalColors.color4 : WalColors.withAlpha(WalColors.color0, 0.75)

                        Text {
                            id: stateIcon

                            anchors.centerIn: parent
                            text: whItem.isSaved ? "󰄬" : (whItem.isLoading ? "󰔟" : "󰇚")
                            font.family: Theme.font
                            font.pixelSize: 17
                            color: whItem.isSaved ? Theme.onAccent : WalColors.color7

                            RotationAnimation on rotation {
                                running: whItem.isLoading
                                from: 0
                                to: 360
                                duration: 1400
                                loops: Animation.Infinite
                                onRunningChanged: {
                                    if (!running)
                                        stateIcon.rotation = 0;

                                }
                            }

                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 160
                            }

                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }

                        }

                    }

                }

                Rectangle {
                    width: root.imgW
                    height: root.imgH
                    anchors.centerIn: parent
                    radius: 20
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.selectionFrame
                    opacity: whItem.isCurrent ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                MouseArea {
                    id: whMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: (mouse) => {
                        const p = whMouse.mapToItem(null, mouse.x, mouse.y);
                        if (Math.abs(p.x - root.lastMouseX) < 3 && Math.abs(p.y - root.lastMouseY) < 3)
                            return ;

                        root.lastMouseX = p.x;
                        root.lastMouseY = p.y;
                        whGrid.currentIndex = whItem.index;
                    }
                    onClicked: {
                        whGrid.currentIndex = whItem.index;
                        root.activateRemote(whItem.model);
                    }
                }

                transform: Translate {
                    y: (1 - whItem.enter) * 18 + (1 - root.browseT) * 24
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

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
