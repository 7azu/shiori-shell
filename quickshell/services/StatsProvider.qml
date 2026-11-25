import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// System values for the stats dropdown.
// RAM and CPU are read directly from /proc (FileView) instead of through sh/grep/awk chains: before,
// about ten processes started every 2 s, even with the dropdown closed. Now it only measures
// every 2 s with the dropdown open; in between a rare intermediate value is enough, so the
// CPU display has a usable average right away when opening.
Singleton {
    id: root

    // Only the stats dropdown shows the values
    readonly property bool watched: DropdownState.current === "stats"
    property real ramPercent: 0
    property string ramText: "--"
    property real cpuPercent: 0
    property string cpuTemp: "--"
    property string gpuUsage: "--"
    property string gpuTemp: "--"
    // GPU detection (scripts/system_stats.py): "dedicated" preferred, otherwise "integrated", otherwise "none"
    property string gpuKind: "dedicated"
    property string gpuVendor: ""
    property string gpuName: ""
    readonly property bool hasGpu: gpuKind !== "none"
    property real diskPercent: 0
    property string diskText: "--"
    // Counters of the last CPU measurement (usage = difference between two measurements)
    property real prevIdle: 0
    property real prevTotal: 0
    property bool firstCpuReading: true
    readonly property string sysScript: Qt.resolvedUrl("../scripts/system_stats.py").toString().replace("file://", "")

    function sample() {
        meminfo.reload();
        cpustat.reload();
    }

    function parseMem(text) {
        const total = parseInt((text.match(/^MemTotal:\s+(\d+)/m) || [])[1], 10);
        const available = parseInt((text.match(/^MemAvailable:\s+(\d+)/m) || [])[1], 10);
        if (!(total > 0) || isNaN(available))
            return ;

        const used = total - available;
        ramPercent = Math.round((used / total) * 100);
        ramText = Math.round(used / 1024) + "M / " + Math.round(total / 1024) + "M (" + ramPercent + "%)";
    }

    function parseCpu(text) {
        const m = text.match(/^cpu\s+(.*)$/m);
        if (!m)
            return ;

        const v = m[1].trim().split(/\s+/).map(Number);
        if (v.length < 7)
            return ;

        // user nice system idle iowait irq softirq steal
        const total = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + (v[7] || 0);
        const totalIdle = v[3] + v[4];
        if (!firstCpuReading) {
            const diffTotal = total - prevTotal;
            if (diffTotal > 0)
                cpuPercent = Math.max(0, Math.min(100, Math.round((1 - (totalIdle - prevIdle) / diffTotal) * 100)));

        }
        firstCpuReading = false;
        prevIdle = totalIdle;
        prevTotal = total;
    }

    onWatchedChanged: {
        if (watched) {
            sample();
            // One more measurement right away: the CPU display needs two, otherwise it shows 0 % for 2 s
            // after the first opening
            quickSample.restart();
            dfProcess.running = true;
        }
    }

    Timer {
        id: quickSample

        interval: 400
        onTriggered: root.sample()
    }

    FileView {
        id: meminfo

        path: "/proc/meminfo"
        printErrors: false
        onLoaded: root.parseMem(text())
    }

    FileView {
        id: cpustat

        path: "/proc/stat"
        printErrors: false
        onLoaded: root.parseCpu(text())
    }

    Timer {
        interval: root.watched ? 2000 : 15000
        // Hidden bar icon (edit mode) = feature off: only sample while the dropdown is open
        running: root.watched || BarIcons.shown("stats")
        repeat: true
        onTriggered: root.sample()
    }

    // Disk usage changes slowly: when opening and then once per minute
    Timer {
        interval: 60000
        running: root.watched
        repeat: true
        onTriggered: dfProcess.running = true
    }

    Process {
        id: dfProcess

        command: ["df", "-h", "--output=size,used,pcent", "/"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length < 2)
                    return ;

                const parts = lines[1].trim().split(/\s+/);
                if (parts.length < 3)
                    return ;

                const percent = parts[2].replace("%", "");
                root.diskText = parts[1] + " / " + parts[0] + " (" + percent + "%)";
                root.diskPercent = parseFloat(percent) || 0;
            }
        }

    }

    // CPU temperature + GPU (vendor independent, scripts/system_stats.py): only runs while the
    // dropdown is open. The last values stay, when opening a new line comes right away.
    Process {
        command: ["python3", root.sysScript]
        running: root.watched

        stdout: SplitParser {
            onRead: (data) => {
                let d;
                try {
                    d = JSON.parse(data);
                } catch (e) {
                    return ;
                }
                root.cpuTemp = (d.cpuTemp !== null && d.cpuTemp !== undefined) ? d.cpuTemp + "°C" : "--";
                const g = d.gpu || {
                    "kind": "none"
                };
                root.gpuKind = g.kind || "none";
                root.gpuVendor = g.vendor || "";
                root.gpuName = g.name || "";
                root.gpuUsage = (g.usage !== null && g.usage !== undefined) ? g.usage + "%" : "--";
                root.gpuTemp = (g.temp !== null && g.temp !== undefined) ? g.temp + "°C" : "--";
            }
        }

    }

}
