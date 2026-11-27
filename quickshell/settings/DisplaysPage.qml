pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick

// Page "Displays" of the settings window (state and saving: services/DisplayState).
// On top the arrangement: every monitor as a tile at its place and size, dragged to a new place it
// snaps to the edges of the others; a turned monitor turns its tile. Below the selected monitor:
// on/off, resolution, refresh rate, scale, rotation. Nothing changes on the screens until "Apply";
// then 15 s to keep it, otherwise it goes back by itself.
Column {
    id: page

    // The monitor whose details are shown
    property string selected: ""
    readonly property var monitors: DisplayState.monitors
    readonly property var cur: monitors.find((m) => {
        return m.name === selected;
    }) || monitors.find((m) => {
        return m.enabled;
    }) || null
    readonly property var curDraft: cur ? DisplayState.draft[cur.name] : null
    readonly property int enabledCount: monitors.filter((m) => {
        return DisplayState.draft[m.name] && DisplayState.draft[m.name].enabled;
    }).length

    // Where a dragged monitor lands: the nearest free place touching another one (DisplayState)
    function snapped(name, x, y) {
        return DisplayState.placeFree(DisplayState.draft, name, x, y);
    }

    function resolutions(m) {
        const seen = {
        }, out = [];
        for (const md of m.modes) {
            const k = md.w + "x" + md.h;
            if (seen[k])
                continue;

            seen[k] = true;
            out.push({
                "value": k,
                "label": md.w + " × " + md.h,
                "w": md.w,
                "h": md.h
            });
        }
        return out.slice(0, 8);
    }

    function rates(m, w, h) {
        return m.modes.filter((md) => {
            return md.w === w && md.h === h;
        }).map((md) => {
            return {
                "value": md.hz,
                "label": (Math.round(md.hz * 10) / 10) + " Hz"
            };
        });
    }

    spacing: Theme.px(22)
    Component.onCompleted: DisplayState.refresh()

    // ---------- Arrangement ----------
    IosGroup {
        width: page.width
        title: "Arrangement"
        footer: "Drag a monitor to move it; it snaps to the edges of the others. The thin line marks the one with the bar."
        actionText: "Identify"
        onActionClicked: DisplayState.identify()

        Item {
            id: canvas

            // Layout coordinates -> pixels: fitted to the card, frozen while a tile is dragged
            readonly property var enabledList: page.monitors.filter((m) => {
                return DisplayState.draft[m.name] && DisplayState.draft[m.name].enabled;
            })
            readonly property var bounds: {
                let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
                for (const m of enabledList) {
                    const d = DisplayState.draft[m.name], s = DisplayState.logical(d);
                    x0 = Math.min(x0, d.x);
                    y0 = Math.min(y0, d.y);
                    x1 = Math.max(x1, d.x + s.w);
                    y1 = Math.max(y1, d.y + s.h);
                }
                return isFinite(x0) ? {
                    "x": x0,
                    "y": y0,
                    "w": x1 - x0,
                    "h": y1 - y0
                } : {
                    "x": 0,
                    "y": 0,
                    "w": 1920,
                    "h": 1080
                };
            }
            readonly property real padding: Theme.px(34)
            readonly property real liveK: Math.min((width - 2 * padding) / bounds.w, (height - 2 * padding) / bounds.h)
            property var frozen: null
            readonly property var map: frozen || {
                "k": liveK,
                "ox": (width - bounds.w * liveK) / 2 - bounds.x * liveK,
                "oy": (height - bounds.h * liveK) / 2 - bounds.y * liveK
            }

            width: parent.width
            height: Theme.px(300)

            // A fine dotted ground, so the empty space reads as a plane the tiles stand on
            Repeater {
                model: Math.floor(canvas.width / Theme.px(24)) * Math.floor(canvas.height / Theme.px(24))

                delegate: Rectangle {
                    required property int index
                    readonly property int cols: Math.floor(canvas.width / Theme.px(24))

                    x: (index % cols) * Theme.px(24) + Theme.px(12)
                    y: Math.floor(index / cols) * Theme.px(24) + Theme.px(12)
                    width: Theme.px(2)
                    height: width
                    radius: width / 2
                    color: Theme.tint(Theme.text, 0.07)
                }

            }

            Repeater {
                model: canvas.enabledList

                delegate: Item {
                    id: tile

                    required property var modelData
                    readonly property string name: modelData.name
                    readonly property var d: DisplayState.draft[name]
                    readonly property var s: DisplayState.logical(d)
                    readonly property bool chosen: page.cur && page.cur.name === name
                    readonly property bool hasBar: MachineConfig.barScreenName === name
                    property bool dragging: false
                    property real dragX: 0
                    property real dragY: 0
                    // Where the drag would land (shown as a soft outline while dragging)
                    property var landing: null

                    x: dragging ? dragX : canvas.map.ox + d.x * canvas.map.k
                    y: dragging ? dragY : canvas.map.oy + d.y * canvas.map.k
                    width: s.w * canvas.map.k
                    height: s.h * canvas.map.k
                    z: dragging ? 10 : (chosen ? 2 : 1)
                    scale: dragging ? 1.04 : (mouse.containsMouse ? 1.02 : 1)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Theme.px(3)
                        radius: Theme.px(12)
                        color: tile.chosen ? Theme.tint(Theme.accent, 0.16) : Theme.tint(Theme.text, mouse.containsMouse ? 0.09 : 0.06)
                        border.width: tile.chosen ? 2 : 1
                        border.color: tile.chosen ? Theme.tint(Theme.accent, 0.75) : Theme.tint(Theme.text, mouse.containsMouse ? 0.22 : 0.12)

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                    }

                    // Where the drag will land: a soft outline at that place
                    Rectangle {
                        readonly property var m: canvas.map

                        x: tile.landing ? tile.landing.x * m.k + m.ox - tile.x + Theme.px(3) : 0
                        y: tile.landing ? tile.landing.y * m.k + m.oy - tile.y + Theme.px(3) : 0
                        width: tile.width - Theme.px(6)
                        height: tile.height - Theme.px(6)
                        radius: Theme.px(12)
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.tint(Theme.accent, 0.6)
                        opacity: tile.landing ? 1 : 0
                        visible: opacity > 0.01
                        z: -1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 160
                            }

                        }

                    }

                    // The bar lives here: a thin line at the top edge
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Theme.px(9)
                        width: parent.width * 0.42
                        height: Theme.px(3)
                        radius: height / 2
                        visible: tile.hasBar
                        color: tile.chosen ? Theme.accent : Theme.tint(Theme.text, 0.35)
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.px(3)

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.name
                            color: tile.chosen ? Theme.accent : Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeLabel
                            font.bold: true
                            font.letterSpacing: 0.6
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: tile.height > Theme.px(56)
                            text: tile.d.w + " × " + tile.d.h
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeSmall
                            font.features: Theme.tabular
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: tile.height > Theme.px(72)
                            text: Math.round(tile.d.hz) + " Hz" + (tile.d.scale !== 1 ? "  ·  " + Number(tile.d.scale.toFixed(2)) + "×" : "")
                            color: Theme.textFaint
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                            font.features: Theme.tabular
                        }

                    }

                    MouseArea {
                        id: mouse

                        property real pressX: 0
                        property real pressY: 0
                        property real startX: 0
                        property real startY: 0

                        anchors.fill: parent
                        hoverEnabled: true
                        // The page scrolls (a Flickable): without this it took every vertical drag for
                        // itself, the page moved instead of the monitor and the drop never came
                        preventStealing: true
                        cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        enabled: !DisplayState.confirming
                        onCanceled: {
                            tile.dragging = false;
                            tile.landing = null;
                            canvas.frozen = null;
                        }
                        onPressed: (e) => {
                            page.selected = tile.name;
                            const p = mapToItem(canvas, e.x, e.y);
                            pressX = p.x;
                            pressY = p.y;
                            startX = tile.x;
                            startY = tile.y;
                        }
                        onPositionChanged: (e) => {
                            if (!pressed)
                                return ;

                            const p = mapToItem(canvas, e.x, e.y);
                            if (!tile.dragging && Math.hypot(p.x - pressX, p.y - pressY) < 4)
                                return ;

                            if (!tile.dragging) {
                                canvas.frozen = canvas.map;
                                tile.dragging = true;
                            }
                            tile.dragX = startX + p.x - pressX;
                            tile.dragY = startY + p.y - pressY;
                            const m = canvas.map;
                            tile.landing = page.snapped(tile.name, (tile.dragX - m.ox) / m.k, (tile.dragY - m.oy) / m.k);
                        }
                        onReleased: {
                            if (!tile.dragging)
                                return ;

                            const to = tile.landing;
                            tile.dragging = false;
                            tile.landing = null;
                            if (to)
                                DisplayState.edit(tile.name, {
                                "x": to.x,
                                "y": to.y
                            });

                            canvas.frozen = null;
                        }
                    }

                    Behavior on x {
                        enabled: !tile.dragging

                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on y {
                        enabled: !tile.dragging

                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

        }

        // Monitors that are turned off: small chips below the plane; a click selects one
        Flow {
            x: Theme.px(16)
            width: parent.width - Theme.px(32)
            spacing: Theme.px(6)
            bottomPadding: visible ? Theme.px(14) : 0
            visible: page.monitors.some((m) => {
                return DisplayState.draft[m.name] && !DisplayState.draft[m.name].enabled;
            })

            Text {
                height: Theme.px(26)
                verticalAlignment: Text.AlignVCenter
                rightPadding: Theme.px(6)
                text: "OFF"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeMicro
                font.bold: true
                font.letterSpacing: Theme.microSpacing
            }

            Repeater {
                model: page.monitors.filter((m) => {
                    return DisplayState.draft[m.name] && !DisplayState.draft[m.name].enabled;
                })

                delegate: Rectangle {
                    id: offChip

                    required property var modelData
                    readonly property bool chosen: page.cur && page.cur.name === modelData.name

                    width: offLabel.implicitWidth + Theme.px(22)
                    height: Theme.px(26)
                    radius: height / 2
                    color: chosen ? Theme.tint(Theme.accent, 0.18) : Theme.tint(Theme.text, offMouse.containsMouse ? 0.1 : 0.05)
                    border.width: 1
                    border.color: chosen ? Theme.tint(Theme.accent, 0.5) : "transparent"

                    Text {
                        id: offLabel

                        anchors.centerIn: parent
                        text: offChip.modelData.name
                        color: offChip.chosen ? Theme.accent : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                    MouseArea {
                        id: offMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.selected = offChip.modelData.name
                    }

                }

            }

        }

    }

    // ---------- The selected monitor ----------
    IosGroup {
        width: page.width
        visible: page.cur !== null
        title: page.cur ? page.cur.name + "  ·  " + page.cur.model : ""

        Line {
            label: "On"
            hint: page.enabledCount <= 1 && page.curDraft && page.curDraft.enabled ? "The last monitor that is on stays on." : ""

            IosSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: !!page.curDraft && page.curDraft.enabled
                opacity: page.enabledCount <= 1 && checked ? 0.4 : 1
                onToggled: {
                    if (page.enabledCount <= 1 && checked)
                        return ;

                    const turnOn = !checked;
                    const patch = {
                        "enabled": turnOn
                    };
                    // A monitor that comes back is placed beside the others
                    if (turnOn) {
                        const at = page.snapped(page.cur.name, page.curDraft.x, page.curDraft.y);
                        patch.x = at.x;
                        patch.y = at.y;
                    }
                    DisplayState.edit(page.cur.name, patch);
                }
            }

        }

        Line {
            label: "Resolution"
            wide: true
            dimmed: !page.curDraft || !page.curDraft.enabled

            SettingChips {
                width: parent.width
                options: page.cur ? page.resolutions(page.cur) : []
                value: page.curDraft ? page.curDraft.w + "x" + page.curDraft.h : ""
                onPicked: (v) => {
                    const r = page.resolutions(page.cur).find((o) => {
                        return o.value === v;
                    });
                    const rs = page.rates(page.cur, r.w, r.h);
                    // Keep the refresh rate if the new resolution has it, else its fastest
                    const keepHz = rs.find((o) => {
                        return Math.abs(o.value - page.curDraft.hz) < 0.5;
                    });
                    DisplayState.edit(page.cur.name, {
                        "w": r.w,
                        "h": r.h,
                        "hz": keepHz ? keepHz.value : rs[0].value
                    });
                }
            }

        }

        Line {
            label: "Refresh rate"
            wide: true
            dimmed: !page.curDraft || !page.curDraft.enabled

            SettingChips {
                width: parent.width
                options: page.cur && page.curDraft ? page.rates(page.cur, page.curDraft.w, page.curDraft.h) : []
                value: page.curDraft ? page.curDraft.hz : 0
                onPicked: (v) => {
                    return DisplayState.edit(page.cur.name, {
                        "hz": v
                    });
                }
            }

        }

        Line {
            label: "Scale"
            hint: "Larger text and controls; 1 = every pixel as it is."
            dimmed: !page.curDraft || !page.curDraft.enabled

            SettingStepper {
                anchors.verticalCenter: parent.verticalCenter
                value: page.curDraft ? page.curDraft.scale : 1
                min: 0.5
                max: 3
                step: 0.25
                decimals: 2
                unit: "×"
                onPicked: (v) => {
                    return DisplayState.edit(page.cur.name, {
                        "scale": v
                    });
                }
            }

        }

        Line {
            label: "Rotation"
            last: true
            dimmed: !page.curDraft || !page.curDraft.enabled

            IosSegmented {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.px(240)
                items: [{
                    "text": "0°"
                }, {
                    "text": "90°"
                }, {
                    "text": "180°"
                }, {
                    "text": "270°"
                }]
                currentIndex: page.curDraft ? page.curDraft.transform % 4 : 0
                onActivated: (index) => {
                    return DisplayState.edit(page.cur.name, {
                        "transform": index
                    });
                }
            }

        }

    }

    // ---------- Apply / keep ----------
    Item {
        id: bar

        readonly property bool shown: DisplayState.dirty || DisplayState.confirming

        width: page.width
        height: shown ? Theme.px(60) : 0
        opacity: shown ? 1 : 0
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusGroup
            color: DisplayState.confirming ? Theme.tint(Theme.accent, 0.12) : Theme.groupFill
            border.width: 1
            border.color: DisplayState.confirming ? Theme.tint(Theme.accent, 0.4) : Theme.separator

            Behavior on color {
                ColorAnimation {
                    duration: 220
                }

            }

        }

        // The time left, as a line that runs out along the bottom
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            x: Theme.px(14)
            width: (parent.width - Theme.px(28)) * DisplayState.confirmLeft / 15
            height: 2
            radius: 1
            visible: DisplayState.confirming
            color: Theme.accent

            Behavior on width {
                NumberAnimation {
                    duration: 1000
                }

            }

        }

        CrossText {
            x: Theme.px(18)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - buttons.width - Theme.px(40)
            text: DisplayState.confirming ? "Keep these settings? Going back in " + DisplayState.confirmLeft + " s" : "Changes are not applied yet"
            color: Theme.text
            font.pixelSize: Theme.sizeLabel
        }

        Row {
            id: buttons

            anchors.right: parent.right
            anchors.rightMargin: Theme.px(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(8)

            IosButton {
                width: Theme.px(104)
                height: Theme.px(36)
                text: DisplayState.confirming ? "Go back" : "Discard"
                kind: "tinted"
                onClicked: DisplayState.confirming ? DisplayState.revert() : DisplayState.resetDraft()
            }

            IosButton {
                width: Theme.px(104)
                height: Theme.px(36)
                text: DisplayState.confirming ? "Keep" : "Apply"
                kind: "filled"
                onClicked: DisplayState.confirming ? DisplayState.keep() : DisplayState.apply()
            }

        }

        Behavior on height {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }

        }

    }

    // A row of the details: the name on the left (and a hint below it), the control on the right, or
    // below the name for wide controls
    component Line: Item {
        id: line

        property string label: ""
        property string hint: ""
        property bool wide: false
        property bool last: false
        property bool dimmed: false
        default property alias control: slot.data

        width: parent ? parent.width : 0
        height: wide ? Theme.px(44) + slot.childrenRect.height + Theme.px(14) : Math.max(Theme.px(54), names.implicitHeight + Theme.px(24))
        opacity: dimmed ? 0.4 : 1
        enabled: !dimmed && !DisplayState.confirming

        Column {
            id: names

            x: Theme.px(16)
            y: line.wide ? Theme.px(14) : (line.height - implicitHeight) / 2
            width: line.wide ? line.width - Theme.px(32) : line.width - Theme.px(32) - slot.width
            spacing: Theme.px(2)

            Text {
                text: line.label
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLead
            }

            Text {
                width: parent.width
                visible: line.hint !== ""
                text: line.hint
                wrapMode: Text.WordWrap
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
            }

        }

        Item {
            id: slot

            x: line.wide ? Theme.px(16) : line.width - width - Theme.px(16)
            y: line.wide ? Theme.px(44) : 0
            width: line.wide ? line.width - Theme.px(32) : childrenRect.width
            height: line.wide ? childrenRect.height : line.height
        }

        Rectangle {
            x: Theme.px(16)
            anchors.bottom: parent.bottom
            width: parent.width - Theme.px(16)
            height: 1
            visible: !line.last
            color: Theme.separator
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }

        }

    }

}
