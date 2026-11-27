pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What happens while you are away (hypridle, steps in settings.json "idle", in minutes, 0 = off):
//   dim        the screen turns darker softly (windows/IdleDim draws it; hypridle calls dim/undim here)
//   lock       lock screen      screenOff  monitors off      suspend  standby
// hypridle reads its file only at start: scripts/idle_config.py writes it from the settings and
// hypr/scripts/idle.sh starts hypridle with it. A changed value restarts hypridle through Hyprland
// (so it does not become a child of the shell and survives a restart of the shell).
Singleton {
    id: root

    // 0..1 how dark the screen is (the overlay follows it)
    property real dimK: 0
    // How dark at most: the screen stays readable, any input brings it back at once
    readonly property real dimMax: 0.6
    // The steps as they are set now; a change restarts hypridle (not at the start of the shell)
    readonly property string steps: JSON.stringify(["dim", "lock", "screenOff", "suspend"].map((k) => {
        return [Number(Settings.get("idle." + k)) || 0, Settings.get("idle." + k + "On") !== false];
    }))
    property bool started: false

    function dim() {
        undimAnim.stop();
        dimAnim.from = dimK;
        dimAnim.restart();
    }

    function undim() {
        dimAnim.stop();
        undimAnim.from = dimK;
        undimAnim.restart();
    }

    onStepsChanged: {
        if (started)
            restartTimer.restart();

    }
    Component.onCompleted: Qt.callLater(() => {
        root.started = true;
    })

    // Slow and soft: you should notice it without it feeling like a switch
    NumberAnimation {
        id: dimAnim

        target: root
        property: "dimK"
        to: 1
        duration: 4000
        easing.type: Easing.InOutSine
    }

    NumberAnimation {
        id: undimAnim

        target: root
        property: "dimK"
        to: 0
        duration: 260
        easing.type: Easing.OutCubic
    }

    // Values change in steps (the stepper in the settings): restart once they rest
    Timer {
        id: restartTimer

        interval: 1200
        onTriggered: {
            const script = Quickshell.env("HOME") + "/.config/hypr/scripts/idle.sh restart";
            Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.exec_cmd("' + script + '")']);
        }
    }

    IpcHandler {
        function dim(): void {
            root.dim();
        }

        function undim(): void {
            root.undim();
        }

        target: "idle"
    }

}
