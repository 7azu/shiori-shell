// Terminals (kitty ...) fade to the new wal colors in sync with the shell on a wallpaper change.
// Before, wal colored them only after the wallpaper wave in one step (delayed). WalColors fades
// from the start of the wave in steps (~22/s) to the precomputed palette; every step goes here to
// scripts/term_colors.py, which writes it to all of the user's terminals as the same escape sequences as wal.
// Runs permanently (only waits on stdin); setpriv --pdeathsig: dies with Quickshell.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/term_colors.py").toString().replace("file://", "")
    // only send after the first real color change: at shell start the terminals already have the
    // colors from wal
    property bool armed: false
    property string lastSent: ""

    // Only so the service is created at shell start (see shell.qml)
    function warmUp() {
    }

    function send() {
        if (!armed || !proc.running)
            return ;

        const line = WalColors.keys.map((k) => {
            return WalColors[k];
        }).join(" ");
        if (line === lastSent)
            return ;

        lastSent = line;
        proc.write(line + "\n");

    }

    Process {
        id: proc

        running: true
        stdinEnabled: true
        onStarted: {
            root.lastSent = "";
            root.send();
        }
        command: ["sh", "-c", "exec setpriv --pdeathsig KILL python3 -u -B \"$1\"", "sh", root.script]
    }

    // ==== Apps with a still-image crossfade (services/SnapshotColorFade.qml, windows/AppColorFade.qml) ====
    // All of them only take new colors in one step or stuttering: freeze the monitor section,
    // change colors underneath, fade the still image out.
    readonly property var snapshotFades: [vesktopFade, obsFade, obsidianFade, steamFade]

    // Vesktop: Chromium only manages the QuickCSS animation of the color variables at ~8 fps (every step
    // changes inherited variables on :root and recomputes the styles of all Discord elements).
    // Hold time: Vencord file watcher 50 ms + style recompute ~130 ms + drawing
    property SnapshotColorFade vesktopFade: SnapshotColorFade {
        name: "Vesktop"
        classPattern: /vesktop/i
        holdMs: 350
        onApplyColors: to => root.writeVesktop(to, to, 0)
        // Fallback: as before with a QuickCSS animation (stutters, but fades)
        onFallback: (from, to, ms) => root.writeVesktop(from, to, ms)
    }

    // OBS: reloads its theme file (Yami variant "Wal" from ~/.config/wal/obs/gen-obs-theme.sh) only as
    // a whole, and only with [Appearance] AutoReload=true in user.ini. Before, wallpaper-apps.sh only
    // wrote the file after the wave -> OBS changed colors late and hard.
    // Hold time: script ~60 ms + OBS reloads the whole stylesheet
    property SnapshotColorFade obsFade: SnapshotColorFade {
        name: "OBS"
        classPattern: /^com\.obsproject\.Studio$/
        holdMs: 500
        onApplyColors: to => root.writeObs(to)
        // no soft fallback possible: then in one step
        onFallback: (from, to, ms) => root.writeObs(to)
    }

    // Obsidian: reloads the snippet .obsidian/snippets/wal-colors.css (~/.config/wal/gen-obsidian-wal.sh)
    // on every change, but in one step. Before, apply-wallpaper.sh only wrote the file after wal
    // -> Obsidian changed colors late and hard.
    // Hold time: script ~70 ms + Obsidian reads the file ~110 ms after writing + redraw
    property SnapshotColorFade obsidianFade: SnapshotColorFade {
        name: "Obsidian"
        classPattern: /^(md\.obsidian\.Obsidian|obsidian)$/i
        holdMs: 450
        onApplyColors: to => root.writeObsidian(to)
        // no soft fallback possible: then in one step
        onFallback: (from, to, ms) => root.writeObsidian(to)
    }

    // Steam (Millennium, theme "Minimal Dark"): the plugin "pywal live" reloads Quick CSS on every change,
    // but in one step. Before, wal only wrote the file after the wave -> Steam changed colors
    // late and hard. scripts/steam_colors.py fills the same wal templates already at the start.
    // Hold time: measured
    property SnapshotColorFade steamFade: SnapshotColorFade {
        name: "Steam"
        classPattern: /^steam$/
        holdMs: 600
        onApplyColors: to => root.writeSteam(to)
        // no soft fallback possible: then in one step
        onFallback: (from, to, ms) => root.writeSteam(to)
    }

    property string steamTarget: ""

    function sendSteam(animated) {
        if (!WalColors.loadedOnce)
            return;
        // Leave the spelling unchanged (wal writes it the same way -> identical file afterwards, no
        // second reload in Steam)
        const target = WalColors.keys.map(k => String(animated ? WalColors.fadeTarget[k] : WalColors[k]));
        const signature = target.join(" ").toLowerCase();
        if (signature === steamTarget)
            return;
        steamTarget = signature;
        if (animated) {
            steamFade.start(null, target, WalColors.fadeAnim.duration);
            return;
        }
        steamFade.cancel();
        writeSteam(target);
    }

    property var steamPending: null

    function writeSteam(palette) {
        if (steamProc.running) {
            steamPending = palette;
            return;
        }
        steamProc.command = ["python3", "-B", Qt.resolvedUrl("../scripts/steam_colors.py").toString().replace("file://", ""),
            JSON.stringify(palette)];
        steamProc.running = true;
    }

    property Process steamProc: Process {
        onExited: {
            const next = root.steamPending;
            root.steamPending = null;
            if (next)
                root.writeSteam(next);
        }
    }

    property string vesktopTarget: ""

    function sendVesktop(animated) {
        if (!vesktopProc.running || !WalColors.loadedOnce)
            return;
        const target = WalColors.keys.map(k => String(animated ? WalColors.fadeTarget[k] : WalColors[k]).toLowerCase());
        const signature = target.join(" ");
        if (signature === vesktopTarget)
            return;
        vesktopTarget = signature;
        const from = WalColors.keys.map(k => String(animated ? WalColors.fadeFrom[k] : WalColors[k]).toLowerCase());
        if (animated) {
            vesktopFade.start(from, target, WalColors.fadeAnim.duration);
            return;
        }
        vesktopFade.cancel();
        writeVesktop(from, target, 0);
    }

    // duration > 0: QuickCSS animation in Vesktop (fallback, stutters), 0: colors in one step
    function writeVesktop(from, to, duration) {
        vesktopProc.write(JSON.stringify({from: from, to: to, duration: duration}) + "\n");
    }

    property string obsTarget: ""

    function sendObs(animated) {
        if (!WalColors.loadedOnce)
            return;
        const target = WalColors.keys.map(k => String(animated ? WalColors.fadeTarget[k] : WalColors[k]).toLowerCase());
        const signature = target.join(" ");
        if (signature === obsTarget)
            return;
        obsTarget = signature;
        if (animated) {
            obsFade.start(null, target, WalColors.fadeAnim.duration);
            return;
        }
        obsFade.cancel();
        writeObs(target);
    }

    // Write the theme file from the palette (16 colors); if the script is still running, the newest afterwards
    property var obsPending: null

    function writeObs(palette) {
        if (obsProc.running) {
            obsPending = palette;
            return;
        }
        obsProc.command = [Quickshell.env("HOME") + "/.config/wal/obs/gen-obs-theme.sh", JSON.stringify(palette)];
        obsProc.running = true;
    }

    property Process obsProc: Process {
        onExited: {
            const next = root.obsPending;
            root.obsPending = null;
            if (next)
                root.writeObs(next);
        }
    }

    property string obsidianTarget: ""

    function sendObsidian(animated) {
        if (!WalColors.loadedOnce)
            return;
        const target = WalColors.keys.map(k => String(animated ? WalColors.fadeTarget[k] : WalColors[k]).toLowerCase());
        const signature = target.join(" ");
        if (signature === obsidianTarget)
            return;
        obsidianTarget = signature;
        if (animated) {
            obsidianFade.start(null, target, WalColors.fadeAnim.duration);
            return;
        }
        obsidianFade.cancel();
        writeObsidian(target);
    }

    // Write the snippet from the palette (16 colors) for all vaults; if the script is still running,
    // the newest afterwards. Unchanged content -> the script leaves the file alone (no reload).
    property var obsidianPending: null

    function writeObsidian(palette) {
        if (obsidianProc.running) {
            obsidianPending = palette;
            return;
        }
        obsidianProc.command = [Quickshell.env("HOME") + "/.config/wal/gen-obsidian-wal.sh", "--palette", JSON.stringify(palette)];
        obsidianProc.running = true;
    }

    property Process obsidianProc: Process {
        onExited: {
            const next = root.obsidianPending;
            root.obsidianPending = null;
            if (next)
                root.writeObsidian(next);
        }
    }

    Connections {
        target: WalColors.fadeAnim
        function onRunningChanged() {
            if (WalColors.fadeAnim.running) {
                root.sendVesktop(true);
                root.sendObs(true);
                root.sendObsidian(true);
                root.sendSteam(true);
                root.sendZen();
                root.sendQt();
            }
        }
    }

    // Qt apps (qt6ct): qt6ct reloads only ~3 s after the color file is replaced (measured), wallpaper-apps.sh
    // only gets there ~3 s after the wave starts -> write the colors already at the start (the later run
    // from wallpaper-apps.sh finds the same content and does not trigger a second reload)
    function sendQt() {
        const palette = WalColors.keys.map(k => String(WalColors.fadeTarget[k] || "").toLowerCase());
        qtProc.command = [Quickshell.env("HOME") + "/.config/wal/qt/gen-qt6ct-colors.sh", JSON.stringify(palette)];
        qtProc.running = true;
    }

    Process {
        id: qtProc
    }

    // Zen: zen-live.cfg (~/.config/wal/zen-live) reads the background color (colors-zen.txt) and
    // YouTube colors (zen-youtube.css) from wal's cache and fades itself with a CSS transition. wal writes
    // both only after the wave -> scripts/zen_colors.py already at the start (wal the same later).
    function sendZen() {
        const palette = WalColors.keys.map(k => String(WalColors.fadeTarget[k] || "").toLowerCase());
        zenProc.command = ["python3", "-B", Qt.resolvedUrl("../scripts/zen_colors.py").toString().replace("file://", ""),
            JSON.stringify(palette)];
        zenProc.running = true;
    }

    Process {
        id: zenProc
    }

    // Writes Vencord's QuickCSS (scripts/vesktop_colors.py); for the crossfade see vesktopFade
    Process {
        id: vesktopProc
        running: true
        stdinEnabled: true
        command: ["sh", "-c", "exec setpriv --pdeathsig KILL python3 -u -B \"$1\"", "sh",
            Qt.resolvedUrl("../scripts/vesktop_colors.py").toString().replace("file://", "")]
        onStarted: {
            root.vesktopTarget = "";
            root.sendVesktop(WalColors.fadeAnim.running);
        }
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
        onTriggered: root.send()
    }

    // Final state (also after instant changes without a fade)
    Connections {
        function onColorsUpdated() {
            root.send();
            root.sendVesktop(false);
            root.sendObs(false);
            root.sendObsidian(false);
            root.sendSteam(false);
        }

        target: WalColors
    }

}
