pragma ComponentBehavior: Bound

import "../services"
import QtQuick

// Starry sky as a recurring motif of the shell: thin stars as in the Wi-Fi/Bluetooth
// picker plus a few sparkle stars (Sparkle). Only draws light, no background: put it over any background.
// Used in the power menu, lock screen (LockBackdrop) and workspace overview. Deliberately NOT in tools
// (clipboard, editors, task manager): it would distract there.
// Twinkling only changes the brightness (size/place fixed), otherwise the fine stars tremble.
Item {
    id: field

    // Overall brightness of the small stars
    property real strength: 1
    // Spacing/size of the stars (1 = as in the Bluetooth picker; big areas rather a bit more)
    property real cellScale: 1
    // Only the size of the stars (1 = unchanged); with a bigger cellScale: few but bigger stars
    property real starSize: 1
    // false = calm: no twinkling, no clock (lock screen: the handover from the power menu must be pixel identical,
    // and a permanently running clock would redraw the screen for hours)
    property bool animated: true
    // Parallax offset of the near layer in pixels (e.g. from the mouse position); the far layer proportionally,
    // sparkle stars a bit more (the frontmost)
    property point pan: Qt.point(0, 0)
    property color starColor: WalColors.color7
    // Sparkle stars: [share x, share y, size, phase]; empty = none
    property var sparkles: []
    // Idle: the sky drifts slowly (pixels per second for the near layer, the far one proportionally -> depth).
    // Only with animated; the stars are pixel-integrated, so they move without flicker. Sparkle stars stay
    property point drift: Qt.point(0, 0)
    // Idle: now and then a shooting star crosses the picture diagonally (every 12-25 s)
    property bool shootingStars: false
    // Share of the small stars that is drawn (1 = all, 0.5 = every second one)
    property real density: 1
    // true = no fixed sky: every star is a particle that fades in, flies its own slow path and fades out
    // again. `drift` is then the mean flight (direction and speed scatter around it), the sparkle
    // stars float along softly. Only with animated; calm = the fixed sky
    property bool particles: false
    property real sparkleOpacity: 0.8

    property real time: 0
    // Setting "desktop.stars" (settings window): off | calm | animated. Applies to every sky: off draws
    // nothing, calm keeps the stars but stops twinkling, drift and shooting stars
    readonly property string mode: (Settings.data.desktop || {
    }).stars || "animated"
    readonly property bool live: animated && mode === "animated"
    readonly property bool flying: particles && live

    FrameAnimation {
        running: field.live && field.visible && field.opacity > 0.01
        onTriggered: field.time += frameTime
    }

    ShaderEffect {
        property real time: field.time
        property real strength: field.strength
        property real twinkle: field.live ? 1 : 0
        property real cellScale: field.cellScale
        property real starSize: field.starSize
        property vector2d size: Qt.vector2d(width, height)
        property real density: field.density
        property real particles: field.flying ? 1 : 0
        // Fixed sky: the drift shifts the whole sky. Particles: every star flies on its own (flow)
        property vector2d pan: field.flying ? Qt.vector2d(field.pan.x, field.pan.y) : Qt.vector2d(field.pan.x + field.drift.x * field.time, field.pan.y + field.drift.y * field.time)
        property vector2d flow: Qt.vector2d(field.drift.x, field.drift.y)
        property color starColor: field.starColor

        anchors.fill: parent
        visible: field.mode !== "off"
        fragmentShader: Qt.resolvedUrl("shaders/starfield.frag.qsb")
    }

    // Shooting star: a fine light trail that moves diagonally down to the left, lighting up and fading meanwhile
    Item {
        id: meteor

        property real t: 0
        // Start point and length of the path (rolled anew before every flight)
        property real sx: 0
        property real sy: 0
        readonly property real travel: 280
        readonly property real angle: 152

        visible: field.shootingStars && t > 0 && t < 1
        x: sx + Math.cos(angle * Math.PI / 180) * travel * t
        y: sy + Math.sin(angle * Math.PI / 180) * travel * t
        rotation: angle
        opacity: Math.sin(Math.PI * t) * 0.85

        // Head in front (on the right in the rotated item), the tail fades out toward the back
        Rectangle {
            x: -width
            y: -height / 2
            width: 110
            height: 1.5
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.lighter(field.starColor, 1.15) }
            }
        }

        NumberAnimation {
            id: meteorAnim

            target: meteor
            property: "t"
            from: 0
            to: 1
            duration: 900
            easing.type: Easing.OutQuad
        }

        Timer {
            id: meteorTimer

            interval: 4000
            running: field.shootingStars && field.live && field.visible && field.opacity > 0.01
            repeat: true
            onTriggered: {
                // Start somewhere in the upper right area, so the trail runs through the picture
                meteor.sx = field.width * (0.35 + 0.6 * Math.random());
                meteor.sy = field.height * (0.05 + 0.45 * Math.random());
                meteorAnim.restart();
                interval = 12000 + Math.random() * 13000;
            }
        }
    }

    // Place rounded to whole pixels (half pixels made the fine rays flicker); the parallax
    // shifts the star as a finished image (layer, softly filtered) - so it glides smoothly
    Repeater {
        model: field.mode === "off" ? [] : field.sparkles

        Sparkle {
            id: glint

            required property var modelData

            x: Math.round(field.width * modelData[0] - width / 2)
            y: Math.round(field.height * modelData[1] - height / 2)
            layer.enabled: true
            layer.smooth: true
            // Particles: floats softly around its place (a slow loop of a few pixels, each in its own rhythm)
            transform: Translate {
                x: field.pan.x * 1.3 + (field.flying ? 7 * Math.sin(field.time * 0.11 + glint.modelData[3] * 1.7) : 0)
                y: field.pan.y * 1.3 + (field.flying ? 5 * Math.sin(field.time * 0.083 + glint.modelData[3] * 2.9) : 0)
            }
            size: modelData[2]
            color: Qt.lighter(WalColors.color7, 1.05)
            glowColor: WalColors.vividAccent
            // Each in its own rhythm; calm = fixed medium brightness
            twinkle: field.live ? 0.5 + 0.5 * Math.sin(field.time * (0.5 + modelData[3] * 0.06) + modelData[3]) : 0.6
            opacity: field.sparkleOpacity
        }

    }

}
