import "../services"
import QtQuick
import QtQuick.Shapes

// One weather symbol: thin lines without a frame, laid out on a 24 x 24 grid and scaled to `size`.
// What gives light (sun, moon, lightning) is drawn in the accent color, clouds and what falls in the
// text color. With `animated` the symbol moves a little: the sun turns, rain and snow fall, fog drifts,
// lightning flickers. Only places and brightness change, never sizes.
//
// Changing `kind` morphs instead of crossfading two drawings: there is only ONE cloud and ONE sun (or
// moon), and each kind is a place and a size for them. The cloud grows in front of the sun, rises and
// gets a little smaller to make room for rain, shrinks to the lower left when the sun comes out.
// Rain, snow, fog and lightning come out of the cloud and fade. (Crossfading two different cloud
// drawings showed both outlines on top of each other for a moment.) The cloud is filled with the
// color behind it (`backdrop`), so a sun behind it is hidden where it overlaps.
// Outlines after the Lucide icons (ISC license, see THIRD_PARTY.md).
Item {
    id: glyph

    // clear | partly | cloud | fog | drizzle | rain | snow | thunder (WeatherState.kindOf)
    property string kind: "clear"
    property bool day: true
    property real size: 40
    property bool animated: true
    property color ink: Theme.tint(Theme.text, 0.85)
    property color glow: Theme.accent
    // The color of a card on the panel; the cloud is filled with `backdrop` (set it where the symbol
    // stands on another surface)
    readonly property color cardColor: Qt.tint(WalColors.color0, Theme.card)
    property color backdrop: cardColor
    // Grid unit and line width in pixels
    readonly property real u: size / 24
    readonly property real line: Math.max(1.2, size / 24)
    readonly property bool moving: animated && visible
    readonly property bool under: kind === "fog" || kind === "drizzle" || kind === "rain" || kind === "snow" || kind === "thunder"
    // One slow clock for everything that loops. It starts somewhere in the middle, so a symbol that
    // never moves (animated: false) shows its drops spread out.
    property real phase: 0.37
    // Where the cloud is (offset on the grid), how large, and how visible
    readonly property var cloudAt: kind === "clear" ? [-3, 4, 0.55, 0] : (kind === "partly" ? [-2.2, 3.6, 0.72, 1] : (under ? [0, -3.2, 0.84, 1] : [0, 0, 1, 1]))
    // Where the sun or moon is (its center), how large, and how visible
    readonly property var lightAt: kind === "clear" ? [12, 12, 1, 1] : (kind === "partly" ? [16, 8.2, 0.62, 1] : [16, 8.2, 0.35, 0])
    property real cloudX: cloudAt[0]
    property real cloudY: cloudAt[1]
    property real cloudS: cloudAt[2]
    property real cloudO: cloudAt[3]
    property real lightX: lightAt[0]
    property real lightY: lightAt[1]
    property real lightS: lightAt[2]
    property real lightO: lightAt[3]
    property real sunK: day ? 1 : 0

    function frac(x) {
        return x - Math.floor(x);
    }

    // Where drop k of n is on its way down (0 top .. 1 bottom)
    function fallOf(k, n, speed) {
        return frac(phase * speed + k / n);
    }

    width: size
    height: size

    // Goes on from where it stood, so starting and stopping (hover) never makes a part jump
    FrameAnimation {
        running: glyph.moving
        onTriggered: glyph.phase = glyph.frac(glyph.phase + Math.min(frameTime, 0.05) / 6)
    }

    // ---- Rain, drizzle, snow, fog and lightning: behind the cloud, so they come out of it ----
    Item {
        id: below

        anchors.fill: parent

        // Raindrops (the first three) and drizzle (the last two): short strokes that fall
        Repeater {
            model: 5

            delegate: Rectangle {
                required property int index
                readonly property bool light: index >= 3
                readonly property int nr: light ? index - 3 : index
                readonly property real t: glyph.fallOf(nr, light ? 2 : 3, light ? 3 : 5)
                property real presence: glyph.kind === (light ? "drizzle" : "rain") ? 1 : 0

                x: (light ? 9.5 + nr * 5 : 8 + nr * 4) * glyph.u - width / 2 - t * glyph.u
                y: (13.5 + t * 5 - (1 - presence) * 2) * glyph.u
                width: glyph.line
                height: (light ? 2 : 3.2) * glyph.u
                radius: width / 2
                rotation: 14
                color: glyph.ink
                opacity: Math.sin(Math.PI * t) * presence
                visible: presence > 0.01

                Behavior on presence {
                    Fade {
                    }

                }

            }

        }

        // Snow: dots that sink slowly and sway
        Repeater {
            model: 3

            delegate: Rectangle {
                required property int index
                readonly property real t: glyph.fallOf(index, 3, 2)
                property real presence: glyph.kind === "snow" ? 1 : 0

                x: (8 + index * 4 + Math.sin((t + index / 3) * 2 * Math.PI) * 0.7) * glyph.u - width / 2
                y: (14.5 + t * 6 - (1 - presence) * 2) * glyph.u
                width: glyph.line * 1.5
                height: width
                radius: width / 2
                color: glyph.ink
                opacity: Math.sin(Math.PI * t) * presence
                visible: presence > 0.01

                Behavior on presence {
                    Fade {
                    }

                }

            }

        }

        // Fog: two lines that slide against each other
        Repeater {
            model: 2

            delegate: Rectangle {
                required property int index
                property real presence: glyph.kind === "fog" ? 1 : 0

                x: (index === 0 ? 7 : 9) * glyph.u + Math.sin(glyph.phase * 2 * Math.PI) * (index === 0 ? 1 : -1) * glyph.u
                y: (index === 0 ? 17 : 20.5) * glyph.u - height / 2 - (1 - presence) * 2 * glyph.u
                width: (index === 0 ? 9 : 8) * glyph.u
                height: glyph.line
                radius: height / 2
                color: glyph.ink
                opacity: 0.8 * presence
                visible: presence > 0.01

                Behavior on presence {
                    Fade {
                    }

                }

            }

        }

        // Lightning: two short flashes per loop, otherwise a steady glow
        Outline {
            readonly property real f: glyph.frac(glyph.phase * 2)

            y: -(1 - presence) * 2 * glyph.u
            shown: glyph.kind === "thunder"
            path: "M13 12l-3 5h4l-3 5"
            color: glyph.glow
            dim: !glyph.moving ? 1 : (f < 0.05 ? 1 : (f < 0.1 ? 0.3 : (f < 0.16 ? 1 : 0.62)))
        }

    }

    // ---- Sun or moon: one of each, placed and sized by the kind ----
    Item {
        id: light

        x: (glyph.lightX - 12) * glyph.u
        y: (glyph.lightY - 12) * glyph.u
        width: glyph.size
        height: glyph.size
        scale: glyph.lightS
        opacity: glyph.lightO
        visible: opacity > 0.01

        // Sun: ring and eight rays. An eighth of a turn per loop looks like turning without end
        Item {
            anchors.fill: parent
            opacity: glyph.sunK
            visible: opacity > 0.01

            Rectangle {
                anchors.centerIn: parent
                width: 8 * glyph.u
                height: width
                radius: width / 2
                color: "transparent"
                border.width: glyph.line / glyph.lightS
                border.color: glyph.glow
            }

            Item {
                anchors.fill: parent
                rotation: glyph.phase * 45

                Repeater {
                    model: 8

                    delegate: Rectangle {
                        id: ray

                        required property int index

                        x: 12 * glyph.u - width / 2
                        y: 2 * glyph.u
                        width: glyph.line / glyph.lightS
                        height: 2.2 * glyph.u
                        radius: width / 2
                        color: glyph.glow

                        transform: Rotation {
                            origin.x: ray.width / 2
                            origin.y: 10 * glyph.u
                            angle: ray.index * 45
                        }

                    }

                }

            }

        }

        // Moon with two small stars that take turns in brightness (the stars only with a clear sky)
        Item {
            anchors.fill: parent
            opacity: 1 - glyph.sunK
            visible: opacity > 0.01

            Outline {
                path: "M11 4a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"
                color: glyph.glow
                k: glyph.lightS
            }

            Repeater {
                model: [{
                    "x": 17.5,
                    "y": 4.5,
                    "at": 0
                }, {
                    "x": 21,
                    "y": 8,
                    "at": 0.5
                }]

                delegate: Rectangle {
                    required property var modelData
                    property real presence: glyph.kind === "clear" ? 1 : 0

                    x: modelData.x * glyph.u - width / 2
                    y: modelData.y * glyph.u - height / 2
                    width: glyph.line * 1.3
                    height: width
                    radius: width / 2
                    color: glyph.glow
                    opacity: presence * (0.3 + 0.7 * Math.abs(Math.sin(Math.PI * (glyph.phase * 2 + modelData.at))))

                    Behavior on presence {
                        Fade {
                        }

                    }

                }

            }

        }

    }

    // ---- The cloud: always the same drawing, moved and sized by the kind. It drifts a little ----
    Item {
        x: (glyph.cloudX + Math.sin(glyph.phase * 2 * Math.PI) * 0.6) * glyph.u
        y: glyph.cloudY * glyph.u
        width: glyph.size
        height: glyph.size
        scale: glyph.cloudS
        opacity: glyph.cloudO
        visible: opacity > 0.01

        Outline {
            path: "M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"
            color: glyph.ink
            fill: glyph.backdrop
            k: glyph.cloudS
        }

    }

    // Moving between the places of two kinds: a soft glide, no bounce
    Behavior on cloudX {
        Glide {
        }

    }

    Behavior on cloudY {
        Glide {
        }

    }

    Behavior on cloudS {
        Glide {
        }

    }

    Behavior on cloudO {
        Fade {
        }

    }

    Behavior on lightX {
        Glide {
        }

    }

    Behavior on lightY {
        Glide {
        }

    }

    Behavior on lightS {
        Glide {
        }

    }

    Behavior on lightO {
        Fade {
        }

    }

    Behavior on sunK {
        Fade {
        }

    }

    component Glide: NumberAnimation {
        duration: 480
        easing.type: Easing.OutCubic
    }

    component Fade: NumberAnimation {
        duration: 300
        easing.type: Easing.OutCubic
    }

    // A line drawing on the 24 x 24 grid, scaled as a whole. k = the scale of what holds it, so the
    // line keeps its width however large the part is shown.
    component Outline: Shape {
        id: outline

        property string path: ""
        property color color: "white"
        property color fill: "transparent"
        property real k: 1
        // Part of the current kind (fades), and its own brightness on top of that
        property bool shown: true
        property real dim: 1
        property real presence: shown ? 1 : 0

        opacity: presence * dim
        visible: opacity > 0.01
        width: 24
        height: 24
        scale: glyph.u
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: outline.color
            strokeWidth: glyph.line / (glyph.u * outline.k)
            fillColor: outline.fill
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: outline.path
            }

        }

        Behavior on presence {
            Fade {
            }

        }

    }

}
