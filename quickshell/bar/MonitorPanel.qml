import "../services"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Monitor panel of the bar: choose the bar monitor. Sits in the morphing shape of the MainBar.
Item {
    id: monClip

    // The bar the panel belongs to: state and logic (morph, selection ...) live there
    required property var mainBar
    // Current height of the morphing shape (the panel is clipped to it)
    property real shapeHeight: 0
    // Natural height of the content (decides how far the shape opens)
    readonly property real contentHeight: monColumn.implicitHeight

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    width: mainBar.monBodyWidth
    height: shapeHeight
    clip: true
    opacity: mainBar.monContentOpacity
    visible: opacity > 0.01
    enabled: mainBar.monitorsOpen && mainBar.pendingBarScreen === ""
    focus: mainBar.monitorsOpen
    Keys.onPressed: (event) => {
        const n = mainBar.monScreens.length;
        event.accepted = true;
        switch (event.key) {
        case Qt.Key_Escape:
            mainBar.closePanels();
            break;
        case Qt.Key_Left:
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            if (n > 0)
                mainBar.monKbIndex = (mainBar.monKbIndex - 1 + n) % n;

            break;
        case Qt.Key_Right:
        case Qt.Key_Down:
        case Qt.Key_Tab:
            if (n > 0)
                mainBar.monKbIndex = (mainBar.monKbIndex + 1) % n;

            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (mainBar.monKbIndex >= 0 && mainBar.monKbIndex < n)
                mainBar.pickBarScreen(mainBar.monScreens[mainBar.monKbIndex].name);

            break;
        default:
            event.accepted = false;
        }
    }

    Column {
        id: monColumn

        width: mainBar.monBodyWidth - 2 * mainBar.calPad
        topPadding: 14
        spacing: 10

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        // Kopfzeile
        Item {
            width: parent.width
            height: 36

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "Displays"
                    color: WalColors.color2
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeHeading
                    font.bold: true
                }

                Text {
                    text: "Choose where the bar lives"
                    color: WalColors.withAlpha(WalColors.color7, 0.55)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                }

            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                height: 22
                radius: height / 2
                width: countText.implicitWidth + 18
                color: WalColors.withAlpha(WalColors.color4, 0.14)

                Text {
                    id: countText

                    anchors.centerIn: parent
                    text: mainBar.monScreens.length + " connected"
                    color: WalColors.color4
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    font.features: Theme.tabular
                    font.bold: true
                }

            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: WalColors.withAlpha(WalColors.color7, 0.1)
        }

        // Monitor arrangement as in Hyprland, true to scale
        Item {
            id: monLayout

            readonly property var bounds: mainBar.monBounds(mainBar.monScreens)
            readonly property real maxH: 190
            readonly property real scaleF: Math.min(width / bounds.w, maxH / bounds.h)
            readonly property real offX: (width - bounds.w * scaleF) / 2
            readonly property real gap: 3

            width: parent.width
            height: Math.round(bounds.h * scaleF)

            Repeater {
                model: mainBar.monScreens

                delegate: Item {
                    id: tile

                    required property var modelData
                    required property int index
                    readonly property var info: mainBar.monInfo(modelData)
                    readonly property bool isBar: modelData.name === mainBar.monBarName
                    readonly property bool hot: tileMouse.containsMouse || mainBar.monKbIndex === index

                    x: monLayout.offX + (modelData.x - monLayout.bounds.x) * monLayout.scaleF + monLayout.gap
                    y: (modelData.y - monLayout.bounds.y) * monLayout.scaleF + monLayout.gap
                    width: modelData.width * monLayout.scaleF - 2 * monLayout.gap
                    height: modelData.height * monLayout.scaleF - 2 * monLayout.gap

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        antialiasing: true
                        color: tile.isBar ? WalColors.withAlpha(WalColors.color4, 0.18) : (tile.hot ? WalColors.withAlpha(WalColors.color2, 0.14) : WalColors.withAlpha(WalColors.color7, 0.05))
                        border.width: tile.isBar ? 1.6 : 1
                        border.color: tile.isBar ? WalColors.color4 : (tile.hot ? WalColors.withAlpha(WalColors.color4, 0.55) : WalColors.withAlpha(WalColors.color7, 0.16))
                        scale: tileMouse.pressed ? 0.97 : (tile.hot ? 1.02 : 1)

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    // Mini bar: shows where the bar sits (glides over on selection)
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 4
                        radius: 2
                        width: tile.isBar ? tile.width - 16 : 0
                        opacity: tile.isBar ? 1 : 0
                        color: WalColors.color4

                        Behavior on width {
                            NumberAnimation {
                                duration: 380
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.3
                            }

                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                            }

                        }

                    }

                    Column {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 3
                        spacing: 1

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.name
                            color: tile.isBar ? WalColors.color4 : WalColors.color7
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeLabel
                            font.bold: true
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(implicitWidth, tile.width - 12)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            visible: tile.height > 64 && text !== ""
                            text: tile.info.model
                            color: WalColors.withAlpha(WalColors.color7, 0.55)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: tile.height > 46
                            text: tile.info.res
                            color: WalColors.withAlpha(WalColors.color7, 0.4)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                            font.features: Theme.tabular
                        }

                    }

                    MouseArea {
                        id: tileMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: mainBar.monKbIndex = tile.index
                        onClicked: mainBar.pickBarScreen(tile.modelData.name)
                    }

                }

            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: WalColors.withAlpha(WalColors.color7, 0.1)
        }

        // Details of the hovered / selected monitor
        Item {
            id: monDetails

            readonly property var info: mainBar.monInfo(mainBar.monInfoScreen)
            readonly property string name: mainBar.monInfoScreen ? mainBar.monInfoScreen.name : ""

            width: parent.width
            height: 36

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.right: monRight.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Row {
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: monDetails.name
                        color: WalColors.color2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeLead
                        font.bold: true
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: monDetails.name === mainBar.monBarName
                        height: 16
                        radius: height / 2
                        width: barTag.implicitWidth + 12
                        color: WalColors.color4

                        Text {
                            id: barTag

                            anchors.centerIn: parent
                            text: "bar"
                            color: WalColors.color0
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                            font.bold: true
                        }

                    }

                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: monDetails.info.desc
                    color: WalColors.withAlpha(WalColors.color7, 0.55)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                }

            }

            Column {
                id: monRight

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    anchors.right: parent.right
                    text: monDetails.info.hz > 0 ? monDetails.info.hz + " Hz" : ""
                    color: WalColors.color4
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLead
                    font.features: Theme.tabular
                    font.bold: true
                }

                Text {
                    anchors.right: parent.right
                    text: monDetails.info.res + "  ·  ×" + monDetails.info.scale.toFixed(2)
                    color: WalColors.withAlpha(WalColors.color7, 0.45)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    font.features: Theme.tabular
                }

            }

        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "click a display  ·  ←/→ + enter  ·  esc"
            color: WalColors.withAlpha(WalColors.color7, 0.3)
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
        }

    }

}
