import "../common"
import "../services"
import "./parts"
import QtQuick

// VPN server selection as a standalone window (not in the tab bundle with app, music,
// wallpaper): panel in space style like Wi-Fi/Bluetooth (parts/RadarPicker), with the planet (VpnGlobe) in it.
// Header: shield + status, compact search, plus (WireGuard import via yazi) and an on/off switch.
// Keys: arrows/Ctrl+J/K select on the globe, Enter connects/disconnects, Esc clears the search or closes,
// Tab is swallowed (no own tabs).
Item {
    id: root

    readonly property string mono: Theme.font
    readonly property real pad: 20
    // Narrow (portrait) screens: small side margin, otherwise there is hardly room for the planet next to the
    // pills. The height follows the width (there the width limits the planet, not the height)
    readonly property real panelWidth: Math.min(1480, width - (width < 1400 ? 24 : 96))
    readonly property real panelHeight: Math.min(1000, height - 100, Math.max(560, panelWidth * 0.72))
    property real shown: 0
    readonly property var filtered: {
        const q = PickerManager.searchText.toLowerCase();
        return VpnPickerState.connections.filter((c) => {
            return c.label.toLowerCase().includes(q) || c.name.toLowerCase().includes(q) || c.code.includes(q);
        });
    }
    readonly property var activeEntry: VpnPickerState.connections.find((c) => {
        return c.name === VpnPickerState.activeConnection;
    }) ?? null
    readonly property bool on: activeEntry !== null
    readonly property string subtitle: {
        if (VpnPickerState.busy)
            return VpnPickerState.pendingTo !== "" ? "Connecting…" : "Disconnecting…";
        if (VpnPickerState.importing)
            return "Importing configs…";
        if (on)
            return "Connected · " + activeEntry.label;
        return VpnPickerState.connections.length > 0 ? "Off · " + VpnPickerState.connections.length + " servers" : "No servers";
    }

    function focusSearch() {
        searchField.input.forceActiveFocus();
    }

    function activate(entry) {
        if (!entry)
            return;
        if (entry.name === VpnPickerState.activeConnection)
            VpnPickerState.disconnect();
        else
            VpnPickerState.connectTo(entry.name, true);
    }

    // Switch: connected -> disconnect; otherwise connect the selected (or last used) server
    function togglePower() {
        if (on) {
            VpnPickerState.disconnect();
            return;
        }
        const e = globe.selectedEntry;
        VpnPickerState.connectTo(e ? e.name : VpnPickerState.lastConnection, true);
    }

    function playIntro() {
        outroAnim.stop();
        introAnim.restart();
        VpnPickerState.refresh();
        Qt.callLater(() => globe.open());
    }

    function playOutro() {
        introAnim.stop();
        outroAnim.restart();
    }

    Component.onCompleted: playIntro()
    onVisibleChanged: {
        if (visible)
            playIntro();
    }

    Connections {
        target: PickerManager
        function onSearchTextChanged() {
            if (root.visible && root.filtered.length > 0 && PickerManager.searchText !== "")
                globe.select(root.filtered[0].name, true);
        }
    }

    NumberAnimation {
        id: introAnim

        target: root
        property: "shown"
        from: 0
        to: 1
        duration: 520
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    NumberAnimation {
        id: outroAnim

        target: root
        property: "shown"
        to: 0
        duration: 200
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.accelerate
    }

    // A click next to the panel closes
    MouseArea {
        anchors.fill: parent
        onClicked: PickerManager.close()
    }

    // ═════════════════════════ Panel ═════════════════════════
    Item {
        id: panel

        width: root.panelWidth
        height: root.panelHeight
        x: (root.width - width) / 2
        y: Math.max(40, (root.height - height) / 2) + (1 - root.shown) * 24
        opacity: Math.min(1, root.shown * 1.6)
        scale: 0.96 + 0.04 * root.shown
        transformOrigin: Item.Top

        SoftShadow {
            panel: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: WalColors.withAlpha(WalColors.color0, 0.97)
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.1)
        }

        // Clicks on the panel do not close, they only bring the focus back to the search
        MouseArea {
            anchors.fill: parent
            onClicked: root.focusSearch()
        }

        // Tilt of the globe also over the header, search bar and edge of the panel: the globe area only starts below
        // the header, there it lost the mouse (takes nothing away, only position)
        HoverHandler {
            onPointChanged: {
                if (hovered)
                    globe.trackPointer(panel, point.position);
            }
        }

        // ───────────── Planet ─────────────
        // Lies below the header: stars and halo run under the header line, the planet stands below it
        VpnGlobe {
            id: globe

            anchors.fill: parent
            anchors.topMargin: header.y + header.height
            anchors.margins: 12
            showStatus: false
            radiusFactor: 0.43
            servers: root.filtered
            allServers: VpnPickerState.connections
            activeName: VpnPickerState.activeConnection
            onActivated: (entry) => root.activate(entry)
        }

        // ───────────── Header ─────────────
        Item {
            id: header

            x: root.pad
            y: root.pad
            width: panel.width - 2 * root.pad
            height: 44

            Rectangle {
                id: badge

                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: height / 2
                color: root.on ? WalColors.withAlpha(Theme.good, 0.16) : WalColors.withAlpha(WalColors.color7, 0.06)

                Text {
                    anchors.centerIn: parent
                    text: root.on ? globe.icShield : globe.icShieldOff
                    font.family: root.mono
                    font.pixelSize: 19
                    color: root.on ? Theme.good : WalColors.withAlpha(WalColors.color7, 0.45)
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }

                }

            }

            Column {
                anchors.left: badge.right
                anchors.leftMargin: 12
                anchors.right: headerControls.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "VPN"
                    font.family: root.mono
                    font.pixelSize: 15
                    font.bold: true
                    color: WalColors.color7
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.subtitle
                    font.family: root.mono
                    font.pixelSize: 10
                    color: root.on ? WalColors.withAlpha(Theme.good, 0.85) : WalColors.withAlpha(WalColors.color7, 0.45)
                }

            }

            Row {
                id: headerControls

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                SearchField {
                    id: searchField

                    anchors.verticalCenter: parent.verticalCenter
                    width: 260
                    height: 38
                    placeholder: "Search countries…"
                    text: PickerManager.searchText
                    onTextChanged: PickerManager.searchText = text
                    onKeyPressed: (event) => {
                        // Ctrl+J/K = arrow down/up, the same in all pickers (PickerManager.navKey)
                        const key = PickerManager.navKey(event);
                        if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
                            // Standalone picker without own tabs: just swallow
                            event.accepted = true;
                        } else if (key >= Qt.Key_Left && key <= Qt.Key_Down) {
                            globe.navigate(key);
                            event.accepted = true;
                        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                            root.activate(globe.selectedEntry);
                            event.accepted = true;
                        } else if (key === Qt.Key_Escape) {
                            if (text !== "")
                                text = "";
                            else
                                PickerManager.close();
                            event.accepted = true;
                        }
                    }
                }

                // Add WireGuard configs (yazi), as before
                PickerAddButton {
                    anchors.verticalCenter: parent.verticalCenter
                    busy: VpnPickerState.importing
                    locked: VpnPickerState.importing
                    onClicked: VpnPickerState.startImport()
                }

                // On/off switch like Wi-Fi/Bluetooth
                Rectangle {
                    id: powerSwitch

                    anchors.verticalCenter: parent.verticalCenter
                    width: 50
                    height: 28
                    radius: height / 2
                    color: root.on ? Theme.good : WalColors.withAlpha(WalColors.color7, powerArea.containsMouse ? 0.16 : 0.1)
                    opacity: VpnPickerState.connections.length > 0 && !VpnPickerState.busy ? 1 : 0.5

                    Rectangle {
                        x: root.on ? parent.width - width - 4 : 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: height / 2
                        color: root.on ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.6)

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xf0425)
                            font.family: root.mono
                            font.pixelSize: 11
                            color: root.on ? Theme.good : WalColors.color0
                        }

                        Behavior on x {
                            Springy {
                            }

                        }

                    }

                    MouseArea {
                        id: powerArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.togglePower();
                            root.focusSearch();
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }

                    }

                }

            }

        }

    }

}
