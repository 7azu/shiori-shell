import "../common"
import "../services"
import QtQuick
import QtQuick.Effects

// Background of the lock screen: the wallpaper freezes (blur, zoom, darken) + an accent glow.
// Its own component, because TWO places show it: LockSurface (lock.qml) and the power menu, where the
// finished lock screen slides in from the top as a surface when locking. Both draw exactly the same this way,
// the real lock screen can take over the image without a jump.
// overlay: images that lie IN the frozen image and are blurred along (desktop screenshots in LockSurface).
Item {
    id: bd

    property string wallpaper: ""
    // Theme still image, in case there is no own wallpaper image for this monitor
    property string fallbackWallpaper: ""
    // 0 = sharp (desktop), 1 = frozen
    property real frost: 1
    property real wake: 0
    // Slow breathing of the image (Ken Burns). Off in the power menu: the lock screen starts with drift = 0
    // and must then look exactly the same
    property bool drifting: true
    // The darkening follows the frost delayed (power): blur and crossfade start fast, the
    // darkening spreads out softly instead of happening in the first frames
    readonly property real dim: Math.pow(frost, 1.8)
    readonly property bool backgroundReady: wallImg.useFallback ? (fallbackImg.status === Image.Ready || fallbackImg.status === Image.Error || fallbackWallpaper === "") : wallImg.status === Image.Ready
    // No default alias: it would also redirect this file's own children
    property alias overlay: overlaySlot.data

    // Opaque base surface: at the edges the blur would otherwise let the underlying surface shine through, and that
    // is a different one in the power menu than in the lock screen
    Rectangle {
        anchors.fill: parent
        color: WalColors.color0
    }

    Item {
        id: frosted

        property real drift: 0

        anchors.fill: parent
        scale: 1 + (0.05 + 0.015 * drift) * bd.frost
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            color: WalColors.color0
        }

        Image {
            id: wallImg

            readonly property bool useFallback: bd.wallpaper === "" || status === Image.Error

            anchors.fill: parent
            source: bd.wallpaper !== "" ? "file://" + bd.wallpaper : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: bd.width
            sourceSize.height: bd.height
            asynchronous: true
            cache: false
            visible: !useFallback
        }

        Image {
            id: fallbackImg

            anchors.fill: parent
            source: wallImg.useFallback && bd.fallbackWallpaper !== "" ? "file://" + bd.fallbackWallpaper : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: bd.width
            sourceSize.height: bd.height
            asynchronous: true
            cache: false
        }

        Item {
            id: overlaySlot

            anchors.fill: parent
        }

        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 64
            // The blur is already full at frost 0.6: this way the wallpaper already appears blurred
            blur: Math.min(1, bd.frost / 0.6) * (0.75 + 0.25 * bd.wake)
            saturation: -0.15 * bd.dim
            brightness: -(0.22 + 0.06 * bd.wake) * bd.dim
        }

        SequentialAnimation on drift {
            running: bd.drifting
            loops: Animation.Infinite

            NumberAnimation {
                to: 1
                duration: 16000
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                to: 0
                duration: 16000
                easing.type: Easing.InOutSine
            }

        }

    }

    // Darken toward the bottom (media card, hints) + vignette
    Rectangle {
        anchors.fill: parent
        opacity: bd.dim

        gradient: Gradient {
            GradientStop {
                position: 0
                color: WalColors.withAlpha(WalColors.color0, 0.15)
            }

            GradientStop {
                position: 0.55
                color: WalColors.withAlpha(WalColors.color0, 0.25)
            }

            GradientStop {
                position: 1
                color: WalColors.withAlpha(WalColors.color0, 0.8)
            }

        }

    }

    // Starry sky (a recurring motif as in the Wi-Fi/Bluetooth picker), appears with the frost.
    // Calm (animated: false): power menu and lock screen both show this component and must be pixel identical at the
    // handover; besides, a clock would otherwise redraw the lock screen for hours.
    StarField {
        anchors.fill: parent
        opacity: bd.dim * 0.9
        visible: opacity > 0.01
        animated: false
        cellScale: 1.3
        sparkles: [[0.1, 0.2, 6, 0], [0.9, 0.16, 5, 1.7], [0.86, 0.62, 7, 4.4]]
        sparkleOpacity: 0.7
    }

    // Accent glow behind the middle. Own shader instead of RadialGradient: that ran linearly from 14 % to 0
    // and showed fine rings on the blurred wallpaper (banding, as in the power menu before);
    // windows/shaders/glow.frag runs out without a kink and with dithering. Same extent (ends at the edge).
    ShaderEffect {
        property color tint: WalColors.color4
        property real strength: 0.14

        anchors.centerIn: parent
        width: parent.width * 1.1
        height: parent.height * 1.2
        opacity: bd.dim * (0.6 + 0.4 * bd.wake)
        fragmentShader: Qt.resolvedUrl("../windows/shaders/glow.frag.qsb")
    }

}
