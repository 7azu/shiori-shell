import "../services"
import QtQuick

// Number with a minus and a plus button (settings window): value, optional unit, steps of `step`.
Row {
    id: stepper

    property real value: 0
    property real min: 0
    property real max: 100
    property real step: 1
    property int decimals: 0
    property string unit: ""

    signal picked(real value)

    function nudge(dir) {
        // Whole steps, so 0.05 steps do not drift (0.30000000000000004)
        const next = Math.max(min, Math.min(max, Math.round((value + dir * step) / step) * step));
        const rounded = Number(next.toFixed(Math.max(decimals, 4)));
        if (rounded !== value)
            stepper.picked(rounded);

    }

    spacing: Theme.px(8)

    component StepButton: Rectangle {
        id: btn

        property string sign: ""
        property bool possible: true

        signal pressed()

        width: Theme.px(28)
        height: Theme.px(28)
        radius: Theme.px(8)
        color: Theme.tint(Theme.text, mouse.pressed && possible ? 0.16 : (mouse.containsMouse && possible ? 0.11 : 0.06))
        opacity: possible ? 1 : 0.35

        Text {
            anchors.centerIn: parent
            text: btn.sign
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLarge
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.possible ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.possible)
                    btn.pressed();

            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.px(52)
        horizontalAlignment: Text.AlignRight
        text: stepper.value.toFixed(stepper.decimals) + (stepper.unit !== "" ? " " + stepper.unit : "")
        color: Theme.text
        font.family: Theme.fontUi
        font.features: Theme.tabular
        font.pixelSize: Theme.sizeLead
    }

    StepButton {
        sign: "−"
        possible: stepper.value > stepper.min + 1e-06
        onPressed: stepper.nudge(-1)
    }

    StepButton {
        sign: "+"
        possible: stepper.value < stepper.max - 1e-06
        onPressed: stepper.nudge(1)
    }

}
