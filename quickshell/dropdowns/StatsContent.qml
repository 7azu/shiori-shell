import "../services"
import QtQuick

// Dropdown: system load (data: StatsProvider). Tabs for CPU/GPU/RAM/SSD, below them a ring.
Item {
    id: dropdown

    readonly property real cornerRadius: 20
    readonly property real menuWidth: 290
    readonly property real innerW: menuWidth - 2 * Theme.padX
    property string activeMetric: "cpu"
    // GPU tab, but no GPU detected -> empty, gray ring with "No GPU"
    readonly property bool noGpu: activeMetric === "gpu" && !StatsProvider.hasGpu
    readonly property bool hasTemp: activeMetric === "cpu" || activeMetric === "gpu"
    readonly property color ringTone: noGpu ? Theme.textFaint : (hasTemp ? Theme.heatTone(tempCelsius(activeMetric)) : Theme.accent)

    function numFrom(s) {
        if (s === undefined || s === null)
            return 0;

        const m = String(s).match(/(-?\d+(?:\.\d+)?)/);
        return m ? parseFloat(m[1]) : 0;
    }

    function fmtSize(gb, unit) {
        let num;
        let suffix;
        if (unit === "TB") {
            num = (gb / 1024).toFixed(2);
            suffix = "TB";
        } else {
            num = gb.toFixed(1);
            suffix = "GB";
        }
        num = num.replace(/\.?0+$/, "");
        return num + suffix;
    }

    function parseMemory(s, unit) {
        unit = unit || "GB";
        const empty = {
            "text": "",
            "used": 0,
            "total": 0,
            "ratio": 0
        };
        if (s === undefined || s === null)
            return empty;

        let str = String(s).trim();
        str = str.replace(/[\(\[]?\s*\d+(?:\.\d+)?\s*%\s*[\)\]]?/g, " ").trim();
        const values = [];
        const re = /(\d+(?:\.\d+)?)\s*(GB|MB|GIB|MIB|TB|TIB|G|M|T)?/gi;
        let m;
        while ((m = re.exec(str)) !== null) {
            const val = parseFloat(m[1]);
            const u = (m[2] || "GB").toUpperCase();
            let gb = val;
            if (u.indexOf("M") === 0)
                gb = val / 1024;
            else if (u.indexOf("T") === 0)
                gb = val * 1024;
            values.push(gb);
        }
        if (values.length >= 2) {
            const used = values[0];
            const total = values[1];
            return {
                "text": fmtSize(used, unit) + " / " + fmtSize(total, unit),
                "used": used,
                "total": total,
                "ratio": total > 0 ? Math.max(0, Math.min(1, used / total)) : 0
            };
        } else if (values.length === 1) {
            return {
                "text": fmtSize(values[0], unit),
                "used": values[0],
                "total": 0,
                "ratio": 0
            };
        }
        return {
            "text": str,
            "used": 0,
            "total": 0,
            "ratio": 0
        };
    }

    function usagePercent(metric) {
        switch (metric) {
        case "cpu":
            return Math.max(0, Math.min(100, StatsProvider.cpuPercent));
        case "gpu":
            if (!StatsProvider.hasGpu)
                return 0;

            return Math.max(0, Math.min(100, numFrom(StatsProvider.gpuUsage)));
        case "ram":
            return Math.round(parseMemory(StatsProvider.ramText, "GB").ratio * 100);
        case "ssd":
            return Math.round(parseMemory(StatsProvider.diskText, "TB").ratio * 100);
        }
        return 0;
    }

    function tempCelsius(metric) {
        switch (metric) {
        case "cpu":
            return numFrom(StatsProvider.cpuTemp);
        case "gpu":
            return numFrom(StatsProvider.gpuTemp);
        }
        return 0;
    }

    function secondaryString(metric) {
        switch (metric) {
        case "cpu":
            return StatsProvider.cpuTemp;
        case "gpu":
            if (!StatsProvider.hasGpu)
                return "not detected";

            // No temperature value from the driver (e.g. NVIDIA without nvidia-smi): vendors show
            return StatsProvider.gpuTemp !== "--" ? StatsProvider.gpuTemp : StatsProvider.gpuVendor;
        case "ram":
            return parseMemory(StatsProvider.ramText, "GB").text;
        case "ssd":
            return parseMemory(StatsProvider.diskText, "TB").text;
        }
        return "";
    }

    function metricName(metric) {
        switch (metric) {
        case "cpu":
            return "CPU";
        case "gpu":
            return StatsProvider.gpuKind === "integrated" ? "iGPU" : "GPU";
        case "ram":
            return "RAM";
        case "ssd":
            return "SSD";
        }
        return "";
    }

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight

    // Pulse on every metric switch: a short breath of the ring
    onActiveMetricChanged: ringPulse.restart()

    SequentialAnimation {
        id: ringPulse

        NumberAnimation {
            target: ring
            property: "scale"
            to: 1.04
            duration: 160
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: ring
            property: "scale"
            to: 1
            duration: 320
            easing.type: Easing.OutCubic
        }

    }

    Column {
        id: content

        width: dropdown.innerW
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gap
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        DropdownHeader {
            glyph: "󰍛"
            title: "System"

            // Temperature as status as soon as it gets warm
            Chip {
                readonly property real t: dropdown.tempCelsius(dropdown.hasTemp ? dropdown.activeMetric : "cpu")

                visible: t > 0
                tone: t < 65 ? Theme.good : Theme.heatTone(t)
                dot: true
                text: t >= 80 ? "Hot" : (t >= 65 ? "Warm" : "Cool")
            }

        }

        Tabs {
            width: parent.width
            current: dropdown.activeMetric
            model: [{
                "key": "cpu",
                "label": "CPU"
            }, {
                "key": "gpu",
                "label": StatsProvider.gpuKind === "integrated" ? "iGPU" : "GPU",
                "dim": !StatsProvider.hasGpu
            }, {
                "key": "ram",
                "label": "RAM"
            }, {
                "key": "ssd",
                "label": "SSD"
            }]
            onSelected: (key) => {
                return dropdown.activeMetric = key;
            }
        }

        // More air between the tab line and the ring: the tip of the arc sticks out over the ring on top
        Item {
            width: parent.width
            height: ring.height + Theme.gapSmall

            Ring {
                id: ring

                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                transformOrigin: Item.Center
                progress: dropdown.usagePercent(dropdown.activeMetric) / 100
                tone: dropdown.ringTone
                showTip: !dropdown.noGpu
                caption: dropdown.metricName(dropdown.activeMetric)
                value: dropdown.noGpu ? "No GPU" : Math.round(shown * 100) + "%"
                valueSize: dropdown.noGpu ? Theme.sizeTitle : Theme.sizeDisplay
                detail: dropdown.secondaryString(dropdown.activeMetric)
                detailColor: dropdown.hasTemp && !dropdown.noGpu && dropdown.tempCelsius(dropdown.activeMetric) >= 65 ? dropdown.ringTone : Theme.textDim
            }

        }

    }

}
