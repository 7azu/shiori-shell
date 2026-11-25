import "../services"
import QtQuick
import Quickshell
import Quickshell.Io

// Bar icon for the VPN dropdown; the status and location queries also run here (VpnState).
// Left click: VPN picker open/close. Disconnecting goes through the hover dropdown.
BarIcon {
    id: root

    readonly property string vpnPattern: "proton"
    // Icon options (all from Nerd Fonts Material Design):
    //   Connected:     󰦝 (shield-check)  |  󰒃 (security)  |  󰿄 (vpn-cloud)
    //   Disconnected:  󰦞 (shield-alert)  |  󰒄 (unsecured) |  󱚦 (vpn-off)
    readonly property string iconOn: "󰦝"
    readonly property string iconOff: "󰦞"
    // Deliberately soft colors: pywal slots with reduced opacity.
    //   color2 is the green slot in most schemes
    //   color1 is the red slot
    readonly property color colorOn: WalColors.withAlpha(WalColors.color2, 0.75)
    readonly property color colorOff: WalColors.withAlpha(WalColors.color1, 0.65)
    // Time of the last location query (ms)
    property double lastGeo: 0

    contentWidth: vpnText.implicitWidth
    onClicked: {
        DropdownState.dismiss();
        VpnPickerState.toggle();
    }
    Component.onCompleted: {
        statusProcess.running = true;
        geoProcess.running = true;
    }

    Connections {
        function onSwitched() {
            statusProcess.running = true;
            geoRefreshTimer.restart();
        }

        target: VpnPickerState
    }

    // Status only when NetworkManager reports a change (before: bash + nmcli + grep every 3 s).
    // The timer is a rare safety net in case a notification gets lost.
    Connections {
        function onChanged() {
            statusProcess.running = true;
        }

        target: NetworkEvents
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: statusProcess.running = true
    }

    // Fetch the location again when the connection changes (before: a request to ip-api every 30 s,
    // whether anything happened or not). Wait briefly: right after switching the tunnel is not up yet.
    Connections {
        function onConnectedChanged() {
            geoRefreshTimer.restart();
        }

        target: VpnState
    }

    // The dropdown opens and the data is older than 5 min -> refresh once
    Connections {
        function onCurrentChanged() {
            if (DropdownState.current === "vpn" && Date.now() - root.lastGeo > 300000)
                geoProcess.running = true;

        }

        target: DropdownState
    }

    Process {
        id: statusProcess

        command: ["bash", "-c", `nmcli connection show --active | grep -q '${root.vpnPattern}' && echo on || echo off`]

        stdout: StdioCollector {
            onStreamFinished: VpnState.connected = text.trim() === "on"
        }

    }

    Process {
        id: geoProcess

        // First line: name of the active WireGuard connection (proton-ch ...), then the ip-api JSON
        command: ["bash", "-c", "nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2==\"wireguard\"{print $1; exit}'; echo; curl -s 'http://ip-api.com/json?fields=status,country,countryCode,regionName,city,timezone,offset,isp,as,query'"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.lastGeo = Date.now();
                try {
                    const nl = text.indexOf("\n");
                    const vpnName = text.slice(0, nl).trim();
                    const data = JSON.parse(text.slice(nl + 1).trim());
                    // The country from the connection name takes precedence: Proton's server country is always right, ip-api
                    // sometimes places VPN addresses (M247) wrong (CH servers as "Stockholm, Sweden").
                    // Then city/region from ip-api are wrong too -> leave them empty instead of showing something wrong.
                    const code = VpnPickerState.codeOf(vpnName);
                    const geoOk = code === "" || code === (data.countryCode ?? "").toLowerCase();
                    VpnState.vpnCity = geoOk ? (data.city ?? "") : "";
                    VpnState.vpnCountry = geoOk ? (data.country ?? "") : (VpnPickerState.countryNames[code] ?? code.toUpperCase());
                    VpnState.vpnOrg = data.isp ?? "";
                    VpnState.vpnIp = data.query ?? "";
                    VpnState.vpnCountryCode = geoOk ? (data.countryCode ?? "") : code.toUpperCase();
                    VpnState.vpnRegion = geoOk ? (data.regionName ?? "") : "";
                    VpnState.vpnTimezone = data.timezone ?? "";
                    VpnState.vpnUtcOffset = data.offset ?? 0;
                    VpnState.vpnAs = data.as ?? "";
                } catch (e) {
                    console.warn("VpnToggle: could not parse the geo lookup:", e);
                }
            }
        }

    }

    Timer {
        id: geoRefreshTimer

        interval: 2000
        onTriggered: geoProcess.running = true
    }

    BarGlyph {
        id: vpnText

        anchors.centerIn: parent
        text: VpnState.connected ? root.iconOn : root.iconOff
        color: VpnState.connected ? root.colorOn : root.colorOff
        font.pixelSize: 17
        hot: root.hovered

        // Soft color morph on a state change (instead of a hard switch)
        Behavior on color {
            ColorAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }

        }

    }

}
