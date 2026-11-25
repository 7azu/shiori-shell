import "../services"
import QtQuick

// Bar icon for the stats dropdown (CPU, GPU, RAM, drives).
// Other symbols to choose from: 󰘚 chip (CPU), 󰍛 memory (RAM), 󰔻 gauge
BarIcon {
    id: root

    contentWidth: glyph.implicitWidth

    BarGlyph {
        id: glyph

        anchors.centerIn: parent
        text: "󰓅"
        hot: root.hovered
    }

}
