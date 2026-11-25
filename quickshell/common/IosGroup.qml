import "../services"
import QtQuick
import Quickshell.Widgets

// Grouped card like in the iOS settings ("inset grouped"): a small heading, below it a
// rounded surface with rows (IosRow) or any content, optionally a hint below it.
// The surface clips, so hover areas of the rows follow the roundings.
Column {
    id: group

    property string title: ""
    property string footer: ""
    // Padding for free content (sliders, color dots); rows bring their own
    property int inset: 0
    // Without a surface: for content with its own background (segmented control), only the heading
    property bool plain: false
    // Action on the right in the heading (like "Revert" on iOS); empty = none
    property string actionText: ""
    property bool actionEnabled: true
    property color actionTone: Theme.accent
    default property alias content: body.data

    signal actionClicked()

    spacing: Theme.px(6)

    Item {
        width: group.width
        height: titleText.height
        visible: group.title !== "" || group.actionText !== ""

        Text {
            id: titleText

            x: Theme.px(4)
            text: group.title.toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.px(4)
            anchors.baseline: titleText.baseline
            visible: group.actionText !== ""
            text: group.actionText
            color: group.actionTone
            opacity: group.actionEnabled ? (actionMouse.containsMouse ? 0.75 : 1) : 0.35
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
            font.weight: Font.DemiBold

            MouseArea {
                id: actionMouse

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: group.actionEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (group.actionEnabled)
                        group.actionClicked();

                }
            }

        }

    }

    ClippingRectangle {
        width: group.width
        height: body.implicitHeight + 2 * group.inset
        radius: Theme.radiusGroup
        color: group.plain ? "transparent" : Theme.groupFill

        Column {
            id: body

            x: group.inset
            y: group.inset
            width: parent.width - 2 * group.inset
            spacing: group.inset > 0 ? Theme.px(10) : 0
        }

    }

    Text {
        x: Theme.px(4)
        width: group.width - Theme.px(8)
        visible: group.footer !== ""
        wrapMode: Text.WordWrap
        text: group.footer
        color: Theme.textFaint
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeSmall
    }

}
