pragma ComponentBehavior: Bound

import "../services"
import QtQuick

// Dropdown: screen. Night light (services/NightLight: off, by schedule or always, with the day as a
// strip and the warmth as a slider) and keep awake (services/KeepAwake: for a set time or until turned
// off). Laptops get the brightness slider below. The height never changes: every part is always there.
Item {
    id: dropdown

    readonly property real cornerRadius: 20
    readonly property real menuWidth: 270
    readonly property real innerW: menuWidth - 2 * Theme.padX
    readonly property bool nightUsable: NightLight.available
    readonly property var nightModes: [{
        "key": "off",
        "label": "Off"
    }, {
        "key": "auto",
        "label": "Auto"
    }, {
        "key": "on",
        "label": "On"
    }]
    readonly property var awakeTimes: [{
        "key": 0,
        "label": "Off"
    }, {
        "key": 30,
        "label": "30 min"
    }, {
        "key": 60,
        "label": "1 h"
    }, {
        "key": 120,
        "label": "2 h"
    }, {
        "key": -1,
        "label": "On"
    }]

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight

    Column {
        id: content

        width: dropdown.innerW
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gap
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        DropdownHeader {
            glyph: "\u{F0379}"
            title: "Screen"
            settingsSection: "desktop"
        }

        // ---------- Night light ----------
        Column {
            width: parent.width
            spacing: Theme.gapSmall

            SectionHead {
                glyph: "\u{F1A4C}"
                title: "Night light"
                status: NightLight.statusText
                lit: NightLight.warm
                problem: !NightLight.available || NightLight.failed
            }

            Tabs {
                width: parent.width
                enabled: dropdown.nightUsable
                opacity: dropdown.nightUsable ? 1 : 0.4
                model: dropdown.nightModes
                current: NightLight.mode
                onSelected: (key) => {
                    return NightLight.setMode(key);
                }
            }

            // The day from midnight to midnight: the warm time as a band that fades in and out with the
            // schedule, a dot for now. Pale unless the schedule decides.
            Item {
                id: strip

                readonly property real fromX: width * NightLight.span.from / 1440
                readonly property real untilX: width * NightLight.span.until / 1440
                // Length of the warm time; over midnight it leaves on the right and comes back on the left
                readonly property real bandW: width * ((NightLight.span.until - NightLight.span.from + 1440) % 1440) / 1440
                // Share of the band that the fade takes at each end
                readonly property real fade: bandW > 0 ? Math.min(0.5, width * NightLight.rampMinutes / 1440 / bandW) : 0
                readonly property bool scheduled: NightLight.mode === "auto" && dropdown.nightUsable

                width: parent.width
                height: 30
                opacity: scheduled ? 1 : 0.38

                Item {
                    id: track

                    width: parent.width
                    height: 4
                    y: 6
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Theme.track
                    }

                    // Twice: the second copy is the part that came back in on the left
                    Repeater {
                        model: 2

                        Rectangle {
                            required property int index

                            x: strip.fromX - index * strip.width
                            width: strip.bandW
                            height: parent.height
                            radius: 2

                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0
                                    color: Theme.tint(Theme.accent, 0)
                                }

                                GradientStop {
                                    position: strip.fade
                                    color: Theme.tint(Theme.accent, 0.85)
                                }

                                GradientStop {
                                    position: 1 - strip.fade
                                    color: Theme.tint(Theme.accent, 0.85)
                                }

                                GradientStop {
                                    position: 1
                                    color: Theme.tint(Theme.accent, 0)
                                }

                            }

                        }

                    }

                }

                // Now
                Rectangle {
                    x: Math.round(strip.width * NightLight.minuteOfDay / 1440 - width / 2)
                    y: track.y + track.height / 2 - height / 2
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.text
                    border.width: 2
                    border.color: WalColors.color0
                }

                // When it starts and ends, under their places on the strip (kept inside the edges)
                Repeater {
                    model: [{
                        "at": strip.fromX,
                        "minutes": NightLight.span.from
                    }, {
                        "at": strip.untilX,
                        "minutes": NightLight.span.until
                    }]

                    Text {
                        required property var modelData

                        x: Math.round(Math.max(0, Math.min(strip.width - width, modelData.at - width / 2)))
                        y: track.y + track.height + 6
                        text: NightLight.clockText(modelData.minutes)
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.features: Theme.tabular
                        font.pixelSize: Theme.sizeSmall
                    }

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

            // Warmth: left = barely warm, right = very warm. The screen shows the color as soon as the
            // slider rests (every color change stalls Hyprland briefly, see services/NightLight).
            PillSlider {
                id: warmth

                readonly property real span: NightLight.maxTemperature - NightLight.minTemperature
                // While dragging the fill follows the mouse; the temperature only moves in steps of 100 K
                property real dragValue: 0

                function kelvinAt(v) {
                    return NightLight.clampK(NightLight.maxTemperature - v * span);
                }

                width: parent.width
                enabled: dropdown.nightUsable
                opacity: dropdown.nightUsable ? 1 : 0.4
                value: pressed ? dragValue : (NightLight.maxTemperature - NightLight.temperature) / span
                glyph: "\u{F050F}"
                label: "warmth"
                valueText: NightLight.temperature + " K"
                onMoved: (v) => {
                    dragValue = v;
                    NightLight.draftTemperature = kelvinAt(v);
                }
                onStepped: (d) => {
                    return NightLight.nudge(-Math.sign(d) * 100);
                }
                onDoubleClicked: NightLight.setTemperature(4000)
                // Released: keep the value and end the preview
                onPressedChanged: {
                    if (!pressed)
                        NightLight.commitDraft();

                }
            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        // ---------- Keep awake ----------
        Column {
            width: parent.width
            spacing: Theme.gapSmall

            SectionHead {
                glyph: KeepAwake.active ? "\u{F0176}" : "\u{F06CA}"
                title: "Keep awake"
                status: KeepAwake.statusText
                lit: KeepAwake.active
            }

            Tabs {
                width: parent.width
                model: dropdown.awakeTimes
                current: KeepAwake.active ? KeepAwake.minutes : 0
                onSelected: (key) => {
                    return KeepAwake.set(key);
                }
            }

        }

        BrightnessSlider {
            width: parent.width
            visible: BrightnessState.available
        }

    }

    // Line above a part: symbol + NAME on the left, what it is doing right now on the right
    component SectionHead: Item {
        id: head

        property string glyph: ""
        property string title: ""
        property string status: ""
        // On right now: the status takes the accent color
        property bool lit: false
        property bool problem: false

        width: parent ? parent.width : 0
        height: Theme.chipHeight

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: head.glyph
                color: head.lit ? Theme.accent : Theme.textDim
                font.family: Theme.font
                font.pixelSize: Theme.sizeBody + 2
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: head.title.toUpperCase()
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeMicro
                font.bold: true
                font.letterSpacing: Theme.microSpacing
            }

        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: head.status
            color: head.problem ? Theme.warn : (head.lit ? Theme.accent : Theme.textFaint)
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeSmall

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

    }

}
