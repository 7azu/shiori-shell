import "../../common"
import "../../services"
import QtQuick

// Segmented control of the pickers (task manager, clipboard, trash, language): pill with a gliding thumb.
// options = [{ key, label }], current = key; picked(key) on click. Optional sort arrow (showArrow/arrowUp).
Rectangle {
    id: seg

    property var options: []
    property string current: ""
    property real segW: 66
    property bool showArrow: false
    property bool arrowUp: false

    signal picked(string key)

    width: segW * options.length + 8
    radius: height / 2
    color: WalColors.withAlpha(WalColors.color7, 0.06)

    Rectangle {
        x: 4 + seg.segW * Math.max(0, seg.options.findIndex((o) => {
            return o.key === seg.current;
        }))
        y: 4
        width: seg.segW
        height: seg.height - 8
        radius: height / 2
        color: WalColors.withAlpha(WalColors.color7, 0.15)

        Behavior on x {
            Springy {
            }

        }

    }

    Row {
        x: 4

        Repeater {
            model: seg.options

            delegate: Item {
                id: option

                required property var modelData
                readonly property bool active: seg.current === modelData.key

                width: seg.segW
                height: seg.height

                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: option.modelData.label
                        font.family: Theme.font
                        font.pixelSize: seg.showArrow ? 11 : 12
                        font.bold: option.active
                        color: option.active ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.5)

                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                            }

                        }

                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: seg.showArrow && option.active
                        text: "↓"
                        font.pixelSize: 11
                        color: WalColors.color7
                        rotation: seg.arrowUp ? 180 : 0

                        Behavior on rotation {
                            Springy {
                            }

                        }

                    }

                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(option.modelData.key)
                }

            }

        }

    }

}
