import "../common"
import "../services"
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Item {
    id: root

    // Song list and cover cache come from the singleton.
    property var allSongs: MusicPickerState.allSongs
    // Play heat taken once per opening (MusicPickerState.heatMap), so a song being counted does not
    // reorder the grid under the mouse
    property var heatSnap: ({
    })
    readonly property string sortMode: MusicPickerState.sortMode
    // Search filters, the order comes from the sort row below the search bar. allSongs is sorted by
    // name, so name is the tie-break everywhere (never played songs follow the played ones A-Z).
    property var filteredSongs: {
        const q = PickerManager.searchText.toLowerCase();
        const list = allSongs.filter((song) => {
            return song.toLowerCase().includes(q);
        });
        if (sortMode === "name")
            return list;

        const order = {
        };
        list.forEach((song, i) => {
            order[song] = i;
        });
        const key = sortMode === "recent" ? MusicPickerState.songAdded : heatSnap;
        return list.sort((a, b) => {
            return ((key[b] || 0) - (key[a] || 0)) || (order[a] - order[b]);
        });
    }
    property var coverCache: MusicPickerState.coverCache
    property real lastMouseX: -1
    property real lastMouseY: -1
    // Download view, built like wallhaven (wallpaper) and the file browser (VPN): the search bar
    // stays and becomes the link field, the + button becomes the X, and instead of the songs the
    // download stage glides in
    property bool addOpen: false
    // 0 = songs, 1 = download (soft transition like browseT in wallpaper/VPN)
    property real addT: addOpen ? 1 : 0
    property bool queueOpen: false
    property real queueT: queueOpen ? 1 : 0
    readonly property bool canToggleQueue: MusicPickerState.pickerVisible && !addOpen
    readonly property var queue: MusicPickerState.queue
    readonly property string nowPlaying: MusicPickerState.nowPlaying
    readonly property string musicDir: MusicPickerState.musicDir
    // The most recently downloaded song (empty when multiple songs)
    readonly property string resultPath: (MusicPickerState.dlName !== "" && MusicPickerState.dlName.indexOf(" Songs") === -1) ? MusicPickerState.dlName + ".mp3" : ""
    readonly property real cellW: Theme.pickerCellW
    readonly property real cellH: Theme.pickerCellH
    readonly property int gridColumns: Math.max(1, Math.min(5, Math.floor((width - Theme.px(96)) / cellW)))
    readonly property real boxSize: Theme.pickerTile
    readonly property real boxRadius: Theme.pickerTileRadius
    readonly property real coverSize: 84
    readonly property real coverRadius: 15
    // ==== Tab switch: only the content animates, the search bar always stays ====
    // tabIn: 0 = content hidden, 1 = fully there. The search bar (and the + button) on the other hand
    // switches right away, so it never flickers or moves during the switch.
    // Also active during the closing animation, so everything fades out together
    readonly property bool tabActive: PickerManager.activePicker === "music" || PickerManager.closingPicker === "music"
    property real tabIn: tabActive ? 1 : 0
    // ==== Elements fade in one after another when showing (as in the clipboard) ====
    // intro: short time window in which newly created elements play the animation.
    // introRun: counted up, so elements that already exist play it too.
    property bool intro: false
    property int introRun: 0

    function playIntro() {
        heatSnap = MusicPickerState.heatMap();
        intro = true;
        introTimer.restart();
        introRun++;
    }

    function focusSearch() {
        searchInput.forceActiveFocus();
    }

    // Plays a song right away. The user's queue survives: the played song drops
    // out of it, the rest is inserted again behind the new song.
    function playSong(songPath, keepOpen) {
        if (!songPath || MusicPickerState.queueSyncing)
            return ;

        MusicPickerState.playSong(songPath);
        if (!keepOpen)
            MusicPickerState.close();

    }

    function displayName(songPath) {
        return MusicPickerState.displayName(songPath);
    }

    function coverUrl(songPath) {
        const cover = root.coverCache[songPath];
        return cover ? "file://" + cover : "";
    }

    function toggleQueueView() {
        if (queueOpen) {
            closeQueue();
        } else {
            queueOpen = true;
            queueList.currentIndex = root.queue.length > 0 ? 0 : -1;
            queueList.positionViewAtBeginning();
            queueList.forceActiveFocus();
        }
    }

    function closeQueue() {
        queueOpen = false;
        root.focusSearch();
    }

    // ==== Queue ====
    // Add to / remove from the queue. srcItem = item the record flies away from.
    function toggleQueue(songPath, srcItem) {
        if (!songPath || MusicPickerState.queueSyncing)
            return ;

        const idx = MusicPickerState.queue.indexOf(songPath);
        if (idx !== -1) {
            MusicPickerState.removeFromQueue(idx);
            return ;
        }
        // Nothing is playing -> there is nothing to queue behind, just start it
        if (MusicPickerState.nowPlaying === "") {
            root.playSong(songPath, true);
            return ;
        }
        if (srcItem)
            root.flyToQueue(songPath, srcItem);

        MusicPickerState.addToQueue(songPath);
    }

    // The record lands at the icon in the search bar.
    function flyToQueue(songPath, srcItem) {
        const from = srcItem.mapToItem(root, srcItem.width / 2, srcItem.height / 2);
        const to = queueIcon.mapToItem(root, queueIcon.width / 2, queueIcon.height / 2);
        flyerComp.createObject(root, {
            "fromX": from.x,
            "fromY": from.y,
            "toX": to.x,
            "toY": to.y,
            "cover": root.coverUrl(songPath)
        });
    }

    // ==== Download view ====
    function openAdd(prefill) {
        root.addOpen = true;
        root.queueOpen = false;
        if (prefill)
            linkInput.text = prefill;
        else if (linkInput.text === "" && MusicPickerState.dlPhase === "idle")
            clipPaste.running = true; // Suggest link from clipboard
        Qt.callLater(linkInput.forceActiveFocus);
    }

    function closeAdd() {
        root.addOpen = false;
        searchInput.forceActiveFocus();
    }

    function toggleAdd() {
        if (root.addOpen)
            closeAdd();
        else
            openAdd("");
    }

    // If a download is already running, the link goes into the queue and the field is cleared
    function submitLink() {
        if (MusicPickerState.downloadUrl(linkInput.text) === "queued")
            linkInput.text = "";

    }

    // Acknowledge done/error and enter another link
    function another(clearText) {
        MusicPickerState.dlAck();
        if (clearText)
            linkInput.text = "";

        linkInput.forceActiveFocus();
    }

    onTabActiveChanged: {
        if (tabActive)
            playIntro();

    }
    Component.onCompleted: {
        // Ensure the song list is loaded,
        // in case the picker is opened first.
        MusicPickerState.loadSongs();
        if (tabActive)
            playIntro();

    }
    // Only after the ScriptModel update: otherwise the GridView holds on to the old selection when inserting
    onFilteredSongsChanged: Qt.callLater(() => {
        grid.currentIndex = 0;
    })
    Behavior on addT {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.standard
        }

    }

    Behavior on queueT {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.standard
        }
    }

    Shortcut {
        sequence: "Alt+S"
        enabled: root.tabActive && !root.addOpen
        onActivated: MusicPickerState.cycleSort(1)
    }

    Shortcut {
        sequence: "Alt+Q"
        enabled: root.canToggleQueue
        onActivated: root.toggleQueueView()
    }

    Keys.onEscapePressed: {
        if (root.queueOpen)
            root.closeQueue();
        else if (root.addOpen)
            root.closeAdd();
        else
            MusicPickerState.close();
    }
    Keys.onReturnPressed: (event) => {
        // In download mode, Enter must not start a (hidden) song
        if (root.addOpen || root.filteredSongs.length === 0)
            return ;

        const song = root.filteredSongs[grid.currentIndex];
        // Ctrl+Enter = add to queue, Enter = play now
        if (event.modifiers & Qt.ControlModifier)
            root.toggleQueue(song, grid.currentItem);
        else
            root.playSong(song);
    }

    Timer {
        id: introTimer

        interval: 700
        onTriggered: root.intro = false
    }

    // Read clipboard (wl-clipboard); only valid links are accepted
    Process {
        id: clipPaste

        command: ["wl-paste", "-n"]

        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (MusicPickerState.serviceOf(t) !== "" && linkInput.text === "")
                    linkInput.text = t;

            }
        }

    }

    Connections {
        function onDlDoneCounterChanged() {
            linkInput.text = "";
            // Prepare cover of the new song for the result display
            if (root.resultPath !== "")
                MusicPickerState.requestCover(root.resultPath);

        }

        function onPickerVisibleChanged() {
            if (!MusicPickerState.pickerVisible)
                root.queueOpen = false;
        }

        target: MusicPickerState
    }

    // ==== Search bar with switcher (the link field in download mode) ====
    // Stays unchanged in both views as in wallpaper/VPN; only the icon, placeholder and
    // the input field change
    Rectangle {
        id: searchBar

        readonly property string svc: MusicPickerState.serviceOf(linkInput.text)

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

        Item {
            id: searchLayer

            anchors.fill: parent

            // Magnifier or link; with a recognized link the icon of the service in the accent color
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: !root.addOpen ? "󰍉" : (searchBar.svc === "spotify" ? "󰓇" : (searchBar.svc === "youtube" ? "󰗃" : (searchBar.svc === "soundcloud" ? "󰓀" : "󰌷")))
                font.family: Theme.font
                font.pixelSize: 18
                color: root.addOpen && searchBar.svc !== "" ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.5)

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

            TextInput {
                id: searchInput

                visible: !root.addOpen
                enabled: !root.addOpen
                anchors.fill: parent
                anchors.leftMargin: 54
                anchors.rightMargin: 156
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.font
                font.pixelSize: 16
                color: WalColors.color7
                text: PickerManager.searchText
                onTextChanged: {
                    // If a Spotify/SoundCloud/YouTube link is pasted: move to the download view
                    if (MusicPickerState.serviceOf(text) !== "") {
                        const link = text.trim();
                        text = "";
                        root.openAdd(link);
                        return ;
                    }
                    PickerManager.searchText = text;
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

            // Download mode: the same field takes the link (Enter = download, if one is running = queue)
            TextInput {
                id: linkInput

                visible: root.addOpen
                enabled: root.addOpen
                // Up to the picker icons, not below them (links are long and scroll to the end)
                anchors.left: parent.left
                anchors.right: pickerSwitcher.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 54
                anchors.rightMargin: 8
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.font
                font.pixelSize: 16
                color: WalColors.color7
                selectionColor: WalColors.withAlpha(WalColors.color4, 0.4)
                clip: true
                selectByMouse: true
                onTextEdited: {
                    if (MusicPickerState.dlPhase !== "busy")
                        MusicPickerState.dlAck();

                }
                Keys.onPressed: (event) => {
                    // Tab switches the picker here too (as in the search)
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        if (event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier))
                            PickerManager.cycleBackward();
                        else
                            PickerManager.cycle();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submitLink();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.closeAdd();
                        event.accepted = true;
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 54
                anchors.right: parent.right
                anchors.rightMargin: 156
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.addOpen ? "Paste a song link" : "Search"
                color: WalColors.withAlpha(WalColors.color7, 0.35)
                font.family: Theme.font
                font.pixelSize: 14
                visible: root.addOpen ? linkInput.text === "" : searchInput.text === ""
            }

            PickerSwitcher {
                id: pickerSwitcher

                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                focusTarget: root.addOpen ? linkInput : searchInput
            }

        }

    }

    // ==== Button next to the search: download songs by link (as in wallpaper and VPN) ====
    // Shared building block (PickerAddButton): in download mode it becomes the X, the number shows running +
    // waiting downloads; if one runs with the view closed, a ring spins, afterwards a green dot
    PickerAddButton {
        id: addButton

        visible: root.tabActive
        anchors.left: searchBar.right
        anchors.leftMargin: 10
        anchors.verticalCenter: searchBar.verticalCenter
        progress: root.addT
        busy: MusicPickerState.dlBusy && !root.addOpen
        count: (MusicPickerState.dlBusy ? 1 : 0) + MusicPickerState.dlQueue.length
        doneDot: MusicPickerState.dlPhase === "done" && !root.addOpen
        onClicked: root.toggleAdd()
    }

    // Queue and download sit on the same axis as the shared search.
    Rectangle {
        id: queueTrigger

        property real landingScale: 1

        objectName: "musicQueueTrigger"
        anchors.right: searchBar.left
        anchors.rightMargin: Theme.gapSmall
        anchors.verticalCenter: searchBar.verticalCenter
        width: queueTriggerContent.implicitWidth + Theme.px(24)
        height: Theme.px(38)
        radius: height / 2
        color: root.queueOpen ? Theme.accentSoft : (queueTriggerMouse.containsMouse ? Theme.cardHover : Theme.card)
        border.color: root.queueOpen ? Theme.tint(Theme.accent, 0.48) : Theme.stroke
        opacity: root.tabIn * (1 - root.addT)
        visible: opacity > 0.01
        enabled: root.canToggleQueue
        scale: queueTrigger.landingScale * (queueTriggerMouse.pressed ? 0.95 : 1)
        Accessible.role: Accessible.Button
        Accessible.name: (root.queueOpen ? "Close queue" : "Open queue") + ", " + root.queue.length + " songs"
        Accessible.onPressAction: root.toggleQueueView()

        Row {
            id: queueTriggerContent

            anchors.centerIn: parent
            spacing: Theme.px(7)

            Text {
                id: queueIcon

                anchors.verticalCenter: parent.verticalCenter
                text: "󰲸"
                font.family: Theme.font
                font.pixelSize: Theme.px(17)
                color: root.queueOpen || root.queue.length > 0 ? Theme.accent : Theme.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: searchBar.x >= Theme.px(142)
                text: "Queue"
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLarge
                font.weight: Font.DemiBold
                color: Theme.text
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.queue.length > 0
                text: root.queue.length
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeLabel
                color: Theme.accent
            }
        }

        MouseArea {
            id: queueTriggerMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleQueueView()
        }

        Controls.ToolTip.text: root.queueOpen ? "Close queue (Alt+Q)" : "Open queue (Alt+Q)"
        Controls.ToolTip.delay: Appearance.anim.durations.slow
        Controls.ToolTip.visible: queueTriggerMouse.containsMouse && !queueTriggerMouse.pressed

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }
        }

        SequentialAnimation {
            id: queuePulse

            NumberAnimation {
                target: queueTrigger
                property: "landingScale"
                to: 1.10
                duration: Appearance.anim.durations.fast / 2
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: queueTrigger
                property: "landingScale"
                to: 1
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }
        }
    }

    // ==== Sort row: quiet words below the search, a dot glides under the active one ====
    Item {
        id: sortRow

        readonly property var modes: [{
            "id": "top",
            "label": "Most played"
        }, {
            "id": "name",
            "label": "Name"
        }, {
            "id": "recent",
            "label": "Recent"
        }]
        readonly property Item activeItem: sortRepeater.count > 0 ? sortRepeater.itemAt(Math.max(0, MusicPickerState.sortModes.indexOf(root.sortMode))) : null

        anchors.horizontalCenter: searchBar.horizontalCenter
        anchors.top: searchBar.bottom
        anchors.topMargin: Theme.px(12)
        width: sortWords.width
        height: sortWords.height + Theme.px(8)
        // Gives way to the queue (it opens in the same place) and the download view
        opacity: root.tabIn * (1 - root.addT) * (1 - root.queueT)
        visible: opacity > 0.01
        enabled: !root.addOpen && !root.queueOpen

        Row {
            id: sortWords

            spacing: Theme.px(20)

            Repeater {
                id: sortRepeater

                model: sortRow.modes

                Text {
                    id: word

                    required property var modelData
                    readonly property bool active: root.sortMode === modelData.id

                    text: modelData.label
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                    font.weight: active ? Font.Medium : Font.Normal
                    color: active ? Theme.text : (wordMouse.containsMouse ? Theme.textDim : Theme.textFaint)

                    MouseArea {
                        id: wordMouse

                        anchors.fill: parent
                        anchors.margins: -Theme.px(6)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MusicPickerState.setSort(word.modelData.id)
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

            }

        }

        Rectangle {
            width: Theme.px(4)
            height: width
            radius: width / 2
            color: Theme.accent
            y: sortWords.height + Theme.px(4)
            x: sortRow.activeItem ? sortRow.activeItem.x + (sortRow.activeItem.width - width) / 2 : 0
            visible: sortRow.activeItem !== null

            Behavior on x {
                Springy {
                }

            }

        }

    }

    // ==== Song grid ====
    Item {
        id: gridArea

        readonly property real collapsedY: searchBar.y + searchBar.height + Theme.px(48)
        readonly property real expandedY: queueReveal.y + queuePanel.height + Theme.px(18)
        readonly property real viewT: 1 - root.addT

        function heightAt(top) {
            const available = Math.max(0, root.height - top - Theme.px(34));
            // In the final state show whole cover rows, as long as one fits.
            return available < root.cellH ? available : Math.floor(available / root.cellH) * root.cellH;
        }

        objectName: "musicSongGrid"
        anchors.horizontalCenter: parent.horizontalCenter
        y: collapsedY + (expandedY - collapsedY) * root.queueT
        width: root.gridColumns * root.cellW
        height: heightAt(collapsedY) * (1 - root.queueT) + heightAt(expandedY) * root.queueT
        opacity: viewT * root.tabIn
        scale: 0.96 + 0.04 * viewT
        enabled: !root.addOpen
        visible: opacity > 0.01 && height > 0

        // Loading indicator, in case the song list is still coming from the mpc scan
        Text {
            anchors.centerIn: parent
            text: "Loading songs…"
            color: WalColors.withAlpha(WalColors.color7, 0.45)
            font.family: Theme.font
            font.pixelSize: 14
            visible: !MusicPickerState.songsLoaded && grid.count === 0
        }

        GridView {
            id: grid

            anchors.fill: parent
            // ScriptModel compares the old and new list and only reports real changes:
            // while typing visible tiles stay instead of all being rebuilt every time
            model: ScriptModel {
                values: root.filteredSongs
            }
            cellWidth: root.cellW
            cellHeight: root.cellH
            currentIndex: 0
            // Keep one row above/below ready: when scrolling the covers are already loaded
            cacheBuffer: root.cellH
            clip: true
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
                text: "No songs found"
                color: WalColors.withAlpha(WalColors.color7, 0.4)
                font.family: Theme.font
                visible: grid.count === 0 && MusicPickerState.songsLoaded
            }

            delegate: Item {
                id: cell

                readonly property bool isCurrent: GridView.isCurrentItem
                readonly property string songPath: modelData
                // Cover cache comes from the state – path remains after
                // closing, no need to re-extract.
                readonly property string coverPath: root.coverCache[songPath] ? ("file://" + root.coverCache[songPath]) : ""
                readonly property int qIndex: MusicPickerState.queue.indexOf(songPath)
                readonly property bool queued: qIndex !== -1
                // The cover only came when the tile was already standing -> fade it in softly. Already known covers
                // (searching, reopening) are shown right away: the preview image is so small that it
                // can be loaded directly, without a gap and without fading in.
                property bool coverArrived: false
                // Fade-in animation (staggered, as in the clipboard)
                property real enter: 1
                // index is briefly -1 when removing (ScriptModel) -> do not let it go negative
                readonly property int gridCol: Math.max(0, index) % root.gridColumns
                readonly property int gridRow: Math.floor(Math.max(0, index) / root.gridColumns)

                function playEnter() {
                    enterAnim.stop();
                    enter = 0;
                    enterAnim.start();
                }

                width: grid.cellWidth
                height: grid.cellHeight
                opacity: enter
                // Buffered covers also load outside the visible grid.
                visible: y < grid.contentY + grid.height && y + height > grid.contentY
                onCoverPathChanged: coverArrived = true
                Component.onCompleted: {
                    if (songPath)
                        MusicPickerState.requestCover(songPath);

                    if (root.intro)
                        playEnter();

                }

                Connections {
                    function onIntroRunChanged() {
                        cell.playEnter();
                    }

                    target: root
                }

                SequentialAnimation {
                    id: enterAnim

                    PauseAnimation {
                        duration: Math.min(cell.gridRow, 4) * 70 + cell.gridCol * 35 + 20
                    }

                    NumberAnimation {
                        target: cell
                        property: "enter"
                        to: 1
                        duration: 460
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.outQuint
                    }

                }

                // The record that slides out of the sleeve (selected song only).
                // Click it -> it flies into the queue.
                Component {
                    id: recordComp

                    Item {
                        id: rec

                        property bool out: false
                        readonly property real slide: out ? (recMouse.containsMouse ? 52 : 40) : 0

                        Component.onCompleted: Qt.callLater(() => {
                            rec.out = true;
                        })

                        VinylDisc {
                            id: recDisc

                            size: 86
                            cover: cell.coverPath
                            anchors.verticalCenter: parent.verticalCenter
                            x: (rec.width - width) / 2 + rec.slide
                            spin: rec.out && MusicPickerState.pickerVisible
                            spinDuration: 5000
                            shadow: true
                            scale: recMouse.containsMouse ? 1.05 : 1

                            Behavior on x {
                                NumberAnimation {
                                    duration: 340
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.4
                                }

                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 160
                                    easing.type: Easing.OutCubic
                                }

                            }

                        }

                        // Hit area = only the part of the record that sticks out of the sleeve
                        MouseArea {
                            id: recMouse

                            x: rec.width + 4
                            y: (rec.height - 60) / 2
                            width: 40
                            height: 60
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleQueue(cell.songPath, recDisc)
                        }

                    }

                }

                // Queued: small spinning record with the queue position in the corner.
                // Click it -> take the song out of the queue again.
                Component {
                    id: badgeComp

                    VinylDisc {
                        id: badge

                        readonly property bool hot: badgeMouse.containsMouse
                        property bool born: false

                        size: 38
                        labelText: hot ? "×" : (cell.qIndex + 1)
                        labelColor: hot ? WalColors.color1 : WalColors.color2
                        spin: !hot && MusicPickerState.pickerVisible
                        spinDuration: 3500
                        shadow: true
                        scale: (born ? 1 : 0) * (hot ? 1.15 : 1)
                        Component.onCompleted: Qt.callLater(() => {
                            badge.born = true;
                        })

                        MouseArea {
                            id: badgeMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleQueue(cell.songPath, null)
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 260
                                easing.type: Easing.OutBack
                                easing.overshoot: 2.2
                            }

                        }

                    }

                }

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    // Above the click area so the record gets its clicks
                    z: 1

                    // Sleeve = cover; the record sits behind it
                    Item {
                        id: sleeve

                        width: root.boxSize
                        height: root.boxSize
                        anchors.horizontalCenter: parent.horizontalCenter

                        Loader {
                            anchors.fill: parent
                            active: cell.isCurrent && !cell.queued
                            sourceComponent: recordComp
                        }

                        Rectangle {
                            id: iconBg

                            anchors.fill: parent
                            radius: root.boxRadius
                            // Opaque ground: the record behind must not shine through
                            color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color2, isCurrent ? 0.2 : 0.1))
                            scale: isCurrent ? 1.06 : 1

                            // Soft shadow under the sleeve (same part as in VPN and apps)
                            SoftShadow {
                                radius: root.boxRadius
                                raised: cell.isCurrent
                                blur: 20
                                spread: 6
                                opacityScale: 2.8
                            }

                            // The cover fills the whole sleeve (no frame in a frame anymore).
                            // ClippingRectangle rounds with a shader; OpacityMask needed two intermediate
                            // textures per tile (expensive on weak GPUs)
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: root.boxRadius
                                color: "transparent"
                                opacity: coverImage.status === Image.Ready ? 1 : 0

                                Image {
                                    id: coverImage

                                    anchors.fill: parent
                                    source: coverPath
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: cell.coverArrived
                                    sourceSize: Qt.size(root.boxSize * 2, root.boxSize * 2)
                                }

                                Behavior on opacity {
                                    enabled: cell.coverArrived

                                    NumberAnimation {
                                        duration: 240
                                        easing.type: Easing.OutCubic
                                    }

                                }

                            }

                            Text {
                                id: fallback

                                // Only without a cover (do not flash briefly while loading)
                                visible: (cell.coverPath === "" && !!MusicPickerState.noCover[cell.songPath]) || coverImage.status === Image.Error
                                anchors.centerIn: parent
                                text: "♪"
                                font.pixelSize: 44
                                color: WalColors.withAlpha(WalColors.color2, 0.8)
                            }

                            // Subtle shine on top, light shadow below: gives the cover depth
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                visible: coverImage.status === Image.Ready

                                gradient: Gradient {
                                    GradientStop {
                                        position: 0
                                        color: "#14FFFFFF"
                                    }

                                    GradientStop {
                                        position: 0.4
                                        color: "#00000000"
                                    }

                                    GradientStop {
                                        position: 1
                                        color: "#2A000000"
                                    }

                                }

                            }

                            // Fine bright edge
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: 1
                                border.color: "#1AFFFFFF"
                            }

                            // Selection ring with a gap: accent = selected, green = in the queue
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -5
                                radius: root.boxRadius + 5
                                color: "transparent"
                                border.width: 2
                                border.color: cell.queued ? WalColors.color2 : WalColors.color4
                                opacity: cell.isCurrent ? 1 : (cell.queued ? 0.8 : 0)

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Appearance.anim.durations.fast
                                        easing.type: Easing.OutCubic
                                    }

                                }

                                Behavior on border.color {
                                    ColorAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }

                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 140
                                }

                            }

                        }

                        Loader {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -12
                            anchors.rightMargin: -12
                            z: 5
                            active: cell.queued
                            sourceComponent: badgeComp
                        }

                    }

                    Text {
                        width: grid.cellWidth - 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: root.displayName(modelData)
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: WalColors.color7
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }

                }

                // Left click = play now, right click = add to / remove from queue
                MouseArea {
                    id: mArea

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: (mouse) => {
                        const p = mArea.mapToItem(null, mouse.x, mouse.y);
                        if (Math.abs(p.x - root.lastMouseX) < 3 && Math.abs(p.y - root.lastMouseY) < 3)
                            return ;

                        root.lastMouseX = p.x;
                        root.lastMouseY = p.y;
                        grid.currentIndex = index;
                    }
                    onClicked: (mouse) => {
                        grid.currentIndex = index;
                        if (mouse.button === Qt.RightButton)
                            root.toggleQueue(modelData, sleeve);
                        else
                            root.playSong(modelData);
                    }
                }

                transform: Translate {
                    y: (1 - cell.enter) * 18
                }

            }

        }


    }

    // ==== Download view: replaces the song grid (like the wallhaven hits in wallpaper) ====
    // No own window anymore: the link field is the search bar on top, below it the stage glides in
    // (ring on the left, text + stages + buttons on the right), below that the queue of links.
    Item {
        id: dlCard

        readonly property string phase: MusicPickerState.dlPhase
        readonly property bool idle: phase === "idle"
        readonly property bool busy: phase === "busy"
        readonly property bool done: phase === "done"
        readonly property bool failed: phase === "error"
        readonly property string svc: searchBar.svc
        readonly property string svcName: svc === "spotify" ? "Spotify" : (svc === "youtube" ? "YouTube Music" : (svc === "soundcloud" ? "SoundCloud" : ""))
        readonly property real prog: MusicPickerState.dlProgress
        readonly property int stage: MusicPickerState.dlStage
        readonly property color accent: failed ? WalColors.color1 : (done ? WalColors.color2 : WalColors.color4)
        readonly property var stageLabels: ["Search", "Download", "Convert", "Library"]
        readonly property bool hasCover: root.resultPath !== "" && !!root.coverCache[root.resultPath]
        // 0..1: ring fill level (done = full)
        readonly property real ringTarget: done ? 1 : (prog >= 0 ? prog : 0)
        property real doneT: done ? 1 : 0
        property real flashT: 1

        anchors.top: searchBar.bottom
        anchors.topMargin: 48
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(720, gridArea.width)
        height: dlColumn.implicitHeight
        opacity: root.addT * root.tabIn
        visible: opacity > 0.01
        enabled: root.addOpen
        onDoneChanged: {
            if (done)
                flashAnim.restart();

        }

        NumberAnimation {
            id: flashAnim

            target: dlCard
            property: "flashT"
            from: 0
            to: 1
            duration: 750
            easing.type: Easing.OutCubic
        }

        Column {
            id: dlColumn

            width: dlCard.width
            spacing: 14

            // ---- Stage: ring on the left, info on the right, equalizer subtly behind ----
            Rectangle {
                id: stage

                width: parent.width
                height: 176
                radius: 18
                color: WalColors.withAlpha(dlCard.accent, 0.05)
                border.width: 1
                border.color: WalColors.withAlpha(dlCard.accent, dlCard.busy ? 0.3 : 0.12)
                clip: true

                // Equalizer bars at the bottom: dance during download
                Row {
                    id: eq

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    height: 70
                    spacing: 4

                    Repeater {
                        model: 36

                        delegate: Rectangle {
                            required property int index
                            // Pseudo-random but fixed properties per bar
                            readonly property real peak: 0.35 + 0.65 * ((index * 37 % 11) / 10)
                            readonly property int dur: 380 + (index * 53 % 7) * 70
                            property real level: 0

                            width: (eq.width - 35 * eq.spacing) / 36
                            anchors.bottom: parent.bottom
                            height: 4 + level * (eq.height - 8)
                            radius: width / 2
                            color: WalColors.withAlpha(dlCard.accent, 0.1 + 0.2 * level)

                            SequentialAnimation on level {
                                running: dlCard.busy && dlCard.visible
                                loops: Animation.Infinite
                                onRunningChanged: {
                                    if (!running)
                                        level = 0;

                                }

                                NumberAnimation {
                                    to: peak
                                    duration: dur
                                    easing.type: Easing.InOutSine
                                }

                                NumberAnimation {
                                    to: 0.08
                                    duration: dur
                                    easing.type: Easing.InOutSine
                                }

                            }

                            Behavior on level {
                                enabled: !dlCard.busy

                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }

                            }

                        }

                    }

                }

                // ---- Ring ----
                Item {
                    id: ring

                    readonly property real size: 124
                    readonly property real thick: 6
                    readonly property real r: size / 2 - thick / 2
                    property real v: dlCard.ringTarget

                    anchors.left: parent.left
                    anchors.leftMargin: 26
                    anchors.verticalCenter: parent.verticalCenter
                    width: size
                    height: size

                    // Pulsing wave during download
                    Rectangle {
                        id: pulse

                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: dlCard.accent
                        visible: dlCard.busy
                        opacity: 0

                        ParallelAnimation {
                            running: dlCard.busy && dlCard.visible
                            loops: Animation.Infinite

                            NumberAnimation {
                                target: pulse
                                property: "scale"
                                from: 1
                                to: 1.38
                                duration: 1500
                                easing.type: Easing.OutCubic
                            }

                            NumberAnimation {
                                target: pulse
                                property: "opacity"
                                from: 0.5
                                to: 0
                                duration: 1500
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    // One-shot flash on completion
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 3
                        border.color: WalColors.color2
                        opacity: (1 - dlCard.flashT) * 0.7
                        scale: 1 + 0.6 * dlCard.flashT
                        visible: dlCard.flashT < 1
                    }

                    // Track
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: WalColors.withAlpha(dlCard.accent, 0.06)
                        border.width: ring.thick
                        border.color: WalColors.withAlpha(WalColors.color7, 0.08)
                    }

                    // Determinate progress
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        visible: dlCard.done || (dlCard.busy && dlCard.prog >= 0)

                        ShapePath {
                            strokeColor: dlCard.accent
                            strokeWidth: ring.thick
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: ring.size / 2
                                centerY: ring.size / 2
                                radiusX: ring.r
                                radiusY: ring.r
                                startAngle: -90
                                sweepAngle: Math.max(0.5, Math.min(359.9, 360 * ring.v))
                            }

                        }

                    }

                    // Indeterminate progress: rotating arc
                    Item {
                        id: spinner

                        anchors.fill: parent
                        visible: dlCard.busy && dlCard.prog < 0

                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: dlCard.accent
                                strokeWidth: ring.thick
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap

                                PathAngleArc {
                                    centerX: ring.size / 2
                                    centerY: ring.size / 2
                                    radiusX: ring.r
                                    radiusY: ring.r
                                    startAngle: -90
                                    sweepAngle: 110
                                }

                            }

                        }

                        NumberAnimation on rotation {
                            running: spinner.visible && dlCard.visible
                            from: 0
                            to: 360
                            duration: 1100
                            loops: Animation.Infinite
                        }

                    }

                    // Core: cover (done), percent (download) or icon
                    Item {
                        id: core

                        anchors.centerIn: parent
                        width: ring.size - 26
                        height: width

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            opacity: dlCard.done && resultCover.status === Image.Ready ? dlCard.doneT : 0
                            scale: 0.7 + 0.3 * dlCard.doneT
                            visible: opacity > 0.01

                            Image {
                                id: resultCover

                                anchors.fill: parent
                                source: dlCard.hasCover ? "file://" + root.coverCache[root.resultPath] : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(160, 160)
                            }

                        }

                        // Icon / percent
                        Text {
                            id: coreText

                            readonly property bool showCheck: dlCard.done && resultCover.status !== Image.Ready

                            anchors.centerIn: parent
                            visible: !(dlCard.done && resultCover.status === Image.Ready)
                            // Done without a cover: instead of a check mark a sparkle fires at the bottom (coreStar, visual language)
                            text: dlCard.failed ? "󰀦" : (showCheck ? "" : (dlCard.busy && dlCard.prog >= 0 ? Math.round(dlCard.prog * 100) + "%" : "󰇚"))
                            font.family: Theme.font
                            font.pixelSize: (dlCard.busy && dlCard.prog >= 0) ? 26 : 40
                            font.bold: true
                            color: dlCard.accent
                            scale: showCheck ? 0.4 + 0.6 * dlCard.doneT : 1
                            opacity: dlCard.idle && dlCard.svc === "" ? 0.45 : 1

                            // Gentle floating when idle or searching
                            SequentialAnimation on anchors.verticalCenterOffset {
                                running: (dlCard.idle || (dlCard.busy && dlCard.prog < 0)) && dlCard.visible
                                loops: Animation.Infinite

                                NumberAnimation {
                                    to: 4
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }

                                NumberAnimation {
                                    to: -4
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }

                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }

                            }

                        }

                    }

                    // Done without a cover: star birth in the middle of the ring (instead of a check mark)
                    StarBurst {
                        anchors.centerIn: parent
                        size: 15
                        color: dlCard.accent
                        glowColor: dlCard.accent
                        active: dlCard.done && resultCover.status !== Image.Ready
                        visible: active
                    }

                    // Checkmark badge when a cover is in the core
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: 32
                        height: 32
                        radius: height / 2
                        color: WalColors.color2
                        border.width: 3
                        border.color: WalColors.color0
                        scale: (dlCard.done && resultCover.status === Image.Ready) ? dlCard.doneT : 0
                        visible: scale > 0.01

                        // Sparkle instead of a check mark (fires when the badge appears)
                        StarBurst {
                            anchors.centerIn: parent
                            size: 6
                            color: WalColors.color0
                            glowColor: WalColors.color0
                            active: dlCard.done && resultCover.status === Image.Ready
                        }

                    }

                    Behavior on v {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                Column {
                    id: texts

                    anchors.left: ring.right
                    anchors.leftMargin: 26
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.bold: true
                        color: dlCard.failed ? WalColors.color1 : WalColors.color7
                        text: dlCard.busy ? MusicPickerState.dlStatus : (dlCard.done ? (MusicPickerState.dlName || "Done") : (dlCard.failed ? "That didn't work" : (dlCard.svc === "" ? "Add a song" : dlCard.svcName + " song detected")))
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: WalColors.withAlpha(WalColors.color7, 0.5)
                        text: dlCard.busy ? (dlCard.prog >= 0 ? Math.round(dlCard.prog * 100) + " % · saving as mp3" : "One moment …") : (dlCard.done ? "Added to library" : (dlCard.failed ? MusicPickerState.dlError : (dlCard.svc === "" ? "Paste a Spotify, SoundCloud or YouTube link above" : "Ready to download as mp3")))
                    }

                    Item {
                        width: 1
                        height: 10
                    }

                    // ---- Stage indicator ----
                    Item {
                        id: stepper

                        readonly property real colW: width / 4

                        width: parent.width
                        height: 42
                        // When idle, faint as a preview of the steps (fills the area, nothing jumps at the start)
                        opacity: (dlCard.busy || dlCard.done) ? 1 : 0.4

                        // Connector line
                        Rectangle {
                            x: stepper.colW / 2
                            y: 6
                            width: stepper.width - stepper.colW
                            height: 2
                            radius: 1
                            color: WalColors.withAlpha(WalColors.color7, 0.1)
                        }

                        Rectangle {
                            x: stepper.colW / 2
                            y: 6
                            width: (stepper.width - stepper.colW) * Math.min(1, dlCard.stage / 3)
                            height: 2
                            radius: 1
                            color: dlCard.accent

                            Behavior on width {
                                NumberAnimation {
                                    duration: 450
                                    easing.type: Easing.OutCubic
                                }

                            }

                        }

                        Repeater {
                            model: 4

                            delegate: Item {
                                id: step

                                required property int index
                                readonly property bool complete: dlCard.stage > index || dlCard.done
                                readonly property bool current: dlCard.busy && dlCard.stage === index

                                x: index * stepper.colW
                                width: stepper.colW
                                height: stepper.height

                                Rectangle {
                                    id: dot

                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 0
                                    width: 14
                                    height: 14
                                    radius: height / 2
                                    color: step.complete ? dlCard.accent : WalColors.color0
                                    border.width: 2
                                    border.color: (step.complete || step.current) ? dlCard.accent : WalColors.withAlpha(WalColors.color7, 0.2)
                                    scale: step.current ? 1.2 : 1

                                    Text {
                                        anchors.centerIn: parent
                                        visible: step.complete
                                        text: "󰄬"
                                        font.family: Theme.font
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: WalColors.color0
                                    }

                                    // Active stage pulses
                                    SequentialAnimation on opacity {
                                        running: step.current && dlCard.visible
                                        loops: Animation.Infinite

                                        NumberAnimation {
                                            to: 0.45
                                            duration: 520
                                            easing.type: Easing.InOutSine
                                        }

                                        NumberAnimation {
                                            to: 1
                                            duration: 520
                                            easing.type: Easing.InOutSine
                                        }

                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 250
                                        }

                                    }

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 260
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 2
                                        }

                                    }

                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: dot.bottom
                                    anchors.topMargin: 6
                                    text: dlCard.stageLabels[step.index]
                                    font.family: Theme.font
                                    font.pixelSize: 10
                                    font.bold: step.current
                                    color: (step.complete || step.current) ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.35)
                                }

                            }

                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 250
                            }

                        }

                    }

                    // ---- Buttons ----
                    Row {
                        id: buttons

                        spacing: 10

                        DlButton {
                            label: dlCard.done ? "Play" : (dlCard.failed ? "Retry" : "Download")
                            primary: true
                            accent: dlCard.accent
                            active: dlCard.done ? root.resultPath !== "" : (dlCard.failed || dlCard.svc !== "")
                            visible: !dlCard.busy
                            onClicked: {
                                if (dlCard.done)
                                    root.playSong(root.resultPath);
                                else
                                    root.submitLink();
                            }
                        }

                        DlButton {
                            label: dlCard.busy ? "In background" : (dlCard.done ? "Another" : "Back")
                            visible: !dlCard.idle
                            onClicked: {
                                if (dlCard.busy)
                                    root.closeAdd();
                                else if (dlCard.done)
                                    root.another(true);
                                else
                                    root.another(false);
                            }
                        }

                    }

                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 250
                    }

                }

            }

            // ---- Queue: links that come after the running download ----
            Column {
                width: parent.width
                spacing: 6
                visible: MusicPickerState.dlQueue.length > 0

                Text {
                    leftPadding: 6
                    text: "UP NEXT  ·  " + MusicPickerState.dlQueue.length
                    font.family: Theme.font
                    font.pixelSize: Theme.sizeMicro
                    font.bold: true
                    font.letterSpacing: Theme.microSpacing
                    color: WalColors.withAlpha(WalColors.color7, 0.45)
                }

                Repeater {
                    model: MusicPickerState.dlQueue

                    delegate: Rectangle {
                        id: qRow

                        required property string modelData
                        required property int index
                        readonly property string svc: MusicPickerState.serviceOf(modelData)

                        width: dlColumn.width
                        height: 40
                        radius: 14
                        color: WalColors.withAlpha(WalColors.color7, qHover.hovered ? 0.07 : 0.04)

                        HoverHandler {
                            id: qHover
                        }

                        Text {
                            id: qIcon

                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: qRow.svc === "spotify" ? "󰓇" : (qRow.svc === "youtube" ? "󰗃" : (qRow.svc === "soundcloud" ? "󰓀" : "󰌷"))
                            font.family: Theme.font
                            font.pixelSize: 15
                            color: WalColors.withAlpha(WalColors.color4, 0.8)
                        }

                        Text {
                            anchors.left: qIcon.right
                            anchors.leftMargin: 12
                            anchors.right: qRemove.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideMiddle
                            text: qRow.modelData.replace(/^https?:\/\/(www\.)?/, "")
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: WalColors.withAlpha(WalColors.color7, 0.65)
                        }

                        // Remove from the queue
                        Rectangle {
                            id: qRemove

                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: height / 2
                            color: WalColors.withAlpha(WalColors.color1, qRemoveMouse.containsMouse ? 0.3 : 0.1)
                            opacity: qHover.hovered ? 1 : 0

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 9
                                color: qRemoveMouse.containsMouse ? WalColors.color1 : WalColors.withAlpha(WalColors.color7, 0.6)
                            }

                            MouseArea {
                                id: qRemoveMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const q = MusicPickerState.dlQueue.slice();
                                    q.splice(qRow.index, 1);
                                    MusicPickerState.dlQueue = q;
                                    linkInput.forceActiveFocus();
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 120
                                }

                            }

                        }

                    }

                }

            }

        }

        // Glides in slightly from below when switching (like the wallhaven tiles)
        transform: Translate {
            y: (1 - root.addT) * 24
        }

    }

    // The bar ends at the cover edges, the grid cells reach further.
    Item {
        id: queueReveal

        readonly property real room: Math.max(0, root.height - y - Theme.px(52))
        // On small displays a usable part of the grid stays free below the queue.
        readonly property real maxPanelHeight: Math.max(0, room - Math.min(root.cellH, Math.max(Theme.px(84), room - Theme.px(170))))

        anchors.horizontalCenter: gridArea.horizontalCenter
        anchors.top: searchBar.bottom
        anchors.topMargin: Theme.gap
        width: gridArea.width - root.cellW + root.boxSize
        height: queuePanel.height * root.queueT
        opacity: root.queueT * root.tabIn * (1 - root.addT)
        visible: root.queueOpen || opacity > 0.01
        enabled: root.queueOpen
        clip: true

        Rectangle {
            id: queuePanel

            readonly property int inset: Math.min(Theme.px(12), Math.floor(width / 12))
            readonly property bool compact: width < Theme.px(560)
            readonly property bool hasNowPlaying: root.nowPlaying !== ""
            readonly property int trackHeight: Theme.px(51)
            readonly property int scrollSpace: Theme.px(6)

            objectName: "musicQueuePanel"
            width: parent.width
            height: Math.min(queueContents.implicitHeight + 2 * inset, queueReveal.maxPanelHeight)
            radius: Theme.radiusL
            color: Qt.tint(WalColors.color0, Theme.card)
            border.color: Theme.tint(Theme.accent, 0.18)

            Behavior on height {
                enabled: root.queueT > 0
                NumberAnimation {
                    duration: Appearance.anim.durations.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.standard
                }
            }

            // Empty areas in the panel also keep the picker open.
            MouseArea {
                anchors.fill: parent
            }

            GridLayout {
                id: queueContents

                anchors.fill: parent
                anchors.margins: queuePanel.inset
                columnSpacing: Theme.gapSmall
                rowSpacing: Theme.gapSmall

                Rectangle {
                    id: nowCard

                    Layout.row: 0
                    Layout.column: 0
                    Layout.fillWidth: queuePanel.compact
                    Layout.fillHeight: !queuePanel.compact
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: 0
                    Layout.preferredWidth: Math.min(Theme.px(220), Math.floor(queuePanel.width * 0.27))
                    Layout.preferredHeight: Theme.px(50)
                    visible: queuePanel.hasNowPlaying
                    clip: true
                    radius: Theme.radiusM
                    color: Theme.accentSoft
                    border.color: Theme.stroke

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.gapSmall
                        spacing: Theme.gapSmall

                        CoverThumb {
                            Layout.preferredWidth: Theme.px(34)
                            Layout.preferredHeight: Theme.px(34)
                            visible: nowCard.width >= Theme.px(120)
                            corner: Theme.radiusS
                            source: root.coverUrl(root.nowPlaying)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)

                            Text {
                                Layout.fillWidth: true
                                text: "NOW PLAYING"
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeMicro
                                font.letterSpacing: Theme.microSpacing
                                font.bold: true
                                color: Theme.accent
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.displayName(root.nowPlaying)
                                textFormat: Text.PlainText
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeLead
                                font.weight: Font.DemiBold
                                color: Theme.text
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: queuePanel.compact ? 1 : 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.row: queuePanel.compact ? 1 : 0
                    Layout.column: queuePanel.compact || !queuePanel.hasNowPlaying ? 0 : 1
                    Layout.columnSpan: queuePanel.compact ? 2 : 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: 0
                    spacing: Theme.px(4)

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(28)
                        spacing: Theme.px(4)

                        Text {
                            Layout.fillWidth: true
                            text: "UP NEXT"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                            font.letterSpacing: Theme.microSpacing
                            font.bold: true
                            color: Theme.accent
                            elide: Text.ElideRight
                        }

                        MiniButton {
                            label: "Clear"
                            description: "Clear queue"
                            visible: root.queue.length > 0
                            implicitHeight: Theme.px(24)
                            onClicked: MusicPickerState.clearQueue()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        Layout.preferredHeight: root.queue.length > 0 ? queuePanel.trackHeight + queuePanel.scrollSpace : Theme.px(36)
                        clip: true

                        Text {
                            anchors.fill: parent
                            visible: root.queue.length === 0
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            text: "Empty"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeLabel
                            color: Theme.textDim
                        }

                        ListView {
                            id: queueList

                            readonly property int slots: Math.max(1, Math.min(3, Math.floor((width + spacing) / (Theme.px(142) + spacing))))
                            readonly property real trackWidth: (width - (slots - 1) * spacing) / slots

                            function playNext(index) {
                                if (index > 0) {
                                    MusicPickerState.queueNext(index);
                                    currentIndex = 0;
                                }
                            }

                            objectName: "musicQueueList"
                            anchors.fill: parent
                            orientation: ListView.Horizontal
                            spacing: Theme.px(6)
                            model: ScriptModel {
                                values: queuePanel.visible ? root.queue : []
                            }
                            boundsBehavior: Flickable.StopAtBounds
                            keyNavigationEnabled: false
                            clip: true

                            HoverHandler {
                                id: queueHover
                            }

                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                enabled: queueList.count > queueList.slots
                                onWheel: (event) => {
                                    const delta = event.angleDelta.y / 120 * (queueList.trackWidth + queueList.spacing);
                                    const right = queueList.originX + queueList.contentWidth - queueList.width;
                                    queueList.contentX = Math.max(queueList.originX, Math.min(right, queueList.contentX - delta));
                                    event.accepted = true;
                                }
                            }

                            Keys.onPressed: (event) => {
                                const key = PickerManager.navKey(event);
                                switch (key) {
                                case Qt.Key_Left:
                                case Qt.Key_Up:
                                    queueList.decrementCurrentIndex();
                                    break;
                                case Qt.Key_Right:
                                case Qt.Key_Down:
                                    queueList.incrementCurrentIndex();
                                    break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    if (event.modifiers & Qt.ControlModifier)
                                        queueList.playNext(queueList.currentIndex);
                                    else
                                        MusicPickerState.playQueued(queueList.currentIndex);
                                    break;
                                case Qt.Key_Delete:
                                    MusicPickerState.removeFromQueue(queueList.currentIndex);
                                    break;
                                case Qt.Key_Tab:
                                case Qt.Key_Backtab:
                                    if (key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier))
                                        PickerManager.cycleBackward();
                                    else
                                        PickerManager.cycle();
                                    break;
                                default:
                                    return;
                                }
                                event.accepted = true;
                            }

                            Controls.ScrollBar.horizontal: Controls.ScrollBar {
                                id: queueScroll

                                policy: queueList.count > queueList.slots ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
                                height: Theme.px(3)
                                padding: 0

                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(20)
                                    radius: height / 2
                                    color: queueScroll.active ? Theme.textDim : Theme.textFaint
                                }
                            }

                            delegate: Rectangle {
                                id: track

                                required property int index
                                required property string modelData
                                readonly property bool hot: ListView.isCurrentItem && (queueList.activeFocus || queueHover.hovered)
                                property real vinylT: hot ? 1 : 0

                                width: queueList.trackWidth
                                height: queuePanel.trackHeight
                                radius: Theme.radiusS
                                color: hot ? Theme.accentSoft : Theme.card
                                border.color: hot ? Theme.tint(Theme.accent, 0.35) : Theme.stroke

                                Accessible.role: Accessible.Button
                                Accessible.name: "Play " + root.displayName(modelData)
                                Accessible.onPressAction: MusicPickerState.playQueued(index)

                                HoverHandler {
                                    onHoveredChanged: {
                                        if (hovered)
                                            queueList.currentIndex = track.index;
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        queueList.currentIndex = track.index;
                                        queueList.forceActiveFocus();
                                        MusicPickerState.playQueued(track.index);
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(6)
                                    spacing: Theme.px(4)

                                    Item {
                                        id: trackArtwork

                                        Layout.preferredWidth: Theme.px(34)
                                        Layout.preferredHeight: Theme.px(28)
                                        visible: track.width >= Theme.px(120)

                                        Loader {
                                            active: trackArtwork.visible && track.vinylT > 0
                                            x: Theme.px(2) + track.vinylT * Theme.px(8)
                                            anchors.verticalCenter: parent.verticalCenter

                                            sourceComponent: VinylDisc {
                                                size: Theme.px(26)
                                                cover: trackCover.source
                                                spin: track.hot && root.queueOpen
                                                spinDuration: 5000
                                            }
                                        }

                                        CoverThumb {
                                            id: trackCover

                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Theme.px(28)
                                            height: width
                                            corner: Theme.radiusXS
                                            source: root.coverUrl(track.modelData)
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.displayName(track.modelData)
                                        textFormat: Text.PlainText
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.sizeLabel
                                        font.weight: Font.DemiBold
                                        color: Theme.text
                                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    MiniButton {
                                        label: "󰁝"
                                        description: "Play next"
                                        icon: true
                                        implicitHeight: Theme.px(22)
                                        visible: track.hot && track.index > 0
                                        onClicked: queueList.playNext(track.index)
                                    }

                                    MiniButton {
                                        label: "󰅖"
                                        description: "Remove from queue"
                                        icon: true
                                        danger: true
                                        implicitHeight: Theme.px(22)
                                        onClicked: MusicPickerState.removeFromQueue(track.index)
                                    }
                                }

                                Behavior on vinylT {
                                    NumberAnimation {
                                        duration: Appearance.anim.durations.normal
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Appearance.anim.curves.outQuint
                                    }
                                }
                            }
                        }
                    }
                }

                MiniButton {
                    Layout.row: 0
                    Layout.column: queuePanel.compact || !queuePanel.hasNowPlaying ? 1 : 2
                    Layout.alignment: Qt.AlignTop | Qt.AlignRight
                    label: "󰅖"
                    description: "Close queue"
                    icon: true
                    onClicked: root.closeQueue()
                }
            }
        }
    }

    // Flying record from the cover tile.
    Component {
        id: flyerComp

        Item {
            id: flyer

            property real fromX: 0
            property real fromY: 0
            property real toX: 0
            property real toY: 0
            property string cover: ""
            // 0..1 progress along the flight path
            property real p: 0

            width: 86
            height: 86
            z: 200
            // Straight line + sine hump = a nice arc
            x: fromX + (toX - fromX) * p - width / 2
            y: fromY + (toY - fromY) * p - Math.sin(Math.PI * p) * 140 - height / 2
            scale: 1 - 0.82 * p
            opacity: p < 0.9 ? 1 : Math.max(0, (1 - p) / 0.1)

            VinylDisc {
                size: 86
                cover: flyer.cover
                spin: true
                spinDuration: 800
                shadow: true
            }

            NumberAnimation {
                id: flight

                target: flyer
                property: "p"
                from: 0
                to: 1
                duration: 560
                easing.type: Easing.InOutCubic
                running: true
                onFinished: {
                    if (root.canToggleQueue)
                        queuePulse.restart();
                    flyer.destroy();
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

    // A vinyl record: dark disc, grooves, a light reflection that spins with it,
    // the cover as the label (or a number) and a spindle hole.
    component VinylDisc: Item {
        id: vd

        property real size: 80
        property string cover: ""
        // Shows this text (e.g. a queue position) instead of the cover on the label
        property string labelText: ""
        property color labelColor: WalColors.color2
        property bool spin: false
        property int spinDuration: 7000
        // Start angle of the reflection, so records do not all look identical
        property real sheenPhase: 0
        // 0..1: darkens the record (depth in the pile)
        property real dim: 0
        property bool shadow: false
        readonly property real labelSize: labelText !== "" ? size * 0.64 : size * 0.54

        width: size
        height: size

        SoftShadow {
            visible: vd.shadow
            radius: vd.size / 2
            blur: 8
            opacityScale: 2
        }

        // Vinyl body
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: WalColors.color0
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.25)
        }

        // Grooves
        Repeater {
            model: 3

            delegate: Rectangle {
                required property int index

                anchors.centerIn: parent
                width: vd.size * (0.93 - index * 0.11)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: WalColors.withAlpha(WalColors.color7, 0.07)
            }

        }

        // Rotating part: reflection + cover label
        Item {
            anchors.fill: parent
            rotation: vd.sheenPhase

            Item {
                id: spinner

                anchors.fill: parent

                // Two opposite light bands, like light on real vinyl
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.13)
                        strokeWidth: vd.size * 0.2
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap

                        PathAngleArc {
                            centerX: vd.size / 2
                            centerY: vd.size / 2
                            radiusX: vd.size * 0.355
                            radiusY: vd.size * 0.355
                            startAngle: 205
                            sweepAngle: 32
                        }

                    }

                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.13)
                        strokeWidth: vd.size * 0.2
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap

                        PathAngleArc {
                            centerX: vd.size / 2
                            centerY: vd.size / 2
                            radiusX: vd.size * 0.355
                            radiusY: vd.size * 0.355
                            startAngle: 25
                            sweepAngle: 32
                        }

                    }

                }

                CoverThumb {
                    anchors.centerIn: parent
                    width: vd.labelSize
                    height: width
                    source: vd.cover
                    visible: vd.labelText === ""
                }

                // NumberAnimation instead of RotationAnimator: animators run in the render thread and, together
                // with the normal animations, messed up the frame timing (laptop: ~20 % dropped frames)
                NumberAnimation on rotation {
                    running: vd.spin
                    from: 0
                    to: 360
                    duration: vd.spinDuration
                    loops: Animation.Infinite
                }

            }

        }

        // Number label (static, so the digit does not spin)
        Rectangle {
            visible: vd.labelText !== ""
            anchors.centerIn: parent
            width: vd.labelSize
            height: width
            radius: width / 2
            color: vd.labelColor

            Behavior on color {
                ColorAnimation {
                    duration: 120
                }

            }

        }

        Text {
            visible: vd.labelText !== ""
            anchors.centerIn: parent
            text: vd.labelText
            font.family: Theme.font
            font.pixelSize: Math.round(vd.size * 0.3)
            font.bold: true
            color: WalColors.color0
        }

        // Label rim
        Rectangle {
            anchors.centerIn: parent
            width: vd.labelSize + 2
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.3)
        }

        // Spindle hole
        Rectangle {
            visible: vd.labelText === ""
            anchors.centerIn: parent
            width: Math.max(4, vd.size * 0.09)
            height: width
            radius: width / 2
            color: WalColors.color0
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.35)
        }

        // Depth dimming
        Rectangle {
            visible: vd.dim > 0.01
            anchors.fill: parent
            radius: width / 2
            color: WalColors.withAlpha(WalColors.color0, vd.dim)
        }

    }

    // Round or rounded-square cover with a "♪" fallback
    component CoverThumb: Item {
        id: thumb

        property string source: ""
        property real corner: width / 2
        property real glyphSize: width * 0.45

        ClippingRectangle {
            anchors.fill: parent
            radius: thumb.corner
            color: "transparent"
            visible: thumbImg.status === Image.Ready

            Image {
                id: thumbImg

                anchors.fill: parent
                source: thumb.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(Math.max(thumb.width, 1) * 2, Math.max(thumb.height, 1) * 2)
            }

        }

        Rectangle {
            anchors.fill: parent
            radius: thumb.corner
            color: WalColors.withAlpha(WalColors.color2, 0.16)
            visible: thumbImg.status !== Image.Ready

            Text {
                anchors.centerIn: parent
                text: "♪"
                font.pixelSize: thumb.glyphSize
                color: WalColors.color2
            }

        }

    }

    component MiniButton: Rectangle {
        id: mb

        required property string label
        required property string description
        property bool icon: false
        property bool danger: false

        signal clicked()

        implicitWidth: icon ? implicitHeight : buttonLabel.implicitWidth + Theme.px(20)
        implicitHeight: Theme.px(28)
        width: implicitWidth
        height: implicitHeight
        radius: height / 2
        color: buttonMouse.containsMouse ? (danger ? Theme.tint(Theme.bad, 0.14) : Theme.glassHover) : Theme.card
        Accessible.role: Accessible.Button
        Accessible.name: description
        Accessible.onPressAction: clicked()

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: mb.label
            font.family: mb.icon ? Theme.font : Theme.fontUi
            font.pixelSize: mb.icon ? Theme.sizeLarge : Theme.sizeLabel
            color: buttonMouse.containsMouse && mb.danger ? Theme.bad : Theme.text
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
        }

        Controls.ToolTip.text: description
        Controls.ToolTip.delay: Appearance.anim.durations.slow
        Controls.ToolTip.visible: buttonMouse.containsMouse && !buttonMouse.pressed

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }
        }
    }

    // Small button for the download card
    component DlButton: Rectangle {
        id: btn

        property string label: ""
        property bool primary: false
        property bool active: true
        property color accent: WalColors.color4

        signal clicked()

        implicitWidth: btnText.implicitWidth + 44
        implicitHeight: 38
        radius: height / 2
        opacity: active ? 1 : 0.4
        color: primary ? (btnMouse.containsMouse ? accent : WalColors.withAlpha(accent, 0.85)) : (btnMouse.containsMouse ? WalColors.withAlpha(WalColors.color7, 0.16) : WalColors.withAlpha(WalColors.color7, 0.08))
        border.width: primary ? 0 : 1
        border.color: WalColors.withAlpha(WalColors.color7, 0.15)
        scale: btnMouse.pressed ? 0.94 : (btnMouse.containsMouse && active ? 1.05 : 1)

        Text {
            id: btnText

            anchors.centerIn: parent
            text: btn.label
            font.family: Theme.font
            font.pixelSize: 13
            font.bold: true
            color: btn.primary ? WalColors.color0 : WalColors.color7
        }

        MouseArea {
            id: btnMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.active
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }

        Behavior on scale {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutBack
                easing.overshoot: 1.6
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 120
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

}
