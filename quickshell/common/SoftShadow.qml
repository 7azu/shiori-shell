pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
    id: shadow

    property bool panel: false
    property real radius: panel ? 28 : 0
    property bool raised: false
    property real blur: panel ? 36 : 12
    property real spread: panel ? 2 : 0
    property real offsetY: panel ? 14 : 5
    property real opacityScale: 1
    // Transparent tiles need a cutout, so the shadow does not darken them.
    property bool hollow: false

    anchors.fill: parent
    z: -1

    RectangularShadow {
        anchors.fill: parent
        visible: !shadow.hollow
        radius: shadow.radius
        offset.y: shadow.offsetY
        blur: shadow.blur
        spread: shadow.spread
        color: Qt.rgba(0, 0, 0, Math.min(1, (shadow.panel ? 0.24 : (shadow.raised ? 0.27 : 0.17)) * shadow.opacityScale))
    }

    // Soft gradient with a cutout, without a separate texture per tile.
    ShaderEffect {
        readonly property size tileSize: Qt.size(shadow.width, shadow.height)
        readonly property size effectSize: Qt.size(width, height)
        readonly property point shadowOffset: Qt.point(0, shadow.offsetY)
        readonly property real cornerRadius: shadow.radius
        readonly property real blurRadius: shadow.blur
        readonly property real strength: Math.min(1, (shadow.raised ? 0.27 : 0.17) * shadow.opacityScale)
        readonly property real padding: blurRadius + Math.abs(shadowOffset.y) + 1

        visible: shadow.hollow
        x: -padding
        y: -padding
        width: shadow.width + 2 * padding
        height: shadow.height + 2 * padding
        fragmentShader: Qt.resolvedUrl("shaders/hollow_shadow.frag.qsb")
    }

}
