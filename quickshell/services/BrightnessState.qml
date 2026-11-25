// Screen brightness (laptop backlight) for the battery dropdown.
// Read directly from /sys/class/backlight/<dev>/brightness, written via
// systemd-logind (Session.SetBrightness) -> no video group, no brightnessctl needed.
// Without a backlight (desktop PC): available = false, the slider stays hidden.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    property string device: ""
    property int maxRaw: 0
    property int raw: 0
    readonly property bool available: device !== "" && maxRaw > 0
    readonly property real level: available ? Math.max(0, Math.min(1, raw / maxRaw)) : 0
    // Below 1% the screen goes black -> never all the way to 0
    readonly property real minLevel: 0.01
    // Last wanted value, while a write is still running
    property int pendingRaw: -1

    function set(v) {
        if (!available)
            return ;

        const target = Math.round(Math.max(minLevel, Math.min(1, v)) * maxRaw);
        raw = target;
        pendingRaw = target;
        flush();
    }

    function step(delta) {
        set(level + delta);
    }

    function refresh() {
        if (available && !writer.running)
            curFile.reload();

    }

    // Do not start hundreds of processes while dragging: always just one, then the newest value
    function flush() {
        if (writer.running || pendingRaw < 0)
            return ;

        writer.command = ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", device, String(pendingRaw)];
        pendingRaw = -1;
        writer.running = true;
    }

    // Find the first backlight device + maximum value
    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] && { echo \"${d##*/} $(cat \"$d/max_brightness\")\"; break; }; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                if (parts.length === 2 && Number(parts[1]) > 0) {
                    root.maxRaw = Number(parts[1]);
                    root.device = parts[0];
                }
            }
        }

    }

    Process {
        id: writer

        onExited: root.flush()
    }

    FileView {
        id: curFile

        path: root.device !== "" ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        printErrors: false
        onLoaded: {
            const v = parseInt(text());
            if (!isNaN(v) && root.pendingRaw < 0 && !writer.running)
                root.raw = v;

        }
    }

}
