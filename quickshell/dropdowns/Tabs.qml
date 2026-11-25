import "../services"
import QtQuick

// Tab bar: plain labels on a fine base line, below them a short accent line glides
// to the active tab. Deliberately without a pill/frame (minimalist). model = [{ key, label, dim? }]
Item {
    id: tabs

    property var model: []
    property var current: "" // key of the active tab (text or number)
    property bool showLine: true // fine base line under all tabs
    readonly property int activeIndex: {
        for (let i = 0; i < model.length; ++i) {
            if (model[i].key === current)
                return i;

        }
        return 0;
    }
    readonly property real slotW: width / Math.max(1, model.length)
    // Fixed width: only x animated (fine elements whose size animates tremble)
    readonly property real markW: Math.round(Theme.sizeBody * 1.6)

    signal selected(var key)

    height: Theme.controlHeight

    // Base line over the whole width (turned off in the trash, only the accent line there)
    Rectangle {
        visible: tabs.showLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.separator
    }

    // Gliding line under the active tab
    Rectangle {
        x: tabs.activeIndex * tabs.slotW + (tabs.slotW - width) / 2
        anchors.bottom: parent.bottom
        width: tabs.markW
        height: 2
        radius: 1
        color: Theme.accent

        Behavior on x {
            NumberAnimation {
                duration: 420
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.outQuint
            }

        }

    }

    Row {
        Repeater {
            model: tabs.model

            delegate: Item {
                id: tab

                required property var modelData
                required property int index
                readonly property bool active: tabs.activeIndex === index

                width: tabs.slotW
                height: tabs.height
                opacity: modelData.dim && !active ? 0.4 : 1

                Text {
                    anchors.centerIn: parent
                    // 1 px higher: optically centered between the top edge and the line
                    anchors.verticalCenterOffset: -1
                    text: tab.modelData.label
                    color: tab.active ? Theme.text : (tabMouse.containsMouse ? Theme.tint(Theme.text, 0.8) : Theme.textFaint)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                    font.weight: Font.Medium
                    font.letterSpacing: 0.4

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

                MouseArea {
                    id: tabMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tabs.selected(tab.modelData.key)
                }

            }

        }

    }

}
