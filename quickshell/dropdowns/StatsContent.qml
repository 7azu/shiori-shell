import "../services"
import QtQuick

// Dropdown: system load (data: StatsProvider). Tabs for CPU/GPU/RAM/Disk, below them a ring.
// Disk: the ring shows one drive (the system drive first). With several drives there are arrows next to
// the ring, like for the players in the audio dropdown. A row below the ring says which drive it is: its
// type as a small label, every other drive as a dot that morphs into the label when its turn comes.
// The ring itself only adds the temperature.
Item {
    id: dropdown

    readonly property real cornerRadius: 20
    readonly property real menuWidth: 290
    readonly property real innerW: menuWidth - 2 * Theme.padX
    property string activeMetric: "cpu"
    // GPU tab, but no GPU detected -> empty, gray ring with "No GPU"
    readonly property bool noGpu: activeMetric === "gpu" && !StatsProvider.hasGpu
    // Drive in the ring: index into StatsProvider.disks. Falls back to the first one (the system drive)
    // when the chosen drive is gone.
    property int diskIndex: 0
    readonly property var disks: StatsProvider.disks
    readonly property int diskAt: diskIndex >= 0 && diskIndex < disks.length ? diskIndex : 0
    readonly property var disk: disks.length > 0 ? disks[diskAt] : null
    readonly property bool manyDisks: activeMetric === "disk" && disks.length > 1
    // For DropdownHost: while true the shell follows the height without its own animation. Without it the
    // whole content jumped down and slid back when the row of drives came or went.
    readonly property bool resizing: pagerAnim.running
    // The row below the ring also stands for a single drive: it is the only place that names the type
    readonly property bool diskRow: activeMetric === "disk" && disks.length > 0
    // Disk tab on a drive that is not mounted -> empty, gray ring: only its size is known
    readonly property bool diskOff: activeMetric === "disk" && disk !== null && disk.mounted !== true
    // Switching drives: the ring glides out to one side and comes back in from the other
    property int slideDir: 1
    property int slideTo: 0
    property real slideX: 0
    property real slideFade: 1
    readonly property real slideLen: MachineConfig.simpleAnimations ? 0 : 22
    // Drive the row below the ring points at: the target right away, not only when the ring has changed
    readonly property int pageAt: diskSwitch.running ? slideTo : diskAt
    readonly property bool hasTemp: activeMetric === "cpu" || activeMetric === "gpu" || (activeMetric === "disk" && tempCelsius("disk") > 0)
    // The ring takes the heat color for CPU and GPU only; a drive's ring stands for how full it is
    readonly property bool heatRing: hasTemp && activeMetric !== "disk"
    readonly property color ringTone: noGpu || diskOff ? Theme.textFaint : (heatRing ? Theme.heatTone(tempCelsius(activeMetric)) : Theme.accent)

    // Arrow: one drive further, around the end. Dot: straight to that drive.
    function stepDisk(dir) {
        if (disks.length > 1)
            showDisk((diskAt + dir + disks.length) % disks.length, dir);

    }

    function showDisk(index, dir) {
        if (index === diskAt || index < 0 || index >= disks.length)
            return ;

        slideDir = dir !== undefined ? dir : (index > diskAt ? 1 : -1);
        slideTo = index;
        diskSwitch.restart();
    }

    // 0 = cool, 1 = warm, 2 = hot. Hard disks and SATA SSDs run cooler than chips: their limits are lower.
    function heatOf(metric) {
        const t = tempCelsius(metric);
        const cooler = metric === "disk" && disk !== null && disk.kind !== "NVMe";
        if (t >= (cooler ? 55 : 80))
            return 2;

        return t >= (cooler ? 45 : 65) ? 1 : 0;
    }

    // Bytes as "931.5GB" or "1.82TB", the same look as the RAM line
    function fmtBytes(bytes) {
        const gb = (bytes || 0) / 1073741824;
        return fmtSize(gb, gb >= 1000 ? "TB" : "GB");
    }

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
        case "disk":
            return disk && disk.mounted ? Math.max(0, Math.min(100, disk.percent)) : 0;
        }
        return 0;
    }

    function tempCelsius(metric) {
        switch (metric) {
        case "cpu":
            return numFrom(StatsProvider.cpuTemp);
        case "gpu":
            return numFrom(StatsProvider.gpuTemp);
        case "disk":
            return disk && disk.temp !== null && disk.temp !== undefined ? disk.temp : 0;
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
        case "disk":
            if (!disk)
                return "";

            return disk.mounted ? fmtBytes(disk.used) + " / " + fmtBytes(disk.total) : fmtBytes(disk.size);
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
        case "disk":
            // Only how warm the drive is, if the kernel knows; what it is stands in the row below the ring
            return tempCelsius("disk") > 0 ? Math.round(tempCelsius("disk")) + "°C" : "";
        }
        return "";
    }

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight

    // Pulse on every metric switch: a short breath of the ring
    onActiveMetricChanged: ringPulse.restart()

    SequentialAnimation {
        id: diskSwitch

        ParallelAnimation {
            NumberAnimation {
                target: dropdown
                property: "slideX"
                to: -dropdown.slideDir * dropdown.slideLen
                duration: 130
                easing.type: Easing.InCubic
            }

            NumberAnimation {
                target: dropdown
                property: "slideFade"
                to: 0
                duration: 130
            }

        }

        ScriptAction {
            script: {
                dropdown.diskIndex = dropdown.slideTo;
                dropdown.slideX = dropdown.slideDir * dropdown.slideLen;
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: dropdown
                property: "slideX"
                to: 0
                duration: 280
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: dropdown
                property: "slideFade"
                to: 1
                duration: 220
            }

        }

    }

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
                readonly property string metric: dropdown.hasTemp ? dropdown.activeMetric : "cpu"
                readonly property int level: dropdown.heatOf(metric)

                visible: dropdown.tempCelsius(metric) > 0
                tone: level === 0 ? Theme.good : (level === 1 ? Theme.warn : Theme.bad)
                dot: true
                text: level === 2 ? "Hot" : (level === 1 ? "Warm" : "Cool")
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
                "key": "disk",
                "label": "Disk"
            }]
            onSelected: (key) => {
                return dropdown.activeMetric = key;
            }
        }

        // More air between the tab line and the ring: the tip of the arc sticks out over the ring on top
        Item {
            width: parent.width
            height: ring.height + Theme.gapSmall + pagerBox.height

            Ring {
                id: ring

                anchors.bottom: parent.bottom
                anchors.bottomMargin: pagerBox.height
                anchors.horizontalCenter: parent.horizontalCenter
                transformOrigin: Item.Center
                progress: dropdown.usagePercent(dropdown.activeMetric) / 100
                tone: dropdown.ringTone
                showTip: !dropdown.noGpu && !dropdown.diskOff
                caption: dropdown.metricName(dropdown.activeMetric)
                value: dropdown.noGpu ? "No GPU" : (dropdown.diskOff ? "Not mounted" : Math.round(shown * 100) + "%")
                valueSize: dropdown.noGpu || dropdown.diskOff ? Theme.sizeTitle : Theme.sizeDisplay
                opacity: dropdown.slideFade

                transform: Translate {
                    x: dropdown.slideX
                }

                detail: dropdown.secondaryString(dropdown.activeMetric)
                detailColor: dropdown.heatRing && !dropdown.noGpu && dropdown.tempCelsius(dropdown.activeMetric) >= 65 ? dropdown.ringTone : Theme.textDim
            }

            // Arrows next to the ring to switch the drive, the same look as for the players in AudioContent
            Repeater {
                model: [-1, 1]

                Item {
                    id: arrow

                    required property int modelData
                    readonly property int dir: modelData

                    width: 26
                    height: 48
                    opacity: dropdown.manyDisks ? 1 : 0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }

                    }

                    x: dir < 0 ? -6 : parent.width - width + 6
                    y: ring.y + (ring.height - height) / 2

                    Rectangle {
                        anchors.fill: parent
                        radius: 13
                        color: Theme.accent
                        opacity: arrowMouse.containsMouse ? 0.14 : 0
                        scale: arrowMouse.containsMouse ? 1 : 0.75

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 160
                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutBack
                            }

                        }

                    }

                    Text {
                        anchors.centerIn: parent
                        // On hover move a bit in the arrow direction
                        anchors.horizontalCenterOffset: arrowMouse.containsMouse ? arrow.dir * 2 : 0
                        text: arrow.dir > 0 ? "󰅂" : "󰅁"
                        color: arrowMouse.containsMouse ? Theme.accent : Theme.textDim
                        font.family: Theme.font
                        font.pixelSize: 20
                        scale: arrowMouse.pressed ? 0.8 : 1

                        Behavior on anchors.horizontalCenterOffset {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }

                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutBack
                            }

                        }

                    }

                    MouseArea {
                        id: arrowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dropdown.stepDisk(arrow.dir)
                    }

                }

            }

            // Which drive of how many: the one in the ring by its type ("NVME", "HDD" ...), the others as dots
            // in their order (pale = not mounted). A click on a dot shows that drive.
            // The box glides open and shut (the Disk tab has it, the others do not): a height that jumps would make
            // DropdownHost slide the whole content, see `resizing` on top.
            Item {
                id: pagerBox

                readonly property real fullH: pager.rowH + Theme.gap

                anchors.bottom: parent.bottom
                width: parent.width
                height: dropdown.diskRow ? fullH : 0
                visible: height > 0
                opacity: height / fullH
                clip: true

                Behavior on height {
                    NumberAnimation {
                        id: pagerAnim

                        duration: 320
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.outQuint
                    }

                }

                Row {
                    id: pager

                    readonly property real dot: 6
                    readonly property real rowH: Theme.sizeMicro + 12
                    // Centered by hand: anchors.centerIn rounds to whole pixels, then the row jumps pixel by pixel
                    // (and at times backwards) while the widths inside glide. Only at rest it settles on the pixel
                    // grid, so the label stays sharp (snapK).
                    readonly property real exactX: (parent.width - width) / 2
                    property real snapK: 1

                    x: exactX + (Math.round(exactX) - exactX) * snapK
                    anchors.bottom: parent.bottom
                    spacing: 10

                    Connections {
                        function onPageAtChanged() {
                            settle.restart();
                        }

                        target: dropdown
                    }

                    SequentialAnimation {
                        id: settle

                        PropertyAction {
                            target: pager
                            property: "snapK"
                            value: 0
                        }

                        // As long as the morph below (Behavior on k)
                        PauseAnimation {
                            duration: 480
                        }

                        NumberAnimation {
                            target: pager
                            property: "snapK"
                            to: 1
                            duration: 320
                            easing.type: Easing.InOutQuad
                        }

                    }

                    Repeater {
                        // Stays while the box glides shut
                        model: pagerBox.visible ? dropdown.disks.length : 0

                        Item {
                            id: page

                            required property int index
                            // Read by index: a Repeater over the list itself turns the entries into Qt lists
                            readonly property var d: dropdown.disks[index] ?? ({
                            })
                            readonly property bool current: index === dropdown.pageAt
                            // 0 = dot, 1 = label. The whole morph hangs on this one value, so it runs back the
                            // same way: the dot stretches to a capsule as wide as the label and dissolves into it.
                            property real k: current ? 1 : 0
                            // First the capsule goes, then the label comes: both at once looked smeared
                            readonly property real bodyK: 1 - Math.max(0, Math.min(1, (k - 0.3) / 0.3))
                            readonly property real textK: Math.max(0, Math.min(1, (k - 0.55) / 0.45))

                            width: pager.dot + (pageName.implicitWidth - pager.dot) * k
                            height: pager.rowH

                            Behavior on k {
                                NumberAnimation {
                                    duration: 460
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.anim.curves.inOutSoft
                                }

                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: pager.dot
                                radius: height / 2
                                color: dotMouse.containsMouse ? Theme.accent : WalColors.color7
                                opacity: page.bodyK * (dotMouse.containsMouse ? 0.9 : (page.d.mounted === true ? 0.5 : 0.2))
                                scale: dotMouse.containsMouse ? 1.3 : 1

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 160
                                        easing.type: Easing.OutBack
                                    }

                                }

                            }

                            // Same look as the other small labels of the dropdowns (header, chips)
                            Text {
                                id: pageName

                                // Not anchors.centerIn: it would round the label to whole pixels while it moves
                                x: (parent.width - width) / 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: (page.d.kind ?? "").toUpperCase()
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeMicro
                                font.bold: true
                                font.letterSpacing: Theme.microSpacing
                                opacity: page.textK
                                visible: opacity > 0.01
                            }

                            MouseArea {
                                id: dotMouse

                                anchors.fill: parent
                                anchors.margins: -5
                                enabled: !page.current
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dropdown.showDisk(page.index)
                            }

                        }

                    }

                }

            }

        }

    }

}
