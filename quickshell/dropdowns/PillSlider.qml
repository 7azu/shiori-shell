import "../services"
import QtQuick
import Quickshell.Widgets

// Slider as a pill (volume, brightness): symbol on the left (clickable), fill in the accent color,
// percent on the right. Drag/click sets, the mouse wheel steps by 5%.
Item {
    id: slider

    property real value: 0 // 0..1
    property string glyph: ""
    property color glyphColor: Theme.text
    property string label: "" // appears before the percentage on hover
    property string valueText: "" // shown instead of the percentage (e.g. "4000 K")
    readonly property bool pressed: area.pressed
    readonly property bool active: area.containsMouse || area.pressed
    readonly property real iconW: 30

    signal moved(real v)
    signal stepped(real delta)
    signal iconClicked()
    signal doubleClicked()

    height: Theme.controlHeight

    ClippingRectangle {
        anchors.fill: parent
        radius: height / 2
        color: slider.active ? Theme.cardHover : Theme.card
        border.width: 1
        border.color: Theme.stroke

        Rectangle {
            width: Math.max(parent.height, parent.width * slider.value)
            height: parent.height
            radius: height / 2
            visible: slider.value > 0.005

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Theme.tint(Theme.accent, 0.25)
                }

                GradientStop {
                    position: 1
                    color: Theme.tint(Theme.accent, slider.pressed ? 0.65 : 0.5)
                }

            }

            Behavior on width {
                enabled: !slider.pressed

                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        text: slider.glyph
        color: slider.glyphColor
        font.family: Theme.font
        font.pixelSize: Theme.sizeBody + 3

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: slider.iconClicked()
        }

    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            anchors.baseline: pct.baseline
            visible: slider.label !== ""
            text: slider.label.toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.bold: true
            font.letterSpacing: Theme.microSpacing
            opacity: slider.active ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        Text {
            id: pct

            text: slider.valueText !== "" ? slider.valueText : Math.round(slider.value * 100) + "%"
            color: Theme.text
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeBody
            font.bold: true
        }

    }

    MouseArea {
        id: area

        // x in coordinates of the whole pill -> the same scale as the fill
        function valueAt(x) {
            return Math.max(0, Math.min(1, (x + slider.iconW) / slider.width));
        }

        anchors.fill: parent
        anchors.leftMargin: slider.iconW
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (mouse) => {
            return slider.moved(valueAt(mouse.x));
        }
        onPositionChanged: (mouse) => {
            if (pressed)
                slider.moved(valueAt(mouse.x));

        }
        onDoubleClicked: slider.doubleClicked()
        onWheel: (wheel) => {
            return slider.stepped(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
        }
    }

}
