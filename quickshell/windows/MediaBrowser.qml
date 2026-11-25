import "../common"
import "../services"
import QtQuick
import Quickshell.Widgets

// Folder browser in the image and video editor (key B or the folder button in the header), in the style of the iOS Files app.
// Lies over the editor's card: on top back, folder name, clickable path bar, filter
// (All/Images/Videos), search and close; below a grid: first subfolders as album tiles
// (2x2 mosaic of their content), then images and videos. Going in, the content glides in from the right,
// back from the left. Controls like the VPN file browser, modeled on yazi:
//   hjkl/arrows move, Enter or Ctrl+L opens or goes into the folder,
//   Ctrl+H or Backspace = parent folder (the one left is then selected), gg/G start/end,
//   Ctrl+D/U page by page, / searches, Tab/Shift+Tab filter, space marks (and moves on),
//   x cuts (the marked ones, otherwise the selection), p pastes here (= move), d twice = trash.
//   Esc: clear the search, unmark, discard the cut, then close.
// Vaults (gocryptfs, see services/VaultService.qml): locked -> lock tile and on entering a
// password prompt instead of "empty"; inside a lock button on top for locking and a "Sort by Date" button
// (scripts/media_sort.py): first shows where the dates come from and what changes, Enter sorts, Esc cancels.
// Selecting a file reports picked(); what happens then (same editor, other editor,
// confirmation for unsaved changes) is decided by the editor.
Item {
    id: browser

    objectName: "mediaBrowser"
    property bool open: false
    // Currently open file: start folder and the "open" mark
    property string currentPath: ""
    // Confirmation/hint from the editor (e.g. unsaved changes), at the bottom in the warning color
    property string hint: ""
    property int filter: 0 // 0 All, 1 Images, 2 Videos
    property string query: ""
    property bool searching: false
    property string selectAfterLoad: ""
    property int navDir: 0 // 1 in, -1 back, 0 open
    property real openK: open ? 1 : 0
    property point lastMouse: Qt.point(-1, -1)
    // Only remember the first mouse report after opening: if the grid appears under the resting pointer,
    // Qt reports a "move" - otherwise the selection jumped from the open file to the tile under the mouse
    property bool hoverArmed: false
    // The folder is read before opening: the animation only starts with a finished grid (Ctrl+H reads a
    // different folder than last time - otherwise the old content zoomed in and jumped to the new one in the middle)
    property bool preparing: false
    // Marked with space (path -> true); applies in the current folder
    property var marks: ({})
    readonly property int markCount: Object.keys(marks).length
    // The first d only asks (like dd in the editor), the second moves to the trash
    property bool confirmTrash: false
    // After a file operation continue at the same place if the selection is gone
    property int keepIndex: -1
    // Short success message ("Moved 3 items"), muted; errors and confirmations are in hint
    property string notice: ""
    readonly property var st: MediaBrowserState
    // ---- Sort by date ----
    property bool sortOpen: false
    property real sortK: sortOpen ? 1 : 0

    Behavior on sortK {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }

    }
    // In a vault (not its root: the name list lies in the folder above) with at least 2 files
    readonly property bool canSort: st.vaultMount !== "" && st.dir !== st.vaultMount && !st.locked && st.files.length >= 2 && !searchActive
    // What speaks against it right now (files in progress); "" = nothing
    readonly property string sortBlocker: {
        const inside = (p) => {
            return p.indexOf(st.dir + "/") === 0;
        };
        if (CompressQueue.paths.some(inside))
            return "Videos here are waiting for compression. Sort when that's done.";

        if (VideoEditorState.exporting && inside(VideoEditorState.path))
            return "A video here is being saved. Sort when that's done.";

        return "";
    }
    // Search active (f or /) and something typed: hits from all subfolders (MediaBrowserState.search)
    readonly property bool searchActive: searching && query.trim() !== ""
    readonly property var entries: {
        if (searchActive) {
            return st.results.filter((r) => {
                return r.type === "folder" || filter === 0 || (filter === 1 && r.kind === "image") || (filter === 2 && r.kind === "video");
            }).map((r) => {
                return r.type === "folder" ? Object.assign({
                    "icon": "\uf07b"
                }, r) : r;
            });
        }
        const out = [];
        for (const f of st.folders) {
            out.push({
                "type": "folder",
                "path": f.path,
                "name": f.name,
                "count": f.count,
                "folders": f.folders,
                "covers": f.covers,
                "vault": f.vault,
                "icon": f.icon || "\uf07b"
            });

        }
        for (const f of st.files) {
            if ((filter === 1 && f.kind !== "image") || (filter === 2 && f.kind !== "video"))
                continue;

            out.push({
                "type": "file",
                "path": f.path,
                "name": f.name,
                "kind": f.kind
            });
        }
        return out;
    }

    // The grid depends on a ListModel that is only synced (syncModel): remaining tiles keep their
    // delegate and preview, deleted ones shrink away, the others glide up (GridView transitions).
    // Only another folder replaces everything (there the whole content glides, see navigate)
    property string modelDir: ""
    property bool animateModel: false
    // Read again after a file operation: no folder change, so no entrance, only the sync
    property bool opReload: false
    readonly property var entryMap: {
        const m = {};
        for (const e of entries)
            m[e.path] = e;
        return m;
    }

    function syncModel() {
        const want = entries.map((e) => {
            return e.path;
        });
        if (modelDir !== st.dir) {
            animateModel = false;
            gridModel.clear();
            for (const p of want)
                gridModel.append({
                "path": p
            });
            modelDir = st.dir;
            return ;
        }
        animateModel = true;
        const keep = {};
        for (const p of want)
            keep[p] = true;
        for (let i = gridModel.count - 1; i >= 0; i--) {
            if (!keep[gridModel.get(i).path])
                gridModel.remove(i);

        }
        for (let i = 0; i < want.length; i++) {
            if (i < gridModel.count && gridModel.get(i).path === want[i])
                continue;

            let from = -1;
            for (let k = i + 1; k < gridModel.count; k++) {
                if (gridModel.get(k).path === want[i]) {
                    from = k;
                    break;
                }
            }
            if (from >= 0)
                gridModel.move(from, i, 1);
            else
                gridModel.insert(i, {
                "path": want[i]
            });
        }
    }

    signal picked(string path, string kind)
    signal dismissed()
    // The password field had the focus: the editor should take it back (keys go to handleKey)
    signal wantsKeys()

    function unlock() {
        if (pw.text === "" || VaultService.unlocking)
            return ;

        VaultService.unlock(st.cipher, st.dir, pw.text);
        pw.text = "";
    }

    // Lock button: first out of the vault, then lock (the folder left stays selected)
    function lockVault() {
        const m = st.vaultMount;
        if (m === "")
            return ;

        selectAfterLoad = m;
        navigate(m.substring(0, m.lastIndexOf("/")) || "/", -1);
        VaultService.lockNow(m);
        showNotice("Locked");
    }

    // levelUp (Ctrl+H in the editor): one level above the open file's folder, this folder selected
    function show(levelUp) {
        hoverArmed = false;
        query = "";
        searching = false;
        hint = "";
        preparing = true;
        prepareTimer.restart();
        const dir = currentPath.substring(0, currentPath.lastIndexOf("/")) || "/";
        if (levelUp && dir !== "/") {
            selectAfterLoad = dir;
            navigate(dir.substring(0, dir.lastIndexOf("/")) || "/", 0);
        } else {
            selectAfterLoad = currentPath;
            navigate(dir, 0);
        }
    }

    function navigate(dir, direction) {
        navDir = direction;
        query = "";
        searching = false;
        marks = {};
        if (confirmTrash) {
            confirmTrash = false;
            hint = "";
        }
        if (direction !== 0)
            outAnim.restart();

        st.load(dir);
    }

    function up() {
        if (st.parentDir === "")
            return ;

        selectAfterLoad = st.dir;
        navigate(st.parentDir, -1);
    }

    function activate(i) {
        const e = entries[i];
        if (!e)
            return ;

        if (e.type === "folder") {
            selectAfterLoad = "";
            navigate(e.path, 1);
        } else {
            picked(e.path, e.kind);
        }
    }

    function select(i) {
        if (entries.length === 0)
            return ;

        grid.currentIndex = Math.max(0, Math.min(entries.length - 1, i));
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
    }

    // Space: mark/unmark and one further like in yazi (advance), a click on the circle stays
    function toggleMark(i, advance) {
        const e = entries[i];
        if (!e)
            return ;

        const copy = Object.assign({}, marks);
        if (copy[e.path])
            delete copy[e.path];
        else
            copy[e.path] = true;
        marks = copy;
        if (advance)
            select(i + 1);

    }

    // Target of x and d: all marked ones, otherwise the selection
    function targets() {
        const marked = Object.keys(marks);
        if (marked.length > 0)
            return marked;

        const e = entries[grid.currentIndex];
        return e ? [e.path] : [];
    }

    function describe(paths) {
        return paths.length === 1 ? "\u201c" + paths[0].substring(paths[0].lastIndexOf("/") + 1) + "\u201d" : paths.length + " items";
    }

    function requestTrash() {
        const list = targets();
        if (list.length === 0 || st.busy)
            return ;

        if (!confirmTrash) {
            confirmTrash = true;
            hint = "Press d again to move " + describe(list) + " to trash";
            trashTimer.restart();
            return ;
        }
        confirmTrash = false;
        hint = "";
        st.trash(list);
    }

    function cut() {
        const list = targets();
        if (list.length === 0)
            return ;

        st.cutPaths = list;
        marks = {};
        showNotice("Cut " + describe(list) + " \u00b7 paste with p");
    }

    function paste() {
        if (st.cutPaths.length === 0 || st.busy)
            return ;

        st.paste(st.dir);
    }

    function openSort() {
        if (!canSort || st.busy)
            return ;

        sortOpen = true;
        st.checkSort(st.dir);
    }

    function closeSort() {
        if (st.sortApplying)
            return ;

        sortOpen = false;
        st.cancelSortCheck();
    }

    function confirmSort() {
        if (sortBlocker === "" && st.sortPlan && st.sortPlan.renameCount > 0 && !st.sortChecking)
            st.applySort();

    }

    function showNotice(text) {
        notice = text;
        noticeTimer.restart();
    }

    // Passed on by the editor while the browser is open
    function handleKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const key = event.key;
        const i = grid.currentIndex;
        // Sort window open: only Esc (cancel) and Enter (sort), everything else is left alone
        if (sortOpen) {
            if (key === Qt.Key_Escape)
                closeSort();
            else if (key === Qt.Key_Return || key === Qt.Key_Enter)
                confirmSort();
            return ;
        }
        // Locked vault: typing belongs in the password field, Esc/Ctrl+H go back
        if (st.locked) {
            if (key === Qt.Key_Escape || (ctrl && key === Qt.Key_H))
                up();
            else if (key === Qt.Key_Return || key === Qt.Key_Enter)
                unlock();
            else
                pw.forceActiveFocus();
            return ;
        }
        // Ctrl+L = in (enter a folder, open a file), Ctrl+H = one level up, like h/l in yazi.
        // Also during the search: this way you jump straight on from a hit
        if (ctrl && key === Qt.Key_L) {
            activate(i);
            return ;
        }
        if (ctrl && key === Qt.Key_H) {
            up();
            return ;
        }
        if (searching) {
            if (key === Qt.Key_Escape) {
                if (query !== "")
                    query = "";
                else
                    searching = false;
            } else if (key === Qt.Key_Backspace) {
                query = query.slice(0, -1);
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                activate(i);
            } else if (key === Qt.Key_Down || key === Qt.Key_Up || key === Qt.Key_Left || key === Qt.Key_Right) {
                select(i + (key === Qt.Key_Down ? grid.cols : key === Qt.Key_Up ? -grid.cols : key === Qt.Key_Left ? -1 : 1));
            } else if (event.text !== "" && !ctrl && event.text.charCodeAt(0) >= 32) {
                query += event.text;
                Qt.callLater(() => {
                    return select(0);
                });
            }
            return ;
        }
        // The trash confirmation only applies to the d right after
        if (confirmTrash && key !== Qt.Key_D) {
            confirmTrash = false;
            hint = "";
        }
        // B closes again (it is opened with B in the editor)
        if (!ctrl && key === Qt.Key_B) {
            dismissed();
            return ;
        }
        if (key === Qt.Key_Space) {
            toggleMark(i, true);
            return ;
        }
        if (!ctrl && key === Qt.Key_X) {
            cut();
            return ;
        }
        if (!ctrl && key === Qt.Key_P) {
            paste();
            return ;
        }
        if (!ctrl && key === Qt.Key_D) {
            requestTrash();
            return ;
        }
        if (key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            select(entries.length - 1);
        } else if (key === Qt.Key_G) {
            if (ggTimer.running) {
                ggTimer.stop();
                select(0);
            } else {
                ggTimer.restart();
            }
        } else if (key === Qt.Key_Escape) {
            if (markCount > 0)
                marks = {};
            else if (st.cutPaths.length > 0)
                st.cutPaths = [];
            else
                dismissed();
        } else if (ctrl && key === Qt.Key_D) {
            select(i + grid.cols * 3);
        } else if (ctrl && key === Qt.Key_U) {
            select(i - grid.cols * 3);
        } else if (key === Qt.Key_Left || key === Qt.Key_H) {
            select(i - 1);
        } else if (key === Qt.Key_Right || key === Qt.Key_L) {
            select(i + 1);
        } else if (key === Qt.Key_Up || key === Qt.Key_K) {
            select(i - grid.cols);
        } else if (key === Qt.Key_Down || key === Qt.Key_J) {
            select(i + grid.cols);
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            activate(i);
        } else if (key === Qt.Key_Backspace || key === Qt.Key_Minus) {
            up();
        } else if (key === Qt.Key_Slash || key === Qt.Key_F) {
            searching = true;
        } else if (key === Qt.Key_Tab) {
            filter = (filter + 1) % 3;
        } else if (key === Qt.Key_Backtab) {
            filter = (filter + 2) % 3;
        }
    }

    // Open like iOS going from a photo back to the overview: the background covers right away (otherwise
    // the editor's sidebar shone through), the content zooms from slightly big to normal and fades
    // in. Closing in reverse: first the content, then the background
    readonly property real backdropK: Math.min(1, openK * 3)
    readonly property real contentK: Math.max(0, Math.min(1, (openK - 0.12) / 0.88))

    onEntriesChanged: Qt.callLater(syncModel)
    onQueryChanged: {
        if (searchActive)
            searchTimer.restart();

    }
    visible: openK > 0.01 || preparing
    onOpenChanged: st.active = open
    onDismissed: preparing = false
    // Quiet crossfade, so the card underneath does not flash through
    z: 50

    Connections {
        function onLoaded() {
            browser.syncModel();
            const idx = browser.entries.findIndex((e) => {
                return e.path === browser.selectAfterLoad;
            });
            grid.currentIndex = idx >= 0 ? idx : Math.max(0, Math.min(browser.entries.length - 1, browser.keepIndex));
            browser.keepIndex = -1;
            if (browser.st.locked) {
                pw.text = "";
                pw.forceActiveFocus();
            } else if (pw.activeFocus) {
                browser.wantsKeys();
            }
            grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
            if (browser.preparing) {
                browser.preparing = false;
                browser.open = true;
            }
            if (browser.opReload) {
                browser.opReload = false;
                return ;
            }
            outAnim.stop();
            pane.x = browser.navDir * Theme.px(40);
            pane.opacity = browser.navDir === 0 ? 1 : 0;
            inAnim.restart();
        }

        // After moving/trashing: keep the selection (or the place), report the result briefly
        function onOperationDone(trashed, moved) {
            browser.opReload = true;
            const cur = browser.entries[grid.currentIndex];
            browser.selectAfterLoad = cur && trashed.indexOf(cur.path) < 0 && moved[cur.path] === undefined ? cur.path : "";
            browser.keepIndex = grid.currentIndex;
            browser.marks = {};
            const n = Object.keys(moved).length;
            if (browser.st.lastError !== "")
                browser.hint = browser.st.lastError;
            else if (n > 0)
                browser.showNotice("Moved " + (n === 1 ? "1 item" : n + " items") + " here");
            else if (trashed.length > 0)
                browser.showNotice("Moved " + (trashed.length === 1 ? "1 item" : trashed.length + " items") + " to trash");
        }

        // Sorted: read again as after a file operation (no entrance), selection at the same place
        function onSorted(renamed) {
            browser.sortOpen = false;
            browser.opReload = true;
            browser.selectAfterLoad = "";
            browser.keepIndex = grid.currentIndex;
            browser.marks = {};
            browser.showNotice(renamed > 0 ? "Sorted by date · " + renamed + (renamed === 1 ? " file renamed" : " files renamed") : "Already sorted by date");
        }

        target: MediaBrowserState
    }

    Connections {
        // Unlocked: read the content, it glides in as when entering a folder
        function onUnlocked(mount) {
            if (mount !== browser.st.dir)
                return ;

            browser.navDir = 1;
            browser.st.load(mount);
        }

        function onWrongPassword() {
            shake.restart();
            pw.forceActiveFocus();
        }

        target: VaultService
    }

    // If reading hangs: open anyway
    Timer {
        id: prepareTimer

        interval: 300
        onTriggered: {
            if (browser.preparing) {
                browser.preparing = false;
                browser.open = true;
            }
        }
    }

    // Only search when typing has stopped briefly (every search reads all subfolders)
    Timer {
        id: searchTimer

        interval: 110
        onTriggered: {
            if (browser.searchActive)
                browser.st.search(browser.st.dir, browser.query.trim());

        }
    }

    Connections {
        function onResultsChanged() {
            if (browser.searchActive)
                Qt.callLater(() => {
                browser.syncModel();
                browser.select(0);
            });

        }

        target: MediaBrowserState
    }

    Timer {
        id: trashTimer

        interval: 4000
        onTriggered: {
            if (browser.confirmTrash) {
                browser.confirmTrash = false;
                browser.hint = "";
            }
        }
    }

    Timer {
        id: noticeTimer

        interval: 2600
        onTriggered: browser.notice = ""
    }

    Timer {
        id: ggTimer

        interval: 400
    }

    NumberAnimation {
        id: outAnim

        target: pane
        property: "opacity"
        to: 0
        duration: 110
        easing.type: Easing.InCubic
    }

    ParallelAnimation {
        id: inAnim

        NumberAnimation {
            target: pane
            property: "x"
            to: 0
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: pane
            property: "opacity"
            to: 1
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutCubic
        }

    }

    Behavior on openK {
        NumberAnimation {
            duration: browser.open ? 420 : 240
            easing.type: Easing.OutCubic
        }

    }

    // Covers the card (same color and rounding: the card only clips rectangularly)
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusXL
        opacity: browser.backdropK
        color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.04))

        // Clicks and the mouse wheel must not fall through to the editor underneath (the wheel zooms there)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: (wheel) => {
                wheel.accepted = true;
            }
        }

    }

    // Header, grid and footer zoom together (see contentK)
    Item {
        id: content

        anchors.fill: parent
        opacity: browser.contentK
        scale: 1 + 0.045 * (1 - browser.contentK)

        // ---------- Header ----------
        Item {
            id: topBar

            x: Theme.px(28)
            y: Theme.px(24)
            width: parent.width - 2 * x
            height: Theme.px(56)

            GlassButton {
                id: backButton

                anchors.verticalCenter: parent.verticalCenter
                glyph: ""
                dimmed: browser.st.parentDir === ""
                onClicked: browser.up()
            }

            Column {
                x: backButton.width + Theme.px(14)
                anchors.verticalCenter: parent.verticalCenter
                width: tools.x - x - Theme.px(16)
                spacing: Theme.px(3)

                // Folder icon as in yazi before the name (locked vault: lock)
                Row {
                    width: parent.width
                    spacing: Theme.px(10)

                    Text {
                        id: titleIcon

                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        text: browser.st.locked ? "" : browser.st.dirIcon
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.sizeTitleLarge
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (titleIcon.visible ? titleIcon.width + parent.spacing : 0)
                        elide: Text.ElideRight
                        text: {
                            const d = browser.st.dir;
                            if (d === "/")
                                return "/";

                            if (d === browser.st.home)
                                return "Home";

                            return d.substring(d.lastIndexOf("/") + 1);
                        }
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeTitleLarge
                        font.weight: Font.DemiBold
                    }

                }

                // Path bar: every piece jumps straight back there
                Row {
                    spacing: Theme.px(4)

                    Repeater {
                        model: {
                            const pretty = browser.st.pretty(browser.st.dir);
                            const parts = pretty.split("/").filter((p) => {
                                return p !== "";
                            });
                            const out = [];
                            let acc = pretty.indexOf("~") === 0 ? browser.st.home : "";
                            for (let n = 0; n < parts.length; n++) {
                                if (n > 0 || parts[0] !== "~")
                                    acc += "/" + parts[n];

                                out.push({
                                    "name": parts[n],
                                    "path": acc || "/"
                                });
                            }
                            return out.slice(0, -1);
                        }

                        delegate: Row {
                            required property var modelData
                            required property int index

                            spacing: Theme.px(4)

                            Text {
                                visible: parent.index > 0
                                text: "›"
                                color: Theme.textFaint
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                            }

                            Text {
                                text: parent.modelData.name
                                color: crumbMouse.containsMouse ? Theme.text : Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                                font.weight: Font.Medium

                                MouseArea {
                                    id: crumbMouse

                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        browser.selectAfterLoad = "";
                                        browser.navigate(parent.parent.modelData.path, -1);
                                    }
                                }

                            }

                        }

                    }

                }

            }

            Row {
                id: tools

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(10)

                // Search: glass button, expanded a capsule with the search text (typing goes through handleKey)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: browser.searching ? Theme.px(220) : Theme.px(34)
                    height: Theme.px(34)
                    radius: height / 2
                    color: browser.searching ? Theme.groupFill : (searchMouse.containsMouse ? Theme.glassHover : Theme.glass)
                    clip: true

                    Text {
                        id: searchGlyph

                        x: (Theme.px(34) - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: browser.searching ? Theme.textDim : Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.sizeBody
                    }

                    Text {
                        x: Theme.px(34)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - Theme.px(12)
                        visible: browser.searching
                        elide: Text.ElideLeft
                        text: browser.query !== "" ? browser.query : "Search all folders"
                        color: browser.query !== "" ? Theme.text : Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody

                        // Blinking line like in a text field
                        Rectangle {
                            x: browser.query !== "" ? Math.min(parent.contentWidth, parent.width) + 1 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: 1.5
                            height: parent.font.pixelSize + 4
                            color: Theme.accent

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: browser.searching

                                NumberAnimation {
                                    to: 0
                                    duration: 500
                                }

                                NumberAnimation {
                                    to: 1
                                    duration: 500
                                }

                            }

                        }

                    }

                    MouseArea {
                        id: searchMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: browser.searching = !browser.searching
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: Appearance.anim.durations.normal
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                IosSegmented {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.px(250)
                    items: [{
                        "text": "All"
                    }, {
                        "glyph": "",
                        "text": "Images"
                    }, {
                        "glyph": "",
                        "text": "Videos"
                    }]
                    currentIndex: browser.filter
                    onActivated: (i) => {
                        browser.filter = i;
                    }
                }

                // In a vault: rename all files of this folder by date (first a preview, then confirm)
                GlassButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: browser.canSort
                    glyph: "\uf160"
                    active: browser.sortOpen
                    onClicked: browser.sortOpen ? browser.closeSort() : browser.openSort()
                }

                // In an unlocked vault: lock right away (otherwise it locks itself when you leave)
                GlassButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: browser.st.vaultMount !== ""
                    glyph: "\uf023"
                    active: true
                    onClicked: browser.lockVault()
                }

                GlassButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: ""
                    onClicked: browser.dismissed()
                }

            }

        }

        // ---------- Raster ----------
        Item {
            id: pane

            y: topBar.y + topBar.height + Theme.px(16)
            width: parent.width
            height: footer.y - y - Theme.px(8)

            GridView {
                id: grid

                objectName: "browserGrid"

                readonly property int cols: Math.max(1, Math.floor(width / Theme.px(200)))

                visible: !browser.st.locked
                x: Theme.px(20)
                width: parent.width - 2 * x
                height: parent.height
                cellWidth: width / cols
                cellHeight: (cellWidth - Theme.px(16)) * 0.64 + Theme.px(62)
                model: gridModel
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                highlightFollowsCurrentItem: false
                currentIndex: 0
                // Room for the ring and the enlargement of the top row
                topMargin: Theme.px(6)
                bottomMargin: Theme.px(6)

                // Gone: shrinks and fades out; the others glide into the free places; new: grows in
                remove: Transition {
                    enabled: browser.animateModel

                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            to: 0
                            duration: 200
                            easing.type: Easing.InCubic
                        }

                        NumberAnimation {
                            property: "scale"
                            to: 0.82
                            duration: 240
                            easing.type: Easing.InCubic
                        }

                    }

                }

                add: Transition {
                    enabled: browser.animateModel

                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 260
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            property: "scale"
                            from: 0.85
                            to: 1
                            duration: 340
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }

                    }

                }

                displaced: Transition {
                    enabled: browser.animateModel

                    NumberAnimation {
                        properties: "x,y"
                        duration: 380
                        easing.type: Easing.OutCubic
                    }

                    // Finish an interrupted fade-in cleanly (fast deleting in a row)
                    NumberAnimation {
                        properties: "opacity,scale"
                        to: 1
                        duration: 200
                    }

                }

                move: Transition {
                    enabled: browser.animateModel

                    NumberAnimation {
                        properties: "x,y"
                        duration: 380
                        easing.type: Easing.OutCubic
                    }

                }

                delegate: Item {
                    id: cell

                    required property string path
                    required property int index
                    // Last valid state: if the entry disappears (deleted), the tile keeps showing it while shrinking away
                    property var lastData: ({
                        "path": path,
                        "name": "",
                        "type": "file",
                        "covers": []
                    })
                    readonly property var modelData: browser.entryMap[path] ?? lastData

                    onModelDataChanged: {
                        if (browser.entryMap[path] !== undefined)
                            lastData = modelData;

                    }

                    readonly property bool selected: GridView.isCurrentItem
                    readonly property bool isFolder: modelData.type === "folder"
                    readonly property bool isOpen: modelData.path === browser.currentPath
                    readonly property bool marked: browser.marks[modelData.path] === true
                    readonly property bool isCut: browser.st.cutPaths.indexOf(modelData.path) >= 0
                    readonly property bool isVault: isFolder && modelData.vault !== undefined
                    readonly property bool isLockedVault: isVault && modelData.vault.locked

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Item {
                        id: tile

                        x: Theme.px(8)
                        y: Theme.px(8)
                        width: parent.width - Theme.px(16)
                        height: width * 0.64
                        // Hover/selection like the cards of the pickers: ring + slight enlargement
                        scale: cell.selected ? 1.04 : 1
                        // Cut: faint until it is pasted elsewhere (like in yazi)
                        opacity: cell.isCut ? 0.4 : 1

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: Theme.radiusS + 2
                            color: Theme.groupFill

                            // File: preview
                            Image {
                                anchors.fill: parent
                                visible: !cell.isFolder
                                source: cell.isFolder ? "" : browser.st.previewFor(cell.modelData.path)
                                sourceSize.width: 420
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                autoTransform: true
                                opacity: status === Image.Ready ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Appearance.anim.durations.normal
                                    }

                                }

                            }

                            // Video without a preview (in a vault there deliberately is none, otherwise it is still loading): film symbol
                            Text {
                                anchors.centerIn: parent
                                visible: !cell.isFolder && cell.modelData.kind === "video" && browser.st.previewFor(cell.modelData.path) === ""
                                text: "\uf03d"
                                color: Theme.textFaint
                                font.family: Theme.font
                                font.pixelSize: tile.height * 0.26
                            }

                            // Folder: mosaic of up to 4 files (1 = big, 2-3 = side by side, 4 = 2x2)
                            Grid {
                                anchors.fill: parent
                                visible: cell.isFolder && cell.modelData.covers && cell.modelData.covers.length > 0
                                columns: visible && cell.modelData.covers.length >= 2 ? 2 : 1
                                spacing: 2

                                Repeater {
                                    model: cell.isFolder ? (cell.modelData.covers.length >= 4 ? cell.modelData.covers.slice(0, 4) : cell.modelData.covers.slice(0, 2)) : []

                                    delegate: Image {
                                        required property string modelData

                                        readonly property int n: cell.modelData.covers.length >= 4 ? 4 : Math.min(2, cell.modelData.covers.length)

                                        width: n === 1 ? tile.width : (tile.width - 2) / 2
                                        height: n === 4 ? (tile.height - 2) / 2 : tile.height
                                        source: browser.st.previewFor(modelData)
                                        sourceSize.width: 240
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        autoTransform: true
                                    }

                                }

                            }

                            // Empty folder (or only subfolders): big folder symbol
                            Text {
                                anchors.centerIn: parent
                                visible: cell.isFolder && (!cell.modelData.covers || cell.modelData.covers.length === 0)
                                text: cell.isLockedVault ? "\uf023" : (cell.modelData.icon || "")
                                color: Theme.tint(Theme.accent, 0.55)
                                font.family: Theme.font
                                font.pixelSize: tile.height * 0.38
                            }

                            // Light gradient at the bottom, so badges stay readable on bright images
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: parent.height * 0.4
                                visible: cell.isFolder ? cell.modelData.covers.length > 0 : cell.modelData.kind === "video"
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0
                                        color: "transparent"
                                    }

                                    GradientStop {
                                        position: 1
                                        color: Qt.rgba(0, 0, 0, 0.35)
                                    }

                                }

                            }

                        }

                        // Badge at the bottom left: folder with count, video with play
                        Rectangle {
                            x: Theme.px(8)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.px(8)
                            visible: cell.isFolder || cell.modelData.kind === "video"
                            width: badgeRow.implicitWidth + Theme.px(14)
                            height: Theme.px(22)
                            radius: height / 2
                            color: Qt.rgba(0, 0, 0, 0.45)

                            Row {
                                id: badgeRow

                                anchors.centerIn: parent
                                spacing: Theme.px(5)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: cell.isFolder ? (cell.isLockedVault ? "\uf023" : (cell.modelData.icon || "")) : "\uf04b"
                                    color: "white"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.sizeSmall
                                }

                                // Folder without its own files (only subfolders): only the symbol, no "0"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: cell.isFolder && cell.modelData.count > 0
                                    text: cell.isFolder ? cell.modelData.count : ""
                                    color: "white"
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.sizeSmall
                                    font.weight: Font.DemiBold
                                    font.features: Theme.tabular
                                }

                            }

                        }

                        // Marked: light tint over the whole tile
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusS + 2
                            visible: cell.marked
                            color: Theme.tint(Theme.accent, 0.2)
                            border.width: 2
                            border.color: Theme.tint(Theme.accent, 0.7)
                        }

                        // Selection circle as in the iOS selection mode: appears on all tiles as soon as something
                        // is marked; a click on it marks too
                        Rectangle {
                            x: Theme.px(8)
                            y: Theme.px(8)
                            width: Theme.px(22)
                            height: width
                            radius: width / 2
                            visible: browser.markCount > 0
                            color: cell.marked ? Theme.accent : Qt.rgba(0, 0, 0, 0.3)
                            border.width: cell.marked ? 0 : 2
                            border.color: Qt.rgba(1, 1, 1, 0.85)

                            Text {
                                anchors.centerIn: parent
                                visible: cell.marked
                                text: "\uf00c"
                                color: Theme.onAccent
                                font.family: Theme.font
                                font.pixelSize: Theme.sizeSmall
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: browser.toggleMark(cell.index, false)
                            }

                        }

                        // Open in the editor right now
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.px(8)
                            visible: cell.isOpen
                            width: openLabel.implicitWidth + Theme.px(14)
                            height: Theme.px(22)
                            radius: height / 2
                            color: Theme.accent

                            Text {
                                id: openLabel

                                anchors.centerIn: parent
                                text: "Open"
                                color: Theme.onAccent
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                                font.weight: Font.DemiBold
                            }

                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -Theme.px(3)
                            radius: Theme.radiusS + 2 + Theme.px(3)
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.accent
                            opacity: cell.selected ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.anim.durations.fast
                                }

                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: Appearance.anim.durations.fast
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    Column {
                        x: tile.x
                        y: tile.y + tile.height + Theme.px(9)
                        width: tile.width
                        spacing: Theme.px(1)

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: cell.modelData.name
                            color: cell.selected ? Theme.text : Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeBody
                            font.weight: Font.Medium
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: {
                                const m = cell.modelData;
                                // Search hit: where it lies (relative to the folder being searched)
                                if (m.rel !== undefined)
                                    return m.rel === "" ? "In this folder" : m.rel;

                                if (!cell.isFolder)
                                    return m.name.substring(m.name.lastIndexOf(".") + 1).toUpperCase();

                                if (cell.isLockedVault)
                                    return "Locked";

                                const parts = [];
                                if (m.folders > 0)
                                    parts.push(m.folders + (m.folders === 1 ? " folder" : " folders"));

                                if (m.count > 0 || m.folders === 0)
                                    parts.push(m.count + (m.count === 1 ? " item" : " items"));

                                return parts.join(" · ");
                            }
                            color: Theme.textFaint
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeSmall
                        }

                    }

                    // Hover is the selection, but only on a real mouse move (convention of the pickers):
                    // otherwise the selection jumps when the grid scrolls under the resting mouse
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: (mouse) => {
                            const p = mapToItem(browser, mouse.x, mouse.y);
                            if (!browser.hoverArmed) {
                                browser.hoverArmed = true;
                                browser.lastMouse = p;
                                return ;
                            }
                            if (Math.hypot(p.x - browser.lastMouse.x, p.y - browser.lastMouse.y) < 3)
                                return ;

                            browser.lastMouse = p;
                            grid.currentIndex = cell.index;
                        }
                        onClicked: browser.activate(cell.index)
                    }

                }

            }

            Text {
                anchors.centerIn: parent
                visible: browser.entries.length === 0 && !browser.st.loading && !browser.st.locked && !(browser.searchActive && (browser.st.searchBusy || browser.st.resultsFor !== browser.query.trim()))
                text: browser.query !== "" ? "No matches for “" + browser.query + "”" : "No photos or videos here"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLarge
            }

            // ---------- Locked vault: password prompt ----------
            Column {
                id: lockSheet

                property real shakeX: 0

                anchors.centerIn: parent
                anchors.horizontalCenterOffset: shakeX
                anchors.verticalCenterOffset: -Theme.px(30)
                width: Theme.px(300)
                spacing: Theme.px(14)
                visible: browser.st.locked

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.px(68)
                    height: width
                    radius: width / 2
                    color: Theme.tint(Theme.accent, 0.16)

                    Text {
                        anchors.centerIn: parent
                        text: "\uf023"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.px(28)
                    }

                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: browser.st.dir.substring(browser.st.dir.lastIndexOf("/") + 1) + " is locked"
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeTitleLarge
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: VaultService.error === "wrong" ? "Wrong password, try again" : (VaultService.error !== "" ? VaultService.error : "Enter the password to unlock")
                    color: VaultService.error !== "" ? Theme.bad : Theme.textDim
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                }

                Rectangle {
                    width: parent.width
                    height: Theme.px(44)
                    radius: Theme.px(12)
                    color: Theme.groupFill
                    border.width: pw.activeFocus ? 2 : 1
                    border.color: VaultService.error === "wrong" ? Theme.bad : (pw.activeFocus ? Theme.tint(Theme.accent, 0.7) : Theme.separator)

                    TextInput {
                        id: pw

                        x: Theme.px(14)
                        width: parent.width - 2 * x
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "\u2022"
                        enabled: !VaultService.unlocking
                        color: Theme.text
                        selectionColor: Theme.tint(Theme.accent, 0.4)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeLead
                        font.letterSpacing: 2
                        clip: true
                        onAccepted: browser.unlock()
                        onTextChanged: {
                            if (text !== "" && VaultService.error !== "")
                                VaultService.error = "";

                        }
                        // Esc and Ctrl+H go back (the editor does not pass them on while the field has the focus)
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_H)) {
                                browser.up();
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        x: pw.x
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pw.text === ""
                        text: "Password"
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeLead
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onPressed: (mouse) => {
                            pw.forceActiveFocus();
                            mouse.accepted = false;
                        }
                    }

                }

                IosButton {
                    width: parent.width
                    glyph: VaultService.unlocking ? "" : "\uf09c"
                    text: VaultService.unlocking ? "Unlocking\u2026" : "Unlock"
                    dimmed: pw.text === "" && !VaultService.unlocking
                    onClicked: browser.unlock()
                }

                // Wrong password: shake briefly like iOS
                SequentialAnimation {
                    id: shake

                    NumberAnimation { target: lockSheet; property: "shakeX"; to: -14; duration: 50 }
                    NumberAnimation { target: lockSheet; property: "shakeX"; to: 12; duration: 70 }
                    NumberAnimation { target: lockSheet; property: "shakeX"; to: -8; duration: 70 }
                    NumberAnimation { target: lockSheet; property: "shakeX"; to: 5; duration: 60 }
                    NumberAnimation { target: lockSheet; property: "shakeX"; to: 0; duration: 60 }
                }

            }

        }

        // ---------- Sort by date ----------
        // Dimming + card in the middle like an iOS dialog: where the dates come from, what changes, then
        // "Sort". Lies above grid and footer (z), a click beside cancels
        Item {
            anchors.fill: parent
            z: 10
            visible: browser.sortK > 0.01
            opacity: browser.sortK

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusXL
                color: Qt.rgba(0, 0, 0, 0.35)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onClicked: browser.closeSort()
                    onWheel: (wheel) => {
                        wheel.accepted = true;
                    }
                }

            }

            Rectangle {
                id: sortCard

                readonly property var plan: browser.st.sortPlan
                readonly property var counts: plan ? plan.counts : ({})
                // Sources for the list, in the order of their reliability; estimates of earlier
                // sorts (estimated, download time ...) count as "Saved in list"
                readonly property var rows: {
                    if (!plan)
                        return [];

                    const known = ["meta", "stream", "tiktok", "name", "mtime", "upload-id", "unbekannt"];
                    let saved = 0;
                    for (const k of Object.keys(counts)) {
                        if (known.indexOf(k) < 0)
                            saved += counts[k];

                    }
                    const out = [{
                        "glyph": "\uf030",
                        "title": "Recording date",
                        "sub": "From the file's metadata",
                        "n": (counts.meta || 0) + (counts.stream || 0)
                    }, {
                        "glyph": "\uf1e0",
                        "title": "TikTok upload date",
                        "sub": "From the video ID",
                        "n": counts.tiktok || 0
                    }, {
                        "glyph": "\uf15c",
                        "title": "Date in file name",
                        "sub": "Current or original name",
                        "n": counts.name || 0
                    }, {
                        "glyph": "\uf0ca",
                        "title": "Saved in list",
                        "sub": "From an earlier sort, may be estimated",
                        "n": saved
                    }, {
                        "glyph": "\uf017",
                        "title": "File date",
                        "sub": "Less reliable",
                        "n": counts.mtime || 0
                    }, {
                        "glyph": "\uf0cb",
                        "title": "Upload order",
                        "sub": "No date, ordered by upload ID",
                        "n": counts["upload-id"] || 0
                    }, {
                        "glyph": "\uf128",
                        "title": "No date",
                        "sub": "Stays at the start, order kept",
                        "n": counts.unbekannt || 0
                    }];
                    return out.filter((r) => {
                        return r.n > 0;
                    });
                }

                anchors.centerIn: parent
                width: Theme.px(400)
                height: sortBody.height + Theme.px(40)
                radius: Theme.radiusXL
                color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.08))
                border.width: 1
                border.color: Theme.stroke
                scale: 0.94 + 0.06 * browser.sortK

                // Clicks on the card do not close
                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: sortBody

                    x: Theme.px(20)
                    y: Theme.px(20)
                    width: parent.width - 2 * x
                    spacing: Theme.px(14)

                    Column {
                        width: parent.width
                        spacing: Theme.px(4)

                        Text {
                            text: "Sort by Date"
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeTitle
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: {
                                const n = browser.st.files.length;
                                const name = browser.st.dir.substring(browser.st.dir.lastIndexOf("/") + 1);
                                if (browser.st.sortMode === "new")
                                    return "Names only the files in \u201c" + name + "\u201d that don't follow the naming pattern yet. Files that already do stay as they are.";

                                return "Renames all " + n + " files in \u201c" + name + "\u201d so the oldest comes first.";
                            }
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeBody
                        }

                    }

                    // Only new ones (default) or sort everything anew; switching reads again
                    IosSegmented {
                        width: parent.width
                        enabled: !browser.st.sortApplying
                        items: [{
                            "text": "New Files Only"
                        }, {
                            "text": "Re-sort All"
                        }]
                        currentIndex: browser.st.sortMode === "new" ? 0 : 1
                        onActivated: (i) => {
                            browser.st.setSortMode(i === 0 ? "new" : "all");
                        }
                    }

                    // Still reading: progress over all files (videos need ffprobe)
                    IosGroup {
                        width: parent.width
                        visible: browser.st.sortChecking

                        IosRow {
                            divider: false
                            glyph: "\uf073"
                            title: "Reading dates"
                            trailing: Math.round(browser.st.sortProgress * 100) + " %"
                            progress: browser.st.sortProgress
                        }

                    }

                    IosGroup {
                        width: parent.width
                        visible: sortCard.plan !== null && !browser.st.sortChecking
                        title: "Dates found"

                        Repeater {
                            model: sortCard.rows

                            IosRow {
                                required property var modelData
                                required property int index

                                divider: index > 0
                                glyph: modelData.glyph
                                title: modelData.title
                                subtitle: modelData.sub
                                trailing: String(modelData.n)
                            }

                        }

                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                        text: {
                            if (browser.st.sortError !== "")
                                return browser.st.sortError;

                            if (browser.sortBlocker !== "")
                                return browser.sortBlocker;

                            const p = sortCard.plan;
                            if (!p || browser.st.sortChecking)
                                return "";

                            if (p.blocked && p.blocked.length > 0)
                                return "\u201c" + p.blocked[0] + "\u201d is in the way. Rename or move it first.";

                            if (p.mode === "new" && p.fresh === 0)
                                return "All " + p.total + " files already follow the naming pattern (" + p.scheme + " \u2026). Nothing to rename.";

                            if (p.renameCount === 0)
                                return "Already sorted. Nothing to rename.";

                            const range = p.first === p.last ? p.first : p.first + " \u2026 " + p.last;
                            if (p.mode === "new" && p.kept > 0)
                                return (p.fresh === 1 ? "1 new file goes" : p.fresh + " new files go") + " after " + p.lastKept + " in date order (" + range + "). The other " + p.kept + " stay as they are. Old names stay listed in .alte_namen.tsv.";

                            return (p.renameCount === 1 ? "1 file gets" : p.renameCount + " files get") + " a new name (" + range + "). Old names stay listed in .alte_namen.tsv.";
                        }
                        color: browser.st.sortError !== "" || browser.sortBlocker !== "" || (sortCard.plan && sortCard.plan.blocked && sortCard.plan.blocked.length > 0) ? Theme.warn : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.px(10)

                        IosButton {
                            width: (parent.width - parent.spacing) / 2
                            kind: "tinted"
                            tone: Theme.textDim
                            text: "Cancel"
                            dimmed: browser.st.sortApplying
                            onClicked: browser.closeSort()
                        }

                        IosButton {
                            readonly property var plan: sortCard.plan

                            width: (parent.width - parent.spacing) / 2
                            glyph: browser.st.sortApplying ? "" : "\uf160"
                            text: {
                                if (browser.st.sortApplying)
                                    return "Sorting " + Math.round(browser.st.sortProgress * 100) + " %";

                                if (plan && plan.renameCount > 0)
                                    return "Sort " + plan.renameCount + (plan.renameCount === 1 ? " File" : " Files");

                                return "Sort";
                            }
                            dimmed: !plan || plan.renameCount === 0 || browser.st.sortChecking || browser.st.sortApplying || browser.sortBlocker !== "" || (plan.blocked && plan.blocked.length > 0)
                            onClicked: browser.confirmSort()
                        }

                    }

                }

            }

            Behavior on opacity {
                enabled: false
            }

        }

        // ---------- Footer ----------
        Item {
            id: footer

            x: Theme.px(28)
            y: parent.height - height - Theme.px(18)
            width: parent.width - 2 * x
            height: Theme.px(20)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (browser.searchActive) {
                        const r = browser.entries.length;
                        return (r === 1 ? "1 result" : r + " results") + (browser.st.searchBusy ? "  \u00b7  Searching\u2026" : "");
                    }
                    const f = browser.st.folders.length;
                    const n = browser.st.files.length;
                    const parts = [];
                    if (f > 0)
                        parts.push(f + (f === 1 ? " folder" : " folders"));

                    parts.push(n + (n === 1 ? " item" : " items"));
                    return parts.join(" · ");
                }
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                font.features: Theme.tabular
            }

            Text {
                anchors.centerIn: parent
                visible: browser.hint !== "" || browser.notice !== ""
                text: browser.hint !== "" ? browser.hint : browser.notice
                color: browser.hint !== "" ? Theme.warn : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                font.weight: Font.Medium
            }

            // Status on the right: how much is marked and what is ready to paste
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(8)

                Repeater {
                    model: {
                        const out = [];
                        if (browser.markCount > 0)
                            out.push({
                            "glyph": "\uf00c",
                            "text": browser.markCount + " selected",
                            "accent": true
                        });

                        if (browser.st.cutPaths.length > 0)
                            out.push({
                            "glyph": "\uf0c4",
                            "text": browser.st.cutPaths.length + " cut",
                            "accent": false
                        });

                        return out;
                    }

                    delegate: Rectangle {
                        required property var modelData

                        anchors.verticalCenter: parent.verticalCenter
                        width: chipRow.implicitWidth + Theme.px(16)
                        height: Theme.px(22)
                        radius: height / 2
                        color: modelData.accent ? Theme.tint(Theme.accent, 0.18) : Theme.groupFill

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: Theme.px(6)

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.glyph
                                color: parent.parent.modelData.accent ? Theme.accent : Theme.textDim
                                font.family: Theme.font
                                font.pixelSize: Theme.sizeSmall
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.text
                                color: parent.parent.modelData.accent ? Theme.accent : Theme.textDim
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                                font.weight: Font.Medium
                                font.features: Theme.tabular
                            }

                        }

                    }

                }

            }

        }

    }


    ListModel {
        id: gridModel
    }

}
