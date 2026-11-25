import QtQuick
pragma Singleton

QtObject {
    id: root

    property bool connected: false
    property string vpnCity: ""
    property string vpnCountry: ""
    property string vpnOrg: ""
    property string vpnIp: ""
    // Also from ip-api: for the flag, local time at the VPN location and network
    property string vpnCountryCode: ""
    property string vpnRegion: ""
    property string vpnTimezone: ""
    property int vpnUtcOffset: 0 // Sekunden
    property string vpnAs: ""
    // Status of the killswitch
    property bool killswitchEnabled: false
}
