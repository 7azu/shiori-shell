import "../../services"
import QtQuick

// Connection device -> PC in the radar picker (Wi-Fi, Bluetooth; base: RadarPicker.qml). Delegate of the
// line Repeater: the picker sets key and the connection state from its model.
// Matching the black hole: a glowing gas stream (pickers/shaders/stream.frag) on a direct path
// from the device into the hole, on it an animated sine wave whose crests travel into the hole. Thinner, brighter
// and hotter toward the hole, the plasma texture flows in. Connecting: a glowing head feels its way from the device
// to the hole. Connected: brighter, light bursts run along, one flash.
// Here only geometry (curve parameters + bounding box, so the shader only computes there) and state.
Item {
    id: link

    required property var picker
    required property int index
    property string key: ""
    property bool connected: false
    property bool busy: false
    // Waiting for input (Wi-Fi password): the stream stops just before the device
    property bool waiting: false
    readonly property var node: picker.nodeMap[key] || null
    readonly property bool placed: node !== null && node.placed
    // How far the stream reaches from the device toward the hole (0..1). Connecting: fills slowly,
    // connected: runs full, disconnected: pulls back
    readonly property real reachTarget: !placed ? 0 : (connected ? 1 : (busy ? 0.85 : (waiting ? 0.3 : 0)))
    property real reach: reachTarget
    property real strength: connected ? 1 : ((busy || waiting) && placed ? 0.5 : 0)
    // 1 -> 0 right after connecting: the stream flashes up once
    property real flash: 0
    readonly property bool flowing: connected && reach > 0.995
    property real live: flowing ? 1 : 0
    // Flow clock: accumulated, so the speed change (connecting -> connected) does not jump
    property real flow: 0
    // Sine wave on the stream: ~42 px wavelength, the amplitude breathes slightly and swings out more strongly
    // briefly when connecting (flash); phase has its own clock (one wave in 2 s, connecting half as fast)
    readonly property real seed: index * 1.3
    readonly property real amp: 5 + Math.sin(picker.sway * 2 + seed) * 0.8 + 5 * flash
    property real wphase: 0
    // ── Geometry (screen, y down): straight base line like pathPt in stream.frag ──
    readonly property real nx: node ? node.cxNow : picker.cx
    readonly property real ny: node ? node.cyNow : picker.cy
    readonly property real dist: Math.max(1, Math.hypot(nx - picker.cx, ny - picker.cy))
    readonly property real theta0: Math.atan2(ny - picker.cy, nx - picker.cx)
    // At the device just before the star; at the hole just inside the shadow (there the stream disappears)
    readonly property real r0: Math.max(10, dist - picker.starR - 3)
    readonly property real rIn: picker.pcR * 0.6
    readonly property real len: Math.max(1, r0 - rIn)
    // Hidden until just before the shadow edge, fully visible after that
    readonly property real holeFade: Math.min(0.5, Math.max(0.02, (picker.pcR * 1.05 - rIn) / len))
    // Bounding box of the line including amplitude and glow: the shader only computes there
    readonly property rect box: {
        const ax = picker.cx + Math.cos(theta0) * rIn, ay = picker.cy + Math.sin(theta0) * rIn;
        const bx = picker.cx + Math.cos(theta0) * r0, by = picker.cy + Math.sin(theta0) * r0;
        const m = 30;
        return Qt.rect(Math.floor(Math.min(ax, bx) - m), Math.floor(Math.min(ay, by) - m), Math.ceil(Math.abs(bx - ax) + 2 * m), Math.ceil(Math.abs(by - ay) + 2 * m));
    }

    anchors.fill: parent
    visible: reach > 0.002 && strength > 0.01
    onConnectedChanged: {
        if (connected && picker && picker.animating)
            picker.pingPc();

    }
    // The stream has arrived at the hole (also when opening with an existing connection)
    onFlowingChanged: {
        if (flowing && picker && picker.animating)
            flashAnim.restart();

    }

    FrameAnimation {
        running: link.visible && !!link.picker && link.picker.animating
        onTriggered: {
            link.flow = (link.flow + frameTime * (link.connected ? 1.1 : 0.5)) % 10000;
            link.wphase = (link.wphase + frameTime * Math.PI * (link.connected ? 1 : 0.5)) % (2 * Math.PI * 1000);
        }
    }

    NumberAnimation {
        id: flashAnim

        target: link
        property: "flash"
        from: 1
        to: 0
        duration: 1300
        easing.type: Easing.OutCubic
    }

    Behavior on live {
        NumberAnimation {
            duration: 800
            easing.type: Easing.OutCubic
        }

    }

    Behavior on strength {
        NumberAnimation {
            duration: 500
            easing.type: Easing.OutCubic
        }

    }

    // Connecting: fill slowly (waits for the service), connected: full quickly, disconnected: pull back
    Behavior on reach {
        NumberAnimation {
            duration: link.connected ? 650 : ((link.busy || link.waiting) ? 2600 : 500)
            easing.type: (link.busy || link.waiting) && !link.connected ? Easing.OutQuad : Easing.OutCubic
        }

    }

    ShaderEffect {
        property point origin: Qt.point(link.box.x, link.box.y)
        property point boxSize: Qt.point(link.box.width, link.box.height)
        property point center: Qt.point(link.picker.cx, link.picker.cy)
        property real r0: link.r0
        property real rIn: link.rIn
        property real theta0: link.theta0
        property real holeFade: link.holeFade
        property real reach: link.reach
        property real strength: link.strength
        property real flash: link.flash
        property real live: link.live
        property real time: link.flow
        property real len: link.len
        property real amp: link.amp
        property real wavelen: 42
        property real wphase: link.wphase
        property color accent: WalColors.vividAccent
        property color hot: Qt.lighter(WalColors.color7, 1.08)

        x: link.box.x
        y: link.box.y
        width: link.box.width
        height: link.box.height
        fragmentShader: Qt.resolvedUrl("../shaders/stream.frag.qsb")
    }

}
