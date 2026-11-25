// "Ink Bloom" on a wallpaper change: the *new* wallpaper runs like ink from the start point over the
// old one (track matte), across all monitors. Goal: both sides live for as long as possible.

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Images (awww), videos (AnimatedWallpaper, bottom layer) and scenes (linux-wallpaperengine,
// background layer) are different surfaces. Depending on the target:
//   Image: the overlay (windows/InkBloom.qml) shows the still image of the new one in the shape, outside the
//          old one keeps running live. Only when everything is covered it switches underneath (applyNow),
//          then waits until awww shows it (markReady).
//   Video: switch right away; AnimatedWallpaper masks the new player itself (maskMode "newSlot",
//          windows/shaders/inkmask.frag). Spreading starts with the first frame -> both live.
//   Scene: old video: switch right away, spreading starts as soon as the new scene draws; the video
//          becomes transparent in the shape (maskMode "reveal") -> both live.
//          Old image/scene: like an image - still image of the new scene (wallpaper_still.sh) in the overlay,
//          linux-wallpaperengine only starts when everything is covered. Before, the new scene already ran
//          live under the shape: its start (textures, shaders on the GPU) made the wave visibly stutter
//          (single frames stood still, then jumps) and it began ~0.4 s later.
// Flow: prepare (load images) -> wait (the new one starts) -> spread (cover 0 -> 1) -> settle (image only)
QtObject {
    id: root

    // "idle" | "prepare" | "wait" | "spread" | "settle" | "closing" | "fadeout" (scene: the still image fades out)
    property string phase: "idle"
    readonly property bool active: phase !== "idle"
    // "image" | "video" | "scene"
    property string kind: ""
    property bool oldVideo: false
    property bool earlyApply: false
    property bool applied: false
    // Monitors without animation (only the bar monitor is animated, WallpaperPickerState.animScreen): there
    // the overlay freezes the old still image, underneath awww sets the new one (paintOthers), the wave
    // makes it visible. Number of animated monitors for the final check (closeProbe).
    property var staticNames: []
    property int animCount: 1
    property bool othersReady: true
    property bool needOld: false
    // Overlay on the bar monitor: "none" | "newStill" (target image, scene over image/scene) | "freezeOld"
    // (only for the monitors without animation now, see modeFor)
    readonly property string overlayMode: !active ? "none" : (kind === "image" || (kind === "scene" && !oldVideo)) ? "newStill" : "none"
    // AnimatedWallpaper: "none" | "newSlot" (target video) | "reveal" (target scene over video)
    readonly property string maskMode: !active ? "none" : kind === "video" ? "newSlot" : (kind === "scene" && oldVideo) ? "reveal" : "none"
    property real cover: 0
    property point origin: Qt.point(0, 0)
    property real maxR: 1000
    property string target: ""
    // Same encoding as WallpaperPickerState.animationUrl (for the comparison in AnimatedWallpaper)
    readonly property string targetUrl: target ? "file://" + target.split("/").map(encodeURIComponent).join("/") : ""
    property bool ready: false
    property real time: 0
    // Monitor name -> frozen old image (freezeOld)
    property var oldStills: ({
    })
    // Monitor format ("WxH") -> still image of the new one (newStill)
    property var newStills: ({
    })
    // Monitors whose overlay image is loaded
    property var loaded: ({
    })
    // Change chosen during a running transition
    property var pending: null
    readonly property int spreadMs: 2200
    readonly property int hurryMs: 350
    // One still image per aspect ratio, in the size of the biggest monitor of that format
    readonly property var stillSizes: {
        const best = {
        };
        for (const s of Quickshell.screens) {
            const w = Math.round(s.width * (s.devicePixelRatio || 1));
            const h = Math.round(s.height * (s.devicePixelRatio || 1));
            const aspect = (w / h).toFixed(2);
            if (!best[aspect] || w * h > best[aspect][0] * best[aspect][1])
                best[aspect] = [w, h];

        }
        return Object.values(best).map((b) => {
            return b[0] + "x" + b[1];
        });
    }
    readonly property string stillScript: Qt.resolvedUrl("../scripts/wallpaper_still.sh").toString().replace("file://", "")

    // Get still images (per format): the new one (newStill) or the old one (freeze)
    property Component stillComponent: Component {
        Process {
            id: sp

            property bool forNew: false
            property var found: ({
            })

            onExited: (code) => {
                if (root.phase === "prepare") {
                    if (code !== 0 || Object.keys(found).length === 0)
                        root.abort();
                    else if (forNew)
                        root.newStills = found;
                    else
                        root.oldStills = root.perScreen(found);
                }
                Qt.callLater(sp.destroy);
            }

            stdout: SplitParser {
                onRead: (line) => {
                    const i = line.indexOf(" ");
                    if (i > 0)
                        sp.found[line.slice(0, i)] = "file://" + line.slice(i + 1).split("/").map(encodeURIComponent).join("/");

                }
            }

        }

    }

    function fetchStills(path, forNew) {
        const proc = stillComponent.createObject(root, {
            "forNew": forNew,
            "command": ["bash", stillScript, path].concat(stillSizes)
        });
        proc.running = true;
    }

    // Overlay per monitor: still-image monitors always "freezeOld", the bar monitor by overlayMode
    function modeFor(screenName) {
        return staticNames.includes(screenName) ? "freezeOld" : overlayMode;
    }

    property NumberAnimation spreadAnim: NumberAnimation {
        target: root
        property: "cover"
        to: 1
        duration: root.spreadMs
        // Start flowing visibly right away and glide long into the corners
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1]
        onFinished: root.spreadDone()
    }

    // Wait a few frames until the overlay is really on screen before switching underneath
    // or the shape grows
    property Timer settleDelay: Timer {
        interval: 70
        onTriggered: root.overlayShown()
    }

    // If something hangs (image does not load, the new one never reports): do not stand still forever
    property Timer failsafe: Timer {
        interval: 6000
        onTriggered: {
            console.log("Wallpaper transition: timeout in phase", root.phase);
            if (root.phase === "prepare")
                root.abort();
            else if (root.phase === "wait") {
                root.othersReady = true;
                root.ready = true;
                root.beginSpread();
            }
            else if (root.phase === "settle")
                root.finish();
        }
    }

    // Flowing of the edge, only runs during the transition
    property NumberAnimation clock: NumberAnimation {
        target: root
        property: "time"
        from: 0
        to: 600
        duration: 600000
        running: root.active
        loops: Animation.Infinite
    }

    // Now set the new wallpaper underneath (apply-wallpaper.sh)
    signal applyNow(string path)
    // Transition done: the old one may go (end the old scene, remove the old players)
    signal finished(string path)
    // The new wallpaper visibly starts to spread (for the "Wallpaper changed" message)
    signal spreadStarted(string path)

    onPhaseChanged: console.log("Wallpaper transition:", phase, kind, target.split("/").pop())

    function kindOf(path) {
        if (path.endsWith("/project.json"))
            return "scene";

        return /\.(gif|mp4|webm|mkv|mov|m4v)$/i.test(path) ? "video" : "image";
    }

    function sizeFor(screen) {
        const w = Math.round(screen.width * (screen.devicePixelRatio || 1));
        const h = Math.round(screen.height * (screen.devicePixelRatio || 1));
        const aspect = (w / h).toFixed(2);
        return stillSizes.find((s) => {
            const p = s.split("x");
            return (p[0] / p[1]).toFixed(2) === aspect;
        }) || stillSizes[0];
    }

    function perScreen(bySize) {
        const out = {
        };
        for (const s of Quickshell.screens) out[s.name] = bySize[sizeFor(s)] || ""
        return out;
    }

    // current: {"path": current wallpaper, "video": does it run in AnimatedWallpaper,
    //           "staticNames": monitors without animation, "animCount": number of animated monitors}
    function start(path, globalPoint, current) {
        // One is already running: let it finish quickly, then start the new one
        if (active) {
            pending = {
                "path": path,
                "origin": globalPoint
            };
            if (phase === "spread") {
                spreadAnim.stop();
                spreadAnim.duration = hurryMs;
                spreadAnim.from = cover;
                spreadAnim.start();
            }
            return ;
        }
        target = path;
        sceneFade.stop();
        overlayFade = 1;
        kind = kindOf(path);
        palette = null;
        paletteApplied = false;
        paletteProc.running = false;
        paletteProc.forTarget = path;
        paletteProc.command = ["python3", Qt.resolvedUrl("../scripts/wal_preview.py").toString().replace("file://", ""), path];
        paletteProc.running = true;
        oldVideo = !!(current && current.video);
        // Target image over video/scene: awww lies hidden underneath and may already load the new image
        // while spreading (saves ~1 s at the end for big PNGs)
        earlyApply = kind === "image" && (oldVideo || !!(current && current.path.endsWith("/project.json")));
        applied = false;
        ready = false;
        origin = globalPoint;
        let far = 0;
        for (const s of Quickshell.screens) {
            for (const c of [[s.x, s.y], [s.x + s.width, s.y], [s.x, s.y + s.height], [s.x + s.width, s.y + s.height]]) far = Math.max(far, Math.hypot(c[0] - globalPoint.x, c[1] - globalPoint.y))
        }
        maxR = far;
        cover = 0;
        oldStills = {
        };
        newStills = {
        };
        loaded = {
        };
        staticNames = (current && current.staticNames) || [];
        animCount = (current && current.animCount) || Quickshell.screens.length;
        othersReady = staticNames.length === 0;
        needOld = overlayMode === "freezeOld" || staticNames.length > 0;
        phase = "prepare";
        failsafe.restart();
        if (overlayMode === "none" && !needOld) {
            // Video or scene over video, everything animated: nothing to prepare, switch underneath right away
            phase = "wait";
            applyNow(path);
            return ;
        }
        // Bar monitor without its own overlay (video, scene over video): switch there right away; the
        // still-image monitors prepare their overlay in parallel
        if (overlayMode === "none") {
            applied = true;
            applyNow(path);
        }
        // Get the overlay images: the old one (freeze) and/or the new still image (target image)
        if (needOld)
            fetchStills(current ? current.path : "", false);
        if (overlayMode === "newStill")
            fetchStills(path, true);
    }

    // Monitors that need an overlay image
    function overlayScreens() {
        return Quickshell.screens.filter((s) => {
            return modeFor(s.name) !== "none";
        });
    }

    // InkBloom reports: the overlay image for this monitor is loaded
    function stillLoaded(screenName) {
        if (phase !== "prepare")
            return ;

        const l = Object.assign({
        }, loaded);
        l[screenName] = true;
        loaded = l;
        if (overlayScreens().every((s) => {
            return loaded[s.name];
        }))
            settleDelay.restart();

    }

    function overlayShown() {
        if (phase !== "prepare")
            return ;

        phase = "wait";
        // Still-image monitors: the old one is frozen -> set the new still image underneath
        if (!othersReady) {
            const path = target;
            paintOthers(path, (ok) => {
                if (path === root.target) {
                    root.othersReady = true;
                    root.tryBegin();
                }
            });
        }
        if (overlayMode === "freezeOld" && !applied) {
            // Scene over image/scene: the old one is frozen -> start underneath, wait for the scene
            applied = true;
            applyNow(target);
        }
        tryBegin();
    }

    // Start the wave as soon as all are ready: still-image monitors and the bar monitor (image: still image
    // in the overlay is enough; video/scene: already draws)
    function tryBegin() {
        if (phase === "wait" && othersReady && (overlayMode === "newStill" || ready))
            beginSpread();
    }

    // WallpaperPickerState sets the still image on the monitors without animation (awww)
    property var paintOthers: function(path, done) {
        done(true);
    }

    // ==== Fade the pywal colors in sync with the wave ====
    // The target's palette is computed in advance at the start (scripts/wal_preview.py, same cache as
    // wal) and fades over the duration of the wave; when wal later writes colors.json, it is already
    // the same palette (WalColors then ignores it). Other programs (kitty, GTK, borders) are still
    // recolored by wal itself.
    property var palette: null
    property bool paletteApplied: false
    property real spreadStartedAt: 0
    property int spreadDuration: spreadMs

    property Process paletteProc: Process {
        property string forTarget: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.paletteProc.forTarget !== root.target)
                    return ;

                try {
                    root.palette = JSON.parse(text);
                    root.applyPalette();
                } catch (e) {
                    console.log("Wallpaper transition: no palette in advance");
                }
            }
        }
    }

    // Duration for a color change now: until the end of the wave (before the start: the whole wave).
    // WalColors also asks this for colors.json from wal: for video/scene wal is often faster than the
    // precomputed palette and should still fade in sync with the wave, not in one fixed step.
    // Colors fade from the start of the wave over colorMs (shorter than the wave itself, which runs over all
    // monitors: over the whole wave it felt too sluggish)
    readonly property int colorMs: 900

    function colorFadeMs() {
        if (phase === "idle")
            return 0;
        if (phase === "prepare" || phase === "wait")
            return colorMs;
        if (phase === "spread")
            return Math.max(300, colorMs - (Date.now() - spreadStartedAt));
        return 300;
    }

    function applyPalette() {
        if (!palette || paletteApplied || !(phase === "spread" || phase === "settle" || phase === "closing"))
            return ;

        paletteApplied = true;
        // Remaining time of the wave (if the palette came late, it fades faster, but ends together)
        WalColors.fadeTo(palette, colorFadeMs());
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/wallpaper-openrgb.sh",
                                "--preview", JSON.stringify(palette)]);
    }

    function beginSpread() {
        phase = "spread";
        spreadStartedAt = Date.now();
        spreadDuration = pending ? hurryMs : spreadMs;
        applyPalette();
        spreadStarted(target);
        if (earlyApply && !applied) {
            applied = true;
            applyNow(target);
        }
        spreadAnim.stop();
        spreadAnim.duration = pending ? hurryMs : spreadMs;
        spreadAnim.from = cover;
        spreadAnim.start();
    }


    // The new wallpaper draws (first video frame, scene layer there, awww shows the image)
    function markReady(path) {
        if (!active || path !== target || ready)
            return ;

        ready = true;
        if (phase === "wait")
            tryBegin();
        else if (phase === "settle")
            finish();
        // Image loaded early: done as soon as the shape covers everything (spreadDone)
    }

    function spreadDone() {
        if (phase !== "spread")
            return ;

        if (overlayMode === "newStill") {
            // Everything covered (still image = new wallpaper) -> now switch underneath until awww shows it
            // or the scene draws
            phase = "settle";
            if (!applied) {
                applied = true;
                applyNow(target);
            }
            if (ready)
                finish();

        } else {
            finish();
        }
    }

    function finish() {
        const path = target;
        failsafe.stop();
        // Let it clean up first (old scene/players gone) ...
        finished(path);
        // ... and only turn off the overlay when Hyprland really no longer shows the old one.
        // Hyprland did not apply both in the same step in the same frame: the overlay was gone one
        // frame earlier -> the old video/scene flashed briefly.
        phase = "closing";
        closeProbe.tries = 0;
        closeProbe.running = true;
    }

    // Checks whether only the new wallpaper is on screen: no video layers anymore (unless the
    // target is a video) and exactly one scene layer per monitor (or none)
    property Process closeProbe: Process {
        property int tries: 0

        command: ["hyprctl", "layers", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                let video = 0, scene = 0;
                try {
                    for (const m of Object.values(JSON.parse(text)))
                        for (const level of Object.values(m.levels || {}))
                            for (const l of level) {
                                if (l.namespace === "quickshell:animated-wallpaper")
                                    video++;
                                else if (l.namespace === "linux-wallpaperengine")
                                    scene++;
                            }
                } catch (e) {}
                const n = root.animCount;
                const clean = (root.kind === "video" ? video === n : video === 0) && scene === (root.kind === "scene" ? n : 0);
                if (clean || ++root.closeProbe.tries > 40)
                    closeDelay.restart(); // two more frames until the state is surely on screen
                else
                    closePoll.restart();
            }
        }
    }

    // Opacity of the overlay (only < 1 when fading out into the scene, InkBloom binds to it)
    property real overlayFade: 1
    property SequentialAnimation sceneFade: SequentialAnimation {
        PauseAnimation {
            duration: 250
        }

        NumberAnimation {
            target: root
            property: "overlayFade"
            from: 1
            to: 0
            duration: 900
            easing.type: Easing.InOutSine
        }

        ScriptAction {
            script: root.closeNow()
        }

    }

    property Timer closePoll: Timer {
        interval: 40
        onTriggered: root.closeProbe.running = true
    }

    property Timer closeDelay: Timer {
        interval: 50
        onTriggered: root.closeNow()
    }

    function closeNow() {
        if (phase !== "closing" && phase !== "fadeout")
            return ;

        // Scene: do not take the still image away abruptly (otherwise the scene suddenly stood there and
        // moved), but let it stand briefly first (the scene starts up calmly) and then
        // fade it out -> its motion fades in softly
        if (phase === "closing" && kind === "scene" && overlayMode === "newStill") {
            phase = "fadeout";
            sceneFade.start();
            return ;
        }
        phase = "idle";
        cover = 0;
        overlayFade = 1;
        if (pending) {
            const p = pending;
            pending = null;
            Qt.callLater(() => {
                return root.startPending(p);
            });
        }
    }

    function startPending(p) {
        currentRequested(p);
    }

    // WallpaperPickerState starts the waiting change (it knows the current wallpaper)
    signal currentRequested(var request)

    // No overlay image possible: switch directly without a transition
    function abort() {
        if (phase !== "prepare")
            return ;

        const path = target;
        phase = "idle";
        failsafe.stop();
        // Switch without a transition; the message then comes from the script itself (no finished needed:
        // nothing had changed before). If the change was already running (video/scene on the
        // bar monitor), only the still images of the other monitors are missing.
        if (!applied)
            applyNow(path);
        else if (staticNames.length > 0)
            paintOthers(path, (ok) => {});
    }

}
