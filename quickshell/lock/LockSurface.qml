import "../services"
import Qt5Compat.GraphicalEffects as GE
import QtQuick
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import Quickshell.Io

// Content of a lock monitor. Idea "frost": when locking the wallpaper slowly freezes (blur +
// zoom), embers rise, a big serif clock stands in the middle, the date vertically at the edge
// in Japanese. Typing wakes the screen: the clock moves up, the avatar orb comes in.
// When unlocking the frost thaws again and everything fades away.
Item {
    id: root

    // The main monitor also shows the media card and power buttons
    property bool primary: true
    property string wallpaper: ""
    // Theme still image, in case there is no own wallpaper image for this monitor
    property string fallbackWallpaper: ""
    // Screenshot of this monitor from right before locking (lock.sh). The frost starts and ends
    // on exactly this image -> locking and unlocking pass seamlessly into the real desktop.
    property string desktopShot: ""
    // Target image when unlocking. Mostly the same; when locking from the power menu the desktop without the
    // menu (the menu is closed after unlocking). If it is missing, desktopShot applies.
    property string thawShot: ""
    // Height (at the bottom) of the desktop visualizer in the thaw image that is covered with the wallpaper (0 = nothing).
    // Is in <thawShot>.strip (power menu -> lock.sh); the surface only appears after storing
    readonly property real thawPatch: Number(patchFile.text().trim()) || 0
    // Background: 0 = sharp desktop, 1 = frozen wallpaper (intro there, back when unlocking)
    property real frost: preEntered ? 1 : 0
    // Foreground (clock, orb, cards): enter = intro (floating in), fade = fading out when unlocking
    property real enter: preEntered ? 1 : 0
    // The lock comes from the power menu and this monitor showed it: there the finished lock screen
    // already slid in as a surface (same components). So the start image IS already the finished
    // lock screen -> no own intro, only swap the start image briefly against our own image.
    property bool preEntered: false
    property real handoffMix: 1
    // Opacity of the start image: normally it fades out with the frost, after the power menu via handoffMix
    readonly property real shotOpacity: preEntered ? handoffMix : Math.max(0, 1 - frost / 0.85)
    // Normal intro: the start image lies IN the frost (is blurred along). Takeover: the image is already the
    // finished lock screen and lies unchanged ABOVE everything (handoffImg), in the frost it would be blurred
    // and darkened twice (test: first image brightness 29 instead of 51)
    property real fade: 1
    readonly property real ui: enter * fade

    // The darkening follows the frost delayed (power): blur and crossfade start fast, the
    // darkening spreads out softly over ~0.6 s instead of happening in the first frames
    readonly property real dim: backdrop.dim
    // 0 = rest (clock centered), 1 = awake (clock on top, input visible). When unlocking it stays at 1,
    // otherwise the clock slides back to the middle while fading out.
    // Only the main monitor wakes up (the login is there); the others calmly show the clock
    property real wake: LockState.awake && primary ? 1 : 0
    readonly property real s: Math.min(width / 2560, height / 1440) * 0.5 + 0.5



    property bool firstFrameLogged: false
    property bool introStarted: false
    property int readyFrames: 0
    // Wallpaper (or replacement) loaded? Before that the start image must not fade out, otherwise the
    // dark base surface shines through (seen in a recording as a sudden darkening)
    readonly property bool backgroundReady: backdrop.backgroundReady

    function startIntro(reason) {
        if (introStarted)
            return ;

        introStarted = true;
        console.log("time", Date.now(), "intro starts (" + reason + ")", preEntered ? "handover" : "");
        if (preEntered)
            handoffAnim.start();
        else
            introAnim.start();
    }

    Component.onCompleted: console.log("time", Date.now(), "surface built", width, "x", height)

    // Only start the intro when the surface is really visible and the wallpaper is loaded.
    // If it started already while building, part of the animation was "used up" until the first visible frame
    // (start image half gone, clock half there). Until then the surface shows the start image
    // unchanged = the screen from before, so the wait does not stand out.
    FrameAnimation {
        running: !root.introStarted
        onTriggered: {
            if (!root.firstFrameLogged) {
                root.firstFrameLogged = true;
                console.log("time", Date.now(), "first frame");
            }
            if (root.backgroundReady && ++root.readyFrames >= 2)
                root.startIntro("ready");

        }
    }

    // Emergency brake: the wallpaper does not load -> start anyway
    Timer {
        interval: 900
        running: !root.introStarted
        onTriggered: root.startIntro("timeout")
    }

    Connections {
        function onPhaseChanged() {
            if (LockState.unlocking)
                outroAnim.start();

        }

        target: LockState
    }

    // Takeover from the power menu: the start image and our own image are the same, only crossfade briefly, so
    // small differences (embers, song progress) do not jump
    NumberAnimation {
        id: handoffAnim

        target: root
        property: "handoffMix"
        from: 1
        to: 0
        duration: 350
        easing.type: Easing.InOutQuad
    }

    ParallelAnimation {
        id: introAnim

        // Fast start, long ending: even the first frames change something visibly. With a
        // slowly starting curve the image seemed to stand still for a while (blur on an already blurred
        // power menu background is hardly visible).
        NumberAnimation {
            target: root
            property: "frost"
            from: 0
            to: 1
            duration: 1300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.outQuint
        }

        NumberAnimation {
            target: root
            property: "enter"
            from: root.preEntered ? 1 : 0
            to: 1
            duration: 1000
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.outQuint
        }

    }

    // Unlocking: first the foreground disappears (exhaling slightly upward), in parallel the
    // background thaws to the desktop image with a long, soft ending. The session is only released
    // when everything stands (lock.qml waits for LockState.thawTotal) -> no jump at the end.
    ParallelAnimation {
        id: outroAnim

        NumberAnimation {
            target: root
            property: "fade"
            to: 0
            duration: LockState.fadeMs
            easing.type: Easing.OutCubic
        }

        SequentialAnimation {
            PauseAnimation {
                duration: LockState.thawDelay
            }

            NumberAnimation {
                target: root
                property: "frost"
                to: 0
                duration: LockState.thawMs
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.standard
            }

        }

    }


    // ---------- Keyboard ----------
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => {
            event.accepted = true;
            const ctrl = event.modifiers & Qt.ControlModifier;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                LockState.submit();
            else if (event.key === Qt.Key_Escape || (ctrl && (event.key === Qt.Key_U || event.key === Qt.Key_Backspace)))
                LockState.clear();
            else if (event.key === Qt.Key_Backspace)
                LockState.backspace();
            else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && !ctrl)
                LockState.type(event.text);
            else
                LockState.poke();
        }
    }

    // Only a deliberate click on the background wakes the login. Mouse moves
    // must not open the input while heading for the media controls.
    MouseArea {
        anchors.fill: parent
        onClicked: LockState.poke()
    }

    FileView {
        id: patchFile

        path: root.thawShot !== "" ? root.thawShot.replace(/\.ppm$/, ".strip") : ""
        blockLoading: true
        // almost always missing (only after the power menu with a visible visualizer)
        printErrors: false
    }

    // ---------- Background ----------
    // Frozen wallpaper (shared with the power menu, see LockBackdrop). In it the desktop images:
    // the start image fades out with the frost, at frost = 0 the desktop can be seen pixel for pixel.
    LockBackdrop {
        id: backdrop

        anchors.fill: parent
        wallpaper: root.wallpaper
        fallbackWallpaper: root.fallbackWallpaper
        frost: root.frost
        wake: root.wake
        overlay: [
            // Start image: load synchronously, even the first frame must be exactly the screen
            Image {
                id: shotImg

                anchors.fill: parent
                source: root.desktopShot !== "" ? "file://" + root.desktopShot : ""
                fillMode: Image.Stretch
                asynchronous: false
                cache: false
                smooth: true
                visible: !LockState.unlocking || thawImg.status !== Image.Ready
                opacity: status === Image.Ready && !root.preEntered ? root.shotOpacity : 0
            },
            // Target image: only needed when unlocking -> load in the background
            Item {
                anchors.fill: parent
                visible: LockState.unlocking && thawImg.status === Image.Ready
                opacity: Math.max(0, 1 - root.frost / 0.6)
                // crossfade together with the cover strip as one image (otherwise the thaw image underneath would shine through)
                layer.enabled: visible && patch.visible

                Image {
                    id: thawImg

                    anchors.fill: parent
                    source: root.thawShot !== "" ? "file://" + root.thawShot : ""
                    fillMode: Image.Stretch
                    asynchronous: true
                    cache: false
                    smooth: true
                }

                // The thaw image from the power menu still shows the desktop visualizer (it only sinks away behind the
                // menu): cover the strip at the bottom with the plain wallpaper, same geometry as in the
                // background (LockBackdrop). The real visualizer fades in anew after unlocking
                Item {
                    id: patch

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.thawPatch
                    clip: true
                    visible: root.thawPatch > 0 && patchImg.status === Image.Ready

                    Image {
                        id: patchImg

                        y: root.thawPatch - root.height
                        width: root.width
                        height: root.height
                        source: root.thawPatch > 0 && root.wallpaper !== "" ? "file://" + root.wallpaper : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: root.width
                        sourceSize.height: root.height
                        asynchronous: true
                        smooth: true
                    }

                }

            }
        ]
    }

    // ---------- Embers: soft dots of light rise slowly ----------
    ParticleSystem {
        id: sparks

        anchors.fill: parent
        running: root.frost > 0.05
    }

    ImageParticle {
        system: sparks
        source: "qrc:///particleresources/glowdot.png"
        color: WalColors.withAlpha(WalColors.color4, 0.55)
        colorVariation: 0.08
        alpha: 0.5
        alphaVariation: 0.4
        entryEffect: ImageParticle.Fade
        opacity: root.frost * root.fade * (1 - root.shotOpacity)
    }

    Emitter {
        system: sparks
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.5
        emitRate: root.primary ? 5 : 2
        lifeSpan: 11000
        lifeSpanVariation: 4000
        size: 18 * root.s
        sizeVariation: 14 * root.s
        endSize: 4 * root.s

        velocity: AngleDirection {
            angle: 270
            angleVariation: 22
            magnitude: 26 * root.s
            magnitudeVariation: 14 * root.s
        }

    }

    Wander {
        system: sparks
        anchors.fill: parent
        xVariance: 40
        pace: 30
    }

    // Clock, date, corners, cards (shared with the power menu, see LockForeground)
    LockForeground {
        anchors.fill: parent
        enter: root.enter
        fade: root.fade
        wake: root.wake
        primary: root.primary
    }

    // ---------- Login (appears on waking) ----------
    LockAuth {
        id: auth

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.5 - 70 * root.s + (1 - root.wake) * 80 * root.s - (1 - root.fade) * 24 * root.s
        opacity: root.wake * root.ui
        visible: root.primary && opacity > 0.01
        scale: 0.94 + 0.06 * root.wake
    }

    // Takeover from the power menu: its last image (= finished lock screen) above everything, fades out
    Image {
        anchors.fill: parent
        visible: root.preEntered && opacity > 0
        source: root.preEntered && root.desktopShot !== "" ? "file://" + root.desktopShot : ""
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
        opacity: status === Image.Ready ? root.handoffMix : 0
    }

    Behavior on wake {
        NumberAnimation {
            duration: 700
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.outQuint
        }

    }

}
