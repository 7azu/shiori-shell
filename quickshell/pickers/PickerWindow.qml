import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: pickerWindow

    readonly property bool isAnyOpen: PickerManager.anyOpen
    // Two surfaces like all modal windows: this one with the pickers ("quickshell:pickers-card", no
    // Hyprland animation) and below it the backdrop with dimming + blur (common/ModalBackdrop,
    // "quickshell:pickers"). Closing: the backdrop goes at once (Hyprland fades it) while the picker
    // content evaporates (common/Evaporate: grows a little, blurs, fades); then this window goes.
    property bool closing: false
    property string lastPicker: ""
    // Media picker player morph: hold the screen while a player is starting / running
    property var lockedScreen: null
    // Tab pickers (app, music, wallpaper): as soon as the active one is loaded, the
    // others are preloaded in the background -> they are there right away on a tab switch.
    readonly property bool tabGroupOpen: PickerManager.tabPickers.indexOf(PickerManager.activePicker) !== -1
    readonly property bool activeTabReady: (PickerManager.activePicker === "app" && appLoader.status === Loader.Ready) || (PickerManager.activePicker === "music" && musicLoader.status === Loader.Ready) || (PickerManager.activePicker === "wallpaper" && wallpaperLoader.status === Loader.Ready)
    readonly property bool preloadTabs: tabGroupOpen && activeTabReady

    // Name -> slot (Loader) of the picker
    readonly property var slots: ({
        "clipboard": clipboardLoader,
        "trash": trashLoader,
        "bluetooth": bluetoothLoader,
        "wifi": wifiLoader,
        "app": appLoader,
        "apps": appsLoader,
        "music": musicLoader,
        "wallpaper": wallpaperLoader,
        "vpn": vpnLoader,
        "media": mediaLoader,
        "language": languageLoader,
        "shortcuts": shortcutsLoader
    })

    function slotFor(name) {
        return slots[name] || null;
    }

    // This picker stays visible during the closing animation.
    // closingPicker is set already BEFORE closing (PickerManager.close),
    // so the slot is not invisible for a single moment.
    function closingFrom(name) {
        return PickerManager.closingPicker === name;
    }

    // The picker stays shown (closingPicker) while it evaporates; the pickers' own playOutro is not
    // used any more, so every picker closes the same way
    function startClose() {
        closing = true;
        PickerManager.closingPicker = lastPicker;
        ev.play();
    }

    function cancelClose() {
        PickerManager.closingPicker = "";
        if (!closing)
            return ;

        ev.stop();
        closing = false;
        resetCloseState();
        freshOpenBounce.restart();
        const slot = slotFor(lastPicker);
        if (slot && slot.item && typeof slot.item.playIntro === "function")
            slot.item.playIntro();

    }

    // Reset outro leftovers; only on the next opening, so Hyprland surely keeps the last frame
    // (without the panel) when fading out
    function resetCloseState() {
        scaleWrapper.scale = 1;
        ev.stop();
    }

    function focusActivePicker() {
        const slot = slotFor(PickerManager.activePicker);
        if (slot && slot.item)
            slot.item.focusSearch();

    }

    WlrLayershell.namespace: "quickshell:pickers-card"
    WlrLayershell.layer: WlrLayer.Overlay
    // While the media player runs: no keyboard focus (mpv gets all keys). Right after the player the
    // picker briefly takes the focus back exclusively.
    WlrLayershell.keyboardFocus: PickerManager.playerActive || LanguageAudioState.videoOpen ? WlrKeyboardFocus.None : (PickerManager.grabFocus && anchor.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
    WlrLayershell.exclusiveZone: -1
    screen: (PickerManager.playerSession && lockedScreen) ? lockedScreen : anchor.screen
    // Empty mask = the whole window is click-through (mpv stays usable) while the player runs
    mask: PickerManager.playerActive ? passThroughMask : null
    visible: (isAnyOpen || closing) && anchor.here
    color: "transparent"
    onIsAnyOpenChanged: {
        if (isAnyOpen)
            cancelClose();
        else if (lastPicker !== "" && !PickerManager.playerSession)
            startClose();
        else
            PickerManager.closingPicker = "";
    }
    onVisibleChanged: {
        if (visible) {
            resetCloseState();
            // Back to the player workspace (loading screen/player keep running): no opening hop,
            // it would briefly shrink the black fullscreen surface
            // Likewise not when the language video player is morphing back into the panel
            if (!PickerManager.playerSession && !LanguageAudioState.morphHandoff)
                freshOpenBounce.restart();

            Qt.callLater(() => {
                return focusActivePicker();
            });
        }
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Region {
        id: passThroughMask
    }

    // Stays on the monitor + workspace where it was opened
    WindowAnchor {
        id: anchor

        open: pickerWindow.isAnyOpen
        onClosedWhileAway: {
            if (pickerWindow.lastPicker !== "")
                PickerManager.open(pickerWindow.lastPicker);

        }
    }

    Evaporate {
        id: ev

        manual: true
        onFinished: {
            pickerWindow.closing = false;
            PickerManager.closingPicker = "";
        }
    }

    // Dimming + blur. The dimming follows the media player morph: gone when the player fills the
    // surface, back when morphing back. Clicks go through to the pickers (they close themselves).
    ModalBackdrop {
        screen: pickerWindow.screen
        name: "quickshell:pickers"
        shown: pickerWindow.isAnyOpen && anchor.here
        clickable: false
        dim: WalColors.withAlpha(WalColors.color0, 0.4 * Math.max(0, Math.min(1, 1 - PickerManager.morph)))
    }

    // Black back surfaces for the player morph. Hyprland hides top layers behind a fullscreen window,
    // so they lie invisible under mpv. When mpv closes, they take over right away until the picker's
    // morph surface is there. There are two: top (covers windows) and bottom (covers the background image, in case
    // Hyprland does not draw the top layers again for one frame yet).
    // While mpv runs, only the bottom surface is black: the player has its own, otherwise empty
    // workspace (PickerManager.playerWorkspace), so there are no windows to cover. A black
    // top surface would flash briefly over the other workspace when switching away.
    Backdrop {
        bdLayer: WlrLayer.Top
        bdName: "quickshell:player-backdrop"
        darkWhilePlaying: false
    }

    Backdrop {
        bdLayer: WlrLayer.Bottom
        bdName: "quickshell:player-backdrop-bottom"
    }

    Connections {
        function onPlayerSessionChanged() {
            pickerWindow.lockedScreen = PickerManager.playerSession ? pickerWindow.screen : null;
        }

        function onPinRequested(workspaceId) {
            anchor.pinTo(workspaceId);
        }

        function onFocusRequested() {
            pickerWindow.focusActivePicker();
        }

        function onActivePickerChanged() {
            if (PickerManager.activePicker !== "")
                pickerWindow.lastPicker = PickerManager.activePicker;

            // Another picker called while the window lies on another workspace -> move it here
            if (PickerManager.activePicker !== "" && anchor.away)
                anchor.pin();

            if (pickerWindow.visible)
                Qt.callLater(() => {
                return pickerWindow.focusActivePicker();
            });

        }

        target: PickerManager
    }

    // Keeps the world map of the VPN globe in memory once it was open: otherwise it is decoded
    // and uploaded to the GPU on every opening (one stuttering frame). Only after the first
    // use, so the ~32 MB are not taken already at shell start.
    Image {
        width: 1
        height: 1
        opacity: 0.01
        source: VpnPickerState.globeUsed ? "../resources/globe/earth.png" : ""
        mipmap: true
        smooth: true
        asynchronous: true
    }

    Item {
        id: backgroundRect

        anchors.fill: parent
        opacity: (pickerWindow.isAnyOpen || pickerWindow.closing) ? 1 : 0

        Item {
            id: scaleWrapper

            anchors.fill: parent
            scale: 1
            transformOrigin: Item.Center

            SequentialAnimation {
                id: freshOpenBounce

                // Damped spring instead of OutBack: the picker panels grow themselves (0.95 -> 1, outQuint),
                // which swallowed the short OutBack hop. The slower spring peaks after the panel has
                // nearly arrived, so one calm ~0.8 % overshoot stays visible.
                NumberAnimation {
                    target: scaleWrapper
                    property: "scale"
                    from: 0.88
                    to: 1
                    duration: Appearance.anim.durations.spring
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.spring
                }

            }

            Item {
                id: crossfadeContainer

                anchors.fill: parent
                enabled: !pickerWindow.closing
                scale: ev.scale
                opacity: ev.opacity
                // Blur only while evaporating
                layer.enabled: ev.running

                layer.effect: MultiEffect {
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: ev.blur
                    blurMax: 64
                    blurMultiplier: 0.6
                }

                // Every picker is a "slot": loads itself and unloads again.
                // The switch animation is done by the picker itself (only its content, not the search bar).
                PickerSlot {
                    id: clipboardLoader

                    shown: PickerManager.activePicker === "clipboard" || pickerWindow.closingFrom("clipboard")

                    sourceComponent: Component {
                        ClipboardPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: trashLoader

                    shown: PickerManager.activePicker === "trash" || pickerWindow.closingFrom("trash")

                    sourceComponent: Component {
                        TrashPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: bluetoothLoader

                    shown: PickerManager.activePicker === "bluetooth" || pickerWindow.closingFrom("bluetooth")

                    sourceComponent: Component {
                        BluetoothPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: wifiLoader

                    shown: PickerManager.activePicker === "wifi" || pickerWindow.closingFrom("wifi")

                    sourceComponent: Component {
                        WifiPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: appLoader

                    tab: true
                    shown: PickerManager.activePicker === "app" || pickerWindow.closingFrom("app")

                    sourceComponent: Component {
                        AppLauncher {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: appsLoader

                    shown: PickerManager.activePicker === "apps" || pickerWindow.closingFrom("apps")

                    sourceComponent: Component {
                        AppPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: musicLoader

                    tab: true
                    shown: PickerManager.activePicker === "music" || pickerWindow.closingFrom("music")

                    sourceComponent: Component {
                        MusicPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: wallpaperLoader

                    tab: true
                    shown: PickerManager.activePicker === "wallpaper" || pickerWindow.closingFrom("wallpaper")

                    sourceComponent: Component {
                        WallpaperPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: vpnLoader

                    shown: PickerManager.activePicker === "vpn" || pickerWindow.closingFrom("vpn")

                    sourceComponent: Component {
                        VpnPicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

                PickerSlot {
                    id: mediaLoader

                    // Private add-on (services/Addons): without addons/media the slot stays empty
                    shown: Addons.media && (PickerManager.activePicker === "media" || pickerWindow.closingFrom("media"))
                    source: Addons.media ? Addons.url(Addons.manifest.media) : ""
                    onLoaded: item.focus = false

                    Connections {
                        function onCloseRequested() {
                            PickerManager.close();
                        }

                        target: mediaLoader.item
                        ignoreUnknownSignals: true
                    }

                }

                PickerSlot {
                    id: shortcutsLoader

                    shown: PickerManager.activePicker === "shortcuts" || pickerWindow.closingFrom("shortcuts")
                    source: "ShortcutPicker.qml"
                }

                PickerSlot {
                    id: languageLoader

                    shown: PickerManager.activePicker === "language" || pickerWindow.closingFrom("language")
                    persist: LanguageAudioState.videoLoaded

                    sourceComponent: Component {
                        LanguagePicker {
                            anchors.fill: parent
                            focus: false
                        }

                    }

                }

            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }

        }

    }

    component Backdrop: PanelWindow {
        id: bd

        property int bdLayer: WlrLayer.Top
        property string bdName: "quickshell:player-backdrop"
        property bool darkWhilePlaying: true
        // Layer surfaces belong to the monitor, not to the workspace: on another workspace (anchor.here
        // false) transparent, otherwise the black surface would lie above everything there
        readonly property real level: !anchor.here ? 0 : PickerManager.playerActive ? (darkWhilePlaying && PickerManager.playerFullscreen ? 1 : 0) : Math.max(0, Math.min(1, (PickerManager.morph - 0.5) * 2))

        screen: pickerWindow.screen
        // Stays mapped the whole session, also on other workspaces (only transparent there): Hyprland does not
        // hide a NEWLY mapped top surface behind the fullscreen mpv -> after switching back
        // it would lie black over the video
        visible: PickerManager.useBackdrop && PickerManager.playerSession
        color: Qt.rgba(0, 0, 0, level)
        WlrLayershell.namespace: bd.bdName
        WlrLayershell.layer: bd.bdLayer
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusiveZone: -1

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
        }

    }

    // ───────────────────────── Slot for a picker ─────────────────────────
    // Loads/unloads a picker. The switch animation is done by the picker itself:
    // It provides `tabIn` (0..1) and only animates its content, the search bar
    // stays unchanged for all pickers. If a picker has no `tabIn`,
    // it is simply hidden or shown right away on a switch.
    component PickerSlot: Loader {
        id: slot

        // Set per slot: is this picker the active one right now?
        property bool shown: false
        // Belongs to the tab cycle: preloaded while a tab picker is open
        property bool tab: false
        property bool keepAlive: false
        // Stay loaded although closed (e.g. the language picker while a video plays: "Back" from the
        // player should show it right away instead of rebuilding it)
        property bool persist: false
        readonly property bool wantAlive: shown || persist || (tab && pickerWindow.preloadTabs)
        readonly property bool hasTabAnim: item !== null && item.tabIn !== undefined

        anchors.fill: parent
        asynchronous: true
        active: keepAlive
        // Visible while it is active or (with the tab animation) still fading out
        visible: keepAlive && (shown || (hasTabAnim && item.tabIn > 0.001))
        enabled: shown
        onWantAliveChanged: {
            if (wantAlive) {
                unloadTimer.stop(); // an unload timer was already on its way: cancel it
                keepAlive = true;
            } else if (keepAlive) {
                unloadTimer.restart();
            }
        }
        // A freshly loaded (e.g. preloaded) picker must not steal the focus from the active one
        onLoaded: Qt.callLater(() => {
            return pickerWindow.focusActivePicker();
        })
        Component.onCompleted: {
            if (wantAlive)
                keepAlive = true;

        }

        Timer {
            id: unloadTimer

            interval: 450
            onTriggered: {
                if (!slot.wantAlive)
                    slot.keepAlive = false;

            }
        }

    }

}
