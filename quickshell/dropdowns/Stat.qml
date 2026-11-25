import "../services"
import QtQuick

// Key figure tile: optional symbol, value, LABEL. Built the same everywhere
// (VPN throughput, Claude tokens, battery details).
Card {
    id: stat

    property string glyph: ""
    property string value: ""
    property string label: ""
    property color tone: Theme.accent

    height: col.implicitHeight + 18

    Column {
        id: col

        anchors.centerIn: parent
        width: parent.width - 8
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: stat.glyph !== ""
            text: stat.glyph
            color: stat.tone
            font.family: Theme.font
            font.pixelSize: Theme.sizeBody + 2
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: stat.value
            color: Theme.text
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeBody + 1
            font.bold: true
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: stat.label.toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.bold: true
            font.letterSpacing: Theme.microSpacing
        }

    }

}
