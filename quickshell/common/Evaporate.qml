import QtQuick

// Closing of the modal windows (settings, calculator, pickers ...): the card "evaporates", it grows a
// little (to 104 %), goes soft (blur) and fades, as if dissolving into the air. Meanwhile the backdrop
// (common/ModalBackdrop: dimming + Hyprland blur) is already gone and Hyprland fades it, so both leave
// together. Rejected before: a calm sink with a breath, an iOS app style shrink to 60 % / 15 %.
//
// Use:
//   Evaporate { id: ev; window: win; open: <state open> }
//   PanelWindow: visible: ev.held && anchor.here
//   card: scale: ... * ev.scale; opacity: ... * ev.opacity
//         layer.enabled: ev.closing
//         layer.effect: MultiEffect { autoPaddingEnabled: true; blurEnabled: true; blur: ev.blur; blurMax: 64; blurMultiplier: 0.6 }
//   onReopened: play the opening again (the window stayed, so onVisibleChanged does not come)
// manual: true = the window keeps its own open/close state (pickers/PickerWindow) and calls play() /
// stop() itself; use `running` instead of `closing` there and `finished` to hide the window.
QtObject {
    id: ev

    // The window whose card evaporates; only a visible window plays the closing
    property var window: null
    // State of the window (bind it); false starts the closing
    property bool open: false
    // Window stays while the closing plays. Set by hand, not bound: a binding would drop to false
    // before the closing could start.
    property bool held: false
    readonly property bool closing: held && !open
    readonly property bool running: anim.running
    // Closing clock 0 -> 1 (linear); the parts take their own eased shares of it
    property real out: 0
    // Size and blur come quickly and settle (ease out), the fade runs evenly to the end
    readonly property real drift: 1 - Math.pow(1 - out, 3)
    readonly property real scale: 1 + 0.04 * drift
    readonly property real blur: drift
    readonly property real opacity: 1 - Math.max(0, Math.min(1, out / 0.95))
    property int duration: 250
    property bool manual: false

    // Opened again while the closing played: the window is still there
    signal reopened()
    // The closing is over and the window is gone
    signal finished()

    property SequentialAnimation anim: SequentialAnimation {
        NumberAnimation {
            target: ev
            property: "out"
            from: 0
            to: 1
            duration: ev.duration
        }

        // Only unmap when the last frame (card gone) is surely drawn
        PauseAnimation {
            duration: 30
        }

        ScriptAction {
            script: {
                ev.held = false;
                ev.finished();
            }
        }

    }

    function play() {
        anim.restart();
    }

    // Back to "not evaporated" (also call before showing the window again in manual mode)
    function stop() {
        anim.stop();
        out = 0;
    }

    onOpenChanged: {
        if (manual)
            return ;

        if (open) {
            const wasClosing = anim.running;
            anim.stop();
            out = 0;
            held = true;
            if (wasClosing)
                reopened();

        } else if (window && window.visible) {
            anim.restart();
        } else {
            held = false;
        }
    }
    Component.onCompleted: held = open
}
