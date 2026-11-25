import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton

QtObject {
    id: root

    readonly property bool pickerVisible: PickerManager.isOpen("wallpaper")
    // Settings "wallpapers" (default $PICTURES/Wallpaper), with trailing slash
    readonly property string wallpaperDir: Settings.folder("wallpapers") + "/"
    // The wallpaper list is loaded once at start and stays in RAM as a
    // light array (only name + URL).
    property var allWallpapers: []
    property bool wallpapersLoaded: false
    property bool wallpapersLoading: false
    // ==== Preview images (file name -> file://... small JPG) ====
    // They stay permanently in ~/.cache/quickshell/wallpaper-thumbs: so the picker does not have to decode
    // the originals of several MB on every opening. If an original is replaced, the preview is
    // created again. If no preview works, the picker shows the original.
    property var thumbCache: ({
    })
    property var thumbFailed: ({
    })
    readonly property size thumbSize: Qt.size(640, 360)
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/wallpaper-thumbs"
    readonly property string thumbScript: Qt.resolvedUrl("../scripts/wallpaper_thumbs.sh").toString().replace("file://", "")
    // md5 -> file name of the wallpapers the running script is working on
    property var thumbInFlight: ({
    })
    // Collect finished ones and take them over in bulk (do not rebind all tiles per image)
    property var thumbPending: ({
    })
    property string activeAnimation: ""
    property string activeScene: ""
    // ==== Seamless change: the old one stays until the new one really draws ====
    // Otherwise the old awww image (below everything) or black flashes in the gap.
    // shownAnimation: what AnimatedWallpaper plays. On a change video -> scene the video stays
    // until the scene stands. Video -> video is crossfaded by AnimatedWallpaper itself (two players).
    property string shownAnimation: ""
    readonly property string animationUrl: shownAnimation ? "file://" + shownAnimation.split("/").map(encodeURIComponent).join("/") : ""
    // Animation paused (lock screen): when unlocking, the lock screen thaws to a screenshot.
    // If the wallpaper keeps running meanwhile, it jumps afterwards -> pause the video
    // (AnimatedWallpaper), freeze scenes with SIGSTOP; afterwards both continue from exactly this frame.
    // Set by the power menu and via IPC by hypr/scripts/lock.sh (`qs ipc call wallpaper freeze`).
    property bool animationFrozen: false

    // When pausing, AnimatedWallpaper stores the still video frame per monitor as
    // <frozenFramePrefix>-<monitor>.bmp: the lock screen takes it as the background, so its frost
    // shows exactly the same image as the desktop (the theme still image is another frame of the video).
    readonly property string frozenFramePrefix: Quickshell.env("XDG_RUNTIME_DIR") + "/wallpaper-frame"

    // Returns the monitors for which a video frame is written (lock.sh waits for it)
    function freezeAnimation(on) {
        const videoMons = animationUrl ? videoScreens.map((s) => s.name) : [];
        if (animationFrozen === on)
            return on ? videoMons : [];

        animationFrozen = on;
        applySceneStop();
        if (!on)
            Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"-*.bmp", "sh", frozenFramePrefix]);

        return on ? videoMons : [];
    }

    // ==== Pause the scene while a fullscreen window is on its monitor ====
    // linux-wallpaperengine pauses by itself on EVERY fullscreen window, also on other monitors:
    // a fullscreen YouTube video on a portrait monitor paused the scene on the main monitor.
    // So it runs with --no-fullscreen-pause, and here it only pauses when the active workspace
    // of a scene monitor shows a fullscreen window (game ...): then the scene is hidden anyway.
    readonly property bool sceneCovered: {
        const names = animScreens.map((s) => s.name);
        const wsIds = Hyprland.monitors.values.filter((m) => names.includes(m.name) && m.activeWorkspace).map((m) => m.activeWorkspace.id);
        return HyprlandData.windowList.some((w) => w.fullscreen > 0 && w.workspace && wsIds.includes(w.workspace.id));
    }
    readonly property bool sceneStopWanted: animationFrozen || sceneCovered
    // Last sent signal (lock and fullscreen share STOP/CONT, only send changes)
    property bool sceneStopped: false

    onSceneStopWantedChanged: applySceneStop()

    function applySceneStop() {
        if (sceneStopWanted === sceneStopped)
            return;

        sceneStopped = sceneStopWanted;
        // comm is cut to 15 characters: linux-wallpaperengine -> linux-wallpaper
        Quickshell.execDetached(["pkill", sceneStopped ? "-STOP" : "-CONT", "-x", "linux-wallpaper"]);
    }
    // Running linux-wallpaperengine processes; the last one is the current one, older ones are ended after the
    // handover (scene -> scene or scene -> video)
    property var sceneProcs: []
    // Path of the currently set wallpaper (for freezing during the transition)
    property string currentPath: ""

    function select(selected, anim, scene) {
        currentPath = selected;
        const sceneChanged = scene !== activeScene;
        // Image: ready as soon as awww shows it on all monitors (imageReady asks)
        if (!anim && !scene) {
            imageReady.path = selected;
            imageReady.tries = 0;
            imageReady.restart();
        }
        activeAnimation = anim;
        activeScene = scene;
        // During a transition the old one keeps running live outside the shape -> only remove it on
        // finished (handover)
        const keepOld = WallpaperTransition.active;
        if (anim)
            showAnimation(anim);
        else if (!scene && !keepOld)
            shownAnimation = ""; // image without a transition: awww has already crossfaded, video gone
        // Video -> scene: shownAnimation stays until the scene draws or the transition is done
        if (sceneChanged && scene)
            launchScene(scene);
        else if (scene)
            WallpaperTransition.markReady(scene); // the same scene is already running
        else if (!scene && !anim && !keepOld)
            retireScenes(0); // image without a transition: end the scene right away
        // Scene -> video: it is ended only when the video draws or the transition is done
        // Animated (bar monitor only): the other monitors show a still image. With a transition
        // WallpaperTransition sets it under its overlay (paintOthers), otherwise here directly.
        if ((anim || scene) && !keepOld)
            paintStatic(selected, null);
    }

    // ==== Animation only on the bar monitor ====
    // One video player or scene output per monitor cost a lot of RAM (4K video: ~225 MB per player).
    // Only the monitor with the bar is animated (MachineConfig, like the bar), the others show
    // a still image of the wallpaper with awww. If the bar moves, the animation moves along.
    readonly property var animScreen: MachineConfig.loaded ? MachineConfig.activeBarScreen(Quickshell.screens) : null
    readonly property var animScreens: animScreen ? [animScreen] : Quickshell.screens
    readonly property var staticScreens: animScreen ? Quickshell.screens.filter((s) => s.name !== animScreen.name) : []

    // The same, computed fresh: in onAnimScreenChanged the bindings above may not be re-evaluated
    // yet - with the old list the monitor left behind by a bar move stayed without a still image
    // (it showed a completely different, old wallpaper)
    function animScreensNow() {
        const a = MachineConfig.loaded ? MachineConfig.activeBarScreen(Quickshell.screens) : null;
        return a ? [a] : Quickshell.screens;
    }
    function staticScreensNow() {
        const a = MachineConfig.loaded ? MachineConfig.activeBarScreen(Quickshell.screens) : null;
        return a ? Quickshell.screens.filter((s) => s.name !== a.name) : [];
    }
    property string lastAnimScreen: ""

    onAnimScreenChanged: {
        const name = animScreen ? animScreen.name : "";
        if (name === lastAnimScreen)
            return;
        // Also on the first value (bar setting read only after the wallpaper): until then the
        // animation ran on all monitors -> now limit it to the bar monitor
        const prev = lastAnimScreen;
        lastAnimScreen = name;
        if (!movePrev)
            movePrev = prev;
        if (!name)
            return;
        // Do not interfere in the middle of a transition: catch up afterwards (onFinished)
        if (WallpaperTransition.active) {
            animMoveDeferred = true;
            return;
        }
        followAnimScreen();
    }

    property bool animMoveDeferred: false
    // Monitor the animation ran on before the bar moved (for the soft change)
    property string movePrev: ""

    // Bar moved: bring the animation softly to the new monitor (moveStart); without a previous
    // monitor (start) or during a running move directly
    function followAnimScreen() {
        animMoveDeferred = false;
        // A soft move is still running: it catches up with the new monitor at the end (moveEnd)
        if (moveState)
            return;
        const prev = movePrev;
        movePrev = "";
        const now = animScreen ? animScreen.name : "";
        if ((activeScene || activeAnimation) && prev && now && prev !== now && !moveState) {
            moveStart(prev, now);
            return;
        }
        if (activeScene)
            launchScene(activeScene);
        if (activeScene || activeAnimation)
            paintStatic(currentPath, null);
    }

    // ==== Soft change on a bar move ====
    // Monitor left behind: the still image fades in over the still running animation (AnimMoveFade),
    // only then the animation ends there. New monitor: the video fades in from the first frame
    // (AnimatedWallpaper, moveNewIn); a scene starts under a still image that fades out as soon as it
    // draws. The still image is exactly what awww shows there afterwards -> no jump at the end.
    // moveState: "" | "prepare" (load still images) | "fading" | "cleanup" (old one gone, overlay still there)
    property string moveState: ""
    property string moveOld: ""
    property string moveNew: ""
    property bool moveScene: false
    property var moveStills: ({})
    property var moveLoaded: ({})
    property real moveOldFade: 0
    property real moveNewFade: 1
    property real moveNewIn: 0
    property bool moveOldDone: false
    property bool moveNewDone: false
    readonly property int moveFadeMs: 600

    // Monitors for AnimatedWallpaper: during the move the old and the new one (both play briefly)
    readonly property var videoScreens: (moveState === "prepare" || moveState === "fading") && !moveScene
        ? Quickshell.screens.filter((s) => s.name === moveOld || s.name === moveNew) : animScreens

    // Opacity of a video window (the new monitor fades in during the move)
    function videoOpacityFor(name) {
        return moveState && !moveScene && name === moveNew ? moveNewIn : 1;
    }

    function moveStart(prev, now) {
        moveOld = prev;
        moveNew = now;
        moveScene = !!activeScene;
        moveOldFade = 0;
        moveNewFade = 1;
        moveNewIn = 0;
        moveOldDone = false;
        moveNewDone = false;
        moveLoaded = {};
        moveStills = {};
        moveState = "prepare";
        moveFailsafe.restart();
        moveStillProc.command = ["bash", Qt.resolvedUrl("../scripts/wallpaper_still.sh").toString().replace("file://", ""), currentPath].concat(WallpaperTransition.stillSizes);
        moveStillProc.running = true;
    }

    property Process moveStillProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf(" ");
                    if (i > 0)
                        m[line.slice(0, i)] = "file://" + line.slice(i + 1).split("/").map(encodeURIComponent).join("/");
                }
                if (Object.keys(m).length === 0)
                    root.moveAbort();
                else
                    root.moveStills = m;
            }
        }
    }

    // AnimMoveFade reports: still image loaded on this monitor
    function moveStillLoaded(name) {
        if (moveState !== "prepare")
            return;
        const l = Object.assign({}, moveLoaded);
        l[name] = true;
        moveLoaded = l;
        if (l[moveOld] && (!moveScene || l[moveNew]))
            moveShownDelay.restart();
    }

    // A few frames until the overlays are really on screen
    property Timer moveShownDelay: Timer {
        interval: 70
        onTriggered: root.moveFading()
    }

    function moveFading() {
        if (moveState !== "prepare")
            return;
        moveState = "fading";
        // The monitor left behind already gets its awww still image underneath (invisible until the end)
        paintStatic(currentPath, null);
        moveOldAnim.restart();
        if (moveScene)
            launchScene(activeScene); // sceneDrawing -> moveNewReady
        else if (moveVideoReadyEarly)
            moveNewReady();
    }

    // The video on the new monitor shows its first frame (can already come during "prepare")
    property bool moveVideoReadyEarly: false
    function moveVideoReady(name) {
        if (!moveState || moveScene || name !== moveNew)
            return;
        if (moveState === "prepare")
            moveVideoReadyEarly = true;
        else
            moveNewReady();
    }

    function moveNewReady() {
        moveVideoReadyEarly = false;
        if (moveState !== "fading" || moveNewAnim.running || moveNewDone)
            return;
        moveNewAnim.restart();
    }

    property NumberAnimation moveOldAnim: NumberAnimation {
        target: root
        property: "moveOldFade"
        from: 0
        to: 1
        duration: root.moveFadeMs
        easing.type: Easing.InOutQuad
        onFinished: {
            root.moveOldDone = true;
            root.moveTryFinish();
        }
    }

    // New monitor: the video fades in (moveNewIn 0 -> 1) or the scene cover fades out
    property SequentialAnimation moveNewAnim: SequentialAnimation {
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "moveNewIn"
                from: 0
                to: 1
                duration: root.moveFadeMs
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: root
                property: "moveNewFade"
                from: 1
                to: 0
                duration: root.moveFadeMs
                easing.type: Easing.InOutQuad
            }
        }
        ScriptAction {
            script: {
                root.moveNewDone = true;
                root.moveTryFinish();
            }
        }
    }

    function moveTryFinish() {
        if (moveState !== "fading" || !moveOldDone || !moveNewDone)
            return;
        // End the old one (now lies completely under the still image): the video window of the old monitor
        // disappears with moveState "cleanup", the old scene is ended
        moveState = "cleanup";
        if (moveScene)
            retireScenes(1);
        moveCleanup.restart();
    }

    // Only remove the overlay when the old animation is surely gone (underneath: awww still image)
    property Timer moveCleanup: Timer {
        interval: 300
        onTriggered: root.moveEnd()
    }

    function moveEnd() {
        moveState = "";
        moveFailsafe.stop();
        // The bar moved on during the move already: catch up now
        if (animScreen && animScreen.name !== moveNew) {
            movePrev = moveNew;
            Qt.callLater(followAnimScreen);
        }
    }

    function moveAbort() {
        if (!moveState)
            return;
        console.log("Wallpaper: soft move cancelled in", moveState);
        const wasScene = moveScene, state = moveState;
        moveState = "";
        moveFailsafe.stop();
        if (wasScene && state === "prepare")
            launchScene(activeScene);
        else if (wasScene)
            retireScenes(1);
        paintStatic(currentPath, null);
    }

    property Timer moveFailsafe: Timer {
        interval: 5000
        onTriggered: {
            if (root.moveState === "fading") {
                root.moveOldDone = true;
                root.moveNewDone = true;
                root.moveTryFinish();
            } else {
                root.moveAbort();
            }
        }
    }

    // Still image of `path` on all non-bar monitors; onDone(ok) afterwards (for the transition)
    function paintStatic(path, onDone) {
        const specs = staticScreensNow().map((s) => s.name + ":" + WallpaperTransition.sizeFor(s));
        if (specs.length === 0 || !path) {
            if (onDone)
                onDone(true);
            return;
        }
        staticProc.running = false;
        staticProc.onDone = onDone;
        staticProc.command = ["bash", Qt.resolvedUrl("../scripts/wallpaper_static_outputs.sh").toString().replace("file://", ""), path].concat(specs);
        staticProc.running = true;
    }

    property Process staticProc: Process {
        property var onDone: null
        onExited: (code) => {
            const cb = onDone;
            onDone = null;
            if (cb)
                cb(code === 0);
        }
    }

    // AnimatedWallpaper reports the first frame of a new video
    function animationReady(path) {
        if (path !== shownAnimation)
            return;
        WallpaperTransition.markReady(shownAnimation);
        // During the transition the old scene keeps running outside the shape (handover)
        if (!activeScene && !WallpaperTransition.active)
            retireScenes(0);
    }

    // ==== Videos in monitor size ====
    // One player per monitor; a 4K video cost ~225 MB of RAM per player that way. Before playing, check
    // whether there are copies scaled down to the monitor (scripts/wallpaper_video_variant.sh, ~30 ms);
    // missing ones are made in the background and used next time.
    // Path -> {"WxH": file}
    property var videoSources: ({})

    function videoUrlFor(path, screen) {
        if (!path)
            return "";
        const m = videoSources[path];
        const file = (m && m[WallpaperTransition.sizeFor(screen)]) || path;
        return "file://" + file.split("/").map(encodeURIComponent).join("/");
    }

    function showAnimation(anim) {
        if (anim === shownAnimation)
            return;
        variantProc.running = false;
        variantProc.forPath = anim;
        variantProc.command = ["bash", Qt.resolvedUrl("../scripts/wallpaper_video_variant.sh").toString().replace("file://", ""), anim].concat(WallpaperTransition.stillSizes);
        variantProc.running = true;
    }

    property Process variantProc: Process {
        property string forPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const path = root.variantProc.forPath;
                const m = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf(" ");
                    if (i > 0)
                        m[line.slice(0, i)] = line.slice(i + 1);
                }
                const all = Object.assign({}, root.videoSources);
                all[path] = m;
                root.videoSources = all;
                // Only show it now, otherwise every monitor would briefly start playing the 4K original
                if (root.activeAnimation === path)
                    root.shownAnimation = path;
            }
        }
    }

    // The old one may go: older scenes, a video when switching to a scene/image
    function handover() {
        retireScenes(activeScene ? 1 : 0);
        if (!activeAnimation)
            shownAnimation = "";
    }

    property Connections transitionHook: Connections {
        target: WallpaperTransition
        function onApplyNow(path) {
            root.runApply(path);
        }
        function onFinished() {
            root.handover();
            if (root.animMoveDeferred)
                Qt.callLater(root.followAnimScreen);
        }
        // Report as soon as the new wallpaper starts to be visible (start of the wave) - at the end of the wave
        // the message only came 2.5-3.5 s after the click
        function onSpreadStarted(path) {
            root.notifyChanged(path);
        }
        function onCurrentRequested(request) {
            root.apply(request.path, request.origin);
        }
    }

    // Image: awww needs up to ~1 s for big images (7K PNG measured at 1.1 s) until it really stands on all
    // monitors. So ask awww instead of assuming a fixed time - otherwise the
    // transition ends while the old image is still underneath (a brief flash).
    property Timer imageReady: Timer {
        property string path: ""
        property int tries: 0
        interval: 80
        onPathChanged: tries = 0
        onTriggered: {
            if (++tries > 60) { // at the latest after ~5 s
                WallpaperTransition.markReady(path);
                return;
            }
            awwwQuery.running = true;
        }
    }
    property Process awwwQuery: Process {
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter((l) => l.includes("currently displaying"));
                const p = root.imageReady.path;
                if (lines.length > 0 && lines.every((l) => l.endsWith("image: " + p)))
                    WallpaperTransition.markReady(p);
                else
                    root.imageReady.restart();
            }
        }
    }

    // ==== Start a scene and detect when it draws ====
    // linux-wallpaperengine reports nothing, but its layer only shows up in Hyprland with the first
    // finished frame (measured ~0.2 s after the start, the frame is complete by then). So: before the
    // start remember the existing scene layers, afterwards wait for new ones (one per monitor).
    property var sceneKnownLayers: []
    property string sceneWaiting: ""
    property int scenePolls: 0

    function sceneLayers(json) {
        const out = [];
        try {
            const mons = JSON.parse(json);
            for (const m of Object.values(mons))
                for (const level of Object.values(m.levels || {}))
                    for (const l of level)
                        if (l.namespace === "linux-wallpaperengine")
                            out.push(l.address);
        } catch (e) {}
        return out;
    }

    function launchScene(scene) {
        sceneWaiting = scene;
        scenePolls = 0;
        layerProbe.phase = "before";
        layerProbe.running = true;
    }

    function startSceneProcess(scene) {
        // The launcher fixes project colors (0/1 without a decimal point) and then replaces itself with exec
        const args = ["python3", Qt.resolvedUrl("../scripts/wallpaperengine_run.py").toString().replace("file://", ""),
            // Background layer (like awww): videos and the transition overlay (bottom) lie above it
            // --no-fullscreen-pause: Quickshell pauses itself, only for fullscreen on this monitor
            // (sceneCovered); the built-in pause kicked in for fullscreen on any monitor
            scene.slice(0, scene.lastIndexOf("/")), "--fps", "30", "--silent", "--layer", "background", "--no-fullscreen-pause"];
        // Only animate on the bar monitor; the others show a still image (paintStatic)
        for (const screen of root.animScreensNow())
            args.push("--screen-root", screen.name);
        const proc = sceneComponent.createObject(root, {"scene": scene, "command": args});
        sceneProcs = sceneProcs.concat([proc]);
        proc.running = true;
        layerPoll.restart();
    }

    function sceneDrawing(scene) {
        if (scene !== activeScene)
            return;
        // On a soft bar move the old scene only goes after the crossfade (moveTryFinish)
        if (moveState === "fading" && moveScene) {
            moveNewReady();
            return;
        }
        WallpaperTransition.markReady(scene);
        // Without a transition: hand over right away; with a transition only on finished (the old one keeps running outside)
        if (!WallpaperTransition.active)
            handover();
    }

    property Process layerProbe: Process {
        property string phase: "before"
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const layers = root.sceneLayers(text);
                const scene = root.sceneWaiting;
                if (root.layerProbe.phase === "before") {
                    root.sceneKnownLayers = layers;
                    root.startSceneProcess(scene);
                    return;
                }
                const fresh = layers.filter((a) => !root.sceneKnownLayers.includes(a));
                // One layer per animated monitor (only the bar monitor, see animScreens)
                if (fresh.length >= root.animScreensNow().length || ++root.scenePolls > 80) {
                    root.sceneWaiting = "";
                    // One frame of air, so the first frame is surely on screen
                    Qt.callLater(() => root.sceneDrawing(scene));
                } else {
                    root.layerPoll.restart();
                }
            }
        }
    }
    property Timer layerPoll: Timer {
        interval: 50
        onTriggered: {
            if (!root.sceneWaiting)
                return;
            root.layerProbe.phase = "after";
            root.layerProbe.running = true;
        }
    }

    // End all scene processes except the last `keep`
    function retireScenes(keep) {
        const old = sceneProcs.slice(0, Math.max(0, sceneProcs.length - keep));
        sceneProcs = sceneProcs.slice(sceneProcs.length - keep);
        for (const proc of old) {
            proc.retired = true;
            if (proc.running)
                proc.running = false;
            else
                proc.destroy();
        }
    }

    property Component sceneComponent: Component {
        Process {
            id: proc
            property string scene: ""
            property bool retired: false
            property string errorText: ""
            stderr: SplitParser {
                onRead: (data) => {
                    // Queries MPRIS constantly and reports this error every time -> would fill the log
                    // and the error message with spam
                    if (data.startsWith("DBus error: Object does not exist at path"))
                        return;
                    proc.errorText = (proc.errorText + data + "\n").slice(-1500);
                    console.warn("Wallpaper scene:", data);
                }
            }
            onExited: (code, status) => {
                if (!retired && (code !== 0 || status !== 0) && root.activeScene === scene)
                    NotificationState.send("Wallpaper", "Scene playback failed",
                        errorText.trim().slice(-500) || "This scene could not be rendered.", {"timeout": 8000});
                root.sceneProcs = root.sceneProcs.filter((p) => p !== proc);
                // Crashed current scene: selecting it again should start it again
                if (!retired && root.activeScene === scene)
                    root.activeScene = "";
                Qt.callLater(proc.destroy);
            }
        }
    }

    property FileView animationFile: FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/current-wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const selected = text().trim();
            root.select(selected, /\.(gif|mp4|webm|mkv|mov|m4v)$/i.test(selected) ? selected : "",
                selected.endsWith("/project.json") ? selected : "");
        }
    }
    onPickerVisibleChanged: {
        deleteArmed = "";
        if (pickerVisible)
            reloadWallpapers();
    }
    property Timer workshopRefresh: Timer {
        interval: 60000
        running: root.pickerVisible
        repeat: true
        onTriggered: root.reloadWallpapers()
    }
    property Process listProcess
    property Process thumbProcess
    // Set wallpaper + colors. Must live here in the singleton (not in the picker): the picker is
    // unloaded after closing, and the running process would end with it.
    property Process applyProcess: Process {
        property string path: ""
        property bool superseded: false
        property bool notifyOnExit: true

        property string errorText: ""
        onStarted: errorText = ""
        stderr: SplitParser {
            onRead: (data) => {
                root.applyProcess.errorText = (root.applyProcess.errorText + data + "\n").slice(-2000);
                console.warn("Wallpaper:", data);
            }
        }
        // Only report success if wallpaper and colors were really set.
        onExited: (exitCode, exitStatus) => {
            if (superseded) {
                superseded = false;
                return;
            }
            if (exitCode !== 0 || exitStatus !== 0) {
                // Let the ink open up again, the old wallpaper is still underneath
                WallpaperTransition.markReady(path);
                NotificationState.send("Wallpaper", "Wallpaper could not be changed",
                    errorText.trim().slice(-500) || "The wallpaper process failed.", {"timeout": 8000});
                return;
            }
            if (notifyOnExit)
                root.notifyChanged(path);
        }
    }
    property Timer thumbFlushTimer: Timer {
        interval: 60
        onTriggered: root.flushThumbs()
    }

    listProcess: Process {
        command: ["python3", Qt.resolvedUrl("../scripts/list_wallpapers.py").toString().replace("file://", ""), root.wallpaperDir]

        stdout: StdioCollector {
            onStreamFinished: root.parseWallpapers(text)
        }

    }

    function loadWallpapers() {
        if (root.wallpapersLoaded || root.wallpapersLoading)
            return ;

        root.wallpapersLoading = true;
        root.listProcess.running = true;
    }

    // Read again, e.g. after a download from wallhaven (previews stay in the cache)
    function reloadWallpapers() {
        if (root.wallpapersLoading)
            return ;

        root.wallpapersLoaded = false;
        loadWallpapers();
    }

    function parseWallpapers(rawText) {
        let entries;
        try {
            entries = JSON.parse(rawText);
            if (!Array.isArray(entries))
                throw new Error("Invalid wallpaper list");
        } catch (error) {
            root.wallpapersLoading = false;
            console.warn("Wallpaper scan:", error);
            return;
        }
        if (JSON.stringify(entries) !== JSON.stringify(root.allWallpapers))
            root.allWallpapers = entries;
        root.wallpapersLoaded = true;
        root.wallpapersLoading = false;
        root.makeThumbs(entries);
    }

    function makeThumbs(names) {
        if (root.thumbProcess.running || names.length === 0)
            return ;

        const flight = {
        };
        const args = ["bash", root.thumbScript, root.wallpaperDir, root.thumbDir, String(root.thumbSize.width), String(root.thumbSize.height)];
        for (const entry of names) {
            // thumbKey (workshop) carries a version: new kind of preview -> new cache file
            const md5 = Qt.md5(entry.thumbKey || entry.key);
            flight[md5] = entry.key;
            args.push(md5, entry.thumbSource);
        }
        root.thumbInFlight = flight;
        // Monitor formats: for scenes the still images of the transition are made along with it
        root.thumbProcess.environment = {"WALLPAPER_STILL_SIZES": WallpaperTransition.stillSizes.join(" ")};
        root.thumbProcess.command = args;
        root.thumbProcess.running = true;
    }

    function flushThumbs() {
        const done = root.thumbPending;
        root.thumbPending = {
        };
        const got = {
        };
        const failed = {
        };
        let nGot = 0, nFailed = 0;
        for (const n in done) {
            if (done[n]) {
                got[n] = done[n];
                nGot++;
            } else {
                failed[n] = true;
                nFailed++;
            }
        }
        // Create a new map, so QML bindings notice the update
        if (nGot > 0)
            root.thumbCache = Object.assign({
        }, root.thumbCache, got);

        if (nFailed > 0)
            root.thumbFailed = Object.assign({
        }, root.thumbFailed, failed);

    }

    // The whole chain (awww, wal, GTK theme, Hyprland, Obsidian, nvim, remaining apps) is in one
    // script (hypr/scripts/apply-wallpaper.sh)
    // origin: desktop point (all monitors) where the ink transition starts; without = no transition
    function apply(path, origin) {
        // With a transition: WallpaperTransition decides when to switch underneath (applyNow).
        // The same wallpaper again: no transition (it would run over itself), only new colors.
        // If one is running, WallpaperTransition remembers the request (currentRequested).
        if (origin && (path !== root.currentPath || WallpaperTransition.active)) {
            WallpaperTransition.start(path, origin, {
                "path": root.currentPath,
                "video": root.shownAnimation !== "",
                "staticNames": root.staticScreensNow().map((sc) => sc.name),
                "animCount": root.animScreensNow().length
            });
            return;
        }
        runApply(path);
    }

    function runApply(path) {
        // Cancel a running change: its cancellation is not an error (no message, the ink stays closed)
        if (root.applyProcess.running) {
            root.applyProcess.superseded = true;
            root.applyProcess.running = false;
        }
        root.applyProcess.path = path;
        root.applyProcess.command = ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/apply-wallpaper.sh", path];
        // No awww crossfade of its own under the ink (see apply-wallpaper.sh)
        root.applyProcess.environment = {"WALLPAPER_AWWW_TRANSITION": WallpaperTransition.active ? "none" : "simple"};
        // With a transition the change reports as soon as the new wallpaper stands (handover);
        // without a transition when the script is done (applyProcess.onExited)
        root.applyProcess.notifyOnExit = !WallpaperTransition.active;
        root.applyProcess.running = true;
    }

    // "Wallpaper changed" with the small preview from the picker cache (640x360, loads right away) and the
    // name (workshop: title instead of "project.json"). Without a preview in the cache: the transition's still image.
    function notifyChanged(path) {
        const entry = allWallpapers.find((w) => decodeURIComponent(w.url.replace(/^file:\/\//, "")) === path);
        let image = entry ? (thumbCache[entry.key] || "") : "";
        if (!image) {
            const still = Object.values(WallpaperTransition.newStills)[0] || "";
            image = still || (/\.(png|jpe?g|webp)$/i.test(path) ? "file://" + path : "");
        }
        NotificationState.send("Wallpaper", "Wallpaper changed", entry ? entry.name : path.split("/").pop(), {
            "timeout": 3500,
            "success": true,
            "image": decodeURIComponent(image.replace(/^file:\/\//, ""))
        });
    }

    // ==== Delete: the first press marks it (tile turns red), a second within 3 s deletes ====
    // It goes to the trash (the trash picker can bring it back), never for good.
    property string deleteArmed: ""
    property Timer deleteDisarm: Timer {
        interval: 3000
        onTriggered: root.deleteArmed = ""
    }
    function pathOf(entry) {
        return decodeURIComponent(entry.url.replace(/^file:\/\//, ""));
    }
    // true = really deleted (second press), so the picker can keep the selection
    function requestDelete(entry) {
        if (!entry)
            return false;
        if (deleteArmed !== entry.key) {
            deleteArmed = entry.key;
            deleteDisarm.restart();
            return false;
        }
        deleteArmed = "";
        deleteDisarm.stop();
        const path = pathOf(entry);
        // Take it out of the list right away; the rescan after the script syncs (or brings it back on error)
        allWallpapers = allWallpapers.filter((w) => w.key !== entry.key);
        trashQueue = trashQueue.concat([{"path": path, "name": entry.name}]);
        if (!trashProcess.running)
            trashNext();
        return true;
    }
    property var trashQueue: []
    function trashNext() {
        if (trashQueue.length === 0) {
            reloadWallpapers();
            return;
        }
        const job = trashQueue[0];
        trashQueue = trashQueue.slice(1);
        trashProcess.job = job;
        trashProcess.command = ["bash", Qt.resolvedUrl("../scripts/wallpaper_trash.sh").toString().replace("file://", ""), root.wallpaperDir, job.path];
        trashProcess.running = true;
    }
    property Process trashProcess: Process {
        id: trashProcess
        property var job: ({})
        property string errorText: ""
        property string result: ""
        onStarted: { errorText = ""; result = ""; }
        stdout: SplitParser {
            onRead: (data) => trashProcess.result = data.trim()
        }
        stderr: SplitParser {
            onRead: (data) => trashProcess.errorText = (trashProcess.errorText + data + "\n").slice(-600)
        }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) {
                NotificationState.send("Wallpaper", "Could not delete wallpaper",
                    trashProcess.errorText.trim() || trashProcess.job.name, {"timeout": 7000});
            } else if (trashProcess.result.startsWith("workshop ")) {
                // Otherwise Steam downloads subscribed items again -> open the page to unsubscribe
                const id = trashProcess.result.split(" ")[1];
                Quickshell.execDetached(["xdg-open", "steam://url/CommunityFilePage/" + id]);
                NotificationState.send("Wallpaper", "Moved to trash", trashProcess.job.name
                    + " — unsubscribe in Steam, or it will be downloaded again.", {"timeout": 7000});
            } else {
                NotificationState.send("Wallpaper", "Moved to trash", trashProcess.job.name, {"timeout": 3500});
            }
            root.trashNext();
        }
    }

    // qs ipc call wallpaper set <path>: set the wallpaper with the ink transition (scripts, shortcuts);
    // the wave starts in the middle of the focused monitor
    property IpcHandler ipc: IpcHandler {
        function set(path: string): void {
            const m = Hyprland.focusedMonitor;
            const s = Quickshell.screens.find((x) => m && x.name === m.name) || Quickshell.screens[0];
            root.apply(path, s ? Qt.point(s.x + s.width / 2, s.y + s.height / 2) : null);
        }

        // qs ipc call wallpaper freeze | unfreeze: pause/resume the animation (hypr/scripts/lock.sh).
        // freeze prints the monitors with a video (space separated): a still image is made for them.
        function freeze(): string {
            return root.freezeAnimation(true).join(" ");
        }

        function unfreeze(): void {
            root.freezeAnimation(false);
        }

        target: "wallpaper"
    }

    function toggle() {
        PickerManager.toggle("wallpaper");
    }

    function close() {
        if (PickerManager.isOpen("wallpaper"))
            PickerManager.close();

    }

    function open() {
        PickerManager.open("wallpaper");
    }

    Component.onCompleted: {
        loadWallpapers();
        // The transition has the still images of the monitors without animation set under its overlay
        WallpaperTransition.paintOthers = (path, done) => root.paintStatic(path, done);
    }

    thumbProcess: Process {
        onExited: (exitCode, exitStatus) => {
            root.flushThumbs();
            root.thumbInFlight = {
            };
        }

        // Zeilen "<md5> ok|fail"
        stdout: SplitParser {
            onRead: (data) => {
                const parts = data.trim().split(" ");
                const name = root.thumbInFlight[parts[0]];
                if (name === undefined)
                    return ;

                root.thumbPending[name] = parts[1] === "ok" ? "file://" + root.thumbDir + "/" + parts[0] + ".jpg" : "";
                if (!root.thumbFlushTimer.running)
                    root.thumbFlushTimer.start();

            }
        }

    }
}
