pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    property var windowList: []
    property var windowByAddress: ({})

    function biggestWindowForWorkspace(workspaceId) {
        const windows = root.windowList.filter(w => w.workspace.id == workspaceId)
        return windows.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0)
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0)
            return winArea > maxArea ? win : maxWin
        }, null)
    }

    function updateWindowList() {
        getClients.running = true
    }

    Component.onCompleted: updateWindowList()

    // Only events that change windows, their size or their workspace, and several in a row
    // bundled: before, EVERY Hyprland event (also focus and title changes) started a
    // `hyprctl clients -j` plus a rebuild of the list.
    readonly property var relevantEvents: /^(openwindow|closewindow|movewindow|changefloatingmode|fullscreen|togglegroup|moveintogroup|moveoutofgroup|createworkspace|destroyworkspace|moveworkspace|monitoradded|monitorremoved|configreloaded)/

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.relevantEvents.test(event.name))
                debounce.restart()
        }
    }

    Timer {
        id: debounce
        interval: 40
        onTriggered: root.updateWindowList()
    }

    // Hyprland does not report size changes (dragging, layout) as an event: check again rarely,
    // so "biggest window of the workspace" does not stay outdated
    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.updateWindowList()
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.windowList = JSON.parse(text)
                let tmp = {}
                for (var i = 0; i < root.windowList.length; i++) {
                    tmp[root.windowList[i].address] = root.windowList[i]
                }
                root.windowByAddress = tmp
            }
        }
    }
}
