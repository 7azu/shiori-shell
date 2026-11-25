pragma ComponentBehavior: Bound

import QtQuick

// Rectangle with round corners that clips its content at these corners (replacement for Quickshell's
// ClippingRectangle, without a border). Reason: ClippingRectangle draws background and content through a
// mask texture (invisible Rectangle with a layer). After a shell restart it was sometimes missing; then
// the whole card was invisible, and because the mask never changes, it was never redrawn either.
// Here the shader computes the shape itself, there is only the content's layer texture, and that one is
// redrawn on every change of the content.
Item {
    id: root

    property color color: "transparent"
    property real radius: 0
    default property alias data: contentItem.data
    readonly property alias contentItem: contentItem

    Item {
        id: contentItem

        anchors.fill: parent
        layer.enabled: true

        layer.effect: ShaderEffect {
            readonly property color backgroundColor: root.color
            readonly property size size: Qt.size(root.width, root.height)
            readonly property real radius: root.radius

            fragmentShader: Qt.resolvedUrl("shaders/roundclip.frag.qsb")
        }

    }

}
