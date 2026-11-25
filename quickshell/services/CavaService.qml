// Audio visualizer data (cava), modeled on the Caelestia shell:
// - cava runs permanently while music plays (not only with the dropdown open). This way cava's
//   autosens is always settled; a restart per opening started overdriven every time.
// - ONLY the music: scripts/cava_music.py records exclusively the stream of the active
//   player with pw-record (Discord, system sounds etc. stay out) and feeds cava with it.
// - strong smoothing in cava (noise_reduction 77) + monstercat filter (factor 1.5): peaks spread
//   to their neighbors -> connected, calm waves instead of flicker
// - gamma 0.6 lifts medium levels (measured via pw-record: typically ~13px, peaks ~25px of 36px,
//   a bit more with settled autosens; quiet and loud music stay distinguishable)
// - after pause/stop the values fall softly to 0 (the ring stays in the dropdown as a resting ring)

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property int bars: 30
    readonly property real monstercat: 1.5
    readonly property real gamma: 0.6
    readonly property int noiseReduction: 77
    readonly property real releaseFactor: 0.88 // fade-out after pause, per frame
    readonly property string script: Qt.resolvedUrl("../scripts/cava_music.py").toString().replace("file://", "")
    property var levels: new Array(bars).fill(0)
    // Only the audio dropdown shows the values. When it is closed, cava keeps running (autosens stays
    // settled), but the script does not even send the 60 frames/s here then (sendWatched tells it).
    readonly property bool watched: DropdownState.current === "audio"

    function sendWatched() {
        if (proc.running)
            proc.write(watched ? "1\n" : "0\n");

    }

    onWatchedChanged: sendWatched()

    // Only so the service is created at shell start (see shell.qml)
    function warmUp() {
    }

    function processFrame(raw) {
        const n = bars;
        const out = new Array(n);
        // Monstercat: left->right and right->left, each with exponential decay
        let carry = 0;
        for (let i = 0; i < n; i++) {
            carry = Math.max(raw[i], carry / monstercat);
            out[i] = carry;
        }
        carry = 0;
        for (let i = n - 1; i >= 0; i--) {
            carry = Math.max(raw[i], carry / monstercat);
            out[i] = Math.pow(Math.min(1, Math.max(out[i], carry)), gamma);
        }
        levels = out;
    }

    Process {
        id: proc

        running: AudioState.isPlaying
        stdinEnabled: true
        command: ["python3", root.script, String(root.bars), String(root.noiseReduction)]
        // The script assumes someone is watching until it hears otherwise
        onStarted: root.sendWatched()
        onRunningChanged: {
            if (running)
                releaseTimer.stop();
            else
                releaseTimer.start();
        }

        stdout: SplitParser {
            onRead: (line) => {
                if (!root.watched)
                    return ;

                const parts = line.split(";");
                const values = [];
                for (const p of parts) {
                    if (p !== "")
                        values.push(Number(p) / 1000);

                }
                if (values.length >= root.bars)
                    root.processFrame(values);

            }
        }

    }

    // After pause/stop fade out softly instead of freezing
    Timer {
        id: releaseTimer

        interval: 16
        repeat: true
        onTriggered: {
            let any = false;
            const out = root.levels.map((v) => {
                const nv = v * root.releaseFactor;
                if (nv > 0.003)
                    any = true;

                return nv > 0.003 ? nv : 0;
            });
            root.levels = out;
            if (!any)
                stop();

        }
    }

}
