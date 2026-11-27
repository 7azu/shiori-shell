import "../services"
import "../windows"
import QtQuick

// Content of the settings window: rail on the left, the open page (or the search result) on the right,
// the footer below it. Keys as in the pickers: Up/Down, Ctrl+K/J and Tab/Shift+Tab switch the page,
// Esc clears the search first and closes on the second press, Ctrl+Z takes the last change back.
// Typing always lands in the search field.
// Folder rows open the folder browser of the editors (windows/MediaBrowser, chooseFolder) over the page:
// SettingsState.browseKey names the row, all keys then go to the browser until it reports a folder or Esc.
// A shortcut row that waits for its keys (Keybinds.captureId) gets every key press the same way.
Item {
    id: view

    readonly property bool searching: SettingsState.query.trim() !== ""
    readonly property var shown: searching ? SettingsState.searchSection(SettingsState.query) : SettingsState.sectionById(SettingsState.section)
    // Identity of what is shown, to restart the page intro and scroll to the top only on a real change
    readonly property string shownId: searching ? "search" : SettingsState.section

    // Start where the row points now; a folder that is missing: the nearest one above that exists is not
    // known here, so the home folder
    function openBrowser() {
        const value = SettingsState.read(SettingsState.browseKey);
        const dir = value ? Settings.expand(value) : "";
        const known = dir !== "" && SettingsState.probe.paths[dir] !== false;
        browser.filter = 0;
        browser.currentPath = (known ? dir : Settings.home) + "/";
        browseKeys.forceActiveFocus();
        browser.show(false);
        // Nothing is "open" in a chooser
        browser.currentPath = "";
    }

    // Esc in the browser; the rest happens where browseKey changes (a chosen folder ends there too)
    function closeBrowser() {
        SettingsState.browseKey = "";
    }

    function handleKey(event) {
        const key = PickerManager.navKey(event);
        if (key === Qt.Key_Escape) {
            if (SettingsState.query !== "")
                SettingsState.query = "";
            else
                SettingsState.close();
        } else if (key === Qt.Key_Down || key === Qt.Key_Tab) {
            SettingsState.query = "";
            SettingsState.step(1);
        } else if (key === Qt.Key_Up || key === Qt.Key_Backtab) {
            SettingsState.query = "";
            SettingsState.step(-1);
        } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
            SettingsState.undo();
        } else {
            return ;
        }
        event.accepted = true;
    }

    onShownIdChanged: {
        page.toTop();
        page.playIntro(0);
    }
    Component.onCompleted: {
        rail.focusSearch();
        // Opening: a little after the rail and the card pop, so the page lands last
        page.playIntro(120);
    }
    Keys.onPressed: (event) => {
        return view.handleKey(event);
    }

    SettingsRail {
        id: rail

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Theme.px(256)
        onKeyPressed: (event) => {
            return view.handleKey(event);
        }
    }

    Rectangle {
        anchors.left: rail.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.separator
    }

    // A click on empty space takes the keyboard out of a text field (which commits it)
    MouseArea {
        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        onClicked: rail.focusSearch()
    }

    SettingsPage {
        id: page

        anchors.left: rail.right
        anchors.leftMargin: 1
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: footer.top
        section: view.shown
        clip: true
    }

    SettingsFooter {
        id: footer

        anchors.left: rail.right
        anchors.leftMargin: 1
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    Connections {
        function onBrowseKeyChanged() {
            if (SettingsState.browseKey !== "") {
                view.openBrowser();
            } else {
                browser.preparing = false;
                browser.open = false;
                rail.focusSearch();
            }
        }

        target: SettingsState
    }

    // Folder browser over page and footer (the rail stays, so it is clear where you are)
    MediaBrowser {
        id: browser

        anchors.left: rail.right
        anchors.leftMargin: 1
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        chooseFolder: true
        backdropRadius: 0
        onFolderChosen: (path) => {
            SettingsState.folderChosen(path);
        }
        onDismissed: view.closeBrowser()
        // After a vault's password field: keys back to the browser
        onWantsKeys: browseKeys.forceActiveFocus()
    }

    // A shortcut row captures: every key goes to Keybinds, none to the search field or the page keys
    Connections {
        function onCaptureIdChanged() {
            if (Keybinds.captureId !== "")
                captureKeys.forceActiveFocus();
            else if (SettingsState.browseKey === "")
                rail.focusSearch();
        }

        target: Keybinds
    }

    Item {
        id: captureKeys

        Keys.onPressed: (event) => {
            Keybinds.captureKey(event.key, event.modifiers, event.nativeScanCode);
            event.accepted = true;
        }
        Keys.onReleased: (event) => {
            Keybinds.keyReleased(event.modifiers);
            event.accepted = true;
        }
    }

    // The browser takes no keys itself (as in the editors): everything to handleKey
    Item {
        id: browseKeys

        Keys.onPressed: (event) => {
            browser.handleKey(event);
            event.accepted = true;
        }
    }

}
