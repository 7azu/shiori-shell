import "../services"
import QtQuick

// Sidebar of the editors in iOS style (image and video editor, built the same): header (MediaHeader with
// buttons in headerActions, properties via header.<name>), tools in grouped cards (tools; scroll
// if there is not enough room), fixed at the bottom the end (footer: main action and side actions).
// shownK: 1 = there, 0 = glided out of the card to the right (image: big view, video: player view).
Item {
    id: side

    property real shownK: 1
    // Color of the card below: the tool list fades its bottom edge into this color
    property color backColor: "transparent"
    property alias header: header
    property alias headerActions: header.actions
    property alias tools: tools.data
    property alias footer: footer.data
    // Subpage like an iOS push (e.g. "Compress" in the video editor): 1 = the tool list is pushed to the left
    // and hidden, the subpage lies above it in toolsArea
    property real pushK: 0
    readonly property alias toolsArea: toolsFlick

    anchors.right: parent.right
    anchors.rightMargin: 20 - (width + 40) * (1 - shownK)
    y: 20
    width: Theme.px(290)
    height: parent.height - 40
    opacity: shownK
    visible: shownK > 0.01

    MediaHeader {
        id: header

        width: parent.width
    }

    Flickable {
        id: toolsFlick

        x: -parent.width * 0.3 * side.pushK
        y: header.height + Theme.px(18)
        width: parent.width
        opacity: 1 - side.pushK
        visible: side.pushK < 0.99
        enabled: side.pushK === 0
        height: footer.y - y - Theme.px(16)
        contentHeight: tools.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: tools

            width: parent.width
            spacing: Theme.px(16)
        }

    }

    // If the list scrolls, the bottom edge fades out softly instead of a hard cut
    Rectangle {
        anchors.bottom: toolsFlick.bottom
        width: toolsFlick.width
        height: Theme.px(32)
        visible: toolsFlick.contentY < toolsFlick.contentHeight - toolsFlick.height - 1 && side.pushK < 0.99
        opacity: 1 - side.pushK

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.rgba(side.backColor.r, side.backColor.g, side.backColor.b, 0)
            }

            GradientStop {
                position: 1
                color: side.backColor
            }

        }

    }

    // ---------- End ----------
    Column {
        id: footer

        anchors.bottom: parent.bottom
        width: parent.width
        spacing: Theme.px(10)
    }

}
