import "../services"
import QtQuick

// Two rotate buttons side by side in an IosGroup, separated by a hairline (image and video editor)
Item {
    id: pair

    signal rotateLeft()
    signal rotateRight()

    width: parent ? parent.width : 0
    height: Theme.rowHeight

    IosRow {
        width: parent.width / 2
        divider: false
        centered: true
        glyph: ""
        title: "Left"
        onClicked: pair.rotateLeft()
    }

    IosRow {
        x: parent.width / 2
        width: parent.width / 2
        divider: false
        centered: true
        glyph: ""
        title: "Right"
        onClicked: pair.rotateRight()
    }

    Rectangle {
        x: parent.width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: parent.height * 0.5
        color: Theme.separator
    }

}
