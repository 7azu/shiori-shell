pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell.Io

// Top of the settings page "Windows": a small desktop with three windows on the current wallpaper,
// drawn from the same values Hyprland gets (gaps, border size and colors, corners, opacity, shadow,
// blur). Every value glides to its new size; how fast follows the animation speed of the page, without
// animations it jumps. Pointing at a window focuses it, so active and inactive borders can be compared.
// Sizes are those of a 1600 px wide screen, scaled to the card.
IosGroup {
    id: root

    function w(key) {
        return Settings.get("windows." + key);
    }

    readonly property real gapsIn: Number(w("gapsIn")) || 0
    readonly property real gapsOut: Number(w("gapsOut")) || 0
    readonly property real borderSize: Number(w("borderSize")) || 0
    readonly property real rounding: Number(w("rounding")) || 0
    readonly property real activeOpacity: (Number(w("activeOpacity")) || 100) / 100
    readonly property real inactiveOpacity: (Number(w("inactiveOpacity")) || 100) / 100
    readonly property bool shadowOn: w("shadow") !== false
    readonly property real shadowRange: Number(w("shadowRange")) || 0
    readonly property bool blurOn: w("blur") !== false
    readonly property real blurSize: Number(w("blurSize")) || 0
    readonly property real blurPasses: Number(w("blurPasses")) || 1
    // Length of one glide: follows the animation speed, 0 without animations
    readonly property int glide: w("animations") === false ? 0 : Math.round(420 * WindowStyle.animSpeed)
    property int focused: 0
    property string wallpaper: ""

    title: "Preview"
    footer: "Point at a window to focus it. Every change is live on your real windows, too."

    // The current wallpaper (pywal keeps its path here)
    FileView {
        path: Settings.home + "/.cache/wal/wal"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wallpaper = text().trim()
    }

    Item {
        width: parent.width
        height: desk.height + Theme.px(28)

        // The screen: rounded, a thin edge, the wallpaper inside
        RoundedClip {
            id: desk

            readonly property real k: width / 1600
            readonly property real barH: 40 * k
            // Area of the windows (Hyprland: outer gaps from the edges and the bar, inner gaps on every
            // side of every window = twice between two)
            readonly property real go: root.gapsOut * k
            readonly property real gi: root.gapsIn * k
            readonly property real ax: go
            readonly property real ay: barH + go
            readonly property real aw: width - 2 * go
            readonly property real ah: height - barH - 2 * go
            readonly property real mw: (aw - 2 * gi) * 0.56
            readonly property real rh: (ah - 2 * gi) / 2
            readonly property var rects: [Qt.rect(ax, ay, mw, ah), Qt.rect(ax + mw + 2 * gi, ay, aw - mw - 2 * gi, rh), Qt.rect(ax + mw + 2 * gi, ay + rh + 2 * gi, aw - mw - 2 * gi, rh)]

            x: Theme.px(14)
            y: Theme.px(14)
            width: parent.width - Theme.px(28)
            height: Math.round(width * 0.5)
            radius: Theme.px(12)
            color: WalColors.color0

            Image {
                id: wall

                anchors.fill: parent
                source: root.wallpaper ? "file://" + root.wallpaper : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 900
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                    }

                }

            }

            // Same picture, hidden: what the windows blur behind themselves
            Image {
                id: wallSource

                width: desk.width
                height: desk.height
                visible: false
                source: wall.source
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 900
                asynchronous: true
                cache: true
            }

            // The bar: a thin strip with the workspaces
            Rectangle {
                width: parent.width
                height: desk.barH
                color: WalColors.withAlpha(WalColors.color0, 0.82)

                Row {
                    x: Theme.px(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.px(5)

                    Repeater {
                        model: 5

                        delegate: Rectangle {
                            required property int index

                            anchors.verticalCenter: parent.verticalCenter
                            width: index === 0 ? Theme.px(16) : Theme.px(6)
                            height: Theme.px(6)
                            radius: height / 2
                            color: index === 0 ? Theme.accent : Theme.tint(Theme.text, 0.3)
                        }

                    }

                }

                Text {
                    anchors.centerIn: parent
                    text: "12:00"
                    color: Theme.tint(Theme.text, 0.75)
                    font.family: Theme.fontUi
                    font.pixelSize: Math.max(Theme.px(8), desk.barH * 0.42)
                    font.features: Theme.tabular
                }

            }

            Repeater {
                model: 3

                delegate: Item {
                    id: win

                    required property int index
                    readonly property rect r: desk.rects[index]
                    readonly property bool active: root.focused === index
                    property real rad: Math.min(root.rounding * desk.k, Math.min(width, height) / 2)

                    x: r.x
                    y: r.y
                    width: r.width
                    height: r.height

                    // Large, soft, slightly downwards like in Hyprland (weaker when unfocused)
                    RectangularShadow {
                        anchors.fill: parent
                        offset.y: 8 * desk.k
                        radius: win.rad
                        blur: root.shadowRange * desk.k
                        spread: 0
                        color: WalColors.withAlpha(WalColors.color0, win.active ? 0.8 : 0.53)
                        opacity: root.shadowOn ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: root.glide
                            }

                        }

                    }

                    RoundedClip {
                        anchors.fill: parent
                        radius: win.rad

                        // What lies behind the window, blurred when blur is on
                        MultiEffect {
                            x: -win.x
                            y: -win.y
                            width: desk.width
                            height: desk.height
                            source: wallSource
                            blurEnabled: true
                            blurMax: 64
                            blur: root.blurOn ? Math.min(1, root.blurSize * Math.sqrt(root.blurPasses) / 24) : 0

                            Behavior on blur {
                                NumberAnimation {
                                    duration: root.glide
                                }

                            }

                        }

                        // The window itself, as see-through as its opacity says
                        Item {
                            anchors.fill: parent
                            opacity: win.active ? root.activeOpacity : root.inactiveOpacity

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.03))
                            }

                            Loader {
                                anchors.fill: parent
                                sourceComponent: [terminal, editor, player][win.index]
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Math.max(200, root.glide)
                                }

                            }

                        }

                    }

                    // The border, drawn over the edge like Hyprland does
                    Rectangle {
                        anchors.fill: parent
                        radius: win.rad
                        color: "transparent"
                        border.width: root.borderSize
                        border.color: win.active ? WindowStyle.activeBorder : WindowStyle.inactiveBorder

                        Behavior on border.color {
                            ColorAnimation {
                                duration: Math.max(180, root.glide)
                            }

                        }

                    }

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered)
                                root.focused = win.index;

                        }
                    }

                    Behavior on x {
                        NumberAnimation {
                            duration: root.glide
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on y {
                        NumberAnimation {
                            duration: root.glide
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: root.glide
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: root.glide
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on rad {
                        NumberAnimation {
                            duration: root.glide
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

        }

        // Thin edge of the desk above everything
        Rectangle {
            anchors.fill: desk
            radius: desk.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.tint(Theme.text, 0.1)
        }

    }

    // Made-up contents: lines in the palette colors, scaled with the desk
    Component {
        id: terminal

        Column {
            padding: Theme.px(12)
            spacing: Theme.px(6)

            Repeater {
                model: [[0.3, 4], [0.55, 1], [0.42, 2], [0.2, 4], [0.62, 5], [0.36, 3], [0.18, 4]]

                delegate: Row {
                    required property var modelData
                    required property int index

                    spacing: Theme.px(5)

                    Rectangle {
                        width: Theme.px(5)
                        height: Theme.px(5)
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: WalColors["color" + parent.modelData[1]]
                    }

                    Rectangle {
                        width: Theme.px(260) * parent.modelData[0]
                        height: Theme.px(5)
                        radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.tint(Theme.text, 0.35)
                    }

                }

            }

            // Blinking cursor
            Rectangle {
                width: Theme.px(7)
                height: Theme.px(10)
                radius: Theme.px(1)
                color: Theme.accent

                SequentialAnimation on opacity {
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 0.15
                        duration: 520
                    }

                    NumberAnimation {
                        to: 1
                        duration: 520
                    }

                }

            }

        }

    }

    Component {
        id: editor

        Column {
            padding: Theme.px(10)
            spacing: Theme.px(5)

            Repeater {
                model: [0.5, 0.75, 0.35, 0.6, 0.28]

                delegate: Rectangle {
                    required property real modelData
                    required property int index

                    x: (index % 3) * Theme.px(8)
                    width: Theme.px(150) * modelData
                    height: Theme.px(4)
                    radius: height / 2
                    color: index === 1 ? WalColors.withAlpha(WalColors.color4, 0.8) : Theme.tint(Theme.text, 0.28)
                }

            }

        }

    }

    Component {
        id: player

        Row {
            padding: Theme.px(10)
            spacing: Theme.px(10)

            Rectangle {
                width: Theme.px(30)
                height: width
                radius: Theme.px(5)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: WalColors.color5
                    }

                    GradientStop {
                        position: 1
                        color: WalColors.color2
                    }

                }

            }

            Column {
                topPadding: Theme.px(8)
                spacing: Theme.px(5)

                Rectangle {
                    width: Theme.px(70)
                    height: Theme.px(4)
                    radius: height / 2
                    color: Theme.tint(Theme.text, 0.45)
                }

                Rectangle {
                    width: Theme.px(46)
                    height: Theme.px(4)
                    radius: height / 2
                    color: Theme.tint(Theme.text, 0.22)
                }

            }

        }

    }

}
