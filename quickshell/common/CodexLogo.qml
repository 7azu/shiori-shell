import QtQuick
import QtQuick.Shapes

Item {
    id: logo
    property color color: "white"
    implicitWidth: 18
    implicitHeight: 18

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: logo.color
            strokeWidth: 1.5
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(logo.width / 18, logo.height / 18)

            PathSvg {
                path: "M7.4 1.9 Q9 1 10.6 1.9 L14.7 4.2 Q16.2 5.1 16.2 6.8 V11.2 Q16.2 12.9 14.7 13.8 L10.6 16.1 Q9 17 7.4 16.1 L3.3 13.8 Q1.8 12.9 1.8 11.2 V6.8 Q1.8 5.1 3.3 4.2 Z M5.3 6.8 L7.6 9 L5.3 11.2 M9.6 11.2 H12.7"
            }
        }
    }
}
