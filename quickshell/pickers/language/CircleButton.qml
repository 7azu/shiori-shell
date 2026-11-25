import "../../common"
import "../../services"
import QtQuick

// Round button of the Listen tab (stage controls, video cards): glass, flat = only the symbol (glass only on
// hover), primary = bright play button, dark = dark glass for buttons on images.
Rectangle {
    id: rb

    property string glyph: ""
    property real size: 32
    property real glyphShift: 0
    property bool primary: false
    property bool flat: false
    property bool dark: false

    signal clicked()

    width: size
    height: size
    radius: size / 2
    color: primary ? (rbMouse.containsMouse ? Qt.rgba(1, 1, 1, 1) : Theme.knob) : dark ? Qt.rgba(0, 0, 0, rbMouse.containsMouse ? 0.7 : 0.5) : rbMouse.containsMouse ? Theme.glassHover : flat ? WalColors.withAlpha(WalColors.color7, 0) : Theme.glass
    scale: rbMouse.pressed ? 0.9 : 1

    Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: rb.glyphShift
        text: rb.glyph
        color: rb.primary ? WalColors.color0 : rb.dark ? "white" : Theme.text
        font.family: Theme.font
        font.pixelSize: rb.primary ? 15 : 13
    }

    MouseArea {
        id: rbMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rb.clicked()
    }

    Behavior on scale {
        Springy {
        }

    }

    Behavior on color {
        ColorAnimation {
            duration: 120
        }

    }

}
