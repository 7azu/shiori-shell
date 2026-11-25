import QtQuick

// Opening in iOS style for the cards of the image and video editor: the card grows from 90 % with a
// well damped spring (measured: ~0.4 % spring-back, almost at the target after ~200 ms, rest after 480 ms),
// lifts a few pixels meanwhile and fades in during the first ~100 ms. Hyprland fades in the dimming and blur itself (layer_rule "fade").
// Use on the card: scale: m.cardScale; opacity: m.cardOpacity; transform: Translate { y: m.rise }
Item {
    id: m

    // 0 = closed, 1 = open; overshoots briefly (OutBack), that is why the opacity is clamped
    property real k: 1
    readonly property real cardScale: 0.9 + 0.1 * k
    readonly property real cardOpacity: Math.max(0, Math.min(1, k * 1.4))
    readonly property real rise: 22 * (1 - k)

    // Before becoming visible: the card small and invisible until play() comes
    function reset() {
        anim.stop();
        k = 0;
    }

    // Calling it several times does no harm (the video editor calls it on every frame)
    function play() {
        if (k === 0 && !anim.running)
            anim.start();

    }

    visible: false

    NumberAnimation {
        id: anim

        target: m
        property: "k"
        from: 0
        to: 1
        duration: 480
        // Small overshoot = a spring with high damping like on iOS; the default (1.7) looks playful
        easing.type: Easing.OutBack
        easing.overshoot: 1.1
    }

}
