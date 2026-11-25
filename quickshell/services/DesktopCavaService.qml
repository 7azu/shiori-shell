// Levels for the desktop visualizer (windows/DesktopVisualizer.qml) on workspace 1.
// Hears EVERYTHING that goes out (music, Discord, browser ...): cava captures the monitor of the default output
// - unlike CavaService (dropdown ring, only the music player). The visualizer is only visible
// while something can really be heard (audible), not by player status: a paused tab that
// reports "Playing" otherwise left a line standing at the bottom.
// Little cava smoothing (noise_reduction 45): the visualizer does the trailing itself (fast up,
// soft down), that feels more direct than cava's symmetric smoothing.
//
// Gain regulated here instead of cava's autosens: autosens lowers the sensitivity on peaks right away,
// but raises it again only by ~0.1 %/frame - after loud Discord, quiet music stayed tiny for a long time.
// Measured (a song into a silent test output, autosens off, sensitivity 100): full volume
// peaks ~0.55, with MPD at 26 % (PipeWire is cubic: ~2 % amplitude) ~0.01 -> factor ~60 between
// Discord and music, the values are linear to the amplitude. So a fine resolution (ascii_max_range 100000)
// and an envelope = loudest peak of the last 1 s (follows peaks right away, then glides in ~0.5 s
// to the new value). An exponential decay would be far too slow at factor 60-85 (1 s half-life
// -> >6 s); this way quiet music is back in full after a loud moment within about 2 s, no matter how big the
// difference was. A lower limit (envFloor), so silence/noise is not pulled up.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property int bars: 48
    readonly property int noiseReduction: 45
    // cava without autosens: 70 still leaves room up to 1.0 for loudly mastered music at full volume
    readonly property int sensitivity: 70
    readonly property int maxRange: 100000
    // Envelope (raw value 0..1): window in frames (60/s) and glide share per frame when sinking (as a
    // ratio, not linear: at factor 85 the last bit would take forever linearly)
    readonly property int envWindow: 60
    readonly property real envRelease: 0.12
    // smallest envelope: anything quieter (MPD at 26 % is at ~0.007) is not amplified further
    readonly property real envFloor: 0.002
    // raw peak from which a frame counts as audible
    readonly property real audibleThreshold: 0.0015
    // share of the height the loudest spot reaches
    readonly property real headroom: 0.92
    // lifts medium levels, so calm passages do not stick to the bottom
    readonly property real gamma: 0.75
    property real env: envFloor
    property var peakHistory: []
    // Levels 0..1, low -> high frequencies (mono)
    property var levels: new Array(bars).fill(0)
    // Can something be heard right now? Drops only after a short silence (pauses between notes)
    property bool audible: false
    // Workspace of the terminal stage (hypr/modules/home.lua), where the visualizer sits
    readonly property int homeWorkspace: 1
    readonly property var homeMonitor: {
        const ws = Hyprland.workspaces.values.find((w) => {
            return w.id === root.homeWorkspace;
        });
        return ws ? ws.monitor : null;
    }
    // Power menu open (PowerMenu) or lock screen active (lock.sh -> qs ipc call visualizer
    // lock/unlock): then it counts as not seen -> level 0, the wave sinks and fades out as after
    // a pause. Separate, because the menu closes when locking (dismiss) while the lock still holds
    property bool menuHold: false
    property bool locked: false
    // Height of the visualizer strip while it is visible (otherwise 0). DesktopVisualizer sets it by binding;
    // the power menu remembers it for the thaw image of the lock screen
    property real shownStrip: 0
    // Is it being seen right now? Otherwise the frames are not processed. Computed here instead of set by the
    // window: on hot reload the old window unregistered the service after the new one had registered it
    // Setting "desktop.visualizer" (settings window): off = the wave sinks as in silence and cava stops
    readonly property bool enabled: (Settings.data.desktop || {
    }).visualizer !== false
    readonly property bool watched: enabled && !menuHold && !locked && !!homeMonitor && !!homeMonitor.activeWorkspace && homeMonitor.activeWorkspace.id === homeWorkspace
    readonly property string conf: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-cava-desktop.conf"
    readonly property string confText: ["[general]", "bars=" + bars, "framerate=60", "autosens=0", "sensitivity=" + sensitivity,
        // after 2 s of silence cava sleeps (no FFT, no output) until sound comes again
        "sleep_timer=2", "lower_cutoff_freq=50", "higher_cutoff_freq=10000",
        "[input]", "method=pipewire", "source=auto",
        "[output]", "method=raw", "raw_target=/dev/stdout", "data_format=ascii", "ascii_max_range=" + maxRange,
        "channels=mono", "mono_option=average",
        "[smoothing]", "noise_reduction=" + noiseReduction, ""].join("\n")

    onWatchedChanged: {
        if (!watched) {
            levels = new Array(bars).fill(0);
            audible = false;
        }
    }

    Process {
        id: proc

        // runs permanently; in silence cava sleeps by itself.
        // setpriv --pdeathsig: cava dies with Quickshell instead of running on as an orphan
        running: root.enabled
        command: ["sh", "-c", "printf '%s' \"$1\" > \"$2\" && exec setpriv --pdeathsig KILL cava -p \"$2\"", "sh", root.confText, root.conf]

        stdout: SplitParser {
            onRead: (line) => {
                if (!root.watched)
                    return ;

                const parts = line.split(";");
                const raw = [];
                let peak = 0;
                for (const p of parts) {
                    if (p === "")
                        continue;

                    const v = Number(p) / root.maxRange;
                    raw.push(v);
                    peak = Math.max(peak, v);
                }
                if (raw.length < root.bars)
                    return ;

                const hist = root.peakHistory;
                hist.push(peak);
                if (hist.length > root.envWindow)
                    hist.shift();

                const target = Math.max(root.envFloor, Math.max.apply(null, hist));
                root.env = target > root.env ? target : root.env * Math.pow(target / root.env, root.envRelease);
                const out = raw.map((v) => {
                    return Math.pow(Math.min(1, v / root.env * root.headroom), root.gamma);
                });
                root.levels = out;
                if (peak > root.audibleThreshold) {
                    root.audible = true;
                    silenceTimer.restart();
                }
            }
        }

    }

    // Silence: cava then sleeps and sends nothing -> set the level to 0 ourselves, the visualizer fades out
    Timer {
        id: silenceTimer

        interval: 1500
        onTriggered: {
            root.audible = false;
            root.levels = new Array(root.bars).fill(0);
            root.env = root.envFloor;
            root.peakHistory = [];
        }
    }

}
