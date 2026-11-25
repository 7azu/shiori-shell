// Wi-Fi via NetworkManager (nmcli) for the Wi-Fi icon in the bar and pickers/WifiPicker.qml.
// - State + networks come from scripts/wifi_status.py as JSON (parses nmcli's terse format).
// - Live: "nmcli monitor" reports every change (connect, disconnect, radio on/off) -> read again
//   bundled. New networks only show up after a scan: when opening (auto-scan) and every
//   20 s while the window is open.
// - Connect: saved profile -> "connection up"; new network -> "device wifi connect"
//   (encrypted: ask for the password first). If a new network fails, the profile created
//   along the way is deleted again, so no broken profile is left behind.
// - Options: ~/.config/quickshell-local/wifi.json  { "autoScan": true, "showWeak": false }

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    readonly property bool pickerVisible: PickerManager.isOpen("wifi")
    readonly property string script: Qt.resolvedUrl("../scripts/wifi_status.py").toString().replace("file://", "")
    // Wi-Fi device (e.g. wlan0); empty = no Wi-Fi adapter
    property string device: ""
    // NetworkManager state: "connected", "connecting", "disconnected", "unavailable" (radio off), ...
    property string deviceState: ""
    // Profile name of the active Wi-Fi connection
    property string activeConnection: ""
    property bool radioOn: false
    property bool radioSwitching: false
    property string ip: ""
    // Networks (one per SSID): { ssid, signal, security, secure, inUse, saved, freq, band }
    property var networks: []
    // Profile names of saved Wi-Fi connections
    property var saved: []
    property bool loaded: false
    property bool scanning: false
    // Radar in the picker (like the Bluetooth search): rescan every few seconds for scanSeconds,
    // a single nmcli scan is over after ~4 s and the beam would stop right away otherwise
    property bool liveScan: false
    readonly property int scanSeconds: 40
    // Host name for the PC in the middle of the picker
    // Network we are connecting to right now (own call, until nmcli is done)
    property string connectingSsid: ""
    property string disconnectingSsid: ""
    // Password prompt in the window: { ssid, retry } or null
    property var prompt: null
    property string notice: ""
    property bool noticeIsError: false
    property bool autoScan: true
    property bool showWeak: false
    // Show networks below this signal strength only with "Weak" (neighbor networks at the edge of the range)
    readonly property int weakSignal: 25
    readonly property bool available: device !== ""
    readonly property bool enabled: available && radioOn
    readonly property bool connected: deviceState === "connected"
    readonly property bool busy: connectingSsid !== "" || disconnectingSsid !== "" || deviceState === "connecting" || deviceState === "deactivating"
    readonly property var current: networks.find((n) => {
        return n.inUse;
    }) ?? null
    readonly property string currentSsid: current ? current.ssid : (connected ? activeConnection : "")
    readonly property int currentSignal: current ? current.signal : 0
    readonly property var shownNetworks: networks.filter((n) => {
        return showWeak || n.inUse || n.saved || n.signal >= weakSignal;
    })

    function toggle() {
        PickerManager.toggle("wifi");
    }

    function refresh() {
        if (statusProc.running) {
            refreshAgain = true;
            return ;
        }
        statusProc.running = true;
    }

    property bool refreshAgain: false

    function rescan() {
        if (!enabled || scanProc.running)
            return ;

        scanning = true;
        scanProc.running = true;
    }

    function startScan() {
        if (!enabled)
            return ;

        liveScan = true;
        liveScanTimer.restart();
        rescan();
    }

    function stopScan() {
        liveScan = false;
        liveScanTimer.stop();
    }

    function toggleScan() {
        if (liveScan)
            stopScan();
        else
            startScan();
    }

    function isSaved(ssid) {
        return saved.indexOf(ssid) !== -1;
    }

    function networkOf(ssid) {
        return networks.find((n) => {
            return n.ssid === ssid;
        }) ?? null;
    }

    // Click on a network: disconnect the connected one, otherwise connect (asks for the password if needed)
    function toggleNetwork(n) {
        if (!n || !enabled || busy)
            return ;

        if (n.inUse)
            disconnect();
        else
            connectTo(n.ssid, "");
    }

    function connectTo(ssid, password) {
        if (!enabled || connectProc.running)
            return ;

        const n = networkOf(ssid);
        const known = isSaved(ssid);
        let cmd;
        if (known && password === "")
            cmd = ["nmcli", "connection", "up", "id", ssid];
        else if (known)
            // Saved profile with a wrong/changed password: replace the password, then connect
            cmd = ["bash", "-c", "nmcli connection modify id \"$1\" wifi-sec.key-mgmt wpa-psk wifi-sec.psk \"$2\" && nmcli connection up id \"$1\"", "_", ssid, password];
        else if (n && n.secure && password === "") {
            prompt = {
                "ssid": ssid,
                "retry": false
            };
            return ;
        } else if (password !== "")
            cmd = ["nmcli", "device", "wifi", "connect", ssid, "password", password, "ifname", device];
        else
            cmd = ["nmcli", "device", "wifi", "connect", ssid, "ifname", device];
        prompt = null;
        connectingSsid = ssid;
        connectProc.ssid = ssid;
        connectProc.wasSaved = known;
        connectProc.withPassword = password !== "";
        connectProc.command = cmd;
        connectProc.running = true;
    }

    function submitPassword(pw) {
        if (prompt && pw !== "")
            connectTo(prompt.ssid, pw);

    }

    function cancelPrompt() {
        prompt = null;
    }

    function disconnect() {
        if (!connected || activeConnection === "" || actionProc.running)
            return ;

        disconnectingSsid = currentSsid;
        runAction(["nmcli", "connection", "down", "id", activeConnection], "Disconnected from " + currentSsid, () => {
            root.disconnectingSsid = "";
        });
    }

    function forget(ssid) {
        if (!isSaved(ssid) || actionProc.running)
            return ;

        runAction(["nmcli", "connection", "delete", "id", ssid], "Forgot " + ssid, null);
    }

    function setRadio(on) {
        if (!available || radioSwitching)
            return ;

        radioSwitching = true;
        prompt = null;
        runAction(["nmcli", "radio", "wifi", on ? "on" : "off"], "", () => {
            root.radioSwitching = false;
            if (on && root.pickerVisible)
                scanAfterRadio.restart();

        });
    }

    function togglePower() {
        setRadio(!radioOn);
    }

    function runAction(cmd, okText, done) {
        actionProc.okText = okText;
        actionProc.done = done;
        actionProc.command = cmd;
        actionProc.running = true;
    }

    function say(text, isError) {
        notice = text;
        noticeIsError = isError;
        noticeTimer.restart();
    }

    // nmcli errors short and understandable
    function errorText(err) {
        const e = String(err || "").trim();
        if (/secrets were required|802-1x|psk|password|invalid key|authentication/i.test(e))
            return "wrong-password";

        if (/no network with ssid/i.test(e))
            return "Network out of range";

        if (/timeout|timed out/i.test(e))
            return "Connection timed out";

        const line = e.split("\n").pop().replace(/^Error:\s*/, "");
        return line !== "" ? line : "Couldn't connect";
    }

    function applyStatus(raw) {
        let s;
        try {
            s = JSON.parse(raw);
        } catch (e) {
            console.warn("WifiState: status not readable:", e);
            return ;
        }
        device = s.device || "";
        deviceState = s.state || "";
        activeConnection = s.connection || "";
        radioOn = s.radio === true;
        ip = s.ip || "";
        saved = s.saved || [];
        networks = s.networks || [];
        loaded = true;
    }

    function applyOptions(raw) {
        let cfg = {
        };
        try {
            cfg = JSON.parse(raw && raw.length > 0 ? raw : "{}");
        } catch (e) {
            console.warn("WifiState: wifi.json invalid:", e);
        }
        autoScan = cfg.autoScan !== false;
        showWeak = cfg.showWeak === true;
    }

    function setOption(key, value) {
        root[key] = value;
        cfgFile.setText(JSON.stringify({
            "autoScan": autoScan,
            "showWeak": showWeak
        }, null, 2) + "\n");
    }

    Component.onCompleted: refresh()
    onPickerVisibleChanged: {
        if (pickerVisible) {
            refresh();
            if (autoScan)
                rescan();

        } else {
            prompt = null;
            stopScan();
        }
    }
    onEnabledChanged: {
        if (!enabled)
            stopScan();

    }

    Timer {
        id: liveScanTimer

        interval: root.scanSeconds * 1000
        onTriggered: root.stopScan()
    }

    // Scan more often during the live search than the 20 s below (NetworkManager throttles itself)
    Timer {
        interval: 8000
        repeat: true
        running: root.liveScan && root.enabled
        onTriggered: root.rescan()
    }

    Process {
        id: statusProc

        command: ["python3", "-I", root.script]
        onExited: {
            if (root.refreshAgain) {
                root.refreshAgain = false;
                Qt.callLater(root.refresh);
            }
        }

        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }

    }

    // Every change in NetworkManager -> read once again (debounced in NetworkEvents)
    Connections {
        function onChanged() {
            root.refresh();
        }

        target: NetworkEvents
    }

    Process {
        id: scanProc

        command: ["nmcli", "device", "wifi", "rescan"]
        // Results only come in after a few seconds: read twice more
        onExited: {
            root.refresh();
            scanDone.restart();
        }
    }

    Timer {
        id: scanDone

        interval: 3500
        onTriggered: {
            root.scanning = false;
            root.refresh();
        }
    }

    // While the window is open, load new networks
    Timer {
        interval: 20000
        repeat: true
        running: root.pickerVisible && root.enabled
        onTriggered: root.rescan()
    }

    Timer {
        id: scanAfterRadio

        // After turning on, the adapter needs a moment before it can scan
        interval: 1500
        onTriggered: root.rescan()
    }

    Process {
        id: connectProc

        property string ssid: ""
        property bool wasSaved: false
        property bool withPassword: false

        stderr: StdioCollector {
            id: connectErr
        }

        onExited: (code) => {
            const ssid = connectProc.ssid;
            root.connectingSsid = "";
            if (code === 0) {
                root.say("Connected to " + ssid, false);
            } else {
                const why = root.errorText(connectErr.text);
                // New network failed: remove the created profile again (otherwise a broken one stays)
                if (!connectProc.wasSaved) {
                    cleanupProc.command = ["nmcli", "connection", "delete", "id", ssid];
                    cleanupProc.running = true;
                }

                if (why === "wrong-password") {
                    root.prompt = {
                        "ssid": ssid,
                        "retry": connectProc.withPassword
                    };
                    root.say(connectProc.withPassword ? "Wrong password for " + ssid : ssid + " needs a password", true);
                } else {
                    root.say(why + "  ·  " + ssid, true);
                }
            }
            root.refresh();
        }
    }

    Process {
        id: cleanupProc

        onExited: root.refresh()
    }

    Process {
        id: actionProc

        property string okText: ""
        property var done: null

        stderr: StdioCollector {
            id: actionErr
        }

        onExited: (code) => {
            if (code === 0 && actionProc.okText !== "")
                root.say(actionProc.okText, false);
            else if (code !== 0)
                root.say(root.errorText(actionErr.text).replace("wrong-password", "Not allowed"), true);
            if (actionProc.done)
                actionProc.done();

            root.refresh();
        }
    }

    Timer {
        id: noticeTimer

        interval: 4200
        onTriggered: root.notice = ""
    }

    FileView {
        id: cfgFile

        path: MachineConfig.dir + "/wifi.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyOptions(text())
        onLoadFailed: root.applyOptions("")
    }

}
