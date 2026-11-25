import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "windows/overview"

// Test setup for tools/overview-shot: renders the REAL workspace overview (OverviewView) with real
// Hyprland data and window captures and saves images without disturbing the running shell or the screen.
// The window is 1x1 pixel on the overlay layer (invisible, click-through, no keyboard),
// the content is stretched to monitor size and captured with grabToImage (technique as in tools/ui-shot.qml).
// Controlled by environment variables (set by tools/overview-shot):
//   OV_OUT, OV_MODE open|close|still, OV_FRAMES n, OV_MONITOR name, OV_BACKDROP png, OV_SELECT ws, OV_SLOWMO x
ShellRoot {
    id: root

    readonly property string out: Quickshell.env("OV_OUT") || "/tmp/overview-shot.png"
    readonly property string mode: Quickshell.env("OV_MODE") || "still"
    readonly property int frames: Number(Quickshell.env("OV_FRAMES") || 12)
    readonly property string monitorName: Quickshell.env("OV_MONITOR") || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    readonly property string backdrop: Quickshell.env("OV_BACKDROP") || ""
    readonly property int selectWs: Number(Quickshell.env("OV_SELECT") || 0)
    readonly property var mon: Hyprland.monitors.values.find((m) => {
        return m.name === root.monitorName;
    }) ?? null
    readonly property var scr: Quickshell.screens.find((s) => {
        return s.name === root.monitorName;
    }) ?? null
    readonly property real slowMo: Number(Quickshell.env("OV_SLOWMO") || 1)
    property int frame: 0
    property double t0: 0

    function base() {
        return out.replace(/\.png$/, "");
    }

    // Images one after another (grabToImage is asynchronous); time + state per image into the log
    function grabNext() {
        if (frame >= frames) {
            Qt.quit();
            return ;
        }
        const f = frame;
        const ms = Date.now() - t0;
        const reveal = view.reveal.toFixed(3), dim = view.dim.toFixed(2);
        content.grabToImage((r) => {
            const path = frames === 1 ? root.out : root.base() + "_f" + String(f).padStart(2, "0") + ".png";
            console.log("OV-SHOT", r.saveToFile(path), path, "t=" + ms, "reveal=" + reveal, "dim=" + dim, "phase=" + view.phase);
            root.frame++;
            root.grabNext();
        });
    }

    PanelWindow {
        implicitWidth: 1
        implicitHeight: 1
        screen: root.scr
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-overview-shot"

        anchors {
            top: true
            left: true
        }

        mask: Region {
        }

        Item {
            id: content

            width: root.scr ? root.scr.width : 2560
            height: root.scr ? root.scr.height : 1440

            // Background: screenshot (there is no Hyprland blur here) or a dark desktop
            Rectangle {
                anchors.fill: parent
                color: "#181a22"
            }

            Image {
                anchors.fill: parent
                source: root.backdrop !== "" ? "file://" + root.backdrop : ""
                visible: root.backdrop !== ""
            }

            OverviewView {
                id: view

                width: parent.width
                height: parent.height
                monitor: root.mon
                capturing: true
                slowMo: root.slowMo
            }

        }

    }

    // First wait until the IPC data and the first captures are there
    Timer {
        running: true
        interval: 1500
        onTriggered: {
            view.refresh();
            prep.start();
        }
    }

    Timer {
        id: prep

        interval: 600
        onTriggered: {
            view.show(root.mon);
            if (root.mode === "open") {
                root.t0 = Date.now();
                root.grabNext();
            } else {
                settle.start();
            }
        }
    }

    Timer {
        id: settle

        interval: 1500 * root.slowMo
        onTriggered: {
            if (root.selectWs > 0)
                view.selectedId = root.selectWs;

            if (root.mode === "close") {
                view.dismiss();
                root.t0 = Date.now();
                root.grabNext();
            } else {
                grabDelay.start();
            }
        }
    }

    Timer {
        id: grabDelay

        interval: 400
        onTriggered: {
            root.t0 = Date.now();
            root.grabNext();
        }
    }

}
