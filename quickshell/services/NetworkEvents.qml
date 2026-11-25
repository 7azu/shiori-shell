import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// One single `nmcli monitor` instance for everyone who reacts to network changes (Wi-Fi, VPN).
// Before, each one polled on its own every second (VPN icon every 3 s, VPN list every 5 s);
// but NetworkManager reports changes itself, so reading once afterwards is enough.
Singleton {
    id: root

    // Fires shortly after every change in NetworkManager (several lines in a row = one signal)
    signal changed()

    Process {
        id: monitor

        command: ["nmcli", "monitor"]
        running: true
        onExited: restart.restart()

        stdout: SplitParser {
            onRead: () => {
                return debounce.restart();
            }
        }

    }

    // NetworkManager restarted or similar: listen again after a short pause
    Timer {
        id: restart

        interval: 5000
        onTriggered: monitor.running = true
    }

    Timer {
        id: debounce

        interval: 350
        onTriggered: root.changed()
    }

}
