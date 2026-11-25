import QtQuick
import QtQuick.Shapes

// Four-pointed sparkle star (shape like the star in the loading screen of the Obsidian plugin "Galaxie",
// vault-galaxy/launcher/Starlight.qml): soft glow, long fine rays, a pointed core.
// A recurring motif of the whole shell: sparkle = on/active/"here"
// (OptionChip, active workspace in the bar, devices in the radar), starry sky decoration in pickers and menus.
// Center = middle of the item; size = length of one point (core), the rays reach further.
Item {
    id: sparkle

    property real size: 10
    property color color: "white"
    property color glowColor: color
    // 0..1, animated by the picker (twinkling). ONLY changes the brightness: when the star grew along, its
    // middle shifted by fractions of a pixel and it trembled visibly (measured in a screen recording: 0.5-0.8 px).
    property real twinkle: 0.5
    // Length of the rays in core points
    property real rays: 2.6

    readonly property real k: 0.6 + 0.4 * twinkle
    // Even pixel count: then the middle lies exactly on a pixel edge, the rays (1 px) sit sharp
    readonly property real rayLen: Math.round(size * rays)

    width: 2 * rayLen
    height: width
    // Only decoration: no mouse, no keyboard
    enabled: false

    // Glow
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            startX: 0
            startY: 0

            fillGradient: RadialGradient {
                centerX: sparkle.width / 2
                centerY: sparkle.height / 2
                focalX: centerX
                focalY: centerY
                centerRadius: sparkle.size * 1.8

                GradientStop {
                    position: 0
                    color: Qt.rgba(sparkle.glowColor.r, sparkle.glowColor.g, sparkle.glowColor.b, 0.18 * sparkle.k)
                }

                GradientStop {
                    position: 0.35
                    color: Qt.rgba(sparkle.glowColor.r, sparkle.glowColor.g, sparkle.glowColor.b, 0.05 * sparkle.k)
                }

                GradientStop {
                    position: 1
                    color: Qt.rgba(sparkle.glowColor.r, sparkle.glowColor.g, sparkle.glowColor.b, 0)
                }

            }

            PathLine { x: sparkle.width; y: 0 }
            PathLine { x: sparkle.width; y: sparkle.height }
            PathLine { x: 0; y: sparkle.height }
            PathLine { x: 0; y: 0 }
        }

    }

    // Rays: horizontal and vertical, fading toward the tip
    Rectangle {
        anchors.centerIn: parent
        width: 2 * sparkle.rayLen
        height: 1

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop { position: 0; color: Qt.rgba(sparkle.color.r, sparkle.color.g, sparkle.color.b, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(sparkle.color.r, sparkle.color.g, sparkle.color.b, 0.55 * sparkle.k) }
            GradientStop { position: 1; color: Qt.rgba(sparkle.color.r, sparkle.color.g, sparkle.color.b, 0) }
        }

    }

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: 2 * Math.round(sparkle.rayLen * 0.85)

        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(sparkle.color.r, sparkle.color.g, sparkle.color.b, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(sparkle.color.r, sparkle.color.g, sparkle.color.b, 0.55 * sparkle.k) }
            GradientStop { position: 1; color: Qt.rgba(sparkle.color.r, sparkle.color.g, sparkle.color.b, 0) }
        }

    }

    // Core: four inward-curved points (path from Starlight.qml, there middle 240/70, points 21-22 px)
    Shape {
        anchors.centerIn: parent
        width: 2 * sparkle.size
        height: width
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.7 + 0.3 * sparkle.k

        ShapePath {
            fillColor: sparkle.color
            strokeColor: "transparent"
            scale: Qt.size(sparkle.size / 21, sparkle.size / 21)

            PathSvg {
                path: "M21 0 C22 18 24 19 42 21 C24 22 22 24 21 42 C20 24 18 22 0 21 C18 19 20 18 21 0Z"
            }

        }

    }

}
