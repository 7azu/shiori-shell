import "../services"
import QtQuick

// Segmented control like on iOS: a track with a bright thumb that glides to the selection.
// items = [{ text, glyph }]; currentIndex = -1 -> no thumb (a plain action bar, e.g. rotate:
// then the pressed segment only flashes briefly).
Item {
    id: seg

    property var items: []
    property int currentIndex: -1
    readonly property real segW: items.length > 0 ? (width - 4) / items.length : 0

    signal activated(int index)

    height: Theme.px(34)

    Rectangle {
        anchors.fill: parent
        radius: Theme.px(10)
        color: Theme.groupFill
    }

    // Separators between segments, not next to the thumb (like on iOS)
    Repeater {
        model: Math.max(0, seg.items.length - 1)

        Rectangle {
            required property int index
            readonly property bool nearThumb: seg.currentIndex === index || seg.currentIndex === index + 1

            x: 2 + seg.segW * (index + 1)
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height * 0.45
            color: Theme.separator
            opacity: nearThumb ? 0 : 1
        }

    }

    Rectangle {
        id: thumb

        x: 2 + seg.segW * Math.max(0, seg.currentIndex)
        y: 2
        width: seg.segW
        height: parent.height - 4
        radius: Theme.px(8)
        visible: seg.currentIndex >= 0
        color: Theme.tint(Theme.text, 0.17)
        border.width: 1
        border.color: Theme.tint(Theme.text, 0.08)

        Behavior on x {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }

        }

    }

    Row {
        x: 2
        height: parent.height

        Repeater {
            model: seg.items

            delegate: Item {
                id: cell

                required property var modelData
                required property int index
                readonly property bool selected: seg.currentIndex === index

                width: seg.segW
                height: parent.height

                // Action bar without a thumb: short press background
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Theme.px(8)
                    color: Theme.groupPressed
                    opacity: seg.currentIndex < 0 && cellMouse.pressed ? 1 : (seg.currentIndex < 0 && cellMouse.containsMouse ? 0.5 : 0)
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.px(6)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (cell.modelData.glyph || "") !== ""
                        text: cell.modelData.glyph || ""
                        color: cell.selected || cellMouse.containsMouse ? Theme.text : Theme.textDim
                        font.family: Theme.font
                        font.pixelSize: Theme.sizeBody + 1
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (cell.modelData.text || "") !== ""
                        text: cell.modelData.text || ""
                        color: cell.selected || cellMouse.containsMouse ? Theme.text : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                        font.weight: cell.selected ? Font.DemiBold : Font.Medium
                        font.features: Theme.tabular
                    }

                }

                MouseArea {
                    id: cellMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.activated(cell.index)
                }

            }

        }

    }

}
