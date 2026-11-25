import "../services"
import QtQuick
import QtQuick.Shapes

// Default profile picture when there is no ~/.face: the usual person silhouette, drawn here instead of a
// fixed image, so it takes the pywal colors (and follows a wallpaper change with the color fade).
// Head and shoulders lie fully inside the circle, so it needs no clipping of its own.
Item {
    id: root

    // Dark disc and light figure, both from the accent
    property color fill: WalColors.mixHex(WalColors.color0, WalColors.color4, 0.3)
    property color figure: WalColors.mixHex(WalColors.color4, WalColors.color7, 0.45)

    // Shoulder outline: left, right, top, bottom, corner radius
    readonly property real sl: width * 0.254
    readonly property real sr: width * 0.746
    readonly property real st: height * 0.578
    readonly property real sb: height * 0.754
    readonly property real sc: width * 0.016

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.fill
    }

    // Head
    Rectangle {
        width: root.width * 0.25
        height: width
        radius: width / 2
        x: (root.width - width) / 2
        y: root.height * 0.39 - height / 2
        color: root.figure
    }

    // Shoulders: dome on top, slightly rounded corners at the bottom
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.figure
            startX: root.sl
            startY: root.sb - root.sc

            PathLine { x: root.sl; y: root.st + (root.sb - root.st) * 0.55 }
            PathCubic {
                x: root.width / 2; y: root.st
                control1X: root.sl; control1Y: root.st + (root.sb - root.st) * 0.1
                control2X: root.width * 0.36; control2Y: root.st
            }
            PathCubic {
                x: root.sr; y: root.st + (root.sb - root.st) * 0.55
                control1X: root.width * 0.64; control1Y: root.st
                control2X: root.sr; control2Y: root.st + (root.sb - root.st) * 0.1
            }
            PathLine { x: root.sr; y: root.sb - root.sc }
            PathQuad { x: root.sr - root.sc; y: root.sb; controlX: root.sr; controlY: root.sb }
            PathLine { x: root.sl + root.sc; y: root.sb }
            PathQuad { x: root.sl; y: root.sb - root.sc; controlX: root.sl; controlY: root.sb }
        }
    }
}
