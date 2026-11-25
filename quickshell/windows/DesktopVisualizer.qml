import "../common"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Audio visualizer at the bottom edge of the monitor with workspace 1 (terminal stage, hypr/modules/home.lua).
// Only visible on workspace 1, glides with Hyprland's workspace slide, click-through.
//
// Structure (back -> front, in DesktopVisualizerLook.qml):
//   Echo   - holds peaks and falls slowly, blurred, brightest wal color -> aurora veil
//   Wave   - mirrored (bass in the middle), gradient through the wal colors from dark (bottom) to bright (top)
//   Crest  - bright line on the wave with a glow in the accent
//   Sparks - rise from the crest on onsets (fast rise of a band)
// Levels: DesktopCavaService (everything that goes out: music, Discord, browser ...). Only visible while
// something can be heard. The trailing happens here per frame: fast up, soft down.
// Wallpaper change: the new palette live, as a clean crossfade in sync with the wallpaper wave (palA/palB, mix).
//
// Layer: top (above the windows), NOT bottom. On bottom it lay between wallpaper and windows, but
// Hyprland stacks surfaces of one layer by appearance: the wallpaper wave (InkBloom, for video/scene an
// opaque still image) and video wallpapers appeared later and covered it. A replacement window on top
// still left gaps from 2 frames up to ~1 s when several surfaces came shortly
// after each other. On top no wallpaper can cover it. So it covers no windows, it fades
// out as soon as a window on workspace 1 reaches into its strip (the stage windows do not do that);
// fullscreen windows cover top surfaces in Hyprland anyway. Big shell surfaces (pickers, editors,
// power menu ...) lie on overlay, so still above it.
Scope {
    id: root

    readonly property int homeWorkspace: DesktopCavaService.homeWorkspace
    readonly property var homeMonitor: DesktopCavaService.homeMonitor
    readonly property var homeScreen: homeMonitor ? Quickshell.screens.find((s) => {
        return s.name === homeMonitor.name;
    }) ?? null : null
    readonly property real stripWidth: homeScreen ? homeScreen.width : 0
    readonly property real stripHeight: MachineConfig.px(300)

    // ==== State ====
    // any sound (music, Discord, browser ...), not the player status
    readonly property bool audible: DesktopCavaService.audible
    readonly property bool shown: !wsSlide.hidden
    // without sound completely gone, not even a line at the bottom
    property real fade: audible ? 1 : 0
    // Does a window of the workspace reach into the strip? Then gone (faster than for sound, so it does not
    // lie visibly above the opening window)
    readonly property bool covered: {
        const m = homeMonitor;
        if (!m)
            return false;

        const top = m.y + m.height / m.scale - stripHeight;
        return HyprlandData.windowList.some((w) => {
            return w.workspace && w.workspace.id === homeWorkspace && !w.hidden && w.at[1] + w.size[1] > top;
        });
    }
    property real free: covered ? 0 : 1
    // Lock screen (lock.sh): gone quickly before the photo the lock screen starts with, so it is neither
    // in the start nor in the thaw image; back only after unlocking. Start value from the service,
    // so a hot reload during the lock does not bring it back
    property real awake: DesktopCavaService.locked ? 0 : 1
    // Levels after trailing (mono, low -> high) and the slowly falling echo
    property var disp: new Array(DesktopCavaService.bars).fill(0)
    property var echo: new Array(DesktopCavaService.bars).fill(0)
    property string wavePath: ""
    property string crestPath: ""
    property string echoPath: ""
    property var sparks: []
    readonly property int sparkCount: 36
    readonly property real baseLine: MachineConfig.px(3)
    // Colors as fixed palettes (paletteOf): palA is shown, palB is the target of a wallpaper
    // change. During the change the windows draw both and crossfade with a shader (mix),
    // as long and with the same curve as WalColors' color change - so in sync with the wallpaper wave.
    // Set once (Component.onCompleted), no binding: that would follow every mixing step of WalColors
    // and jump in the middle of the change
    property var palA: null
    property var palB: null
    property real mix: 0
    // Crossfade path (second look + shader) built / shader shows the image (the direct look is then
    // hidden). Taken down in steps at the end (blendEnd): before, shader and hiding went away at the same
    // moment as the whole path -> in a recording the visualizer was missing for exactly one frame
    property bool blending: false
    property bool shaderOn: false

    // Palette from an object with color1..color7 (WalColors itself or its target fadeTarget)
    function paletteOf(c) {
        const cs = [c.color1, c.color2, c.color3, c.color4, c.color5, c.color6, c.color7];
        // sorted by brightness (dark -> bright) for the gradient in the wave: at the bottom the dark
        // tones of the wallpaper, brighter and brighter toward the top. Sorted instead of fixed roles, because the
        // order of brightness is different per palette
        const ramp = cs.slice().sort((a, b) => {
            return Qt.color(a).hslLightness - Qt.color(b).hslLightness;
        });
        return {
            "ramp": ramp,
            "crest": c.color7,
            "glow": WalColors.vividOf(cs.slice(0, 6))
        };
    }

    // WalColors has started a new color change (fadeTo sets the target and starts its animation right
    // after -> only read the duration afterwards)
    function beginPaletteBlend() {
        const t = WalColors.fadeTarget;
        if (!t || !t.color1)
            return ;

        const next = paletteOf(t);
        // a new change in the middle of the old one: continue from the closer state
        if (mixAnim.running) {
            mixAnim.stop();
            if (mix >= 0.5)
                palA = palB;

        }
        blendEnd.stop();
        blendDrop.stop();
        const anim = WalColors.fadeAnim;
        const ms = anim.running ? Math.max(1, anim.duration * (1 - WalColors.fadeT)) : 0;
        if (ms <= 1) {
            palA = next;
            palB = next;
            mix = 0;
            shaderOn = false;
            blending = false;
            return ;
        }
        palB = next;
        mix = 0;
        blending = true;
        shaderOn = true;
        mixAnim.duration = ms;
        mixAnim.start();
    }

    // Mirrored (bass in the middle) and pulled softly to the base line at the ends
    function mirrored(vals) {
        const n = vals.length;
        const out = new Array(2 * n);
        for (let i = 0; i < n; i++) {
            out[n - 1 - i] = vals[i];
            out[n + i] = vals[i];
        }
        // average slightly with the neighbors: soft hills instead of ECG needles. The peak is almost kept
        // by max(), only the flanks get wider
        const soft = new Array(out.length);
        for (let i = 0; i < out.length; i++) {
            const l = out[Math.max(0, i - 1)], r = out[Math.min(out.length - 1, i + 1)];
            soft[i] = Math.max(out[i] * 0.85, 0.25 * l + 0.5 * out[i] + 0.25 * r);
        }
        for (let i = 0; i < soft.length; i++)
            soft[i] *= Math.pow(Math.sin(Math.PI * (i + 0.5) / soft.length), 0.35);
        return soft;
    }

    function pointsFor(vals, scale) {
        const w = stripWidth, h = stripHeight;
        const top = h - baseLine;
        const pts = [];
        for (let i = 0; i < vals.length; i++)
            pts.push([i / (vals.length - 1) * w, top - Math.min(1, vals[i] * scale) * (top - MachineConfig.px(8))]);
        return pts;
    }

    // Catmull-Rom through all points as cubic Béziers (a soft curve instead of spikes)
    function curve(pts) {
        const h = stripHeight;
        const n = pts.length;
        let d = "M " + pts[0][0] + " " + pts[0][1];
        for (let i = 0; i < n - 1; i++) {
            const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(n - 1, i + 2)];
            const c1y = Math.min(h, p1[1] + (p2[1] - p0[1]) / 6);
            const c2y = Math.min(h, p2[1] - (p3[1] - p1[1]) / 6);
            d += " C " + (p1[0] + (p2[0] - p0[0]) / 6) + " " + c1y + " " + (p2[0] - (p3[0] - p1[0]) / 6) + " " + c2y + " " + p2[0] + " " + p2[1];
        }
        return d;
    }

    function closedPath(d) {
        return d + " L " + stripWidth + " " + (stripHeight + 2) + " L 0 " + (stripHeight + 2) + " Z";
    }

    function step(dt) {
        const target = DesktopCavaService.levels;
        const n = DesktopCavaService.bars;
        const k = Math.min(1, dt * 60);
        const nd = new Array(n), ne = new Array(n);
        const onsets = [];
        for (let i = 0; i < n; i++) {
            const t = target[i] || 0;
            const d = disp[i] || 0;
            // Rise almost instantly, fall softly
            const v = d + (t - d) * (t > d ? 0.55 : 0.14) * k;
            nd[i] = v;
            ne[i] = Math.max(v, (echo[i] || 0) - 0.006 * k);
            if (t - d > 0.16 && t > 0.3)
                onsets.push(i);

        }
        disp = nd;
        echo = ne;
        const wave = pointsFor(mirrored(nd), 1);
        const waveD = curve(wave);
        crestPath = waveD;
        wavePath = closedPath(waveD);
        echoPath = closedPath(curve(pointsFor(mirrored(ne), 1.08)));
        stepSparks(dt, onsets, wave);
    }

    function stepSparks(dt, onsets, wave) {
        const live = [];
        for (const s of sparks) {
            const life = s.life + dt / s.span;
            if (life < 1)
                live.push({
                "x": s.x + Math.sin((s.seed + life) * 6) * 0.3,
                "y": s.y - s.vy * dt,
                "vy": s.vy * 0.985,
                "life": life,
                "span": s.span,
                "size": s.size,
                "seed": s.seed
            });

        }
        // at most 2 new ones per frame, otherwise it turns into snow with drops
        const n = DesktopCavaService.bars;
        for (let j = 0; j < Math.min(2, onsets.length) && live.length < sparkCount; j++) {
            const i = onsets[Math.floor(Math.random() * onsets.length)];
            // Random mirror side
            const idx = Math.random() < 0.5 ? n - 1 - i : n + i;
            const p = wave[idx];
            live.push({
                "x": p[0] + (Math.random() - 0.5) * MachineConfig.px(20),
                "y": p[1],
                "vy": MachineConfig.px(45 + Math.random() * 70),
                "life": 0,
                "span": 1 + Math.random() * 0.8,
                "size": MachineConfig.px(2 + Math.random() * 2.5),
                "seed": Math.random() * 10
            });
        }
        sparks = live;
    }

    function setLocked(l) {
        DesktopCavaService.locked = l;
        awakeAnim.stop();
        awakeAnim.to = l ? 0 : 1;
        // off: fast (lock.sh waits for it before the photo); on: soft like the sound
        awakeAnim.duration = l ? lockHideMs : 600;
        awakeAnim.start();
    }

    readonly property int lockHideMs: 150

    Component.onCompleted: {
        palA = paletteOf(WalColors);
        palB = palA;
    }

    // lock.sh: "lock" before the lock screen photos, "unlock" after unlocking.
    // lock() reports whether it was visible right now -> only then lock.sh waits for the fade-out
    IpcHandler {
        function lock(): string {
            const was = root.shown && root.fade * root.free * root.awake > 0.01;
            root.setLocked(true);
            return was ? "visible" : "hidden";
        }

        function unlock(): void {
            root.setLocked(false);
        }

        target: "visualizer"
    }

    // For the power menu: is it visible right now (then it is in its desktop image)?
    // RestoreNone: on hot reload the old object should not reset the value of the new one
    Binding {
        target: DesktopCavaService
        property: "shownStrip"
        value: root.shown && root.fade * root.free * root.awake > 0.01 ? root.stripHeight : 0
        restoreMode: Binding.RestoreNone
    }

    NumberAnimation {
        id: awakeAnim

        target: root
        property: "awake"
        easing.type: Easing.OutCubic
    }

    Connections {
        function onFadeTargetChanged() {
            Qt.callLater(root.beginPaletteBlend);
        }

        target: WalColors
    }

    // Hyprland does not report moving/dragging windows as an event (HyprlandData otherwise only asks every 20 s):
    // while the visualizer is visible, ask more often
    Timer {
        interval: 1500
        repeat: true
        running: root.shown && root.audible
        onTriggered: HyprlandData.updateWindowList()
    }

    NumberAnimation {
        id: mixAnim

        target: root
        property: "mix"
        from: 0
        to: 1
        // like WalColors.fadeAnim
        easing.type: Easing.InOutQuad
        // 1) prepare the direct look already in the new palette - still hidden, the shader shows mix = 1
        onFinished: {
            root.palA = root.palB;
            blendEnd.restart();
        }
    }

    // 2) a few frames later: direct look visible and shader gone at the same moment
    Timer {
        id: blendEnd

        interval: 50
        onTriggered: {
            root.shaderOn = false;
            blendDrop.restart();
        }
    }

    // 3) then remove the crossfade path
    Timer {
        id: blendDrop

        interval: 100
        onTriggered: {
            root.blending = false;
            root.mix = 0;
        }
    }

    // WorkspaceSlide expects a WindowAnchor; here fixed to the stage's workspace
    QtObject {
        id: homeAnchor

        readonly property var monitor: root.homeMonitor
        readonly property int workspaceId: root.homeWorkspace
        readonly property bool here: !!monitor && !!monitor.activeWorkspace && monitor.activeWorkspace.id === workspaceId
    }

    WorkspaceSlide {
        id: wsSlide

        windowAnchor: homeAnchor
        active: true
        distance: root.stripWidth
    }

    FrameAnimation {
        // At most ~80 steps/s: step() rebuilds paths and sparks in JS. At 240 Hz (Qt timing from a 240 Hz monitor)
        // that took almost half the GUI thread and made the wallpaper transition stutter; cava's levels
        // come less often anyway, and this way it looks as before.
        property real acc: 0

        // keeps running until everything has faded after the stop
        running: root.shown && (root.audible || root.fade > 0) && root.free > 0 && root.awake > 0
        onTriggered: {
            acc += frameTime;
            if (acc < 1 / 80)
                return;

            root.step(Math.min(acc, 0.1));
            acc = 0;
        }
    }

    Behavior on free {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }

    }

    Behavior on fade {
        NumberAnimation {
            duration: 900
            easing.type: Easing.OutCubic
        }

    }

    Variants {
        model: root.homeScreen ? [root.homeScreen] : []

        PanelWindow {
            id: win

            required property var modelData

            screen: root.homeScreen
            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: root.stripHeight
            exclusiveZone: -1
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:desktop-visualizer"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            Item {
                id: stage

                anchors.fill: parent
                // Anti-aliasing via MSAA for the whole layer: the curve renderer (CurveRenderer) re-split the
                // paths every frame and cost ~25 % of a core, geometry + MSAA only a fraction
                layer.enabled: true
                layer.samples: 4
                opacity: root.fade * root.free * root.awake

                // Without a change: only lookA, drawn directly. During a change: both palettes render
                // invisibly into textures (hideSource), the shader shows mix(old, new)
                DesktopVisualizerLook {
                    id: lookA

                    anchors.fill: parent
                    pal: root.palA
                    wavePath: root.wavePath
                    crestPath: root.crestPath
                    echoPath: root.echoPath
                    sparks: root.sparks
                    sparkCount: root.sparkCount
                }

                Loader {
                    anchors.fill: parent
                    active: root.blending

                    sourceComponent: Item {
                        DesktopVisualizerLook {
                            id: lookB

                            anchors.fill: parent
                            pal: root.palB
                            wavePath: root.wavePath
                            crestPath: root.crestPath
                            echoPath: root.echoPath
                            sparks: root.sparks
                            sparkCount: root.sparkCount
                        }

                        ShaderEffectSource {
                            id: fromSrc

                            sourceItem: lookA
                            hideSource: root.shaderOn
                            live: true
                            samples: 4
                            visible: false
                        }

                        ShaderEffectSource {
                            id: toSrc

                            sourceItem: lookB
                            hideSource: true
                            live: true
                            samples: 4
                            visible: false
                        }

                        ShaderEffect {
                            property var fromTex: fromSrc
                            property var toTex: toSrc
                            property real mixT: root.mix

                            anchors.fill: parent
                            visible: root.shaderOn
                            fragmentShader: Qt.resolvedUrl("shaders/visualizer_mix.frag.qsb")
                        }

                    }

                }

                transform: Translate {
                    x: wsSlide.shift
                }

            }

        }

    }

}
