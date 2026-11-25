import "../services"
import QtQuick

// Bar icon for the audio dropdown. Left click = music picker; right-click deliberately does nothing
// (it used to open the volume popup, that was annoying on misclicks).
BarIcon {
    id: root

    contentWidth: glyph.implicitWidth
    acceptedButtons: Qt.LeftButton
    onClicked: MusicPickerState.toggle()

    BarGlyph {
        id: glyph

        anchors.centerIn: parent
        text: ""
        font.pixelSize: 14
        hot: root.hovered
    }

}
