import "../../services"
import QtQuick
import QtQuick.Shapes

Item {
    id: ring

    property real value: 0
    property real thickness: 4
    property color color: WalColors.color4
    property color trackColor: WalColors.withAlpha(WalColors.color7, 0.1)
    property bool spinning: false
    property real spin: 0
    readonly property real r: (Math.min(width, height) - thickness) / 2

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeColor: ring.trackColor
            strokeWidth: ring.thickness
            fillColor: "transparent"

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.r
                radiusY: ring.r
                startAngle: -90
                sweepAngle: 360
            }

        }

        ShapePath {
            strokeColor: (ring.value > 0.002 || ring.spinning) ? ring.color : "transparent"
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.r
                radiusY: ring.r
                startAngle: -90 + (ring.spinning ? ring.spin : 0)
                sweepAngle: ring.spinning ? 100 : 360 * Math.min(1, ring.value)
            }

        }

    }

    NumberAnimation on spin {
        running: ring.spinning
        from: 0
        to: 360
        duration: 1100
        loops: Animation.Infinite
    }

}
