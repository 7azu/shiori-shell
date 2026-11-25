import QtQuick
pragma Singleton

QtObject {
    id: root

    // All pickers that can be opened (e.g. by keybind)
    // The order also decides the slide direction when switching (open): tab pickers in tab order
    readonly property var pickers: ["clipboard", "trash", "bluetooth", "wifi", "app", "apps", "music", "vpn", "wallpaper", "media", "language", "shortcuts"]
    // Only these pickers are reached with Tab / Shift+Tab (order = tab order). Also applies to the
    // icons in the search bar (pickers/PickerSwitcher.qml reads this list)
    // VPN stands on its own (own window in space style like Wi-Fi/Bluetooth)
    readonly property var tabPickers: ["app", "music", "wallpaper"]
    property string activePicker: ""
    // Hovered icon in the search bar (index in tabPickers, -1 = none). Shared by all
    // PickerSwitcher instances: every tab picker has its own; after a click the new
    // picker shows the pill right away on the clicked icon instead of first as a capsule (without
    // mouse movement it gets no hover event), and the old one fading out does not jump back to the capsule.
    property int switcherHover: -1
    // Previously active picker ("" = freshly opened): the search bar icons of the new picker start
    // in the old state with it and then animate visibly to the new one (PickerSwitcher.shownActive)
    property string previousPicker: ""
    // During the closing animation (PickerWindow): name of the picker fading out right now
    property string closingPicker: ""
    property string searchText: ""
    // true when opening fresh right now (none was active)
    property bool openingFresh: false
    readonly property bool anyOpen: activePicker !== ""
    property string switchDirection: "none"
    // For slide animations: 1 = forward, -1 = backward, 0 = no switch (freshly opened)
    readonly property int dirSign: switchDirection === "forward" ? 1 : (switchDirection === "backward" ? -1 : 0)
    // Media picker (add-on) "player morph": the picker is starting a player (playerSession: the window stays
    // on its screen) or the player runs visibly (playerActive: window transparent and
    // click-through, without keyboard focus). grabFocus briefly takes the keyboard focus back after the player.
    property bool playerSession: false
    property bool playerActive: false
    property bool grabFocus: false
    // Morph progress of the media picker (0 = panel, 1 = fullscreen). The window derives dimming
    // and the black back surface from it.
    property real morph: 0
    // true when the player window is fullscreen (then the back surface lies hidden below it)
    property bool playerFullscreen: false
    // false = without the black back surface (fallback, in case it should cover the video)
    property bool useBackdrop: true
    // Own workspace for everything the media picker plays: meanwhile you can freely switch to other
    // workspaces, the player (and the picker behind it) stay there. The bar shows a
    // media icon for it (bar/Workspaces.qml), Hyprland opens mpv there directly by rule
    readonly property int playerWorkspace: 13
    // PID of a player that keeps running without the picker (picker closed during playback or
    // opened elsewhere). Here instead of in the media picker, because that one is unloaded after closing. A new
    // start closes it (always only one player), and the detection does not take it for the new one.
    property int detachedPlayer: 0
    property Timer _releaseFreshTimer

    // Pin the picker window to another workspace (-1 = to none: visible on every one, for the
    // short moment of the workspace switch under the black morph surface). PickerWindow -> WindowAnchor
    signal pinRequested(int workspaceId)
    // The active picker should focus its search field again (e.g. after a click on a button).
    // For building blocks in their own files that do not know their picker (pickers/parts)
    signal focusRequested()

    function requestFocus() {
        focusRequested();
    }

    function isOpen(name) {
        return activePicker === name;
    }

    // Uniform key handling in all pickers: Ctrl+J / Ctrl+K act like arrow down / up
    // (also while typing in the search field). The handlers compute with the result instead of event.key and
    // then no longer count Ctrl as pressed (otherwise Ctrl+K would be "Ctrl+Up" in a picker).
    // H/L stay free on purpose: Ctrl+H/L are already taken there (hidden tab, book language).
    function navKey(event) {
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_J)
                return Qt.Key_Down;

            if (event.key === Qt.Key_K)
                return Qt.Key_Up;

        }
        return event.key;
    }

    function _resetPlayer() {
        playerSession = false;
        playerActive = false;
        grabFocus = false;
        playerFullscreen = false;
        morph = 0;
    }

    function _doOpen(name, direction) {
        if (pickers.indexOf(name) === -1) {
            console.warn("PickerManager: unknown picker:", name);
            return ;
        }
        if (activePicker === name)
            return ;

        const wasOpen = activePicker !== "";
        if (!wasOpen) {
            openingFresh = true;
            releaseFreshTimer.restart();
        }
        switchDirection = wasOpen ? direction : "none";
        if (tabPickers.indexOf(name) === -1)
            switcherHover = -1;

        searchText = "";
        _resetPlayer();
        previousPicker = activePicker;
        activePicker = name;
    }

    function open(name) {
        // The media picker is a private add-on (services/Addons)
        if (name === "media" && !Addons.media)
            return ;

        if (activePicker === "") {
            _doOpen(name, "none");
            return ;
        }
        const fromIdx = pickers.indexOf(activePicker);
        const toIdx = pickers.indexOf(name);
        _doOpen(name, toIdx > fromIdx ? "forward" : "backward");
    }

    function close() {
        // Remember who is closing before clearing: PickerWindow keeps this picker visible for the closing
        // animation. Must happen BEFORE activePicker = "", otherwise the slot is invisible for a moment and the
        // picker replays its intro when it becomes visible again (instead of fading out).
        if (activePicker !== "")
            closingPicker = activePicker;

        _resetPlayer();
        activePicker = "";
        searchText = "";
        switchDirection = "none";
        // On the next opening the mouse is somewhere else -> do not start with the pill on the old icon
        switcherHover = -1;
    }

    function toggle(name) {
        if (activePicker === name)
            close();
        else
            open(name);
    }

    // One step in the tab cycle (dir = 1 forward, -1 back).
    // Only the tab pickers (app, music, wallpaper) are a bundle. All others (clipboard,
    // trash, task manager, Bluetooth, Wi-Fi, VPN, media) stand on their own: Tab does nothing there,
    // instead of jumping into the cycle as before.
    function _step(dir) {
        const list = tabPickers;
        const idx = list.indexOf(activePicker);
        if (idx === -1)
            return ;

        const next = list[(idx + dir + list.length) % list.length];
        _doOpen(next, dir > 0 ? "forward" : "backward");
    }

    function cycle() {
        _step(1);
    }

    function cycleBackward() {
        _step(-1);
    }

    _releaseFreshTimer: Timer {
        id: releaseFreshTimer

        interval: 60
        onTriggered: root.openingFresh = false
    }

}
