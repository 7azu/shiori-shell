import "../../common"
import "../../services"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Node (network/device) on its track or as a blip in the radar (Wi-Fi, Bluetooth; base: RadarPicker.qml).
// Delegate of the node Repeater: the picker sets key, item and the display (glyph, name, status, level ring).
Item {
    id: node

    required property var picker
    required property int index
    property string key: ""
    // Entry of the picker (for modeOf: blip in the radar) and what a click activates
    property var item: null
    property var clickItem: item
    property bool connected: false
    property bool busy: false
    // Waiting for input (Wi-Fi password): breathing ring, status in the accent color
    property bool waiting: false
    // Saved/paired: stronger than a foreign find
    property bool known: false
    // Saved, but out of range right now (Wi-Fi)
    property bool dimmed: false
    property string glyph: ""
    property string name: ""
    property string status: ""
    property bool ringShown: false
    property real ringLevel: 0
    property color ringTone: Theme.accent
    readonly property var target: picker.layout.pos[key]
    readonly property bool placed: target !== undefined && born
    readonly property bool selected: picker.selectedKey === key
    readonly property bool hovered: nodeArea.containsMouse
    // Starts in the middle and flies (staggered) to its place
    property bool born: false
    // Adopted target (null = hidden in the middle). Only switched in retarget() AFTER the
    // current position is remembered - if the position were tied directly to the layout, it would already be on the
    // new target when the place changes and the node would jump there.
    property var ct: null
    // Saved/paired nodes (and the finds in the scan) orbit: their target moves along with the orbit angle orbitA
    readonly property real tx: ct ? (ct.orbit ? picker.cx + ct.rx * Math.cos(ct.a + orbitA) : ct.x) : picker.cx
    readonly property real ty: ct ? (ct.orbit ? picker.cy + ct.ry * Math.sin(ct.a + orbitA) : ct.y) : picker.cy
    // ── Stop under the mouse ──
    // The orbit (picker.orbitAngle) always keeps going; the node under the mouse falls behind: lag = backlog
    // (radians), lagVel = how fast it grows (1 = stands still, -0.5 = catches up at 1.5 times the orbit speed).
    // lagVel follows its target softly (braking/starting instead of a jolt); before, the backlog was made up
    // by an animation in 0.4 s, that felt like a jump to the old place.
    readonly property bool orbiting: ct !== null && ct.orbit === true
    readonly property bool held: hovered && orbiting
    property real lag: 0
    property real lagVel: 0
    readonly property real orbitA: picker.orbitAngle - lag

    FrameAnimation {
        running: picker.animating && node.orbiting && (node.held || node.lag > 0 || Math.abs(node.lagVel) > 0.001)
        onTriggered: {
            // Orbit speed: one round in 90 s (RadarPicker, NumberAnimation on orbitAngle)
            const w = 2 * Math.PI / 90, dt = Math.min(frameTime, 0.05);
            // Catch up at most half as fast as the orbit, slower and slower just before the target (no snapping)
            const goal = node.held ? 1 : -Math.min(0.5, node.lag * 4);
            node.lagVel += (goal - node.lagVel) * (1 - Math.exp(-dt / 0.3));
            node.lag = Math.max(0, node.lag + node.lagVel * w * dt);
            if (node.lag < 1e-4 && !node.held) {
                node.lag = 0;
                node.lagVel = 0;
            }
        }
    }

    // Flight: from the position at the place change (fromX/Y) by the progress "fly" to the moving target.
    // At fly = 1 the node sits exactly on the orbit and keeps circling without animation.
    // (A spring animation on x/y restarts on every frame of the circling and never arrives.)
    property real fromX: picker.cx
    property real fromY: picker.cy
    property real fly: 1
    // It flies on an arc around the PC (angle and distance separately, squashed like the
    // orbit ellipse), not straight - otherwise a change left -> right would go right through the PC.
    readonly property real squash: picker.outerRy / Math.max(1, picker.outerRx)
    readonly property real fromA: Math.atan2((fromY - picker.cy) / squash, fromX - picker.cx)
    readonly property real fromR: Math.hypot(fromX - picker.cx, (fromY - picker.cy) / squash)
    readonly property real toA: Math.atan2((ty - picker.cy) / squash, tx - picker.cx)
    readonly property real toR: Math.hypot(tx - picker.cx, (ty - picker.cy) / squash)
    // The direction of rotation is fixed at the start (retarget), so the arc does not flip in mid-flight
    property int flyDir: 1
    readonly property real dA: {
        let d = toA - fromA;
        if (flyDir > 0) {
            while (d < -0.5)d += 2 * Math.PI
            while (d >= 2 * Math.PI - 0.5)d -= 2 * Math.PI
        } else {
            while (d > 0.5)d -= 2 * Math.PI
            while (d <= -2 * Math.PI + 0.5)d += 2 * Math.PI
        }
        return d;
    }
    // Out of the middle or into the middle: straight out/in
    readonly property real curA: fromR < 2 ? toA : (toR < 2 ? fromA : fromA + dA * fly)
    readonly property real curR: fromR + (toR - fromR) * fly
    readonly property real cxNow: picker.cx + curR * Math.cos(curA)
    readonly property real cyNow: picker.cy + curR * Math.sin(curA) * squash
    // Only real place changes trigger a flight, not every recompute of the layout
    readonly property string targetKey: placed ? (target.orbit ? "o" + target.a.toFixed(4) + "/" + target.rx.toFixed(1) + "/" + target.ry.toFixed(1) : target.x.toFixed(1) + "/" + target.y.toFixed(1)) : "hidden"
    // Scan find: lights up when the beam brushes it and fades afterwards (like a real radar)
    readonly property bool asBlip: picker.shownMode === "scan" && picker.modeOf(item) === "scan"
    readonly property real behind: {
        const a = Math.atan2((cyNow - picker.cy) * (picker.outerRx + 30) / (picker.outerRy + 30), cxNow - picker.cx) * 180 / Math.PI;
        return ((picker.sweepDeg - a) % 360 + 360) % 360;
    }
    readonly property bool blipLive: asBlip && picker.sweeping
    readonly property real lit: blipLive ? Math.max(0, 1 - behind / 320) : 1
    readonly property real hit: blipLive ? Math.max(0, 1 - behind / 45) : 0

    function retarget() {
        // Order matters: first hold the visible position (still to the old target) ...
        const x = cxNow, y = cyNow;
        flyAnim.stop();
        fromX = x;
        fromY = y;
        fly = 0;
        // ... only then take the new target and fly there
        ct = placed ? target : null;
        // Shortest arc; if the target is almost opposite, rather over the top than through the label below
        let d = toA - fromA;
        while (d > Math.PI)d -= 2 * Math.PI
        while (d <= -Math.PI)d += 2 * Math.PI
        if (Math.abs(d) > 0.8 * Math.PI && Math.sin(fromA + d / 2) > 0)
            d -= Math.sign(d) * 2 * Math.PI;

        flyDir = d < 0 ? -1 : 1;
        flyAnim.start();
    }

    onTargetKeyChanged: retarget()
    x: cxNow - width / 2
    y: cyNow - picker.nodeR
    width: 112
    height: 2 * picker.nodeR + 38
    opacity: placed ? 1 : 0
    scale: placed ? 1 : 0.3
    visible: opacity > 0.01
    z: hovered || selected ? 2 : (connected ? 1 : 0)
    Component.onCompleted: {
        picker.registerNode(key, node);
        bornTimer.start();
    }
    Component.onDestruction: {
        if (picker.nodeMap[key] === node)
            picker.registerNode(key, null);

        // If the node under the mouse disappears, no hover may get stuck
        if (picker.hoveredKey === key)
            picker.hoveredKey = "";

    }
    onConnectedChanged: {
        if (connected && picker.animating)
            pingAnim.restart();

    }

    // ── The node as a glowing symbol (no bubble) ──
    // No frame: everything in the scene glows (stars, sparkles, disc), an outlined button looked like
    // glued in from an app. So the device symbol itself glows, with a glow and a tiny sparkle.
    // starR = radius of the old bubble (scale for ping/glow); level/connect arcs lie on ringR.
    readonly property real starR: picker.starR
    readonly property real ringR: starR - 4
    // Bright star color; connected/selected/radar hit warm (tinted with the accent: the pure accent is dark with
    // many palettes and hardly glowed on the dark background)
    readonly property color cream: Qt.lighter(WalColors.color7, 1.15)
    readonly property color warm: Qt.tint(cream, WalColors.withAlpha(WalColors.vividAccent, 0.55))
    readonly property color tone: node.connected || node.selected ? warm : node.asBlip ? WalColors.withAlpha(warm, 0.35 + 0.6 * node.lit) : WalColors.withAlpha(cream, node.hovered ? 1 : (node.known ? 0.8 : 0.5))
    readonly property color glowTone: node.connected || node.selected || node.asBlip ? WalColors.vividAccent : cream
    // Strength of the glow; when connected it breathes slowly (own rhythm per node)
    readonly property real glowK: node.connected ? 0.8 + 0.2 * Math.sin(picker.starTime * 1.1 + index) : node.selected ? 0.8 : node.hovered ? 0.7 : node.asBlip ? 0.2 + 0.6 * node.lit : (node.known ? 0.5 : 0.3)
    // ── Idle animation while orbiting: the symbol breathes (size + glow), rhythm offset per node ──
    // idleK fades in/out softly (hover stops it -> breathing fades out, the hover enlargement fades in)
    readonly property real breath: 0.5 + 0.5 * Math.sin(picker.starTime * 2 * Math.PI / 4.5 + index * 1.7)
    property real idleK: orbiting && !held ? 1 : 0
    property real hoverK: hovered || selected ? 1 : 0
    readonly property real glyphScale: 1 + 0.07 * breath * idleK + 0.12 * hoverK

    Behavior on idleK {
        NumberAnimation {
            duration: 500
            easing.type: Easing.InOutSine
        }

    }

    Behavior on hoverK {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }

    }

    Timer {
        id: bornTimer

        interval: 60 + Math.min(node.index, 14) * 40
        onTriggered: node.born = true
    }

    // Ping when the connection stands
    Rectangle {
        id: ping

        property real t: 1

        x: (node.width - width) / 2
        y: picker.nodeR - height / 2
        width: 2 * node.starR * (1 + 1.2 * t)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: WalColors.withAlpha(WalColors.color4, 0.7 * (1 - t))

        NumberAnimation on t {
            id: pingAnim

            running: false
            from: 0
            to: 1
            duration: 900
            easing.type: Easing.OutCubic
        }

    }

    // Blip hit: a fine ring runs out (the symbol itself lights up meanwhile, see bubble.opacity)
    Rectangle {
        x: (node.width - width) / 2
        y: picker.nodeR - height / 2
        width: 2 * node.starR * (1 + 0.8 * (1 - node.hit))
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.vividAccent, 0.5 * node.hit)
        visible: node.hit > 0.01
    }

    // Connected: a tiny satellite circles the symbol
    Item {
        x: node.width / 2
        y: picker.nodeR
        rotation: picker.wavePhase * 180 / Math.PI
        opacity: node.connected ? 0.9 : 0
        visible: opacity > 0.01

        Rectangle {
            x: node.ringR + 4 - width / 2
            y: -height / 2
            width: 4
            height: 4
            radius: 2
            color: Qt.lighter(WalColors.color4, 1.3)
        }

        Behavior on opacity {
            Smooth {
            }

        }

    }

    // Soft glow (connected in the accent color, radar hit depending on the beam, otherwise a touch)
    Shape {
        id: halo

        readonly property real r: node.starR * 1.7
        readonly property color tone: node.connected || node.asBlip ? WalColors.vividAccent : WalColors.color7
        property real strength: node.connected ? 0.2 : (node.asBlip ? 0.14 * node.lit : (node.hovered || node.selected ? 0.07 : 0))

        x: node.width / 2 - r
        y: picker.nodeR - r
        width: 2 * r
        height: 2 * r
        preferredRendererType: Shape.CurveRenderer
        opacity: node.dimmed && !node.hovered ? 0.5 : 1

        ShapePath {
            strokeColor: "transparent"
            startX: 0
            startY: 0

            fillGradient: RadialGradient {
                centerX: halo.r
                centerY: halo.r
                focalX: halo.r
                focalY: halo.r
                centerRadius: halo.r

                GradientStop {
                    position: 0
                    color: WalColors.withAlpha(halo.tone, halo.strength)
                }

                GradientStop {
                    position: 1
                    color: WalColors.withAlpha(halo.tone, 0)
                }

            }

            PathLine { x: 2 * halo.r; y: 0 }
            PathLine { x: 2 * halo.r; y: 2 * halo.r }
            PathLine { x: 0; y: 2 * halo.r }
            PathLine { x: 0; y: 0 }
        }

        Behavior on strength {
            NumberAnimation {
                duration: 220
            }

        }

    }

    // Placeholder in bubble size: name, click area and rings align to it
    Item {
        id: bubble

        x: (node.width - width) / 2
        width: 2 * picker.nodeR
        height: width
        // Saved but out of range (Wi-Fi): dimmed; radar finds follow the beam
        opacity: (node.hovered || node.selected ? 1 : 0.45 + 0.55 * node.lit) * (node.dimmed && !node.hovered ? 0.5 : 1)

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }

        }

        // The symbol: sharp in front, behind it the same glyph blurred as a glow. Both scale together
        // (glyphScale: breathing while orbiting, bigger on hover/selection).
        Item {
            anchors.centerIn: parent
            width: 40
            height: 40
            scale: node.glyphScale

            Text {
                anchors.centerIn: parent
                text: node.glyph
                font.family: picker.mono
                font.pixelSize: 24
                // Distributed glyphs scale smoothly (native rendering snaps to pixels while breathing)
                renderType: Text.QtRendering
                color: node.glowTone
                opacity: node.glowK * (0.8 + 0.2 * node.breath * node.idleK)
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1
                    blurMax: 24
                    brightness: 0.3
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 240
                    }

                }

            }

            Text {
                anchors.centerIn: parent
                text: node.glyph
                font.family: picker.mono
                font.pixelSize: 24
                // Distributed glyphs scale smoothly (native rendering snaps to pixels while breathing)
                renderType: Text.QtRendering
                color: node.tone

                Behavior on color {
                    ColorAnimation {
                        duration: 220
                    }

                }

            }

        }

        // Tiny sparkle at the top left of the symbol (only brightness animated, otherwise it trembles); set on whole pixels.
        // On the left, because the battery and connect arcs start at the top and run to the right
        Sparkle {
            x: Math.round(bubble.width / 2 - 14 - width / 2)
            y: Math.round(bubble.height / 2 - 13 - height / 2)
            size: 3
            rays: 3
            color: node.cream
            glowColor: node.glowTone
            twinkle: 0.5 + 0.5 * Math.sin(picker.starTime * 1.7 + node.index * 2.3)
            opacity: node.connected || node.selected || node.hovered ? 1 : (node.known ? 0.7 : 0.35)
        }

        // Hover/selection shows the symbol itself (brighter, bigger, stronger glow), no extra ring

        // Level as a fine arc around the symbol (Wi-Fi: signal strength, Bluetooth: battery)
        Shape {
            anchors.centerIn: parent
            width: 2 * node.ringR + 2
            height: width
            visible: node.ringShown
            opacity: 0.75
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: node.ringTone
                strokeWidth: 1.5
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                PathAngleArc {
                    centerX: node.ringR + 1
                    centerY: node.ringR + 1
                    radiusX: node.ringR
                    radiusY: node.ringR
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0, Math.min(1, node.ringLevel))
                }

            }

        }

        // Circling arc while connecting/disconnecting/pairing
        Shape {
            anchors.centerIn: parent
            width: 2 * node.ringR + 2
            height: width
            visible: node.busy
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: WalColors.color4
                strokeWidth: 1.5
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                PathAngleArc {
                    centerX: node.ringR + 1
                    centerY: node.ringR + 1
                    radiusX: node.ringR
                    radiusY: node.ringR
                    startAngle: 0
                    sweepAngle: 90
                }

            }

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                running: node.busy && picker.animating
            }

        }

        // Waiting for input (Wi-Fi password): a ring that breathes slowly (opacity only)
        Rectangle {
            anchors.centerIn: parent
            width: 2 * node.ringR + 2
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: WalColors.withAlpha(WalColors.color4, 0.35 + 0.4 * picker.busyWave)
            visible: node.waiting
        }

    }

    Text {
        id: nameText

        anchors.horizontalCenter: parent.horizontalCenter
        // Below the tips and the level arc (ringR), not below the old bubble
        y: picker.nodeR + node.ringR + 4
        width: node.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: node.name
        font.family: picker.mono
        font.pixelSize: 10
        font.bold: node.connected || node.selected
        color: node.connected || node.selected ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, node.known ? 0.7 : 0.5)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: nameText.bottom
        anchors.topMargin: 1
        text: node.status
        font.family: picker.mono
        font.pixelSize: 9
        color: node.connected || node.busy || node.waiting ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.38)
    }

    MouseArea {
        id: nodeArea

        x: bubble.x - 6
        width: bubble.width + 12
        height: node.height
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: {
            if (containsMouse)
                picker.hoveredKey = node.key;
            else if (picker.hoveredKey === node.key)
                picker.hoveredKey = "";
        }
        onClicked: (mouse) => {
            picker.select(node.key);
            if (mouse.button === Qt.LeftButton)
                picker.activate(node.clickItem);

            picker.focusSearch();
        }
    }

    // Slight overshoot like the spring before
    NumberAnimation {
        id: flyAnim

        target: node
        property: "fly"
        from: 0
        to: 1
        duration: 950
        easing.type: Easing.OutBack
        easing.overshoot: 1.3
    }

    Behavior on opacity {
        Smooth {
            duration: 260
        }

    }

    Behavior on scale {
        Springy {
        }

    }

}
