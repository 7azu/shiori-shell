import "../services"
import QtQuick

// Slider in iOS style (image and video editor): label and value on top, below it a narrow track with
// a bright round knob. Drag/click sets, a double click reports (e.g. back to 0).
// zeroAt: the fill starts there (brightness & co. fill from the middle).
Item {
    id: vs

    property string label: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real value: 0
    property real zeroAt: from
    readonly property bool pressed: drag.pressed
    readonly property real k: Math.max(0, Math.min(1, (value - from) / (to - from)))
    readonly property real baseK: (zeroAt - from) / (to - from)
    // The knob must not stick out over the track: the travel is shorter by its diameter
    readonly property real knobSize: Theme.px(20)
    readonly property real travel: width - knobSize

    signal moved(real v)
    signal grabbed()
    signal released()
    signal doubleClicked()

    height: Theme.px(42)

    Text {
        text: vs.label
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeBody
        font.weight: Font.Medium
    }

    Text {
        anchors.right: parent.right
        text: vs.valueText
        // Moved off zero = highlighted, neutral = restrained
        color: Math.abs(vs.k - vs.baseK) > 0.001 ? Theme.accent : Theme.textDim
        font.family: Theme.fontUi
        font.features: Theme.tabular
        font.pixelSize: Theme.sizeBody
        font.weight: Font.Medium
    }

    Item {
        id: lane

        y: parent.height - height
        width: parent.width
        height: vs.knobSize

        Rectangle {
            x: vs.knobSize / 2
            anchors.verticalCenter: parent.verticalCenter
            width: vs.travel
            height: Theme.px(4)
            radius: height / 2
            color: Theme.tint(Theme.text, 0.14)

            Rectangle {
                x: Math.min(vs.k, vs.baseK) * parent.width
                width: Math.abs(vs.k - vs.baseK) * parent.width
                height: parent.height
                radius: height / 2
                color: Theme.accent
            }

            // Make the zero point in the middle visible
            Rectangle {
                x: vs.baseK * parent.width - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: Theme.px(8)
                radius: 1
                visible: vs.baseK > 0.001 && vs.baseK < 0.999
                color: Theme.tint(Theme.text, 0.3)
            }

        }

        // Soft shadow under the knob, so it stands out from the track
        Rectangle {
            x: vs.k * vs.travel - 1
            y: 1
            width: vs.knobSize + 2
            height: width
            radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.3)
        }

        Rectangle {
            x: vs.k * vs.travel
            width: vs.knobSize
            height: width
            radius: width / 2
            color: Theme.knob
            scale: vs.pressed ? 1.12 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: 120
                }

            }

        }

    }

    MouseArea {
        id: drag

        function apply(mx) {
            const t = Math.max(0, Math.min(1, (mx - vs.knobSize / 2) / Math.max(1, vs.travel)));
            vs.moved(vs.from + t * (vs.to - vs.from));
        }

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: (mouse) => {
            vs.grabbed();
            apply(mouse.x);
        }
        onPositionChanged: (mouse) => {
            apply(mouse.x);
        }
        onReleased: vs.released()
        onDoubleClicked: vs.doubleClicked()
    }

}
