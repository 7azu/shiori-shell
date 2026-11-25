pragma ComponentBehavior: Bound

import "../services"
import QtQuick

// "Star birth" as a confirmation (visual language: star = on/done). The same animation as
// when turning on an OptionChip in the Wi-Fi/Bluetooth picker: the star fires with a rotation and slight
// overshoot, a shock wave runs out, six sparks fly away diagonally (between the rays).
// Usage: bind active to the state (e.g. "just copied"); when it becomes true, the star fires once,
// then it stands calmly. When it becomes false, it stays: the surrounding area does the fading (softly), otherwise
// the star would vanish abruptly before it. The next firing sets it up anew.
// Scaling/rotation only happens during the animation; at the end the values stand exactly at 1 or 0 (otherwise
// the 1 px rays tremble, see Sparkle.qml).
Item {
    id: burst

    property bool active: false
    // Size of one point (like Sparkle.size); shock wave and sparks grow along
    property real size: 5
    // Ray length like Sparkle.rays (set the same as a calm star next to it, otherwise it looks bigger)
    property real rays: 2.6
    property color color: Qt.lighter(WalColors.color7, 1.1)
    property color glowColor: WalColors.vividAccent

    // true = fades out softly by itself when active becomes false (0.75 s), instead of staying. For places without
    // an own surface that fades out (e.g. a star next to a counter)
    property bool fadeOut: false
    property real shown: 1

    property real starScale: 1
    property real starOpacity: 0
    property real starRot: 0
    property real burstT: 1

    function play() {
        ignite.stop();
        starOpacity = 0;
        ignite.start();
    }

    function reset() {
        ignite.stop();
        starOpacity = 0;
        starScale = 1;
        starRot = 0;
        burstT = 1;
    }

    width: size * 2
    height: size * 2
    opacity: shown
    onActiveChanged: {
        fadeAnim.stop();
        if (active) {
            shown = 1;
            play();
        } else if (fadeOut) {
            fadeAnim.start();
        }
    }
    Component.onCompleted: {
        if (active)
            play();
        else if (fadeOut)
            shown = 0;
    }

    NumberAnimation {
        id: fadeAnim

        target: burst
        property: "shown"
        to: 0
        duration: 750
        easing.type: Easing.InOutSine
    }

    // Druckwelle
    Rectangle {
        anchors.centerIn: parent
        width: burst.size * (0.8 + 5 * burst.burstT)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, burst.size / 6)
        border.color: WalColors.withAlpha(Qt.lighter(burst.glowColor, 1.15), 0.7 * (1 - burst.burstT))
        visible: burst.burstT < 0.999
    }

    // Sparks diagonally between the rays
    Repeater {
        model: 6

        Rectangle {
            required property int index
            readonly property real a: (index * 60 + 30) * Math.PI / 180
            readonly property real d: burst.size * (0.6 + 2.6 * burst.burstT)

            x: burst.width / 2 + Math.cos(a) * d - width / 2
            y: burst.height / 2 + Math.sin(a) * d - height / 2
            width: Math.max(1.5, burst.size / (index % 2 ? 3.4 : 2.6))
            height: width
            radius: width / 2
            color: burst.color
            opacity: Math.min(1, burst.burstT * 6) * (1 - burst.burstT)
            visible: burst.burstT < 0.999
        }

    }

    Sparkle {
        anchors.centerIn: parent
        size: burst.size
        rays: burst.rays
        color: burst.color
        glowColor: burst.glowColor
        twinkle: 0.9
        opacity: burst.starOpacity
        scale: burst.starScale
        rotation: burst.starRot
        visible: opacity > 0.01
    }

    SequentialAnimation {
        id: ignite

        PropertyAction { target: burst; property: "starScale"; value: 0.15 }
        PropertyAction { target: burst; property: "starRot"; value: -90 }
        PropertyAction { target: burst; property: "burstT"; value: 0 }

        ParallelAnimation {
            NumberAnimation { target: burst; property: "starOpacity"; to: 1; duration: 160 }
            NumberAnimation { target: burst; property: "starScale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            NumberAnimation { target: burst; property: "starRot"; to: 0; duration: 620; easing.type: Easing.OutCubic }
            NumberAnimation { target: burst; property: "burstT"; to: 1; duration: 620; easing.type: Easing.OutCubic }
        }

        // Exactly to the rest values
        PropertyAction { target: burst; property: "starScale"; value: 1 }
        PropertyAction { target: burst; property: "starRot"; value: 0 }
    }

}
