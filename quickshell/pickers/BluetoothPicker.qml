import "../services"
import "./parts"
import QtQuick
import Quickshell.Bluetooth

// Bluetooth with the PC in the middle, sibling of the Wi-Fi picker: look, animations and controls in
// parts/RadarPicker.qml.
// - "devices": connected devices orbit on the side on the inner track (wave to the PC),
//   paired ones on the outer one.
// - "scan": found devices appear as blips in the radar.
// Click = connect/disconnect (in the scan: pair + connect), right-click = only select.
// Logic and pairing agent: services/BluetoothState.qml
RadarPicker {
    id: root

    readonly property var shownDevices: BluetoothState.devices.filter((d) => {
        return modeOf(d) === "devices" || BluetoothState.showUnnamed || !BluetoothState.isUnnamed(d);
    })
    readonly property bool promptNeedsInput: prompt !== null && (prompt.type === "pin" || prompt.type === "passkey")
    readonly property string promptDevName: promptShown && promptShown.device ? BluetoothState.displayName(promptShown.device) : "A device"
    readonly property string promptKind: promptShown ? promptShown.type : ""

    on: BluetoothState.enabled
    available: BluetoothState.available
    scanning: BluetoothState.scanning
    anyConnected: BluetoothState.connectedCount > 0
    title: "Bluetooth"
    subtitle: {
        if (!BluetoothState.available)
            return "No adapter found";

        if (BluetoothState.switching)
            return on ? "Turning off…" : "Turning on…";

        if (!on)
            return "Off";

        if (mode === "scan")
            return (BluetoothState.scanning ? "Scanning  ·  " : "Scan finished  ·  ") + foundCount + " found";

        const n = BluetoothState.connectedCount;
        return n === 0 ? "Not connected" : n + " connected";
    }
    headerGlyph: String.fromCodePoint(on ? (BluetoothState.connectedCount > 0 ? 0xf00b1 : 0xf00af) : 0xf00b2)
    notice: BluetoothState.notice
    noticeIsError: BluetoothState.noticeIsError
    items: shownDevices
    nodeModel: BluetoothState.adapter ? BluetoothState.adapter.devices : null
    selectedItem: {
        const list = BluetoothState.devices;
        for (let i = 0; i < list.length; i++) {
            if (list[i].address === selectedKey)
                return list[i];

        }
        return null;
    }
    keyOf: (d) => {
        return d.address;
    }
    // Belongs in the device window (known or pairing right now) or is a scan find
    modeOf: (d) => {
        return (d.connected || d.paired || BluetoothState.isBusy(d)) ? "devices" : "scan";
    }
    isInner: (d) => {
        return d.connected || BluetoothState.isBusy(d);
    }
    outerLess: (a, b) => {
        return BluetoothState.displayName(a).localeCompare(BluetoothState.displayName(b));
    }
    glyphOf: (d) => {
        return d ? BluetoothState.glyphFor(d.icon) : "";
    }
    nameOf: (d) => {
        return BluetoothState.displayName(d);
    }
    detailInfo: (d) => {
        return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "";
    }
    isConnected: (d) => {
        return d.connected;
    }
    canForget: (d) => {
        return d.paired || d.trusted;
    }
    // Click/Enter on a device. A scan find is paired + connected; for that back to the
    // device view, where it arrives on the inner track with the wave (searching disturbs pairing).
    activate: (d) => {
        if (!d || !on)
            return ;

        if (modeOf(d) === "scan") {
            BluetoothState.connectDevice(d);
            setMode("devices");
            select(d.address);
        } else {
            BluetoothState.toggleDevice(d);
        }
    }
    forget: (d) => {
        BluetoothState.forget(d);
    }
    startScan: () => {
        BluetoothState.startScan();
    }
    // Only stop our own search (another one, e.g. from bluetoothctl, keeps running)
    stopScan: () => {
        if (BluetoothState.ownScan)
            BluetoothState.stopScan();

    }
    toggleScan: () => {
        BluetoothState.toggleScan();
    }
    togglePower: () => {
        BluetoothState.togglePower();
    }
    powerOn: () => {
        BluetoothState.setEnabled(true);
    }
    prompt: BluetoothState.prompt
    promptInput: promptNeedsInput ? pinInput : null
    cancelPrompt: () => {
        BluetoothState.answerPrompt(false);
    }
    // Enter confirms an open request, T = trust, Ctrl+D = forget (like Del)
    extraKey: (key, event) => {
        const p = prompt;
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && p && p.type !== "display") {
            BluetoothState.answerPrompt(true);
            return true;
        }
        if (key === Qt.Key_T) {
            if (selectedItem)
                BluetoothState.setTrusted(selectedItem, !selectedItem.trusted);

            return true;
        }
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0 && key === event.key;
        if (key === Qt.Key_D && ctrl) {
            forgetSelected();
            return true;
        }
        return false;
    }
    Component.onCompleted: {
        if (BluetoothState.autoScan && on)
            setMode("scan");

    }
    onPromptNeedsInputChanged: {
        if (promptNeedsInput) {
            pinInput.text = "";
            pinInput.forceActiveFocus();
        } else {
            focusKeys();
        }
    }

    nodeDelegate: Component {
        RadarNode {
            required property BluetoothDevice modelData

            picker: root
            key: modelData.address
            item: modelData
            connected: modelData.connected
            busy: BluetoothState.isBusy(modelData)
            known: modelData.paired
            glyph: BluetoothState.glyphFor(modelData.icon)
            name: BluetoothState.displayName(modelData)
            status: {
                const d = modelData;
                if (d.pairing)
                    return "pairing…";

                if (d.state === BluetoothDeviceState.Connecting || BluetoothState.pendingPair[d.address] === true)
                    return "connecting…";

                if (d.state === BluetoothDeviceState.Disconnecting)
                    return "disconnecting…";

                if (d.connected)
                    return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "connected";

                return "";
            }
            // Battery as a ring around the bubble
            ringShown: modelData.connected && modelData.batteryAvailable
            ringLevel: modelData.battery
            ringTone: Theme.levelTone(modelData.battery * 100)
        }

    }

    linkDelegate: Component {
        RadarLink {
            required property BluetoothDevice modelData

            picker: root
            key: modelData.address
            connected: modelData.connected
            busy: BluetoothState.isBusy(modelData)
        }

    }

    // Request of the pairing agent (confirm a code / enter it / type it on the device)
    promptContent: [
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: {
                switch (root.promptKind) {
                case "confirm":
                    return "Same code on " + root.promptDevName + "?";
                case "authorize":
                    return "Pair with " + root.promptDevName + "?";
                case "service":
                    return "Allow " + root.promptDevName + "?";
                case "pin":
                    return "PIN for " + root.promptDevName;
                case "passkey":
                    return "Passkey for " + root.promptDevName;
                case "display":
                    return "Type on " + root.promptDevName;
                }
                return "";
            }
            font.family: root.mono
            font.pixelSize: 11
            color: WalColors.withAlpha(WalColors.color7, 0.8)
        },
        // Show the code big
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.promptKind === "confirm" || root.promptKind === "display"
            text: {
                const k = root.promptShown ? root.promptShown.passkey : "";
                return k.length === 6 ? k.slice(0, 3) + " " + k.slice(3) : k;
            }
            font.family: root.mono
            font.pixelSize: 28
            font.bold: true
            font.letterSpacing: 3
            color: WalColors.color4
        },
        Rectangle {
            width: parent.width
            height: 36
            radius: height / 2
            visible: root.promptKind === "pin" || root.promptKind === "passkey"
            color: WalColors.withAlpha(WalColors.color7, 0.07)
            border.width: 1.5
            border.color: pinInput.activeFocus ? WalColors.withAlpha(WalColors.color4, 0.55) : "transparent"

            TextInput {
                id: pinInput

                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: Text.AlignVCenter
                font.family: root.mono
                font.pixelSize: 15
                font.letterSpacing: 2
                color: WalColors.color7
                clip: true
                inputMethodHints: root.promptKind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        BluetoothState.answerPrompt(true, text);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        BluetoothState.answerPrompt(false);
                        event.accepted = true;
                    }
                }

                validator: RegularExpressionValidator {
                    regularExpression: root.promptKind === "passkey" ? /[0-9]{0,6}/ : /.{0,16}/
                }

            }

        },
        Row {
            anchors.right: parent.right
            spacing: 8

            PillButton {
                label: root.promptKind === "display" ? "Cancel" : "Reject"
                onClicked: BluetoothState.answerPrompt(false)
            }

            PillButton {
                visible: root.promptKind !== "display"
                label: root.promptKind === "service" ? "Allow" : "Pair"
                primary: true
                onClicked: BluetoothState.answerPrompt(true, pinInput.text)
            }

        }
    ]

    detailActions: [
        // Trust = reconnects by itself (e.g. headphones after turning them on)
        RoundButton {
            glyph: String.fromCodePoint(root.selectedItem && root.selectedItem.trusted ? 0xf0565 : 0xf0499)
            lit: root.selectedItem !== null && root.selectedItem.trusted
            visible: root.selectedItem !== null && root.selectedItem.paired
            onClicked: BluetoothState.setTrusted(root.selectedItem, !root.selectedItem.trusted)
        },
        RoundButton {
            glyph: String.fromCodePoint(0xf0a7a)
            danger: true
            lit: root.confirmForget
            visible: root.selectedItem !== null && (root.selectedItem.paired || root.selectedItem.trusted)
            onClicked: root.forgetSelected()
        },
        PillButton {
            readonly property var d: root.selectedItem
            readonly property bool busy: d !== null && BluetoothState.isBusy(d)

            primary: d !== null && !d.connected && !busy
            label: {
                if (!d)
                    return "";

                if (d.pairing)
                    return "Cancel";

                if (busy)
                    return d.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…" : "Connecting…";

                if (d.connected)
                    return "Disconnect";

                return d.paired ? "Connect" : "Pair";
            }
            enabled: root.on
            onClicked: root.activate(d)
        }
    ]

    options: [
        OptionChip {
            label: "Visible"
            checked: BluetoothState.discoverable
            enabled: root.on
            onToggled: BluetoothState.setDiscoverable(!BluetoothState.discoverable)
        },
        OptionChip {
            label: "Auto-scan"
            checked: BluetoothState.autoScan
            onToggled: BluetoothState.setOption("autoScan", !BluetoothState.autoScan)
        },
        OptionChip {
            label: "Unnamed"
            checked: BluetoothState.showUnnamed
            onToggled: BluetoothState.setOption("showUnnamed", !BluetoothState.showUnnamed)
        },
        OptionChip {
            label: "Auto-trust"
            checked: BluetoothState.autoTrust
            onToggled: BluetoothState.setOption("autoTrust", !BluetoothState.autoTrust)
        }
    ]
}
