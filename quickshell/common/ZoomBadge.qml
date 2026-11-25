import "../services"
import QtQuick

// Small badge with the zoom level (image and video editor), only fades in while zooming
Rectangle {
    id: root

    property bool shown: false
    property real percent: 100

    width: label.implicitWidth + 20
    height: 24
    radius: height / 2
    color: WalColors.withAlpha(WalColors.color0, 0.8)
    border.width: 1
    border.color: Theme.stroke
    opacity: shown ? 1 : 0
    visible: opacity > 0.01

    Text {
        id: label

        anchors.centerIn: parent
        text: Math.round(root.percent) + " %"
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeSmall
        font.weight: Font.DemiBold
        font.features: {
            "tnum": 1
        }
    }

    Behavior on opacity {
        Anim {
            duration: Appearance.anim.durations.fast
        }

    }

}
