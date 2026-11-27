pragma ComponentBehavior: Bound

import "../services"
import QtQuick
import QtQuick.Shapes

// Dropdown: screen. Night light (services/NightLight: off, by schedule or always, the warmth as a
// slider) and keep awake (services/KeepAwake: for a set time or until turned off). Laptops get the
// brightness slider below. The height never changes: every part is always there.
// Deliberately few kinds of elements (it was too busy with three head lines, two tab bars, a day strip
// and a divider): each feature is one round switch with its name and what it is doing right now, and
// one pill to choose from. No lines. What moves: the switch (ring, symbol), the thumb of the pill,
// the status text, and the parts glide in one after the other when the dropdown opens.
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
    // Share of the set time that is left (1 = just started or without an end)
    readonly property real awakeLeft: {
        if (!KeepAwake.active)
            return 0;

        if (KeepAwake.minutes <= 0)
            return 1;

        return Math.max(0, Math.min(1, (KeepAwake.until - KeepAwake.clock) / (KeepAwake.minutes * 60000)));
    }
    // 0 -> 1 once after loading (the dropdown is loaded anew every time it opens): the parts glide in
    property real intro: 0

    // Color of a white surface at k Kelvin (Tanner Helland's fit, only its part below 6600 K)
    function kelvinColor(k) {
        const t = k / 100;
        const g = Math.max(0, Math.min(255, 99.4708025861 * Math.log(t) - 161.1195681661));
        const b = t <= 19 ? 0 : Math.max(0, Math.min(255, 138.5177312231 * Math.log(t - 10) - 305.0447927307));
        return Qt.rgba(1, g / 255, b / 255, 1);
    }

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight
    Component.onCompleted: introAnim.start()

    NumberAnimation {
        id: introAnim

        target: dropdown
        property: "intro"
        from: 0
        to: 1
        duration: 620
        easing.type: Easing.Linear
    }

    Column {
        id: content

        width: dropdown.innerW
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gap + Theme.px(6)
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        DropdownHeader {
            glyph: "\u{F0379}"
            title: "Screen"
            settingsSection: "desktop"
        }

        // ---------- Night light ----------
        Part {
            order: 0
            enabled: dropdown.nightUsable
            dimmed: !dropdown.nightUsable

            Head {
                // Sun while the colors are untouched, moon while they are warm (as the bar icon)
                glyph: "\u{F05A8}"
                glyphOn: "\u{F0594}"
                title: "Night light"
                status: NightLight.statusText
                lit: NightLight.warm
                // During the half hour in which the schedule fades in or out the ring is partly closed
                progress: NightLight.level
                problem: !NightLight.available || NightLight.failed
                onToggled: NightLight.toggle()
            }

            Segmented {
                model: dropdown.nightModes
                current: NightLight.mode
                offKey: "off"
                onSelected: (key) => {
                    return NightLight.setMode(key);
                }
            }

            // Warmth: left = barely warm, right = very warm. The screen shows the color as soon as the
            // slider rests (every color change stalls Hyprland briefly, see services/NightLight).
            Warmth {
                opacity: NightLight.mode === "off" ? 0.5 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.anim.durations.normal
                    }

                }

            }

        }

        // ---------- Keep awake ----------
        Part {
            order: 1

            Head {
                glyph: "\u{F06CA}"
                glyphOn: "\u{F0176}"
                title: "Keep awake"
                status: KeepAwake.statusText
                lit: KeepAwake.active
                // With a set time the ring runs down
                progress: dropdown.awakeLeft
                onToggled: KeepAwake.toggle()
            }

            Segmented {
                model: dropdown.awakeTimes
                current: KeepAwake.active ? KeepAwake.minutes : 0
                offKey: 0
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

    // One feature: head, pill and whatever else belongs to it. Glides in after the one above it
    component Part: Column {
        id: part

        property int order: 0
        property bool dimmed: false
        // Own share of the intro: starts 90 ms after the part above, eased out softly
        readonly property real shown: {
            const t = Math.max(0, Math.min(1, (dropdown.intro * 620 - 60 - order * 90) / 440));
            return 1 - Math.pow(1 - t, 4);
        }

        width: parent ? parent.width : 0
        spacing: Theme.px(10)
        opacity: shown * (dimmed ? 0.4 : 1)

        transform: Translate {
            y: (1 - part.shown) * 10
        }

    }

    // Round switch + name, below it what the feature is doing right now. A click on the switch turns it
    // off, or on again the way it was.
    component Head: Item {
        id: head

        property string glyph: ""
        property string glyphOn: ""
        property string title: ""
        property string status: ""
        property bool lit: false
        property real progress: 0
        property bool problem: false
        // 0 = off, 1 = on: everything of the switch hangs on this one value
        property real k: lit ? 1 : 0
        property real ring: lit ? progress : 0

        signal toggled()

        width: parent ? parent.width : 0
        height: orb.height

        Item {
            id: orb

            width: Theme.px(36)
            height: width
            scale: orbMouse.pressed ? 0.9 : 1

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.tint(Theme.accent, 0.16 * head.k)
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: orbMouse.containsMouse ? Theme.cardHover : Theme.card
                opacity: 1 - head.k

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

            // Ring: closes from the top when turned on. Hidden at 0: the round cap would draw a dot
            Shape {
                anchors.fill: parent
                visible: head.ring > 0.004
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                ShapePath {
                    strokeColor: Theme.accent
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: orb.width / 2
                        centerY: orb.height / 2
                        radiusX: orb.width / 2 - 0.75
                        radiusY: radiusX
                        startAngle: -90
                        sweepAngle: 360 * head.ring
                    }

                }

            }

            // The two symbols turn into each other: the old one turns away and fades, the new one turns in
            Text {
                anchors.centerIn: parent
                text: head.glyph
                color: Theme.textDim
                font.family: Theme.font
                font.pixelSize: Theme.sizeLarge + 2
                opacity: 1 - head.k
                rotation: 70 * head.k
                scale: 1 - 0.4 * head.k
            }

            Text {
                anchors.centerIn: parent
                text: head.glyphOn
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.sizeLarge + 2
                opacity: head.k
                rotation: -70 * (1 - head.k)
                scale: 0.6 + 0.4 * head.k
            }

            MouseArea {
                id: orbMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: head.toggled()
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutBack
                }

            }

        }

        Column {
            anchors.left: orb.right
            anchors.leftMargin: Theme.px(11)
            anchors.right: parent.right
            anchors.verticalCenter: orb.verticalCenter
            spacing: 1

            Text {
                text: head.title
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLabel
                font.weight: Font.Medium
            }

            SwapText {
                width: parent.width
                text: head.status
                color: head.problem ? Theme.warn : (head.lit ? Theme.accent : Theme.textFaint)
            }

        }

        Behavior on k {
            NumberAnimation {
                duration: 520
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.outQuint
            }

        }

        Behavior on ring {
            NumberAnimation {
                duration: 700
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.outQuint
            }

        }

    }

    // A line of text that changes softly: the old text leaves upward, the new one comes from below
    component SwapText: Item {
        id: swap

        property string text: ""
        property color color: Theme.textFaint
        property string current: ""
        property string previous: ""
        property real t: 1
        // The first text is simply there, only later ones glide
        property bool ready: false

        height: now.implicitHeight
        clip: true
        Component.onCompleted: {
            current = text;
            ready = true;
        }
        onTextChanged: {
            if (!ready || text === current)
                return ;

            previous = current;
            current = text;
            swapAnim.restart();
        }

        Text {
            width: parent.width
            y: -swap.height * 0.6 * swap.t
            text: swap.previous
            color: swap.color
            opacity: 1 - swap.t
            visible: opacity > 0.01
            elide: Text.ElideRight
            font: now.font
        }

        Text {
            id: now

            width: parent.width
            y: swap.height * 0.6 * (1 - swap.t)
            text: swap.current
            color: swap.color
            opacity: swap.t
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeSmall

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.normal
                }

            }

        }

        NumberAnimation {
            id: swapAnim

            target: swap
            property: "t"
            from: 0
            to: 1
            duration: 320
            easing.type: Easing.OutCubic
        }

    }

    // Choice as one pill: the thumb glides to the chosen entry. model = [{ key, label }]
    component Segmented: Item {
        id: seg

        property var model: []
        property var current: ""
        // The entry that means "off": there the thumb stays neutral, on every other one it takes the accent
        property var offKey: ""
        readonly property int activeIndex: {
            for (let i = 0; i < model.length; ++i) {
                if (model[i].key === current)
                    return i;

            }
            return 0;
        }
        readonly property bool lit: current !== offKey
        readonly property real pad: 3
        readonly property real slotW: (width - 2 * pad) / Math.max(1, model.length)
        readonly property real targetX: pad + activeIndex * slotW
        // Two followers of the same target, one quick and one slow. The thumb spans from the one behind
        // to the one in front, so it stretches on the way and settles at its width, in both directions
        property real lead: targetX
        property real trail: targetX

        signal selected(var key)

        width: parent ? parent.width : 0
        height: Theme.px(30)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.card
        }

        Rectangle {
            x: Math.min(seg.lead, seg.trail)
            y: seg.pad
            width: Math.abs(seg.lead - seg.trail) + seg.slotW
            height: parent.height - 2 * seg.pad
            radius: height / 2
            color: seg.lit ? Theme.tint(Theme.accent, 0.2) : Theme.glass

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.normal
                }

            }

        }

        Row {
            x: seg.pad

            Repeater {
                model: seg.model

                delegate: Item {
                    id: slot

                    required property var modelData
                    required property int index
                    readonly property bool active: seg.activeIndex === index

                    width: seg.slotW
                    height: seg.height

                    Text {
                        anchors.centerIn: parent
                        text: slot.modelData.label
                        color: slot.active ? (seg.lit ? Theme.accent : Theme.text) : (slotMouse.containsMouse ? Theme.tint(Theme.text, 0.8) : Theme.textFaint)
                        font.family: Theme.fontUi
                        font.features: Theme.tabular
                        font.pixelSize: Theme.sizeBody
                        font.weight: Font.Medium

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.expressiveDefaultEffects
                            }

                        }

                    }

                    MouseArea {
                        id: slotMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.selected(slot.modelData.key)
                    }

                }

            }

        }

        Behavior on lead {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }

        }

        Behavior on trail {
            NumberAnimation {
                duration: 460
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.outQuint
            }

        }

    }

    // Warmth as a fine line in the real colors of the temperatures, a knob, the value next to it.
    // Drag/click sets, the mouse wheel steps by 100 K, a double click returns to 4000 K.
    component Warmth: Item {
        id: warmth

        readonly property real span: NightLight.maxTemperature - NightLight.minTemperature
        // While dragging the knob follows the mouse; the temperature only moves in steps of 100 K
        property real dragValue: 0
        readonly property real value: area.pressed ? dragValue : (NightLight.maxTemperature - NightLight.temperature) / span
        readonly property bool active: area.containsMouse || area.pressed
        readonly property real knobD: Theme.px(14)
        readonly property real trackW: width - valueText.width - Theme.px(12)
        // Middle of the knob: it stays inside the ends of the line
        readonly property real knobX: knobD / 2 + (trackW - knobD) * shownValue
        property real shownValue: value

        function kelvinAt(v) {
            return NightLight.clampK(NightLight.maxTemperature - v * span);
        }

        function valueAt(x) {
            return Math.max(0, Math.min(1, (x - knobD / 2) / (trackW - knobD)));
        }

        width: parent ? parent.width : 0
        height: Theme.px(24)

        // The whole range, faint
        Rectangle {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            width: warmth.trackW
            height: 4
            radius: 2
            opacity: 0.22
            gradient: warmGradient
        }

        // Up to the knob in full color
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: warmth.knobX
            height: 4
            clip: true

            Rectangle {
                width: warmth.trackW
                height: parent.height
                radius: 2
                gradient: warmGradient
            }

        }

        Gradient {
            id: warmGradient

            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: dropdown.kelvinColor(NightLight.maxTemperature)
            }

            GradientStop {
                position: 0.5
                color: dropdown.kelvinColor((NightLight.maxTemperature + NightLight.minTemperature) / 2)
            }

            GradientStop {
                position: 1
                color: dropdown.kelvinColor(NightLight.minTemperature)
            }

        }

        // Halo while the knob is held
        Rectangle {
            x: warmth.knobX - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: warmth.knobD + Theme.px(12)
            height: width
            radius: width / 2
            color: Theme.tint(Theme.knob, 0.14)
            opacity: area.pressed ? 1 : 0
            scale: area.pressed ? 1 : 0.6

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.fast
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
            x: warmth.knobX - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: warmth.knobD
            height: width
            radius: width / 2
            color: Theme.knob
            scale: area.pressed ? 0.88 : (warmth.active ? 1.12 : 1)

            Behavior on scale {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutBack
                }

            }

        }

        Text {
            id: valueText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // Fixed width (the widest value): the line does not change its length while dragging
            width: Math.ceil(valueMetrics.width)
            horizontalAlignment: Text.AlignRight
            text: NightLight.temperature + " K"
            color: warmth.active ? Theme.text : Theme.textDim
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeBody
            font.weight: Font.Medium

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        TextMetrics {
            id: valueMetrics

            font: valueText.font
            text: "0000 K"
        }

        MouseArea {
            id: area

            width: warmth.trackW
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => {
                warmth.dragValue = warmth.valueAt(mouse.x);
                NightLight.draftTemperature = warmth.kelvinAt(warmth.dragValue);
            }
            onPositionChanged: (mouse) => {
                if (!pressed)
                    return ;

                warmth.dragValue = warmth.valueAt(mouse.x);
                NightLight.draftTemperature = warmth.kelvinAt(warmth.dragValue);
            }
            // Still held at this moment: as the value under the mouse, the release keeps it
            onDoubleClicked: {
                warmth.dragValue = (NightLight.maxTemperature - 4000) / warmth.span;
                NightLight.draftTemperature = 4000;
            }
            onWheel: (wheel) => {
                return NightLight.nudge(wheel.angleDelta.y > 0 ? -100 : 100);
            }
            // Released: keep the value and end the preview
            onPressedChanged: {
                if (!pressed)
                    NightLight.commitDraft();

            }
        }

        // Dragging follows the mouse directly; a click elsewhere, the wheel and a reset glide
        Behavior on shownValue {
            enabled: !area.pressed

            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }

        }

    }

}
