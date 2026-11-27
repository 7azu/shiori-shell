pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Window look of Hyprland from the settings page "Windows" (settings.json "windows": gaps, borders,
// corners, opacity, shadow, blur, animations). Hyprland reads the values itself when its config loads
// (hypr/modules/style.lua); a change here is sent live at once, so nothing has to reload:
//   hyprctl eval 'hl.config(dofile(".../style.lua").config())'
// A changed animation speed runs animations.lua again (every speed is multiplied there).
// Border colors: "wal:colorN" = color of the wallpaper palette (follows a wallpaper change, see
// HyprlandColorFade), "#rrggbb" = fixed.
Singleton {
    id: root

    readonly property string modules: Quickshell.env("HOME") + "/.config/hypr/modules"
    // Everything Hyprland gets from the page; a change sends it (not at the start of the shell)
    readonly property string look: JSON.stringify(Settings.get("windows") || {
    })
    readonly property real animSpeed: Number(Settings.get("windows.animSpeed")) || 1
    property bool started: false
    property real sentSpeed: 1
    property bool pending: false

    // "wal:color5" -> the palette color now (also during a wallpaper fade), "#rrggbb" -> itself
    function resolve(v, fallback) {
        const s = String(v || "");
        if (s.startsWith("wal:")) {
            const c = WalColors[s.slice(4)];
            if (c)
                return String(c);

        }
        if (/^#[0-9a-fA-F]{6}$/.test(s))
            return s;

        return String(WalColors[fallback] || "#888888");
    }

    readonly property string activeBorder: resolve(Settings.get("windows.activeBorder"), "color5")
    readonly property string inactiveBorder: resolve(Settings.get("windows.inactiveBorder"), "color0")

    function send() {
        if (proc.running) {
            pending = true;
            return ;
        }
        pending = false;
        let lua = 'hl.config(dofile("' + modules + '/style.lua").config())';
        if (Math.abs(animSpeed - sentSpeed) > 0.001) {
            lua += '; dofile("' + modules + '/animations.lua")';
            sentSpeed = animSpeed;
        }
        proc.command = ["hyprctl", "eval", lua];
        proc.running = true;
    }

    onLookChanged: {
        if (started)
            sendTimer.restart();

    }
    Component.onCompleted: Qt.callLater(() => {
        root.sentSpeed = root.animSpeed;
        root.started = true;
    })

    // Steppers change in quick steps: send once they rest a moment (still feels instant)
    Timer {
        id: sendTimer

        interval: 90
        onTriggered: root.send()
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && text.trim() !== "ok")
                    console.warn("WindowStyle: hyprctl eval said: " + text.trim());

            }
        }

        onExited: {
            if (root.pending)
                root.send();

        }
    }

}
