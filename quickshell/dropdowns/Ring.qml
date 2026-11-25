import "../services"
import QtQuick
import QtQuick.Shapes

// Ring display for all dropdowns: track, arc in the status color, glowing tip.
// In the middle: small label, big number, side line.
Item {
    id: ring

    property real progress: 0 // 0..1, animated softly
    property color tone: Theme.accent
    property real thickness: 8
    property bool showTip: true
    property string caption: ""
    property string value: ""
    property string detail: ""
    property color detailColor: Theme.textDim
    property int valueSize: Theme.sizeDisplay
    // Softly following display
    property real shown: progress
    property color shownTone: tone
    readonly property real r: width / 2 - thickness / 2
    readonly property real tipAngle: (-90 + 360 * shown) * Math.PI / 180

    width: 150
    height: width

    // Spur
    Rectangle {
        anchors.fill: parent
        anchors.margins: ring.thickness / 2 - 0.5
        radius: width / 2
        color: "transparent"
        border.width: ring.thickness - 1
        border.color: Theme.track
    }

    // Soft glow of the status color in the middle
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.62
        height: width
        radius: width / 2
        color: ring.shownTone
        opacity: 0.06
    }

    // Hide at 0 %: the round cap would otherwise draw a dot
    Shape {
        anchors.fill: parent
        visible: ring.shown > 0.005
        preferredRendererType: Shape.CurveRenderer
        // The arc changes per frame with every animation: triangulation in the worker thread,
        // otherwise it blocks the GUI thread and all animations stutter (especially on a laptop).
        asynchronous: true

        ShapePath {
            strokeColor: ring.shownTone
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.r
                radiusY: ring.r
                startAngle: -90
                sweepAngle: Math.max(0.001, 360 * ring.shown)
            }

        }

    }

    // Glowing tip at the end of the arc
    Item {
        x: ring.width / 2 + ring.r * Math.cos(ring.tipAngle)
        y: ring.height / 2 + ring.r * Math.sin(ring.tipAngle)
        visible: ring.showTip && ring.shown > 0.005

        Rectangle {
            anchors.centerIn: parent
            width: ring.thickness * 2.4
            height: width
            radius: width / 2
            color: ring.shownTone
            opacity: 0.25

            SequentialAnimation on scale {
                loops: Animation.Infinite

                NumberAnimation {
                    to: 1.35
                    duration: 1400
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    to: 1
                    duration: 1400
                    easing.type: Easing.InOutSine
                }

            }

        }

        Rectangle {
            anchors.centerIn: parent
            width: ring.thickness + 2
            height: width
            radius: width / 2
            color: ring.shownTone
            border.width: 2
            border.color: WalColors.withAlpha(WalColors.color0, 0.8)
        }

    }

    Column {
        anchors.centerIn: parent
        width: ring.width - 2 * ring.thickness - 24
        spacing: 2

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: ring.caption !== ""
            text: ring.caption.toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.bold: true
            font.letterSpacing: Theme.microSpacing
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: ring.value
            color: ring.shownTone
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: ring.valueSize
            font.bold: true
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: ring.detail !== ""
            text: ring.detail
            color: ring.detailColor
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeSmall
        }

    }

    Behavior on shown {
        NumberAnimation {
            duration: 480
            easing.type: Easing.OutCubic
        }

    }

    Behavior on shownTone {
        ColorAnimation {
            duration: 480
            easing.type: Easing.OutCubic
        }

    }

}
