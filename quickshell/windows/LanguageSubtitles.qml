import "../common"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Subtitle bar in list mode (the video only plays as audio, no player window): at the bottom of the
// focused monitor, above everything (overlay). Content = common/LanguageSubtitleBox (as in the player).
// While a picker or the video player is open, it stays away.
PanelWindow {
    id: win

    readonly property bool active: LanguageSubtitleState.subsShown && LanguageSubtitleState.cues.length > 0 && LanguageAudioState.currentIsVideo && LanguageAudioState.mediaActive && !LanguageAudioState.watching && !PickerManager.anyOpen

    onActiveChanged: {
        // Hold the monitor on appearing, do not jump after the mouse
        if (active)
            screen = MachineConfig.focusedScreen();

    }
    visible: active || subs.barItem.opacity > 0.01
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:language-subtitles"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // With an open explanation the whole window catches clicks (a click beside = close + continue),
    // otherwise only the bar: everything below stays usable
    mask: Region {
        item: subs.popupOpen ? full : subs.barItem
    }

    MouseArea {
        id: full

        anchors.fill: parent
        enabled: subs.popupOpen
        onClicked: subs.close()
    }

    LanguageSubtitleBox {
        id: subs

        shown: win.active
        maxWidth: win.width - Theme.px(96)
        x: Math.round((win.width - width) / 2)
        y: win.height - height - Math.max(Theme.px(56), win.height * 0.06) + (1 - barItem.opacity) * 16
    }

}
