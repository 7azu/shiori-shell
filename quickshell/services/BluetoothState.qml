// Bluetooth: adapter, devices, pairing/connecting and the pairing agent (scripts/bt_agent.py).
// Settings (created on the first change): ~/.config/quickshell-local/bluetooth.json
//   { "autoScan": false, "showUnnamed": false, "autoTrust": true }

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter ? adapter.enabled : false
    readonly property bool switching: adapter !== null && (adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling)
    readonly property bool scanning: adapter ? adapter.discovering : false
    readonly property bool discoverable: adapter ? adapter.discoverable : false
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var connectedDevices: devices.filter((d) => {
        return d.connected;
    })
    readonly property int connectedCount: connectedDevices.length
    readonly property bool pickerVisible: PickerManager.isOpen("bluetooth")
    // ---------- Settings ----------
    // Open the picker directly in search mode (the search itself is controlled by the mode in the picker)
    property bool autoScan: false
    // Show devices without a name (MAC address only) - in public places there are dozens of them
    property bool showUnnamed: false
    // Trust newly paired devices -> they reconnect by themselves later
    property bool autoTrust: true
    // ---------- Runtime ----------
    // Addresses being paired right now at our request (connect right after)
    property var pendingPair: ({
    })
    // Short message for the picker (error or hint)
    property string notice: ""
    property bool noticeIsError: false
    // Open request of the agent: { type, id, device (object), passkey } or null
    property var prompt: null
    property bool agentReady: false
    // We started the search ourselves (only then stop it again when closing)
    property bool ownScan: false
    // Search wanted while the adapter was still off
    property bool scanAfterPower: false
    readonly property int scanSeconds: 40
    // Re-pair: address/name of the device whose pairing mode we wait for ("" = none).
    // Needed when the device was paired with another computer in the meantime: controllers & co.
    // remember only one, the old pairing here is then worthless ("Permission denied").
    property string rePairAddress: ""
    property string rePairName: ""
    property string rePairIcon: ""
    readonly property bool rePairing: rePairAddress !== ""
    readonly property int rePairSeconds: 90

    // Create the singleton early, so the pairing agent also runs without an open picker
    function warmUp() {
    }

    function toggle() {
        PickerManager.toggle("bluetooth");
    }

    function setEnabled(on) {
        if (!adapter)
            return ;

        adapter.enabled = on;
        if (!on) {
            ownScan = false;
            scanTimer.stop();
        }
    }

    function togglePower() {
        setEnabled(!enabled);
    }

    function startScan() {
        if (!adapter)
            return ;

        if (!adapter.enabled) {
            // Turn it on first; the search starts as soon as the adapter is ready
            scanAfterPower = true;
            adapter.enabled = true;
            return ;
        }
        ownScan = true;
        adapter.discovering = true;
        scanTimer.restart();
    }

    function stopScan() {
        scanTimer.stop();
        ownScan = false;
        if (adapter && adapter.discovering)
            adapter.discovering = false;

    }

    function toggleScan() {
        if (scanning)
            stopScan();
        else
            startScan();
    }

    function setDiscoverable(on) {
        if (!adapter)
            return ;

        // Without pairable, phones can see each other but not pair
        if (on)
            adapter.pairable = true;

        adapter.discoverable = on;
    }

    // BlueZ sets the address as alias ("AA-BB-..") if the device sends no name
    function isUnnamed(d) {
        const n = d.deviceName || "";
        return n === "" || /^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(n) || /^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(d.name || "");
    }

    function displayName(d) {
        if (!d)
            return "";

        return (d.name && !/^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(d.name)) ? d.name : (d.deviceName || d.address);
    }

    // Glyphs (Material Design Icons from the Nerd Font) matching the BlueZ icon name
    function glyphFor(icon) {
        const i = icon || "";
        if (i === "audio-headset")
            return String.fromCodePoint(0xf02ce);

        if (i === "audio-headphones")
            return String.fromCodePoint(0xf02cb);

        if (i === "audio-card" || i === "multimedia-player")
            return String.fromCodePoint(0xf04c3);

        if (i.startsWith("audio-input"))
            return String.fromCodePoint(0xf036c);

        if (i === "input-keyboard")
            return String.fromCodePoint(0xf030c);

        if (i === "input-mouse")
            return String.fromCodePoint(0xf037d);

        if (i === "input-gaming")
            return String.fromCodePoint(0xf0297);

        if (i === "input-tablet")
            return String.fromCodePoint(0xf04f6);

        if (i === "phone")
            return String.fromCodePoint(0xf011c);

        if (i === "computer")
            return String.fromCodePoint(0xf0322);

        if (i === "video-display")
            return String.fromCodePoint(0xf0502);

        if (i === "printer")
            return String.fromCodePoint(0xf042a);

        if (i.startsWith("camera"))
            return String.fromCodePoint(0xf0100);

        return String.fromCodePoint(0xf00af);
    }

    function kindLabel(icon) {
        const map = {
            "audio-headset": "Headset",
            "audio-headphones": "Headphones",
            "audio-card": "Speaker",
            "multimedia-player": "Media player",
            "input-keyboard": "Keyboard",
            "input-mouse": "Mouse",
            "input-gaming": "Controller",
            "input-tablet": "Tablet",
            "phone": "Phone",
            "computer": "Computer",
            "video-display": "Display",
            "printer": "Printer"
        };
        return map[icon || ""] || ((icon || "").startsWith("camera") ? "Camera" : "Device");
    }

    function isBusy(d) {
        return d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting || pendingPair[d.address] === true;
    }

    function setPending(addr, on) {
        const p = Object.assign({
        }, pendingPair);
        if (on)
            p[addr] = true;
        else
            delete p[addr];
        pendingPair = p;
    }

    function connectDevice(d) {
        if (!d || !enabled)
            return ;

        if (d.paired) {
            d.connect();
        } else {
            // Pair first; connecting happens as soon as "paired" comes (see the Instantiator below)
            setPending(d.address, true);
            d.pair();
        }
    }

    function disconnectDevice(d) {
        if (d)
            d.disconnect();

    }

    function toggleDevice(d) {
        if (!d)
            return ;

        if (d.pairing) {
            d.cancelPair();
            setPending(d.address, false);
        } else if (d.connected || d.state === BluetoothDeviceState.Connecting) {
            d.disconnect();
        } else {
            connectDevice(d);
        }
    }

    function setTrusted(d, on) {
        if (d)
            d.trusted = on;

    }

    function forget(d) {
        if (!d)
            return ;

        setPending(d.address, false);
        say("Forgot " + displayName(d), false);
        d.forget();
    }

    // Delete the old pairing and wait for the device in pairing mode; when it shows up in the search,
    // it is paired, trusted and connected automatically (see Instantiator: Component.onCompleted)
    function rePair(d) {
        if (!d || !enabled)
            return ;

        rePairAddress = d.address;
        rePairName = displayName(d);
        rePairIcon = d.icon || "";
        setPending(d.address, false);
        d.forget();
        ownScan = true;
        adapter.discovering = true;
        scanTimer.stop();
        rePairTimer.restart();
    }

    function cancelRePair() {
        if (!rePairing)
            return ;

        rePairAddress = "";
        rePairTimer.stop();
        if (ownScan)
            stopScan();

    }

    function rePairFound(d) {
        if (!rePairing || d.address !== rePairAddress)
            return ;

        rePairAddress = "";
        rePairTimer.stop();
        // Searching disturbs pairing -> stop it
        stopScan();
        connectDevice(d);
    }

    // Typical pairing mode per device type (for the hint in the picker)
    function pairingHint(icon) {
        if (icon === "input-gaming")
            return "Hold Create/Share + PS until the light bar flashes quickly";

        if ((icon || "").startsWith("audio"))
            return "Hold the power or pairing button until the light flashes";

        return "Put it in pairing mode (see its manual)";
    }

    function say(text, isError) {
        notice = text;
        noticeIsError = isError;
        noticeTimer.restart();
    }

    function deviceByPath(path) {
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].dbusPath === path)
                return devices[i];

        }
        return null;
    }

    // Answer to an agent request (code confirmed / rejected / entered)
    function answerPrompt(ok, value) {
        const p = prompt;
        prompt = null;
        if (!p)
            return ;

        if (p.type === "display") {
            // Display requests have no answer; cancel = cancel the pairing
            if (!ok && p.device)
                p.device.cancelPair();

            return ;
        }
        agentProc.write((ok ? "ok " : "no ") + p.id + (ok && value ? " " + value : "") + "\n");
    }

    function handleAgent(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return ;
        }
        if (msg.type === "ready") {
            agentReady = true;
            return ;
        }
        if (msg.type === "error") {
            agentReady = false;
            console.warn("BluetoothState: Agent:", msg.error);
            return ;
        }
        if (msg.type === "cancel") {
            prompt = null;
            return ;
        }
        // If a request is already waiting, the new one replaces it (BlueZ never asks in parallel)
        prompt = {
            "type": msg.type,
            "id": msg.id || 0,
            "device": deviceByPath(msg.device),
            "passkey": msg.passkey || "",
            "entered": msg.entered || 0
        };
        // Incoming pairing (e.g. from a phone): show the picker, so it can be confirmed
        if (!pickerVisible)
            PickerManager.open("bluetooth");

    }

    function applyRaw(raw) {
        let cfg = {
        };
        try {
            cfg = JSON.parse(raw && raw.length > 0 ? raw : "{}");
        } catch (e) {
            console.warn("BluetoothState: bluetooth.json invalid:", e);
        }
        autoScan = cfg.autoScan === true;
        showUnnamed = cfg.showUnnamed === true;
        autoTrust = cfg.autoTrust !== false;
    }

    function save() {
        cfgFile.setText(JSON.stringify({
            "autoScan": autoScan,
            "showUnnamed": showUnnamed,
            "autoTrust": autoTrust
        }, null, 2) + "\n");
    }

    function setOption(key, value) {
        root[key] = value;
        save();
    }

    onPickerVisibleChanged: {
        if (!pickerVisible) {
            if (ownScan)
                stopScan();

            if (prompt && prompt.type === "display")
                prompt = null;

        }
    }
    onEnabledChanged: {
        if (enabled && scanAfterPower) {
            scanAfterPower = false;
            startScan();
        }
    }

    FileView {
        id: cfgFile

        path: MachineConfig.dir + "/bluetooth.json"
        printErrors: false
        // Take changes made by hand to the file right away too
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyRaw(text())
        onLoadFailed: root.applyRaw("")
    }

    // End the search after a while (discovery costs radio time and disturbs audio connections)
    Timer {
        id: scanTimer

        interval: root.scanSeconds * 1000
        onTriggered: root.stopScan()
    }

    // If the device does not go into pairing mode, do not search forever
    Timer {
        id: rePairTimer

        interval: root.rePairSeconds * 1000
        onTriggered: {
            root.say(root.rePairName + " didn't show up in pairing mode  ·  try Re-pair again", true);
            root.cancelRePair();
        }
    }

    Timer {
        id: noticeTimer

        interval: 4200
        onTriggered: root.notice = ""
    }

    // Per device: watch pairing/connection, to connect after pairing and report errors
    Instantiator {
        model: root.adapter ? root.adapter.devices : null

        delegate: Connections {
            id: watch

            required property BluetoothDevice modelData
            property int lastState: modelData.state
            // Time at which a connection started by us was established (0 = none)
            property double ownConnectAt: 0

            function onPairedChanged() {
                const d = watch.modelData;
                if (!d.paired || root.pendingPair[d.address] !== true)
                    return ;

                root.setPending(d.address, false);
                if (root.prompt && root.prompt.device === d)
                    root.prompt = null;

                if (root.autoTrust)
                    d.trusted = true;

                d.connect();
            }

            function onPairingChanged() {
                const d = watch.modelData;
                // Pairing over but not paired -> rejected, timed out or cancelled
                if (!d.pairing && !d.paired && root.pendingPair[d.address] === true) {
                    root.setPending(d.address, false);
                    if (root.prompt && root.prompt.device === d)
                        root.prompt = null;

                    root.say("Pairing with " + root.displayName(d) + " failed", true);
                }
            }

            function onStateChanged() {
                const d = watch.modelData;
                // Mostly the device is off or asleep (BlueZ: "Host is down"); the PC cannot
                // wake it up; controllers connect by themselves as soon as you press the PS/Home button.
                if (watch.lastState === BluetoothDeviceState.Connecting && d.state === BluetoothDeviceState.Disconnected) {
                    root.say("Couldn't reach " + root.displayName(d) + "  ·  is it on? Controllers: press PS/Home", true);
                } else if (watch.lastState === BluetoothDeviceState.Connecting && d.state === BluetoothDeviceState.Connected) {
                    watch.ownConnectAt = Date.now();
                    root.say("Connected to " + root.displayName(d), false);
                } else if (d.state === BluetoothDeviceState.Disconnected && watch.ownConnectAt > 0 && Date.now() - watch.ownConnectAt < 4000) {
                    // Connected and gone again right away: the radio link stood, but the HID channel was rejected
                    // (BlueZ "Permission denied"). With the DualSense the cause was an invalid key: it remembers
                    // only one computer, pairing it with a laptop invalidates the pairing here -> pair again.
                    root.say(root.displayName(d) + " rejected the connection  ·  paired with another PC? Remove it, then hold PS + Create to pair again", true);
                }
                if (d.state === BluetoothDeviceState.Disconnected)
                    watch.ownConnectAt = 0;

                watch.lastState = d.state;
            }

            target: modelData
        }

    }

    // Pairing agent: asks for the codes BlueZ needs for pairing; if it dies, it is restarted.
    Process {
        id: agentProc

        command: ["python3", Qt.resolvedUrl("../scripts/bt_agent.py").toString().replace("file://", "")]
        running: true
        stdinEnabled: true
        onExited: {
            root.agentReady = false;
            agentRestart.restart();
        }

        stdout: SplitParser {
            onRead: (line) => {
                return root.handleAgent(line);
            }
        }

    }

    Timer {
        id: agentRestart

        interval: 5000
        onTriggered: agentProc.running = true
    }

}
