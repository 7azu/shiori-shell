import "../common"
import "../services"
import QtQuick

// Bar icon and remaining limit of the active provider. Right-click refreshes the data.
BarIcon {
    id: root

    readonly property var provider: AiUsageState.provider
    readonly property var usage: provider.usage()
    readonly property int switchDuration: 320
    readonly property int iconSize: 18
    readonly property int labelGap: 5

    function percentLabel(limit) {
        return limit.known ? Math.round(limit.left) + "%" : "";
    }

    pillExtra: 10
    padding: 8
    contentWidth: content.width
    acceptedButtons: Qt.RightButton
    onClicked: usage.refresh()

    TextMetrics {
        id: percentMetrics

        font.family: Theme.font
        font.pixelSize: 12
        font.bold: true
        text: root.percentLabel(root.usage.five)
    }

    Item {
        id: content

        anchors.centerIn: parent
        width: root.iconSize + (percentMetrics.text ? root.labelGap + Math.ceil(percentMetrics.advanceWidth) : 0)
        height: root.iconSize

        Behavior on width {
            NumberAnimation {
                duration: root.switchDuration
                easing.type: Easing.InOutCubic
            }
        }

        Repeater {
            model: AiUsageState.providers

            delegate: Item {
                id: providerLayer

                required property var modelData
                readonly property var limit: modelData.usage().five
                property real blend: modelData.key === root.provider.key ? 1 : 0

                width: content.width
                height: content.height
                // On machines with simpleAnimations (laptop, 60 Hz) only crossfade
                readonly property real motion: MachineConfig.simpleAnimations ? 0 : 1 - blend
                y: -2 * motion
                visible: blend > 0
                opacity: blend

                Behavior on blend {
                    NumberAnimation {
                        duration: root.switchDuration
                        easing.type: Easing.InOutCubic
                    }
                }

                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconSize
                    height: root.iconSize
                    source: providerLayer.modelData.icon
                    onLoaded: item.color = Qt.binding(() => WalColors.vividAccent)

                    property real hoverScale: root.hovered ? 1.3 : 1
                    property real hoverAngle: root.hovered ? providerLayer.modelData.hoverRotation : 0
                    scale: hoverScale * (1 - 0.12 * providerLayer.motion)
                    rotation: hoverAngle - 12 * providerLayer.motion

                    Behavior on hoverScale {
                        NumberAnimation {
                            duration: Appearance.anim.durations.fast
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on hoverAngle {
                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutBack
                        }
                    }
                }

                Text {
                    x: root.iconSize + root.labelGap
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: providerLayer.limit.known ? 1 : 0
                    text: root.percentLabel(providerLayer.limit)
                    color: WalColors.color2
                    font: percentMetrics.font

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.switchDuration
                            easing.type: Easing.InOutCubic
                        }
                    }
                }
            }
        }
    }
}
