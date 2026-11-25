import "../services"
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// VPN dropdown: location, combined throughput, connection details and actions.
Item {
    id: dropdown

    // The IP is masked, a click shows it
    property bool ipRevealed: false
    readonly property real cornerRadius: 20
    readonly property real menuWidth: Theme.px(400)
    readonly property real innerW: menuWidth - 2 * Theme.padX
    readonly property bool up: VpnState.connected
    readonly property string iface: VpnPickerState.activeConnection
    readonly property string countryCode: {
        const cc = (VpnState.vpnCountryCode || "").trim().toLowerCase();
        if (cc.length === 2)
            return cc;

        // Fallback via the name (old data / API without countryCode)
        const names = VpnPickerState.countryNames;
        const name = (VpnState.vpnCountry || "").toLowerCase();
        for (const code in names) {
            if (names[code].toLowerCase() === name)
                return code === "uk" ? "gb" : code;

        }
        return "";
    }
    readonly property string flagSource: countryCode !== "" ? "../resources/flags/" + countryCode + ".svg" : ""
    readonly property color statusColor: up ? Theme.good : Theme.bad
    // ---- Live data ----
    property real nowMs: Date.now()
    property real sinceSec: 0
    property real lastRx: -1
    property real lastTx: -1
    property real rxRate: 0
    property real txRate: 0
    property real sessionRx: 0
    property real sessionTx: 0
    readonly property int histLen: 40
    // Prefilled with zeros: the graph starts flat and the measurements run in from the right
    property var rxHist: zeros()
    property var txHist: zeros()
    // Softly shown rates (do not jump every second)
    property real shownRx: rxRate
    property real shownTx: txRate

    function maskIp(ip) {
        return ip ? String(ip).replace(/\d/g, "•") : "";
    }

    function fmtRate(b) {
        if (b >= 1048576)
            return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1) + " MB/s";

        if (b >= 1024)
            return Math.round(b / 1024) + " KB/s";

        return Math.round(b) + " B/s";
    }

    function fmtBytes(b) {
        if (b >= 1073741824)
            return (b / 1073741824).toFixed(1) + " GB";

        if (b >= 1048576)
            return Math.round(b / 1048576) + " MB";

        return Math.round(b / 1024) + " KB";
    }

    function fmtDuration(s) {
        const m = Math.floor(s / 60);
        const h = Math.floor(m / 60);
        if (h >= 24)
            return Math.floor(h / 24) + "d " + (h % 24) + "h";

        return h > 0 ? h + "h " + (m % 60) + "m" : m + "m";
    }

    // Local time at the VPN location (UTC + offset from ip-api)
    function vpnClock() {
        if (!VpnState.vpnTimezone)
            return "";

        const d = new Date(nowMs + VpnState.vpnUtcOffset * 1000);
        const hh = d.getUTCHours();
        const mm = d.getUTCMinutes();
        return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm;
    }

    function zeros() {
        const a = [];
        for (let i = 0; i < 40; i++) a.push(0)
        return a;
    }

    function pushHist(arr, v) {
        const a = arr.concat([v]);
        return a.length > histLen ? a.slice(a.length - histLen) : a;
    }

    function setConnection(up) {
        connProcess.command = up ? ["nmcli", "connection", "up", VpnPickerState.lastConnection] : ["nmcli", "connection", "down", iface !== "" ? iface : "proton"];
        connProcess.running = true;
    }

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: col.implicitHeight

    // ---------- Killswitch ----------
    Process {
        id: ksStatusProcess

        command: ["bash", "-c", "sudo -n nft list tables 2>/dev/null | grep -q 'table inet killswitch' && echo 'true' || echo 'false'"]
        Component.onCompleted: running = true

        stdout: StdioCollector {
            onStreamFinished: VpnState.killswitchEnabled = (text.trim() === "true")
        }

    }

    Process {
        id: ksToggleProcess

        command: VpnState.killswitchEnabled ? ["sudo", "-n", "nft", "delete", "table", "inet", "killswitch"] : ["sudo", "-n", "nft", "-f", "/etc/vpn-killswitch.nft"]
        onRunningChanged: {
            if (!running)
                ksStatusProcess.running = true;

        }
    }

    // ---------- Connect / disconnect ----------
    Process {
        id: connProcess

        onRunningChanged: {
            if (!running) {
                VpnPickerState.refresh();
                // VpnToggle then checks status + location again
                VpnPickerState.switched();
            }
        }
    }

    // ---------- Throughput + connection duration (from /sys, every second, only while open) ----------
    Process {
        id: statProcess

        command: ["sh", "-c", "d=/sys/class/net/$1; cat $d/statistics/rx_bytes $d/statistics/tx_bytes; stat -c %Y $d", "vpn-stat", dropdown.iface]

        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split("\n").map(Number);
                if (v.length < 3 || v.some(isNaN))
                    return ;

                if (dropdown.lastRx >= 0) {
                    dropdown.rxRate = Math.max(0, v[0] - dropdown.lastRx);
                    dropdown.txRate = Math.max(0, v[1] - dropdown.lastTx);
                    dropdown.rxHist = dropdown.pushHist(dropdown.rxHist, dropdown.rxRate);
                    dropdown.txHist = dropdown.pushHist(dropdown.txHist, dropdown.txRate);
                }
                dropdown.lastRx = v[0];
                dropdown.lastTx = v[1];
                dropdown.sessionRx = v[0];
                dropdown.sessionTx = v[1];
                dropdown.sinceSec = v[2];
            }
        }

    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            dropdown.nowMs = Date.now();
            if (dropdown.up && dropdown.iface !== "")
                statProcess.running = true;

        }
    }

    // New tunnel -> start the history anew
    onIfaceChanged: {
        lastRx = -1;
        lastTx = -1;
        rxHist = zeros();
        txHist = zeros();
        rxRate = 0;
        txRate = 0;
    }

    Column {
        id: col

        width: dropdown.innerW
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gapSmall
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        DropdownHeader {
            glyph: "󰖂"
            title: "VPN"

            Chip {
                tone: dropdown.statusColor
                dot: true
                text: dropdown.up ? "Protected" : (VpnState.killswitchEnabled ? "Offline" : "Exposed")
            }
        }

        Row {
            width: parent.width
            height: Math.max(flag.height, location.implicitHeight)
            spacing: Theme.gap

            ClippingRectangle {
                id: flag

                anchors.verticalCenter: parent.verticalCenter
                width: Theme.px(44)
                height: width
                radius: height / 2
                color: Theme.card
                opacity: dropdown.up ? 1 : 0.65

                Image {
                    id: flagImage

                    anchors.fill: parent
                    source: dropdown.flagSource
                    sourceSize: Qt.size(flag.width * 2, flag.height * 2)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: flagImage.status !== Image.Ready
                    text: "󰖟"
                    color: Theme.textDim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(23)
                }
            }

            Column {
                id: location

                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - flag.width - parent.spacing
                spacing: Theme.px(3)

                Text {
                    width: parent.width
                    text: dropdown.up ? VpnState.vpnCountry || "Connected" : "Not connected"
                    textFormat: Text.PlainText
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeHeading
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: {
                        if (!dropdown.up)
                            return VpnState.vpnCountry ? "Visible as " + VpnState.vpnCountry : "";

                        return [VpnState.vpnCity || VpnState.vpnRegion, dropdown.vpnClock()].filter(Boolean).join(" · ");
                    }
                    textFormat: Text.PlainText
                    color: Theme.textDim
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.features: Theme.tabular
                    font.pixelSize: Theme.sizeLabel
                }
            }
        }

        // Live rates, history and totals belong on one shared surface.
        Card {
            id: graphCard

            readonly property real peak: Math.max(2048, Math.max.apply(null, dropdown.rxHist.concat(dropdown.txHist, [0])))

            function points(hist, w, h) {
                const n = dropdown.histLen;
                const pts = [];
                const start = n - hist.length;
                for (let i = 0; i < hist.length; i++)
                    pts.push(Qt.point((start + i) / (n - 1) * w, h - 2 - hist[i] / peak * (h - 6)));

                return pts;
            }

            width: parent.width
            height: traffic.implicitHeight + 2 * Theme.gapSmall
            visible: dropdown.up

            Column {
                id: traffic

                width: parent.width - 2 * Theme.gapSmall
                anchors.centerIn: parent
                spacing: Theme.px(3)

                Row {
                    width: parent.width
                    spacing: Theme.px(4)

                    Stat {
                        width: (parent.width - 2 * parent.spacing) / 3
                        height: Theme.px(40)
                        color: "transparent"
                        value: dropdown.sinceSec > 0 ? dropdown.fmtDuration(dropdown.nowMs / 1000 - dropdown.sinceSec) : "–"
                        label: "Uptime"
                    }

                    Stat {
                        width: (parent.width - 2 * parent.spacing) / 3
                        height: Theme.px(40)
                        color: "transparent"
                        value: dropdown.fmtRate(dropdown.shownRx)
                        label: "Download"
                    }

                    Stat {
                        width: (parent.width - 2 * parent.spacing) / 3
                        height: Theme.px(40)
                        color: "transparent"
                        value: dropdown.fmtRate(dropdown.shownTx)
                        label: "Upload"
                    }
                }

                Shape {
                    id: graph

                    x: Theme.px(2)
                    width: parent.width - 2 * x
                    height: Theme.px(32)
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: Theme.tint(Theme.accent, 0.8)
                        strokeWidth: 1.5
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin

                        PathPolyline {
                            path: graphCard.points(dropdown.rxHist, graph.width, graph.height)
                        }
                    }

                    ShapePath {
                        strokeColor: Theme.tint(Theme.accent2, 0.5)
                        strokeWidth: 1
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin

                        PathPolyline {
                            path: graphCard.points(dropdown.txHist, graph.width, graph.height)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(sessionLabel.implicitHeight, total.implicitHeight)

                    Text {
                        id: sessionLabel

                        anchors.left: parent.left
                        text: "Session"
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                    Text {
                        id: total

                        anchors.right: parent.right
                        text: "↓ " + dropdown.fmtBytes(dropdown.sessionRx) + "   ↑ " + dropdown.fmtBytes(dropdown.sessionTx)
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.features: Theme.tabular
                        font.pixelSize: Theme.sizeSmall
                    }
                }
            }
        }

        Column {
            width: parent.width

            InfoRow {
                label: "IP"
                value: VpnState.vpnIp === "" ? "–" : (dropdown.ipRevealed ? VpnState.vpnIp : dropdown.maskIp(VpnState.vpnIp))
                clickable: VpnState.vpnIp !== ""
                copyable: dropdown.ipRevealed && VpnState.vpnIp !== ""
                onActivated: dropdown.ipRevealed = !dropdown.ipRevealed
                onCopied: Quickshell.execDetached(["wl-copy", "--", VpnState.vpnIp])
            }

            InfoRow {
                label: "Provider"
                value: VpnState.vpnOrg || "–"
            }

            InfoRow {
                label: "Server"
                value: dropdown.up && dropdown.iface !== "" ? dropdown.iface : "–"
            }
        }

        Row {
            readonly property real serverWidth: Theme.px(76)
            readonly property real actionWidth: (width - 2 * spacing - serverWidth) / 2

            width: parent.width
            spacing: Theme.gapSmall

            CardButton {
                width: parent.actionWidth
                glyph: "󰒃"
                text: "Killswitch"
                active: VpnState.killswitchEnabled
                tone: Theme.good
                onClicked: ksToggleProcess.running = true
            }

            CardButton {
                width: parent.actionWidth
                text: connProcess.running ? "…" : (dropdown.up ? "Disconnect" : "Connect")
                active: !dropdown.up
                tone: Theme.good
                onClicked: {
                    if (!connProcess.running)
                        dropdown.setConnection(!dropdown.up);
                }
            }

            CardButton {
                width: parent.serverWidth
                text: "Servers"
                onClicked: VpnPickerState.openPicker()
            }
        }
    }

    Behavior on shownRx {
        NumberAnimation {
            duration: 700
            easing.type: Easing.OutCubic
        }

    }

    Behavior on shownTx {
        NumberAnimation {
            duration: 700
            easing.type: Easing.OutCubic
        }

    }

    // Label on the left, value and an optional copy action on the right
    component InfoRow: Item {
        id: infoRow

        property string label: ""
        property string value: ""
        property bool clickable: false
        property bool copyable: false

        signal activated()
        signal copied()

        width: parent.width
        height: Theme.px(24)

        Text {
            id: infoLabel

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: infoRow.label
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLabel
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, infoRow.width - infoLabel.implicitWidth
                    - (infoRow.copyable ? Theme.px(34) : Theme.gapSmall)))
                text: infoRow.value
                textFormat: Text.PlainText
                color: rowMouse.containsMouse && infoRow.clickable ? Theme.accent : Theme.text
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeBody

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    enabled: infoRow.clickable
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: infoRow.activated()
                }

            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: infoRow.copyable
                text: "󰆏"
                color: copyMouse.containsMouse ? Theme.accent : Theme.textDim
                font.family: Theme.font
                font.pixelSize: Theme.sizeBody + 1

                MouseArea {
                    id: copyMouse

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: infoRow.copied()
                }

            }

        }

    }

}
