import "../services"
import QtQuick
import QtQuick.Shapes

Shape {
    id: root

    property real cornerRadius: 20
    property real menuWidth: 200
    property real menuHeight: 120
    property color fillColor: WalColors.withAlpha(WalColors.color0, 1)

    width: menuWidth + 2 * cornerRadius
    height: menuHeight
    // Smooth edges directly by shader. Before, a layer with 16x multisampling: the texture was created anew
    // with a new height in every frame while opening/closing (expensive on weak GPUs).
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        id: path

        fillColor: root.fillColor
        strokeColor: "transparent"
        strokeWidth: 0

        PathMove {
            x: 0
            y: 0
        }

        PathArc {
            x: root.cornerRadius
            y: root.cornerRadius
            radiusX: root.cornerRadius
            radiusY: root.cornerRadius
            direction: PathArc.Clockwise
        }

        PathLine {
            x: root.cornerRadius
            y: root.menuHeight - root.cornerRadius
        }

        PathArc {
            x: 2 * root.cornerRadius
            y: root.menuHeight
            radiusX: root.cornerRadius
            radiusY: root.cornerRadius
            direction: PathArc.Counterclockwise
        }

        PathLine {
            x: root.cornerRadius + root.menuWidth - root.cornerRadius
            y: root.menuHeight
        }

        PathArc {
            x: root.cornerRadius + root.menuWidth
            y: root.menuHeight - root.cornerRadius
            radiusX: root.cornerRadius
            radiusY: root.cornerRadius
            direction: PathArc.Counterclockwise
        }

        PathLine {
            x: root.cornerRadius + root.menuWidth
            y: root.cornerRadius
        }

        PathArc {
            x: root.cornerRadius + root.menuWidth + root.cornerRadius
            y: 0
            radiusX: root.cornerRadius
            radiusY: root.cornerRadius
            direction: PathArc.Clockwise
        }

        PathLine {
            x: 0
            y: 0
        }

    }

    // The workaround from the earlier dropdowns - implemented once centrally here
    // instead of duplicated in every dropdown file.
    // Without the earlier intermediate step "transparent" (it was visible for one frame = flicker on every
    // color change). The binding is only renewed - as a binding, not as a fixed value, otherwise the
    // soft color crossfade (WalColors.fadeTo) would no longer arrive afterwards.
    Connections {
        function onColorsUpdated() {
            redrawTimer.start();
        }

        target: WalColors
    }

    Timer {
        id: redrawTimer

        interval: 10
        onTriggered: path.fillColor = Qt.binding(() => {
            return root.fillColor;
        })
    }

}
