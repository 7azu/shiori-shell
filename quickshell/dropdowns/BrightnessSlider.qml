import "../services"
import QtQuick

// Brightness for the battery dropdown, the same slider as the volume.
// Drag/click = set, mouse wheel = +-5%, double click = 100%.
PillSlider {
    id: slider

    // While dragging the display follows the mouse directly, otherwise the system value
    property real dragValue: 0

    value: pressed ? dragValue : BrightnessState.level
    glyph: value < 0.34 ? "󰃞" : (value < 0.67 ? "󰃟" : "󰃠")
    label: "brightness"
    onMoved: (v) => {
        dragValue = Math.max(BrightnessState.minLevel, v);
        BrightnessState.set(dragValue);
    }
    onStepped: (d) => {
        return BrightnessState.step(d);
    }
    onDoubleClicked: BrightnessState.set(1)
    onIconClicked: BrightnessState.set(value < 0.5 ? 1 : BrightnessState.minLevel)

    // Follow values set from outside by brightness keys or similar
    Timer {
        interval: 700
        repeat: true
        running: slider.visible && !slider.pressed
        triggeredOnStart: true
        onTriggered: BrightnessState.refresh()
    }

}
