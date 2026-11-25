import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    // ---- Picker state ----
    // The picker is a tab in the picker window (PickerManager, search: PickerManager.searchText)
    readonly property bool open: PickerManager.isOpen("vpn")
    // ---- VPN data ----
    // [{ name: "proton-nl", code: "nl", label: "Netherlands" }, ...]
    property var connections: []
    property string activeConnection: ""
    property string lastConnection: "proton"
    // Connection last saved in ~/.cache/vpn-last (restored at login by
    // ~/.config/hypr/scripts/vpn-state.sh restore)
    property string savedConnection: ""
    property bool busy: false
    // Stable end points for the animation; a refresh may overwrite lastConnection.
    property string pendingFrom: ""
    property string pendingTo: ""
    // true while the import runs
    property bool importing: false
    readonly property string importScript: Qt.resolvedUrl("../scripts/vpn_pick.sh").toString().replace("file://", "")
    readonly property var countryNames: ({
        "at": "Austria",
        "au": "Australia",
        "be": "Belgium",
        "bg": "Bulgaria",
        "br": "Brazil",
        "ca": "Canada",
        "ch": "Switzerland",
        "cz": "Czechia",
        "de": "Germany",
        "dk": "Denmark",
        "ee": "Estonia",
        "es": "Spain",
        "fi": "Finland",
        "fr": "France",
        "gb": "United Kingdom",
        "uk": "United Kingdom",
        "gr": "Greece",
        "hk": "Hong Kong",
        "hr": "Croatia",
        "hu": "Hungary",
        "ie": "Ireland",
        "il": "Israel",
        "in": "India",
        "is": "Iceland",
        "it": "Italy",
        "jp": "Japan",
        "kr": "South Korea",
        "li": "Liechtenstein",
        "lt": "Lithuania",
        "lu": "Luxembourg",
        "lv": "Latvia",
        "mx": "Mexico",
        "nl": "Netherlands",
        "no": "Norway",
        "nz": "New Zealand",
        "pl": "Poland",
        "pt": "Portugal",
        "ro": "Romania",
        "rs": "Serbia",
        "ru": "Russia",
        "se": "Sweden",
        "sg": "Singapore",
        "sk": "Slovakia",
        "tr": "Turkey",
        "ua": "Ukraine",
        "us": "USA",
        "za": "South Africa"
    })

    // Location of the servers for the globe: [latitude, longitude] of the city where the servers usually are
    readonly property var countryCoords: ({
        "at": [48.21, 16.37],
        "au": [-33.87, 151.21],
        "be": [50.85, 4.35],
        "bg": [42.7, 23.32],
        "br": [-23.55, -46.63],
        "ca": [43.65, -79.38],
        "ch": [47.37, 8.54],
        "cz": [50.08, 14.44],
        "de": [50.11, 8.68],
        "dk": [55.68, 12.57],
        "ee": [59.44, 24.75],
        "es": [40.42, -3.7],
        "fi": [60.17, 24.94],
        "fr": [48.86, 2.35],
        "gb": [51.51, -0.13],
        "uk": [51.51, -0.13],
        "gr": [37.98, 23.73],
        "hk": [22.32, 114.17],
        "hr": [45.81, 15.98],
        "hu": [47.5, 19.04],
        "ie": [53.35, -6.26],
        "il": [32.08, 34.78],
        "in": [19.08, 72.88],
        "is": [64.15, -21.94],
        "it": [45.46, 9.19],
        "jp": [35.68, 139.69],
        "kr": [37.57, 126.98],
        "li": [47.14, 9.52],
        "lt": [54.69, 25.28],
        "lu": [49.61, 6.13],
        "lv": [56.95, 24.11],
        "mx": [19.43, -99.13],
        "nl": [52.37, 4.9],
        "no": [59.91, 10.75],
        "nz": [-36.85, 174.76],
        "pl": [52.23, 21.01],
        "pt": [38.72, -9.14],
        "ro": [44.43, 26.1],
        "rs": [44.79, 20.45],
        "ru": [55.76, 37.62],
        "se": [59.33, 18.07],
        "sg": [1.35, 103.82],
        "sk": [48.15, 17.11],
        "tr": [41.01, 28.98],
        "ua": [50.45, 30.52],
        "us": [40.71, -74.01],
        "za": [-26.2, 28.05]
    })
    // The globe was open once -> from then on PickerWindow keeps its map in memory
    property bool globeUsed: false

    signal switched()
    // "proton-nl" -> "nl"
    function codeOf(name) {
        const m = /^proton-([a-z]{2})(?:[-_.]|$)/i.exec(name);
        return m ? m[1].toLowerCase() : "";
    }

    function labelOf(name, code) {
        if (code !== "")
            return countryNames[code] ?? code.toUpperCase();

        return name;
    }

    function openPicker() {
        refresh();
        PickerManager.open("vpn");
    }

    function close() {
        if (open)
            PickerManager.close();

    }

    function toggle() {
        if (open)
            close();
        else
            openPicker();
    }

    function refresh() {
        listProcess.running = true;
    }

    function saveLast(name) {
        if (name === "" || name === savedConnection)
            return ;

        savedConnection = name;
        saveProcess.command = ["bash", "-c", 'mkdir -p "$HOME/.cache" && printf "%s\\n" "$1" > "$HOME/.cache/vpn-last"', "_", name];
        saveProcess.running = true;
    }

    // Yazi takes over the selection; the script waits until the import ends.
    function startImport() {
        if (importing || busy)
            return;
        importing = true;
        close();
        importProcess.command = ["bash", importScript];
        importProcess.running = true;
    }

    // Switch to the selected connection (old one is taken down first)
    // keepOpen: the picker stays open and shows the switch (that is how the VPN picker itself calls it)
    function connectTo(name, keepOpen) {
        if (busy || name === "")
            return ;

        lastConnection = name;
        if (name === activeConnection) {
            if (!keepOpen)
                close();

            return ;
        }
        pendingFrom = activeConnection;
        pendingTo = name;
        busy = true;
        switchProcess.command = ["bash", "-c", 'if [ -n "$1" ]; then nmcli connection down "$1" >/dev/null 2>&1; fi; nmcli connection up "$2"', "_", activeConnection, name];
        switchProcess.running = true;
        if (!keepOpen)
            close();

    }

    // Disconnect the active connection (the picker stays open and then shows "Exposed")
    function disconnect() {
        if (busy || activeConnection === "")
            return ;

        pendingFrom = activeConnection;
        pendingTo = "";
        busy = true;
        switchProcess.command = ["nmcli", "connection", "down", activeConnection];
        switchProcess.running = true;
    }

    // Load the saved connection first, then fetch the list
    Component.onCompleted: loadProcess.running = true

    // NetworkManager reports every change (NetworkEvents); the timer is only a rare
    // safety net in case a notification gets lost (before: two nmcli calls every 5 s)
    Connections {
        function onChanged() {
            root.refresh();
        }

        target: NetworkEvents
    }

    Timer {
        interval: 60000
        // Safety net besides NetworkEvents; not needed while the VPN icon is hidden (edit mode)
        running: BarIcons.shown("vpn")
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: importProcess

        onRunningChanged: {
            if (!running && root.importing) {
                root.importing = false;
                root.openPicker();
            }
        }
    }

    Process {
        id: loadProcess

        command: ["bash", "-c", 'printf "%s\\n" "$(head -n 1 "$HOME/.cache/vpn-last" 2>/dev/null)"']
        onRunningChanged: {
            if (!running)
                root.refresh();

        }

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n");
                const name = parts[0].trim();
                if (name !== "") {
                    root.savedConnection = name;
                    root.lastConnection = name;
                }
            }
        }

    }

    Process {
        id: saveProcess
    }

    Process {
        id: listProcess

        command: ["bash", "-c", "nmcli -t -f NAME,TYPE connection show; echo '---'; nmcli -t -f NAME,TYPE connection show --active"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                let inActive = false;
                const all = [];
                let active = "";
                for (const line of lines) {
                    if (line.trim() === "---") {
                        inActive = true;
                        continue;
                    }
                    if (!line.endsWith(":wireguard"))
                        continue;

                    const name = line.slice(0, line.length - ":wireguard".length);
                    if (inActive) {
                        if (active === "")
                            active = name;

                    } else {
                        const code = root.codeOf(name);
                        all.push({
                            "name": name,
                            "code": code,
                            "label": root.labelOf(name, code)
                        });
                    }
                }
                all.sort((a, b) => {
                    return a.label.localeCompare(b.label, "en");
                });
                if (JSON.stringify(all) !== JSON.stringify(root.connections))
                    root.connections = all;

                root.activeConnection = active;
                if (active !== "") {
                    root.lastConnection = active;
                    root.saveLast(active);
                } else if (!all.some((c) => {
                    return c.name === root.lastConnection;
                }) && all.length > 0)
                    root.lastConnection = all[0].name;
            }
        }

    }

    Process {
        id: switchProcess

        onRunningChanged: {
            if (!running) {
                root.busy = false;
                root.pendingFrom = "";
                root.pendingTo = "";
                root.refresh();
                root.switched();
            }
        }
    }

}
