// The cursor fades to the new accent color in sync with the shell on a wallpaper change.
// Before, only wallpaper-apps.sh (gen-cursor.sh) colored it after the wave, in one step and with
// a brief Adwaita image in between. Here every fade step of WalColors (old + new accent color by the
// vividAccent rule as in gen-cursor.sh, plus the progress) goes to ~/.config/wal/cursor/cursor-fade.py: it
// blends the old and new cursor, writes the step into an intermediate theme in RAM and
// switches Hyprland to it; "final" writes the real theme. Only for cursor themes with src/ (Kitty, BongoCat).
// wallpaper-apps.sh skips gen-cursor.sh while the script runs.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/wal/cursor/cursor-fade.py"
    // only send after the first real color change (at start the cursor already matches the colors)
    property bool armed: false
    property bool initialSeen: false
    property string lastSent: ""

    // Only so the service is created at shell start (see shell.qml)
    function warmUp() {
    }

    // step: old + new accent color + progress (the same step as WalColors) - the script blends two
    // finished cursors. Tinting a mixed accent color turned the hue through colors
    // that neither palette has (olive -> green -> blue).
    function send(kind) {
        if (!armed || !proc.running)
            return ;

        let line;
        if (kind === "step") {
            if (WalColors.fadeStep < 0 || !WalColors.fadeFrom.color1 || !WalColors.fadeTarget.color1)
                return ;

            const from = WalColors.vividOf(WalColors.slotsOf(WalColors.fadeFrom));
            const to = WalColors.vividOf(WalColors.slotsOf(WalColors.fadeTarget));
            line = "step " + String(from).toLowerCase() + " " + String(to).toLowerCase() + " " + (WalColors.fadeStep / WalColors.fadeSteps).toFixed(3);
        } else {
            line = "final " + String(WalColors.vividAccent).toLowerCase();
        }
        if (line === lastSent)
            return ;

        lastSent = line;
        proc.write(line + "\n");
    }

    // Runs permanently, reads lines "step #rrggbb" / "final #rrggbb" (it drops older steps itself).
    // pdeathsig TERM instead of KILL: ended in the middle of a fade, the script still sets the real theme.
    Process {
        id: proc

        running: true
        stdinEnabled: true
        command: ["sh", "-c", "exec setpriv --pdeathsig TERM python3 -u -B \"$1\"", "sh", root.script]
        onStarted: root.lastSent = ""
    }

    // while WalColors fades: pass on every step (WalColors sets ~22 steps/s, here at most 20/s)
    Timer {
        interval: 50
        repeat: true
        triggeredOnStart: true
        running: WalColors.fadeAnim.running
        onRunningChanged: {
            if (running)
                root.armed = true;

        }
        onTriggered: root.send("step")
    }

    // Final state (also after instant changes without a fade); skip the very first load at start
    Connections {
        function onColorsUpdated() {
            if (!root.initialSeen) {
                root.initialSeen = true;
                return ;
            }
            root.armed = true;
            root.send("final");
        }

        target: WalColors
    }

}
