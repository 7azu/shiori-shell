// Window borders and shadows (hypr/modules/looks.lua) fade to the new wal colors in sync with the shell
// on a wallpaper change. looks.lua only reads the colors when the config loads; the wallpaper script
// does a `hyprctl reload` after wal - so they only came after the wallpaper wave, in one step.
// Here every fade step of WalColors goes to Hyprland as hl.config via `hyprctl eval`; the later
// reload sets the same final colors, so it changes nothing anymore.
// Same mapping as looks.lua (update along with changes there):
//   active border = color5, inactive border = color0, shadow = color0 with alpha cc / 88 (inactive)

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    // only send after the first real color change (at start Hyprland already has the colors from looks.lua)
    property bool armed: false
    property string lastSent: ""
    // a call is still running: only pass on the newest step, do not pile anything up
    property bool pending: false

    // Only so the service is created at shell start (see shell.qml)
    function warmUp() {
    }

    function luaFor(c5, c0) {
        const rgb = c0.replace("#", "");
        return "hl.config({ general = { col = { active_border = \"" + c5 + "\", inactive_border = \"" + c0 + "\" } }, " + "decoration = { shadow = { color = \"rgba(" + rgb + "cc)\", color_inactive = \"rgba(" + rgb + "88)\" } } })";
    }

    function send() {
        if (!armed)
            return ;

        const lua = luaFor(WalColors.color5, WalColors.color0);
        if (lua === lastSent)
            return ;

        if (proc.running) {
            pending = true;
            return ;
        }
        lastSent = lua;
        pending = false;
        proc.command = ["hyprctl", "eval", lua];
        proc.running = true;
    }

    Process {
        id: proc

        onExited: {
            if (root.pending)
                root.send();

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
        }

        target: WalColors
    }

}
