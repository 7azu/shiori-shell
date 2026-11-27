pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick

// Color row of the settings (type "color"): the colors of the wallpaper palette as round swatches
// (value "wal:colorN", follows every wallpaper change), then one own color (value "#rrggbb"). The own
// color opens a small editor below: hue line, shade line and a hex field. Dragging only shows the
// color; it is stored on release, so the undo list gets one step per pick.
Column {
    id: pick

    // "wal:color5" or "#rrggbb"
    property string value: ""
    readonly property bool custom: value.startsWith("#")
    readonly property var slots: ["color0", "color1", "color2", "color3", "color4", "color5", "color6", "color7", "color8"]
    // The color while a line is dragged (null = the stored one)
    property var dragColor: null
    readonly property color shown: dragColor !== null ? dragColor : WindowStyle.resolve(value, "color5")
    readonly property real dot: Theme.px(26)

    signal picked(string value)

    function hex(c) {
        const h = (v) => {
            return ("0" + Math.round(v * 255).toString(16)).slice(-2);
        };
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    spacing: Theme.px(12)

    Row {
        spacing: Theme.px(8)

        Repeater {
            model: pick.slots

            delegate: Swatch {
                required property string modelData

                fill: WalColors[modelData] || "#888888"
                chosen: pick.value === "wal:" + modelData
                onClicked: pick.picked("wal:" + modelData)
            }

        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: pick.dot * 0.7
            color: Theme.separator
        }

        // Own color: shows it once chosen, before that a ring of hues
        Swatch {
            fill: pick.custom ? pick.shown : "transparent"
            chosen: pick.custom
            rainbow: !pick.custom
            onClicked: {
                if (!pick.custom)
                    pick.picked(pick.hex(Qt.color(WindowStyle.resolve(pick.value, "color5"))));

            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Theme.px(4)
            text: pick.custom ? "Custom" : "From the wallpaper"
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
        }

    }

    // Editor of the own color
    Item {
        width: parent.width
        height: pick.custom ? editor.height : 0
        opacity: pick.custom ? 1 : 0
        clip: true

        Row {
            id: editor

            width: parent.width
            spacing: Theme.px(14)

            Column {
                width: parent.width - hexField.width - Theme.px(14)
                spacing: Theme.px(10)
                topPadding: Theme.px(2)

                Strip {
                    width: parent.width
                    // Hue: keeps shade and saturation (a grey gets some color, so the hue shows)
                    colorAt: (t) => {
                        return Qt.hsla(t % 1, 0.58, 0.62, 1);
                    }
                    pos: Math.max(0, pick.shown.hslHue)
                    onMoved: (t) => {
                        const c = pick.shown;
                        pick.dragColor = Qt.hsla(Math.min(t, 0.999), Math.max(c.hslSaturation, 0.45), c.hslLightness < 0.08 || c.hslLightness > 0.92 ? 0.55 : c.hslLightness, 1);
                    }
                    onDone: {
                        pick.picked(pick.hex(pick.dragColor));
                        pick.dragColor = null;
                    }
                }

                Strip {
                    width: parent.width
                    // Shade: from almost black over the color to almost white
                    colorAt: (t) => {
                        const c = pick.shown;
                        return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, 0.04 + t * 0.92, 1);
                    }
                    pos: (pick.shown.hslLightness - 0.04) / 0.92
                    onMoved: (t) => {
                        const c = pick.shown;
                        pick.dragColor = Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, 0.04 + t * 0.92, 1);
                    }
                    onDone: {
                        pick.picked(pick.hex(pick.dragColor));
                        pick.dragColor = null;
                    }
                }

            }

            SettingField {
                id: hexField

                anchors.verticalCenter: parent.verticalCenter
                width: Theme.px(108)
                text: pick.hex(pick.shown)
                placeholder: "#rrggbb"
                onCommitted: (t) => {
                    const s = t.trim().replace(/^([^#])/, "#$1");
                    if (/^#[0-9a-fA-F]{6}$/.test(s))
                        pick.picked(s.toLowerCase());

                }
            }

        }

        Behavior on height {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }

        }

    }

    // A round color: grows a little under the mouse; the chosen one gets a ring with a gap
    component Swatch: Item {
        id: sw

        property color fill: "transparent"
        property bool chosen: false
        property bool rainbow: false

        signal clicked()

        width: pick.dot
        height: pick.dot
        scale: swMouse.pressed ? 0.92 : (swMouse.containsMouse ? 1.12 : 1)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.text
            opacity: sw.chosen ? 0.85 : 0
            scale: sw.chosen ? 1 : 0.8

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutBack
                }

            }

        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - Theme.px(8)
            height: width
            radius: width / 2
            color: sw.fill
            border.width: 1
            border.color: Theme.tint(Theme.text, 0.14)

            Behavior on color {
                ColorAnimation {
                    duration: 260
                }

            }

        }

        // Ring of hues for "pick your own"
        Repeater {
            model: sw.rainbow ? 12 : 0

            delegate: Rectangle {
                required property int index

                x: sw.width / 2 + Math.cos(index / 12 * 2 * Math.PI) * (sw.width / 2 - Theme.px(8)) - width / 2
                y: sw.height / 2 + Math.sin(index / 12 * 2 * Math.PI) * (sw.width / 2 - Theme.px(8)) - height / 2
                width: Theme.px(4)
                height: width
                radius: width / 2
                color: Qt.hsla(index / 12, 0.7, 0.62, 1)
            }

        }

        MouseArea {
            id: swMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.clicked()
        }

        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }

        }

    }

    // A thin color line with a round knob; drag or click along it
    component Strip: Item {
        id: strip

        property var colorAt: null
        property real pos: 0

        signal moved(real t)
        signal done()

        height: Theme.px(18)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Theme.px(8)
            radius: height / 2
            border.width: 1
            border.color: Theme.tint(Theme.text, 0.1)

            // Seven fixed stops are smooth enough for hue and shade
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0/6
                    color: strip.colorAt ? strip.colorAt(0/6) : "black"
                }

                GradientStop {
                    position: 1/6
                    color: strip.colorAt ? strip.colorAt(1/6) : "black"
                }

                GradientStop {
                    position: 2/6
                    color: strip.colorAt ? strip.colorAt(2/6) : "black"
                }

                GradientStop {
                    position: 3/6
                    color: strip.colorAt ? strip.colorAt(3/6) : "black"
                }

                GradientStop {
                    position: 4/6
                    color: strip.colorAt ? strip.colorAt(4/6) : "black"
                }

                GradientStop {
                    position: 5/6
                    color: strip.colorAt ? strip.colorAt(5/6) : "black"
                }

                GradientStop {
                    position: 6/6
                    color: strip.colorAt ? strip.colorAt(6/6) : "black"
                }

            }

        }

        Rectangle {
            x: Math.max(0, Math.min(1, strip.pos)) * (strip.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(16)
            height: width
            radius: width / 2
            color: strip.colorAt ? strip.colorAt(Math.max(0, Math.min(1, strip.pos))) : "white"
            border.width: 2
            border.color: Theme.text
            scale: stripMouse.pressed ? 1.18 : (stripMouse.containsMouse ? 1.08 : 1)

            Behavior on scale {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }

            }

        }

        MouseArea {
            id: stripMouse

            function at(x) {
                return Math.max(0, Math.min(1, x / width));
            }

            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (e) => {
                return strip.moved(at(e.x));
            }
            onPositionChanged: (e) => {
                if (pressed)
                    strip.moved(at(e.x));

            }
            onReleased: strip.done()
        }

    }

}
