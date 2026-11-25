import "../services"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// The look of the desktop visualizer (windows/DesktopVisualizer.qml) in ONE palette: echo, wave,
// crest + sparks. A separate file, because the visualizer draws it twice briefly on a wallpaper change
// (old and new palette) and crossfades with a shader. The colors come in as a fixed palette
// (DesktopVisualizer.paletteOf), not live from WalColors: WalColors mixes in steps during the change, and
// the gradient sorted by brightness could have swapped its order in the middle of the change.
//
//   pal: { ramp: [7 colors dark -> bright], crest: crest/sparks, glow: glow of the crest }
Item {
    id: look

    required property var pal
    property string wavePath: ""
    property string crestPath: ""
    property string echoPath: ""
    property var sparks: []
    property int sparkCount: 0
    // transparent until the visualizer has set its start palette (Component.onCompleted)
    readonly property var p: pal && pal.ramp ? pal : ({
        "ramp": new Array(7).fill("#00000000"),
        "crest": "#00000000",
        "glow": "#00000000"
    })
    readonly property color echoColor: p.ramp[6]

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        layer.enabled: true

        // brightest color: a medium gray-blue darkened bright parts of the wallpaper when the echo briefly
        // stood alone above the falling wave
        ShapePath {
            strokeColor: "transparent"

            PathSvg {
                path: look.echoPath
            }

            fillGradient: LinearGradient {
                x1: 0
                y1: look.height
                x2: 0
                y2: 0

                GradientStop {
                    position: 0
                    color: WalColors.withAlpha(look.echoColor, 0.32)
                }

                GradientStop {
                    position: 1
                    color: WalColors.withAlpha(look.echoColor, 0)
                }

            }

        }

        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 0.7
            blurMax: 48
        }

    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer

        ShapePath {
            strokeColor: "transparent"

            PathSvg {
                path: look.wavePath
            }

            // over the whole possible wave height: high peaks reach into the bright tones,
            // quiet parts stay dark. Slightly more transparent toward the top, so it fades out softly
            fillGradient: LinearGradient {
                x1: 0
                y1: look.height
                x2: 0
                y2: MachineConfig.px(8)

                GradientStop {
                    position: 0
                    color: WalColors.withAlpha(look.p.ramp[0], 0.9)
                }

                GradientStop {
                    position: 0.25
                    color: WalColors.withAlpha(look.p.ramp[1], 0.8)
                }

                GradientStop {
                    position: 0.5
                    color: WalColors.withAlpha(look.p.ramp[3], 0.7)
                }

                GradientStop {
                    position: 0.75
                    color: WalColors.withAlpha(look.p.ramp[5], 0.6)
                }

                GradientStop {
                    position: 1
                    color: WalColors.withAlpha(look.p.ramp[6], 0.5)
                }

            }

        }

    }

    // Crest + sparks in one layer, so both get the same glow. Own layer = own MSAA
    // (the outer layer's does not apply here): without it line and sparks were pixelated in places
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 8
        layer.smooth: true

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                strokeColor: look.p.crest
                strokeWidth: MachineConfig.px(2)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: look.crestPath
                }

            }

        }

        Repeater {
            model: look.sparkCount

            Rectangle {
                required property int index
                readonly property var s: look.sparks[index] ?? null

                visible: s !== null
                x: s ? s.x - width / 2 : 0
                y: s ? s.y - height / 2 : 0
                width: s ? s.size : 0
                height: width
                radius: width / 2
                color: look.p.crest
                opacity: s ? Math.pow(1 - s.life, 1.6) : 0
            }

        }

        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: look.p.glow
            shadowBlur: 1
            shadowOpacity: 1
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            blurMax: 32
            autoPaddingEnabled: false
        }

    }

}
