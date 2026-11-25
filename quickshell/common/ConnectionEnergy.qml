pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// A short light segment follows the existing cubic connection line exactly.
Item {
    id: energy

    property point startPoint: Qt.point(0, 0)
    property point control1: Qt.point(0, 0)
    property point control2: Qt.point(0, 0)
    property point endPoint: Qt.point(0, 0)
    property color tone: "white"
    property bool busy: false
    property bool allowed: true
    property real phase: -0.18
    readonly property bool playing: flight.running
    readonly property real tail: Math.max(0, Math.min(1, phase - 0.28))
    readonly property real head: Math.max(0, Math.min(1, phase))
    readonly property real arrivalProgress: Math.max(0, Math.min(1, (phase - 0.96) / 0.54))
    readonly property real arrival: playing ? Math.sin(Math.PI * arrivalProgress) : 0
    readonly property real beamOpacity: playing ? Math.min(1, Math.max(0, phase / 0.12)) * Math.min(1, Math.max(0, (1.28 - phase) / 0.28)) : 0
    readonly property point a: pointAt(tail)
    readonly property point b: pointAt(head)
    readonly property point da: derivativeAt(tail)
    readonly property point db: derivativeAt(head)
    readonly property real span: (head - tail) / 3

    function pointAt(t) {
        const u = 1 - t;
        return Qt.point(u*u*u*startPoint.x + 3*u*u*t*control1.x + 3*u*t*t*control2.x + t*t*t*endPoint.x,
                        u*u*u*startPoint.y + 3*u*u*t*control1.y + 3*u*t*t*control2.y + t*t*t*endPoint.y);
    }

    function derivativeAt(t) {
        const u = 1 - t;
        return Qt.point(3*u*u*(control1.x-startPoint.x) + 6*u*t*(control2.x-control1.x) + 3*t*t*(endPoint.x-control2.x),
                        3*u*u*(control1.y-startPoint.y) + 6*u*t*(control2.y-control1.y) + 3*t*t*(endPoint.y-control2.y));
    }

    function begin() {
        if (busy && allowed && visible && !flight.running)
            flight.start();
    }

    onBusyChanged: begin()
    onAllowedChanged: {
        if (!allowed)
            flight.stop();
        else
            begin();
    }
    onVisibleChanged: {
        if (visible)
            begin();
        else
            flight.stop();
    }
    Component.onCompleted: begin()

    SequentialAnimation {
        id: flight
        // A fast connection also gets a complete pulse.
        NumberAnimation {
            target: energy
            property: "phase"
            from: -0.12
            to: 1.50
            duration: 1150
            easing.type: Easing.Linear
        }
        PauseAnimation { duration: 180 }
        onFinished: energy.begin()
    }

    // Short start pulse at the location before the bright tip sets off.
    Rectangle {
        readonly property real launch: Math.max(0, Math.min(1, energy.phase / 0.28))
        x: energy.startPoint.x - width / 2
        y: energy.startPoint.y - height / 2
        width: 6 + 20 * launch
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: energy.tone
        opacity: energy.playing && energy.phase > 0 ? (1 - launch) * 0.75 : 0
    }

    // Soft light seam under the narrow tail.
    Shape {
        anchors.fill: parent
        visible: energy.playing && energy.head > energy.tail
        opacity: energy.beamOpacity * 0.2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 12
            strokeColor: energy.tone
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: energy.a.x
            startY: energy.a.y
            PathCubic {
                x: energy.b.x; y: energy.b.y
                control1X: energy.a.x + energy.da.x * energy.span
                control1Y: energy.a.y + energy.da.y * energy.span
                control2X: energy.b.x - energy.db.x * energy.span
                control2Y: energy.b.y - energy.db.y * energy.span
            }
        }
    }

    // Short Bézier sections make a light tail that fades out toward the back.
    Repeater {
        model: 7
        Shape {
            id: beam
            required property int index
            readonly property real t0: Math.max(0, Math.min(1, energy.phase - (index + 1) * 0.04))
            readonly property real t1: Math.max(0, Math.min(1, energy.phase - index * 0.04))
            readonly property point a: energy.pointAt(t0)
            readonly property point b: energy.pointAt(t1)
            readonly property point da: energy.derivativeAt(t0)
            readonly property point db: energy.derivativeAt(t1)
            readonly property real span: (t1 - t0) / 3
            anchors.fill: parent
            visible: energy.playing && t1 > t0
            opacity: energy.beamOpacity * Math.pow(1 - index / 7, 1.5)
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 3.5 - beam.index * 0.3
                strokeColor: Qt.lighter(energy.tone, 1.25 - beam.index * 0.025)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: beam.a.x
                startY: beam.a.y
                PathCubic {
                    x: beam.b.x; y: beam.b.y
                    control1X: beam.a.x + beam.da.x * beam.span
                    control1Y: beam.a.y + beam.da.y * beam.span
                    control2X: beam.b.x - beam.db.x * beam.span
                    control2Y: beam.b.y - beam.db.y * beam.span
                }
            }
        }
    }

    Rectangle {
        x: energy.b.x - width / 2
        y: energy.b.y - height / 2
        width: 14; height: width; radius: width / 2
        color: energy.tone
        opacity: energy.beamOpacity * 0.26
    }
    Rectangle {
        x: energy.b.x - width / 2
        y: energy.b.y - height / 2
        width: 4; height: width; radius: width / 2
        color: Qt.lighter(energy.tone, 1.6)
        opacity: energy.beamOpacity
    }
}
