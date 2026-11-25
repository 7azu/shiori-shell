import "../services"
import QtQuick

// Bar icon for the battery dropdown: battery symbol by charge (with a bolt when charging) + percent.
// Without a laptop battery (desktop PC): plug symbol without a number.
BarIcon {
    id: root

    readonly property var levelGlyphs: ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    readonly property var chargeGlyphs: ["󰢟", "󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    readonly property string glyph: {
        if (!BatteryState.hasBattery)
            return "󰚥";

        const i = Math.round(BatteryState.percent / 10);
        return (BatteryState.charging || BatteryState.full) ? chargeGlyphs[i] : levelGlyphs[i];
    }
    readonly property color ink: WalColors.color2

    // With the percentage less padding (as with Claude): the number brings no air of its own,
    // instead the hover pill is pillExtra wider than the tile (see MainBar)
    pillExtra: BatteryState.hasBattery ? 10 : 0
    padding: BatteryState.hasBattery ? 10 : 16
    contentWidth: content.implicitWidth

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 4

        BarGlyph {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            color: root.ink
            hot: root.hovered
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: BatteryState.hasBattery
            text: Math.round(BatteryState.percent) + "%"
            color: root.ink
            font.family: Theme.font
            font.pixelSize: 12
            font.bold: true
        }

    }

}
