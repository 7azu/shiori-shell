import "../services"
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Choice tile (image/icon, title, hover tilt, light streak, shadow), shared by the choice views:
// media picker add-on (categories, pickers/media/CategoryTile) and language picker (languages, LanguageChooser).
// Knows no picker: the state comes in through properties, hover/click go out as signals.
//   selected  selected (keyboard/hover) -> lifts, tilts toward the mouse
//   enter     0 -> 1 on appearing;  leave 0 -> 1 when going in (side = -1/0/1: left/chosen/right)
//   glyph     character in the circle (Nerd Font icon or script character, glyphFont/glyphSize)
//   label/sublabel/detail/note  title, subtitle, lines at the bottom (empty = gone)
//   cover     optional image (tinted by pywal);  showContent: false hides icon/text (own content)
//   Children (default) lie above the tile and tilt along (e.g. an input field)
Item {
    id: tile

    property bool selected: false
    property bool ready: true
    property real enter: 1
    property string cover: ""
    property string glyph: ""
    property string glyphFont: Theme.font
    property int glyphSize: 40
    property string label: ""
    property string sublabel: ""
    property string sublabelFont: Theme.fontUi
    property string detail: ""
    property string note: ""
    property bool noteAccent: false
    // Small dot at the top right (e.g. last used)
    property bool dot: false
    property bool showContent: true
    // Show the icon circle (off when the image itself is already the icon/logo)
    property bool showGlyph: true
    default property alias content: extra.data
    // Last mouse position in scene coordinates (for hoverEntered on real movement)
    property point lastScenePos: Qt.point(-1e+06, -1e+06)

    // On entering AND on real mouse movement over the tile (>= 3 px in scene coordinates, like the pickers'
    // hoverSelect). Entering alone was not enough: the language choice ignores it during its transition, and a
    // mouse that was already on a tile then never selected it until it crossed a tile border. Tiles moving under a
    // resting mouse (animations) do not change its scene position, so keyboard selection stays.
    signal hoverEntered()
    signal clicked()

    function noteMouse(area, mouse) {
        const p = area.mapToItem(null, mouse.x, mouse.y);
        if (Math.abs(p.x - lastScenePos.x) < 3 && Math.abs(p.y - lastScenePos.y) < 3)
            return false;

        lastScenePos = p;
        return true;
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    // pywal accent as the hue for the tint (gray accents have no hue -> -1)
    readonly property real tintHue: {
        const h = Qt.color(WalColors.color4).hslHue;
        return h < 0 ? 0.6 : h;
    }
    // When going in: 0 -> 1
    property real leave: 0
    // Hover/selection as ONE soft value 0..1: tilt, zoom, color, icon, line all depend on it
    property real hot: selected && ready ? 1 : 0
    // Mouse position in the tile (-1..1), sprung: tilt + parallax follow the mouse
    property real mx: 0
    property real my: 0
    // Short light streak on hover (-0.6 .. 1.6 across the width)
    property real sweep: -1
    property real press: tileArea.pressed && ready ? 1 : 0
    // Tilt only while the tile is active and not being entered right now
    readonly property real tilt: hot * (1 - leave)
    // Left/right of the chosen tile: move aside when entering
    property int side: 0

    z: selected ? 2 : 0
    // The others step back, so the active tile leads
    opacity: enter * (selected ? 1 - 0.35 * leave : 1 - leave) * (0.7 + 0.3 * hot)
    onSelectedChanged: {
        if (selected && ready && leave < 0.01 && enter > 0.99)
            sweepAnim.restart();

    }

    NumberAnimation {
        id: sweepAnim

        target: tile
        property: "sweep"
        from: -0.6
        to: 1.6
        duration: 950
        easing.type: Easing.InOutCubic
    }

    // Soft shadow in the accent color under the lifted tile
    Repeater {
        model: 4

        Rectangle {
            required property int index
            readonly property real grow: (index + 1) * 6

            x: -grow
            y: -grow + 6 + 14 * tile.hot
            width: tile.width + 2 * grow
            height: tile.height + 2 * grow
            radius: 24 + grow
            color: Qt.darker(WalColors.color4, 3)
            opacity: 0.09 * tile.hot * (1 - tile.leave)
            visible: tile.hot > 0.01
        }

    }

    Item {
        id: tileBody

        anchors.fill: parent
        // The active tile grows slightly; when entering it zooms forward, the others shrink away
        // hot stands OUTSIDE the case distinction: otherwise the tile jumped to 1 right away on deselecting
        // (the other branch did not know hot), instead of running back with hot
        scale: (1 + 0.035 * tile.hot + (tile.selected ? 0.07 : -0.06) * tile.leave) * (1 - 0.03 * tile.press)
        transform: [
            // 3D tilt toward the mouse (rotation around x/y projected in perspective)
            Rotation {
                origin.x: tileBody.width / 2
                origin.y: tileBody.height / 2
                axis.x: 1
                axis.y: 0
                axis.z: 0
                angle: -tile.my * 7 * tile.tilt
            },
            Rotation {
                origin.x: tileBody.width / 2
                origin.y: tileBody.height / 2
                axis.x: 0
                axis.y: 1
                axis.z: 0
                angle: tile.mx * 7 * tile.tilt
            }
        ]

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: Qt.tint(WalColors.withAlpha(WalColors.color7, 0.045), WalColors.withAlpha(WalColors.color4, 0.12 * tile.hot))
        }

        Rectangle {
            id: tileMask

            anchors.fill: parent
            radius: 24
            visible: false
        }

        // Image: masked to the round tile outside, tinted in pywal colors inside. As a layer.effect
        // both are fixed to the item; none of it can stand unclipped next to the tile
        Item {
            anchors.fill: parent
            visible: tile.cover !== "" && tileImg.status === Image.Ready
            opacity: 0.2 + 0.3 * tile.hot
            layer.enabled: true

            // Zoom and parallax work within this frame (the layer clips to its size)
            Item {
                anchors.fill: parent
                layer.enabled: true

                Image {
                    id: tileImg

                    anchors.fill: parent
                    source: tile.cover
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.ceil(width * 1.8)
                    // Slightly oversized, so the parallax never shows the edge
                    scale: 1.08 + 0.06 * tile.hot + (tile.selected ? 0.12 * tile.leave : 0)

                    transform: Translate {
                        x: -tile.mx * 12 * tile.tilt
                        y: -tile.my * 12 * tile.tilt
                    }

                }

                // Washed out in the pywal colors; stronger when active
                layer.effect: Colorize {
                    hue: tile.tintHue
                    saturation: 0.3 + 0.32 * tile.hot
                    // hardly darken: dark images (movies) would otherwise disappear completely
                    lightness: -0.03
                }

            }

            layer.effect: OpacityMask {
                maskSource: tileMask
            }

        }

        // Light streak: a slanted band that runs over the tile once. Only exists during the
        // animation and is masked to the round tile
        Item {
            id: sweepBox

            anchors.fill: parent
            visible: sweepAnim.running
            layer.enabled: visible

            Rectangle {
                x: tile.sweep * sweepBox.width - width / 2
                y: -sweepBox.height * 0.5
                width: sweepBox.width * 0.35
                height: sweepBox.height * 2
                rotation: 18

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: Qt.rgba(1, 1, 1, 0)
                    }

                    GradientStop {
                        position: 0.5
                        color: Qt.rgba(1, 1, 1, 0.09)
                    }

                    GradientStop {
                        position: 1
                        color: Qt.rgba(1, 1, 1, 0)
                    }

                }

            }

            layer.effect: OpacityMask {
                maskSource: tileMask
            }

        }

        // Darken toward the bottom, so the label stays readable on every cover
        Rectangle {
            anchors.fill: parent
            radius: 24

            gradient: Gradient {
                GradientStop {
                    position: 0.35
                    color: WalColors.withAlpha(WalColors.color0, 0)
                }

                GradientStop {
                    position: 1
                    color: WalColors.withAlpha(WalColors.color0, 0.85)
                }

            }

        }

        // Light from above: follows the mouse a bit (glossy surface)
        Rectangle {
            anchors.fill: parent
            radius: 24
            opacity: tile.tilt

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, 0.07 + 0.05 * Math.max(0, -tile.my))
                }

                GradientStop {
                    position: 0.4
                    color: Qt.rgba(1, 1, 1, 0)
                }

            }

        }

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: "transparent"
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.08)
        }

        Rectangle {
            anchors.fill: parent
            radius: 24
            color: "transparent"
            border.width: 1.5
            border.color: WalColors.withAlpha(WalColors.color4, 0.7)
            opacity: tile.hot
        }

        // Icon: lifts and gets a glow in the accent color
        Item {
            visible: tile.showContent && tile.showGlyph
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.3 - 8 * tile.hot
            width: 88
            height: 88
            scale: 1 + 0.1 * tile.hot

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 1.6
                height: width
                radius: width / 2
                color: WalColors.withAlpha(WalColors.color4, 0.1)
                opacity: tile.hot
                scale: 0.7 + 0.3 * tile.hot
            }

            Rectangle {
                anchors.fill: parent
                radius: 44
                color: Qt.tint(WalColors.withAlpha(WalColors.color7, 0.07), WalColors.withAlpha(WalColors.color4, 0.22 * tile.hot))
                border.width: 1
                border.color: WalColors.withAlpha(WalColors.color4, 0.35 * tile.hot)
            }

            Text {
                anchors.centerIn: parent
                text: tile.glyph
                font.family: tile.glyphFont
                font.pixelSize: tile.glyphSize
                // Scaled along: without hinting no snapping at the end of the animation
                font.hintingPreference: Font.PreferNoHinting
                renderType: Text.QtRendering
                color: Qt.tint(WalColors.withAlpha(WalColors.color7, 0.75), WalColors.withAlpha(WalColors.color4, tile.hot))
            }

        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            spacing: 8
            visible: tile.showContent

            // A bit bigger when active: by scale (fluid) instead of letterSpacing, which Qt rounds to whole
            // pixels -> the line jumped in steps when running back. Without hinting the font does not snap
            // to the pixel grid at the end of the animation either.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label
                font.family: Theme.font
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 0.6
                font.hintingPreference: Font.PreferNoHinting
                renderType: Text.QtRendering
                scale: 1 + 0.06 * tile.hot
                color: WalColors.withAlpha(WalColors.color7, 0.8 + 0.2 * tile.hot)
            }

            // The accent line grows out of the middle. Fixed width + scale instead of width: 40 * hot - a Column
            // drops elements with width 0 from the layout, then the name jumped 10 px down at the end
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 2
                radius: 1
                color: WalColors.color4
                opacity: tile.hot

                transform: Scale {
                    origin.x: 20
                    xScale: tile.hot
                }

            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tile.sublabel !== ""
                text: tile.sublabel
                font.family: tile.sublabelFont
                font.pixelSize: 12
                color: WalColors.withAlpha(WalColors.color7, 0.5 + 0.2 * tile.hot)
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tile.detail !== "" || tile.note !== ""
                spacing: 3

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: tile.detail !== ""
                    text: tile.detail
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    font.features: Theme.tabular
                    color: WalColors.withAlpha(WalColors.color7, 0.55)
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: tile.note !== ""
                    text: tile.note
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro + 1
                    font.weight: Font.DemiBold
                    font.features: Theme.tabular
                    color: tile.noteAccent ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.4)
                }

            }

        }

        Rectangle {
            visible: tile.dot
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            width: 7
            height: 7
            radius: 3.5
            color: WalColors.color4
        }

        // The user's own content (tilts with the tile)
        Item {
            id: extra

            anchors.fill: parent
        }

        // Not built yet
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            width: soonText.implicitWidth + 18
            height: 22
            radius: height / 2
            visible: !tile.ready
            color: WalColors.withAlpha(WalColors.color7, 0.08)

            Text {
                id: soonText

                anchors.centerIn: parent
                text: "soon"
                font.family: Theme.font
                font.pixelSize: 10
                color: WalColors.withAlpha(WalColors.color7, 0.5)
            }

        }

    }

    MouseArea {
        id: tileArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: tile.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: tile.hoverEntered()
        onPositionChanged: (mouse) => {
            tile.mx = tile.clamp01(mouse.x / width) * 2 - 1;
            tile.my = tile.clamp01(mouse.y / height) * 2 - 1;
            if (tile.noteMouse(tileArea, mouse))
                tile.hoverEntered();

        }
        // Mouse gone: the tilt glides back to the middle
        onExited: {
            tile.mx = 0;
            tile.my = 0;
        }
        onClicked: {
            if (tile.ready)
                tile.clicked();

        }
    }

    // In: MD3 "emphasized decelerate" (fast start, soft end). Out: even (ease-in-out)
    // over 420 ms - with a fast starting curve most of it was done after 2 frames (= a jump).
    // Both as Bézier: a set bezierCurve forces BezierSpline, an easing.type next to it does not count.
    Behavior on hot {
        NumberAnimation {
            duration: tile.selected ? Appearance.anim.durations.slow - 60 : 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: tile.selected ? Appearance.anim.curves.emphasizedDecelerate : [0.65, 0, 0.35, 1, 1, 1]
        }

    }

    Behavior on mx {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }

    }

    Behavior on my {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }

    }

    Behavior on press {
        NumberAnimation {
            duration: 110
            easing.type: Easing.OutCubic
        }

    }

    transform: Translate {
        // Fade in from below; when entering the neighbors push outward
        x: tile.side * 70 * tile.leave
        y: (1 - tile.enter) * 18 - 6 * tile.hot * (1 - tile.leave)
    }

}
