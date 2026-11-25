import "../services"
import "./parts"
import QtQuick

// Wi-Fi, sibling of the Bluetooth picker: look, animations and controls in parts/RadarPicker.qml.
// - "devices": the connected network sits on the side on the inner track (wave to the PC),
//   saved networks orbit on the outer one (also those out of range right now, dimmed).
// - "scan": newly found networks appear as blips in the radar.
// Click = connect/disconnect (encrypted new networks ask for the password),
// right-click = only select. Logic: services/WifiState.qml
RadarPicker {
    id: root

    property bool showPassword: false
    // Networks in range + saved ones out of range (like paired BT devices that are off right now)
    readonly property var nets: {
        const list = WifiState.shownNetworks.slice();
        const seen = {
        };
        for (let i = 0; i < list.length; i++) seen[list[i].ssid] = true
        for (let i = 0; i < WifiState.saved.length; i++) {
            const s = WifiState.saved[i];
            if (!seen[s])
                list.push({
                "ssid": s,
                "signal": 0,
                "security": "",
                "secure": false,
                "inUse": false,
                "saved": true,
                "freq": 0,
                "band": "",
                "away": true
            });

        }
        return list;
    }
    readonly property var netMap: {
        const m = {
        };
        for (let i = 0; i < nets.length; i++) m[nets[i].ssid] = nets[i]
        return m;
    }
    // Placeholder while a node still lives but its network is already gone from the list
    readonly property var ghost: ({
        "ssid": "",
        "signal": 0,
        "security": "",
        "secure": false,
        "inUse": false,
        "saved": false,
        "freq": 0,
        "band": "",
        "away": true
    })

    // Signal strength -> 1..4 bars
    function level(signal) {
        return signal >= 75 ? 4 : (signal >= 50 ? 3 : (signal >= 25 ? 2 : 1));
    }

    // Nerd Font glyph "wifi-strength-N" (with a lock for encrypted networks)
    function glyph(n) {
        if (!n)
            return String.fromCodePoint(0xf092f);

        if (n.away)
            return String.fromCodePoint(0xf092e);

        const plain = [0xf091f, 0xf0922, 0xf0925, 0xf0928];
        const locked = [0xf0921, 0xf0924, 0xf0927, 0xf092a];
        return String.fromCodePoint((n.secure ? locked : plain)[level(n.signal) - 1]);
    }

    function isBusy(n) {
        return WifiState.connectingSsid === n.ssid || WifiState.disconnectingSsid === n.ssid;
    }

    // Waiting for the password (prompt open)
    function isWaiting(n) {
        return prompt !== null && prompt.ssid === n.ssid;
    }

    // Stable model for the Repeaters: nmcli's JSON comes as a new array on every re-read,
    // as a model all nodes would be created anew and fly out of the PC every time.
    function syncModel() {
        const want = {
        };
        for (let i = 0; i < nets.length; i++) want[nets[i].ssid] = true
        for (let i = netModel.count - 1; i >= 0; i--) {
            if (!want[netModel.get(i).ssid])
                netModel.remove(i);

        }
        const have = {
        };
        for (let i = 0; i < netModel.count; i++) have[netModel.get(i).ssid] = true
        for (let i = 0; i < nets.length; i++) {
            if (!have[nets[i].ssid])
                netModel.append({
                "ssid": nets[i].ssid
            });

        }
    }

    on: WifiState.enabled
    available: WifiState.available
    scanning: WifiState.liveScan
    anyConnected: WifiState.connected
    title: "Wi-Fi"
    subtitle: {
        if (!WifiState.loaded)
            return "Loading…";

        if (!WifiState.available)
            return "No Wi-Fi adapter found";

        if (WifiState.radioSwitching)
            return WifiState.radioOn ? "Turning off…" : "Turning on…";

        if (!on)
            return "Off";

        if (mode === "scan")
            return (WifiState.liveScan ? "Scanning  ·  " : "Scan finished  ·  ") + foundCount + " found";

        if (WifiState.connectingSsid !== "")
            return "Connecting to " + WifiState.connectingSsid + "…";

        if (WifiState.connected)
            return WifiState.currentSsid;

        return "Not connected";
    }
    headerGlyph: !on ? String.fromCodePoint(0xf05aa) : (WifiState.connected ? glyph(WifiState.current) : String.fromCodePoint(0xf05a9))
    notice: WifiState.notice
    noticeIsError: WifiState.noticeIsError
    items: nets
    nodeModel: netModel
    selectedItem: netMap[selectedKey] ?? null
    keyOf: (n) => {
        return n.ssid;
    }
    // Belongs in the network view (connected, saved or connecting right now) or is a scan find
    modeOf: (n) => {
        return (n.inUse || n.saved || isBusy(n) || isWaiting(n)) ? "devices" : "scan";
    }
    isInner: (n) => {
        return n.inUse || isBusy(n) || isWaiting(n);
    }
    // In range first, then by name
    outerLess: (a, b) => {
        return (a.away === true) - (b.away === true) || a.ssid.localeCompare(b.ssid);
    }
    glyphOf: (n) => {
        return glyph(n);
    }
    nameOf: (n) => {
        return n ? n.ssid : "";
    }
    detailInfo: (n) => {
        if (n.away)
            return "out of range";

        const parts = [n.signal + "%"];
        if (n.band !== "")
            parts.push(n.band);

        if (n.inUse && WifiState.ip !== "")
            parts.push(WifiState.ip);

        return parts.join("  ·  ");
    }
    isConnected: (n) => {
        return n.inUse;
    }
    canForget: (n) => {
        return n.saved;
    }
    // Click/Enter on a network. A scan find is connected; for that back to the network view,
    // where it arrives on the inner track with the wave (or waits for the password there).
    activate: (n) => {
        if (!n || !on)
            return ;

        if (modeOf(n) === "scan") {
            WifiState.toggleNetwork(n);
            setMode("devices");
            select(n.ssid);
        } else {
            WifiState.toggleNetwork(n);
        }
    }
    forget: (n) => {
        WifiState.forget(n.ssid);
    }
    startScan: () => {
        WifiState.startScan();
    }
    stopScan: () => {
        WifiState.stopScan();
    }
    toggleScan: () => {
        WifiState.toggleScan();
    }
    togglePower: () => {
        WifiState.togglePower();
    }
    powerOn: () => {
        WifiState.setRadio(true);
    }
    prompt: WifiState.prompt
    promptInput: prompt ? pwInput : null
    promptAccent: promptShown && promptShown.retry ? Theme.bad : WalColors.color4
    cancelPrompt: () => {
        WifiState.cancelPrompt();
    }
    Component.onCompleted: syncModel()
    onItemsChanged: syncModel()
    onIntroStarted: showPassword = false
    // The password prompt appears/disappears: focus there or back
    onPromptChanged: {
        pwInput.text = "";
        showPassword = false;
        if (prompt)
            select(prompt.ssid);

        Qt.callLater(focusSearch);
    }

    ListModel {
        id: netModel
    }

    nodeDelegate: Component {
        RadarNode {
            required property string ssid
            readonly property var n: root.netMap[ssid] ?? root.ghost

            picker: root
            key: ssid
            item: n
            clickItem: root.netMap[ssid] ?? null
            connected: n.inUse
            busy: root.isBusy(n)
            waiting: root.isWaiting(n)
            known: !!n.saved
            dimmed: !!n.away
            glyph: root.glyph(n)
            name: ssid
            status: {
                if (WifiState.connectingSsid === n.ssid)
                    return "connecting…";

                if (WifiState.disconnectingSsid === n.ssid)
                    return "disconnecting…";

                if (root.isWaiting(n))
                    return "password…";

                if (n.inUse)
                    return n.signal + "%";

                return "";
            }
            // Signal strength as a ring around the bubble (like the battery in Bluetooth)
            ringShown: n.inUse && !root.isBusy(n)
            ringLevel: n.signal / 100
            ringTone: Theme.levelTone(n.signal)
        }

    }

    linkDelegate: Component {
        RadarLink {
            required property string ssid
            readonly property var n: root.netMap[ssid] ?? root.ghost

            picker: root
            key: ssid
            connected: n.inUse
            busy: root.isBusy(n)
            waiting: root.isWaiting(n)
        }

    }

    // Password prompt for an encrypted network (like the pairing card in Bluetooth)
    promptContent: [
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: {
                const p = root.promptShown;
                if (!p)
                    return "";

                return (p.retry ? "Wrong password for " : "Password for ") + p.ssid;
            }
            font.family: root.mono
            font.pixelSize: 11
            color: root.promptShown && root.promptShown.retry ? Theme.bad : WalColors.withAlpha(WalColors.color7, 0.8)
        },
        Rectangle {
            width: parent.width
            height: 36
            radius: height / 2
            color: WalColors.withAlpha(WalColors.color7, 0.07)
            border.width: 1.5
            border.color: pwInput.activeFocus ? WalColors.withAlpha(WalColors.color4, 0.55) : "transparent"

            TextInput {
                id: pwInput

                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: Text.AlignVCenter
                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                font.family: root.mono
                font.pixelSize: 15
                font.letterSpacing: 2
                color: WalColors.color7
                selectionColor: WalColors.withAlpha(WalColors.color4, 0.4)
                clip: true
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        WifiState.submitPassword(text);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        WifiState.cancelPrompt();
                        event.accepted = true;
                    }
                }
            }

        },
        Row {
            anchors.right: parent.right
            spacing: 8

            RoundButton {
                glyph: String.fromCodePoint(root.showPassword ? 0xf06d1 : 0xf06d0)
                lit: root.showPassword
                onClicked: root.showPassword = !root.showPassword
            }

            PillButton {
                label: "Cancel"
                onClicked: WifiState.cancelPrompt()
            }

            PillButton {
                label: "Connect"
                primary: true
                enabled: pwInput.text !== ""
                onClicked: WifiState.submitPassword(pwInput.text)
            }

        }
    ]

    detailActions: [
        RoundButton {
            glyph: String.fromCodePoint(0xf0a7a)
            danger: true
            lit: root.confirmForget
            visible: root.selectedItem !== null && root.selectedItem.saved
            onClicked: root.forgetSelected()
        },
        PillButton {
            readonly property var n: root.selectedItem
            readonly property bool busy: n !== null && root.isBusy(n)
            readonly property bool waiting: n !== null && root.isWaiting(n)

            primary: n !== null && !n.inUse && !busy && !waiting
            label: {
                if (!n)
                    return "";

                if (waiting)
                    return "Cancel";

                if (busy)
                    return WifiState.disconnectingSsid === n.ssid ? "Disconnecting…" : "Connecting…";

                return n.inUse ? "Disconnect" : "Connect";
            }
            enabled: root.on && !busy
            onClicked: waiting ? WifiState.cancelPrompt() : root.activate(n)
        }
    ]

    options: [
        OptionChip {
            label: "Auto-scan"
            checked: WifiState.autoScan
            onToggled: WifiState.setOption("autoScan", !WifiState.autoScan)
        },
        OptionChip {
            label: "Weak"
            checked: WifiState.showWeak
            onToggled: WifiState.setOption("showWeak", !WifiState.showWeak)
        }
    ]
}
