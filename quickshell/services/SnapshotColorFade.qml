import QtQuick
import Quickshell
import Quickshell.Io

// Color change of an app on a wallpaper change as a real crossfade with a still image, for apps
// that can only take new colors in one step (or stuttering): Vesktop (QuickCSS),
// OBS (theme file). Instances in services/TerminalColorFade.qml, window: windows/AppColorFade.qml.
//
// Freeze the monitor section above the app window, set the new colors below it in ONE step
// (signal applyColors) and fade the still image out (GPU, full frame rate). A section of the
// finished frame instead of a window image, because the windows are semi-transparent (active_opacity): this way
// the still image is pixel identical.
// Flow: waitPicker (the wallpaper picker must be gone, otherwise it is in the picture) -> probe (hyprctl:
// window visible, nothing above it?) -> capture -> hold (the app changes colors underneath) -> fade
QtObject {
    id: root

    // Name for the log
    property string name: "App"
    // Window class of the app
    property var classPattern: /^$/
    // This is how long the app surely needs after applyColors until the new frame
    property int holdMs: 350

    // Set the new colors in one step (under the still image or without a crossfade)
    signal applyColors(var to)
    // Crossfade not possible, but the app is visible: its own fallback (remaining time in ms)
    signal fallback(var from, var to, int ms)

    property var request: null
    property string phase: "idle"
    property var screen: null
    property rect rect: Qt.rect(0, 0, 0, 0)
    property real opacity: 1
    readonly property bool active: phase === "capture" || phase === "hold" || phase === "fade"

    function elapsed() {
        return request ? Date.now() - request.at : 0;
    }

    function start(from, to, duration) {
        cancel();
        request = {from: from, to: to, duration: duration, at: Date.now()};
        phase = "waitPicker";
        pickerPoll.restart();
    }

    function cancel() {
        pickerPoll.stop();
        probe.running = false;
        captureTimeout.stop();
        hold.stop();
        anim.stop();
        phase = "idle";
    }

    // Without a crossfade: remaining time to the app's fallback
    function giveUp(reason) {
        console.log(name + "-Fade: fallback (" + reason + ")");
        const r = request;
        cancel();
        if (r)
            fallback(r.from, r.to, Math.max(300, r.duration - (Date.now() - r.at)));
    }

    // App not visible right now: nothing to fade
    function instant() {
        const r = request;
        cancel();
        if (r)
            applyColors(r.to);
    }

    function decide(text) {
        if (phase !== "probe")
            return;
        let clients, monitors;
        try {
            [clients, monitors] = JSON.parse(text);
        } catch (e) {
            giveUp("hyprctl unlesbar");
            return;
        }
        const v = clients.find(c => root.classPattern.test(c.class) && c.mapped && !c.hidden);
        const mon = v && monitors.find(m => m.id === v.monitor);
        // No special workspace open = empty name (this Hyprland version then gives NO id)
        const special = mon && mon.specialWorkspace && mon.specialWorkspace.name || "";
        if (!mon || mon.activeWorkspace.name !== v.workspace.name && special !== v.workspace.name) {
            instant();
            return;
        }
        // A special workspace or another window above the app: the still image would cover it
        const r = {x: v.at[0], y: v.at[1], w: v.size[0], h: v.size[1]};
        const covered = (special !== "" && special !== v.workspace.name)
            || clients.some(c => c.address !== v.address && c.mapped && !c.hidden
                && (c.workspace.id === v.workspace.id || c.pinned)
                && c.at[0] < r.x + r.w - 1 && c.at[0] + c.size[0] > r.x + 1
                && c.at[1] < r.y + r.h - 1 && c.at[1] + c.size[1] > r.y + 1);
        const scr = Quickshell.screens.find(s => s.name === mon.name);
        if (covered || !scr) {
            giveUp(covered ? "verdeckt" : "Monitor fehlt");
            return;
        }
        screen = scr;
        rect = Qt.rect(r.x - mon.x, r.y - mon.y, r.w, r.h);
        opacity = 1;
        phase = "capture";
        captureTimeout.restart();
    }

    // From the window: the still image lies visibly above the app -> change colors underneath
    function captured() {
        if (phase !== "capture")
            return;
        captureTimeout.stop();
        applyColors(request.to);
        phase = "hold";
        hold.restart();
        console.log(name + "-Fade: still image after " + elapsed() + " ms, crossfading");
    }

    property Timer pickerPoll: Timer {
        interval: 40
        repeat: true
        onTriggered: {
            if (PickerManager.anyOpen || PickerManager.closingPicker !== "") {
                // The picker stays open (e.g. only the preview changed): then without a still image
                if (root.elapsed() > 2000)
                    root.giveUp("Picker offen");
                return;
            }
            stop();
            root.phase = "probe";
            root.probe.running = true;
        }
    }

    property Process probe: Process {
        command: ["sh", "-c", "printf '[%s,%s]' \"$(hyprctl -j clients)\" \"$(hyprctl -j monitors)\""]
        stdout: StdioCollector {
            onStreamFinished: root.decide(text)
        }
    }

    property Timer captureTimeout: Timer {
        interval: 700
        onTriggered: root.giveUp("no still image")
    }

    property Timer hold: Timer {
        interval: root.holdMs
        onTriggered: {
            root.phase = "fade";
            root.anim.duration = Math.max(450, root.request.duration - root.elapsed());
            root.anim.start();
        }
    }

    property NumberAnimation anim: NumberAnimation {
        target: root
        property: "opacity"
        from: 1
        to: 0
        easing.type: Easing.InOutSine
        onFinished: root.phase = "idle"
    }
}
