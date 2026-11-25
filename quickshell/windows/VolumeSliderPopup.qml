import "../services"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Performance principle: the window has a FIXED size (no layer shell resize
// per frame). Only panelBody is visible/clickable (mask). All animations run
// inside the window. The stream list is a ListModel that is synced
// in place -> no newly created delegates, no icon flicker.
PanelWindow {
    id: popup

    readonly property real panelWidth: 440
    // Room for the shadow left/right in the (fixed) window; on top windowHeight gives enough
    readonly property real shadowPad: 32
    readonly property real baseHeight: 60
    readonly property real cornerR: 18
    readonly property real sideMargin: 32
    readonly property real rowHeight: 56
    readonly property real headerHeight: 34
    readonly property real mixerPadding: 10
    readonly property real emptyHeight: 64
    readonly property int streamsMaxVisible: 5
    readonly property int streamCount: streamModel.count
    readonly property real listTarget: streamCount === 0 ? emptyHeight : Math.min(streamCount, streamsMaxVisible) * rowHeight
    readonly property real windowHeight: baseHeight + headerHeight + streamsMaxVisible * rowHeight + mixerPadding + 32
    // The window is created anew on every opening (layer surface, configure with Hyprland, scene graph,
    // measured ~15 ms). The slide only starts after the first shown frame, otherwise its start is missing.
    property bool surfaceReady: false
    property real shown: (VolumeSliderState.open && surfaceReady) ? 1 : 0
    onVisibleChanged: {
        if (!visible)
            surfaceReady = false;

    }
    property real expandT: VolumeSliderState.expanded ? 1 : 0
    property real listHeight: listTarget
    readonly property real mixerContentHeight: headerHeight + listHeight + mixerPadding
    readonly property real mixerHeight: Math.max(0, expandT * mixerContentHeight)
    readonly property real panelHeight: baseHeight + mixerHeight

    // Keeps the ListModel in sync in place with VolumeSliderState.streams.
    // Grouped: one entry per app, `skey` as a stable ID.
    function syncStreams() {
        const arr = VolumeSliderState.streams;
        // 1) Remove what is no longer there
        for (let i = streamModel.count - 1; i >= 0; i--) {
            const sk = streamModel.get(i).skey;
            let keep = false;
            for (let k = 0; k < arr.length; k++) {
                if (arr[k].key === sk) {
                    keep = true;
                    break;
                }
            }
            if (!keep)
                streamModel.remove(i);

        }
        // 2) Insert/update in order
        for (let i = 0; i < arr.length; i++) {
            const s = arr[i];
            let at = -1;
            for (let j = i; j < streamModel.count; j++) {
                if (streamModel.get(j).skey === s.key) {
                    at = j;
                    break;
                }
            }
            if (at === -1) {
                streamModel.insert(i, {
                    "skey": s.key,
                    "name": s.name,
                    "subtitle": s.subtitle,
                    "icon": String(s.icon || ""),
                    "volume": s.volume,
                    "muted": s.muted
                });
            } else {
                if (at !== i)
                    streamModel.move(at, i, 1);

                const m = streamModel.get(i);
                if (m.name !== s.name)
                    streamModel.setProperty(i, "name", s.name);

                if (m.subtitle !== s.subtitle)
                    streamModel.setProperty(i, "subtitle", s.subtitle);

                // Always as a string (see VolumeSliderState.resolveIcon)
                const icon = String(s.icon || "");
                if (m.icon !== icon)
                    streamModel.setProperty(i, "icon", icon);

                if (Math.abs(m.volume - s.volume) > 0.001)
                    streamModel.setProperty(i, "volume", s.volume);

                if (m.muted !== s.muted)
                    streamModel.setProperty(i, "muted", s.muted);

            }
        }
    }

    Component.onCompleted: syncStreams()
    WlrLayershell.namespace: "quickshell:volume-slider"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    visible: VolumeSliderState.open || shown > 0
    color: "transparent"
    implicitWidth: panelWidth + 2 * shadowPad
    implicitHeight: windowHeight
    anchors.bottom: true
    anchors.left: true

    margins {
        bottom: 0
        left: (screen.width - panelWidth) / 2 - popup.shadowPad
    }

    ListModel {
        id: streamModel
    }

    Connections {
        function onFrameSwapped() {
            popup.surfaceReady = true;
        }

        target: panelBody.Window.window
        enabled: popup.visible && !popup.surfaceReady
    }

    // Fallback in case no frameSwapped comes: better open late than not at all
    Timer {
        interval: 200
        running: popup.visible && !popup.surfaceReady
        onTriggered: popup.surfaceReady = true
    }

    Connections {
        function onStreamsChanged() {
            popup.syncStreams();
        }

        target: VolumeSliderState
    }

    Item {
        id: panelBody

        width: popup.panelWidth
        height: popup.panelHeight
        anchors.bottom: parent.bottom
        // Only moved, not faded: slides out of the picture at the bottom by its whole own height
        // (the window edge clips it). The Hyprland layer animation is off for this (hypr/modules/windows.lua).
        anchors.bottomMargin: -(1 - popup.shown) * (popup.panelHeight + 2)
        anchors.horizontalCenter: parent.horizontalCenter

        // ==================== Shadow ====================
        // As under the dropdown (DropdownHost): a RectangularShadow (one shader, no intermediate texture) under
        // the body of the panel, without the bulges at the bottom left/right. Extended down over the
        // screen edge, so no round shadow corners are visible there. Slides with the
        // panel and fades out with shown, otherwise a shimmer would stay at the edge when closing.
        RectangularShadow {
            x: popup.cornerR
            y: 0
            width: parent.width - 2 * popup.cornerR
            height: parent.height + popup.cornerR
            radius: popup.cornerR
            offset: Qt.vector2d(0, -2)
            blur: 19
            color: Qt.rgba(0, 0, 0, 0.5)
            opacity: popup.shown
        }

        // ==================== Panel-Shape ====================
        Shape {
            id: bgShape

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: shapePath

                fillColor: WalColors.withAlpha(WalColors.color0, 0.97)
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0
                startY: bgShape.height

                PathArc {
                    x: popup.cornerR
                    y: bgShape.height - popup.cornerR
                    radiusX: popup.cornerR
                    radiusY: popup.cornerR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: popup.cornerR
                    y: popup.cornerR
                }

                PathArc {
                    x: 2 * popup.cornerR
                    y: 0
                    radiusX: popup.cornerR
                    radiusY: popup.cornerR
                    direction: PathArc.Clockwise
                }

                PathLine {
                    x: bgShape.width - 2 * popup.cornerR
                    y: 0
                }

                PathArc {
                    x: bgShape.width - popup.cornerR
                    y: popup.cornerR
                    radiusX: popup.cornerR
                    radiusY: popup.cornerR
                    direction: PathArc.Clockwise
                }

                PathLine {
                    x: bgShape.width - popup.cornerR
                    y: bgShape.height - popup.cornerR
                }

                PathArc {
                    x: bgShape.width
                    y: bgShape.height
                    radiusX: popup.cornerR
                    radiusY: popup.cornerR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: 0
                    y: bgShape.height
                }

            }

            Connections {
                function onColorsUpdated() {
                    // Without an intermediate step "transparent": it was visible for one frame (flicker)
                    redrawTimer.start();
                }

                target: WalColors
            }

            Timer {
                id: redrawTimer

                interval: 10
                onTriggered: shapePath.fillColor = Qt.binding(() => {
                    return WalColors.withAlpha(WalColors.color0, 0.97);
                })
            }

        }

        // ==================== Content ====================
        Column {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: popup.sideMargin
            anchors.rightMargin: popup.sideMargin
            anchors.bottomMargin: 12
            spacing: 0

            // ---------- Mixer (only when expanded) ----------
            Item {
                id: mixer

                width: parent.width
                height: popup.mixerHeight
                clip: true
                visible: height > 0.5

                Item {
                    id: mixerContent

                    width: parent.width
                    height: popup.mixerContentHeight
                    anchors.bottom: parent.bottom
                    opacity: Math.max(0, Math.min(1, (popup.expandT - 0.2) / 0.8))

                    Item {
                        id: mixerHeader

                        width: parent.width
                        height: popup.headerHeight

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 3
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4
                                height: 12
                                radius: 2
                                color: WalColors.color4
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "MIXER"
                                color: WalColors.withAlpha(WalColors.color7, 0.5)
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeSmall
                                font.letterSpacing: 1.6
                                font.bold: true
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: countText.implicitWidth + 12
                                height: 16
                                radius: height / 2
                                color: WalColors.withAlpha(WalColors.color4, 0.16)

                                Text {
                                    id: countText

                                    anchors.centerIn: parent
                                    text: popup.streamCount
                                    color: WalColors.color4
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.sizeSmall
                                    font.features: Theme.tabular
                                    font.bold: true
                                }

                            }

                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 3
                            text: "scroll = ±5%"
                            color: WalColors.withAlpha(WalColors.color7, 0.22)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                        }

                    }

                    ListView {
                        id: streamList

                        anchors.top: mixerHeader.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: popup.listHeight
                        clip: true
                        interactive: contentHeight > height + 1
                        boundsBehavior: Flickable.StopAtBounds
                        model: streamModel

                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation {
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration: 260
                                    easing.type: Easing.OutCubic
                                }

                                NumberAnimation {
                                    property: "scale"
                                    from: 0.9
                                    to: 1
                                    duration: 340
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.1
                                }

                            }

                        }

                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation {
                                    property: "opacity"
                                    to: 0
                                    duration: 180
                                    easing.type: Easing.InCubic
                                }

                                NumberAnimation {
                                    property: "scale"
                                    to: 0.9
                                    duration: 180
                                    easing.type: Easing.InCubic
                                }

                            }

                        }

                        displaced: Transition {
                            NumberAnimation {
                                property: "y"
                                duration: 260
                                easing.type: Easing.OutCubic
                            }

                        }

                        delegate: Item {
                            id: row

                            required property int index
                            required property string skey
                            required property string name
                            required property string subtitle
                            required property string icon
                            required property real volume
                            required property bool muted
                            readonly property int barCount: 30
                            property real localV: volume
                            readonly property real shownV: sliderMouse.pressed ? localV : volume
                            readonly property bool hot: cardHover.hovered || sliderMouse.pressed
                            readonly property color accent: muted ? WalColors.color1 : WalColors.color4

                            width: ListView.view ? ListView.view.width : 0
                            height: popup.rowHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 2
                                anchors.bottomMargin: 2
                                radius: 18
                                color: WalColors.withAlpha(WalColors.color7, row.hot ? 0.055 : 0)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                            }

                            HoverHandler {
                                id: cardHover
                            }

                            // ---- Ring-Icon ----
                            Item {
                                id: ring

                                readonly property real size: 44
                                readonly property real thick: 3
                                readonly property real r: size / 2 - thick / 2
                                readonly property real tipRad: (-90 + 360 * row.shownV) * Math.PI / 180

                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: size
                                height: size
                                scale: ringMouse.pressed ? 0.94 : (ringMouse.containsMouse ? 1.06 : 1)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: ring.thick
                                    border.color: WalColors.withAlpha(WalColors.color7, 0.08)
                                }

                                Shape {
                                    anchors.fill: parent
                                    antialiasing: true
                                    layer.enabled: true
                                    layer.samples: 4

                                    ShapePath {
                                        strokeColor: row.muted ? WalColors.withAlpha(WalColors.color1, 0.45) : row.accent
                                        strokeWidth: ring.thick
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap

                                        PathAngleArc {
                                            centerX: ring.size / 2
                                            centerY: ring.size / 2
                                            radiusX: ring.r
                                            radiusY: ring.r
                                            startAngle: -90
                                            sweepAngle: Math.max(0.001, 360 * row.shownV)
                                        }

                                    }

                                }

                                Rectangle {
                                    visible: row.shownV > 0.02 && row.shownV < 0.995 && !row.muted
                                    width: 7
                                    height: 7
                                    radius: height / 2
                                    color: row.accent
                                    border.width: 1.5
                                    border.color: WalColors.withAlpha(WalColors.color0, 0.9)
                                    x: ring.size / 2 + ring.r * Math.cos(ring.tipRad) - width / 2
                                    y: ring.size / 2 + ring.r * Math.sin(ring.tipRad) - height / 2
                                }

                                Rectangle {
                                    id: tile

                                    anchors.centerIn: parent
                                    width: ring.size - 14
                                    height: width
                                    radius: width / 2
                                    color: WalColors.withAlpha(row.accent, 0.12)
                                    opacity: row.muted ? 0.45 : 1

                                    Image {
                                        id: appIcon

                                        anchors.centerIn: parent
                                        width: 20
                                        height: 20
                                        source: row.icon
                                        sourceSize: Qt.size(64, 64)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        // Synchronous: the icons are small (64 px) and mostly come from the cache. Asynchronously
                                        // the letter stood there for one frame first and the icon popped up later
                                        asynchronous: false
                                        visible: status === Image.Ready
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: appIcon.status !== Image.Ready
                                        text: row.name.length > 0 ? row.name.charAt(0).toUpperCase() : "♪"
                                        color: row.accent
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.sizeLarge
                                        font.bold: true
                                    }

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 200
                                        }

                                    }

                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: -3
                                    anchors.bottomMargin: -3
                                    width: 18
                                    height: 18
                                    radius: height / 2
                                    color: row.muted ? WalColors.color1 : WalColors.color0
                                    border.width: 1
                                    border.color: row.muted ? WalColors.color1 : WalColors.withAlpha(WalColors.color7, 0.25)
                                    opacity: (row.muted || ringMouse.containsMouse) ? 1 : 0
                                    scale: (row.muted || ringMouse.containsMouse) ? 1 : 0.6
                                    visible: opacity > 0.01

                                    Text {
                                        anchors.centerIn: parent
                                        text: row.muted ? "󰖁" : (row.shownV < 0.5 ? "󰕿" : "󰕾")
                                        color: row.muted ? WalColors.color0 : WalColors.color7
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                    }

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 160
                                        }

                                    }

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 220
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 1.5
                                        }

                                    }

                                }

                                MouseArea {
                                    id: ringMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // Group key instead of a single stream ID
                                        VolumeSliderState.toggleStreamMute(row.skey);
                                        VolumeSliderState.restartAutoClose();
                                    }
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.3
                                    }

                                }

                            }

                            // ---- Name + Equalizer-Slider ----
                            Item {
                                id: info

                                anchors.left: ring.right
                                anchors.leftMargin: 14
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                height: 38
                                opacity: row.muted ? 0.55 : 1

                                Item {
                                    id: titleRow

                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 16

                                    Text {
                                        id: pctText

                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Math.round(row.shownV * 100) + "%"
                                        color: row.accent
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.sizeBody
                                        font.features: Theme.tabular
                                        font.bold: true
                                    }

                                    Text {
                                        id: nameText

                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, titleRow.width * 0.55)
                                        text: row.name
                                        color: WalColors.color7
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.sizeLabel
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        anchors.left: nameText.right
                                        anchors.leftMargin: 8
                                        anchors.right: pctText.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: text !== ""
                                        text: row.subtitle
                                        color: WalColors.withAlpha(WalColors.color7, 0.35)
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.sizeMicro
                                        elide: Text.ElideRight
                                    }

                                }

                                Item {
                                    id: sl

                                    readonly property real gap: 3
                                    readonly property real barW: Math.max(1, (width - gap * (row.barCount - 1)) / row.barCount)
                                    property int hoverIdx: -1

                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 18

                                    Repeater {
                                        model: row.barCount

                                        delegate: Rectangle {
                                            id: bar

                                            required property int index
                                            readonly property real t: index / (row.barCount - 1)
                                            readonly property bool filled: (index + 0.5) / row.barCount <= row.shownV + 0.0001
                                            readonly property bool edge: filled && (index + 1.5) / row.barCount > row.shownV
                                            readonly property bool preview: !filled && sl.hoverIdx >= index

                                            anchors.bottom: parent.bottom
                                            x: index * (sl.barW + sl.gap)
                                            width: sl.barW
                                            height: 5 + 11 * t + (edge ? 2 : 0)
                                            radius: width / 2
                                            color: edge ? WalColors.color7 : row.accent
                                            opacity: filled ? (edge ? 1 : 0.5 + 0.5 * t) : (preview ? 0.3 : 0.12)
                                        }

                                    }

                                    MouseArea {
                                        id: sliderMouse

                                        function update(me) {
                                            const v = Math.max(0, Math.min(me.x / width, 1));
                                            row.localV = v;
                                            // Group key instead of a stream ID
                                            VolumeSliderState.setStreamVolume(row.skey, v);
                                            VolumeSliderState.restartAutoClose();
                                        }

                                        anchors.fill: parent
                                        anchors.topMargin: -6
                                        anchors.bottomMargin: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: (mouse) => {
                                            // Group key for the drag protection
                                            VolumeSliderState.draggingGroupKey = row.skey;
                                            update(mouse);
                                        }
                                        onPositionChanged: (mouse) => {
                                            sl.hoverIdx = Math.max(0, Math.min(row.barCount - 1, Math.floor(mouse.x / width * row.barCount)));
                                            if (pressed)
                                                update(mouse);

                                        }
                                        onExited: sl.hoverIdx = -1
                                        onReleased: {
                                            if (VolumeSliderState.draggingGroupKey === row.skey)
                                                VolumeSliderState.draggingGroupKey = "";

                                        }
                                        onCanceled: {
                                            if (VolumeSliderState.draggingGroupKey === row.skey)
                                                VolumeSliderState.draggingGroupKey = "";

                                        }
                                        onWheel: (wheel) => {
                                            const d = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                                            VolumeSliderState.setStreamVolume(row.skey, Math.max(0, Math.min(1, row.volume + d)));
                                            VolumeSliderState.restartAutoClose();
                                        }
                                    }

                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 200
                                    }

                                }

                            }

                        }

                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: mixerHeader.bottom
                        anchors.topMargin: 8
                        spacing: 6
                        opacity: popup.streamCount === 0 ? 1 : 0
                        visible: opacity > 0.01

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰝟"
                            color: WalColors.withAlpha(WalColors.color7, 0.18)
                            font.family: Theme.font
                            font.pixelSize: 24
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Nothing is playing"
                            color: WalColors.withAlpha(WalColors.color7, 0.35)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeBody
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                            }

                        }

                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        height: 1
                        color: WalColors.withAlpha(WalColors.color7, 0.08)
                    }

                }

            }

            // ---------- Top-Row (Orb + Slider + %) ----------
            Row {
                id: topRow

                width: parent.width
                height: popup.baseHeight - 24
                spacing: 16

                VolumeOrb {
                    id: audioOrb

                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: VolumeSliderState.toggleSystemMute()
                    onRightClicked: VolumeSliderState.toggleExpanded()
                }

                Item {
                    id: sliderArea

                    readonly property real v: Math.max(0, Math.min(VolumeSliderState.systemVolume, 1))
                    readonly property bool dragging: volMouse.pressed
                    readonly property bool hot: dragging || volMouse.containsMouse

                    anchors.verticalCenter: parent.verticalCenter
                    width: topRow.width - audioOrb.width - percentLabel.width - 2 * topRow.spacing
                    height: 34

                    Rectangle {
                        id: track

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 10
                        radius: height / 2
                        color: WalColors.withAlpha(WalColors.color7, 0.1)

                        Repeater {
                            model: 4

                            delegate: Rectangle {
                                readonly property real pos: (index + 1) / 5

                                x: track.width * pos - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1.5
                                height: 1.5
                                radius: 1
                                color: WalColors.withAlpha(WalColors.color7, 0.3)
                            }

                        }

                    }

                    Rectangle {
                        id: filled

                        anchors.left: track.left
                        anchors.verticalCenter: track.verticalCenter
                        width: track.width * sliderArea.v
                        height: track.height
                        radius: track.radius

                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: WalColors.withAlpha(WalColors.color4, 0.7)
                            }

                            GradientStop {
                                position: 1
                                color: WalColors.color4
                            }

                        }

                    }

                    Rectangle {
                        anchors.verticalCenter: track.verticalCenter
                        x: track.width * sliderArea.v - width / 2
                        width: 26
                        height: 26
                        radius: width / 2
                        color: WalColors.color4
                        opacity: sliderArea.hot ? 0.3 : 0.1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 250
                            }

                        }

                        Behavior on x {
                            NumberAnimation {
                                duration: 80
                                easing.type: Easing.OutQuad
                            }

                        }

                    }

                    Rectangle {
                        id: handle

                        anchors.verticalCenter: parent.verticalCenter
                        x: track.width * sliderArea.v - width / 2
                        width: 22
                        height: 22
                        radius: width / 2
                        color: WalColors.color7
                        border.width: 2
                        border.color: WalColors.withAlpha(WalColors.color0, 0.9)
                        scale: sliderArea.dragging ? 1.15 : (volMouse.containsMouse ? 1.08 : 1)

                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: height / 2
                            color: WalColors.color4
                            opacity: 0.85
                        }

                        Behavior on scale {
                            SpringAnimation {
                                spring: 5.5
                                damping: 0.4
                                epsilon: 0.1
                            }

                        }

                        Behavior on x {
                            NumberAnimation {
                                duration: 80
                                easing.type: Easing.OutQuad
                            }

                        }

                    }

                    Text {
                        anchors.centerIn: handle
                        text: Math.round(sliderArea.v * 100)
                        color: WalColors.color0
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                        font.features: Theme.tabular
                        font.bold: true
                        opacity: sliderArea.dragging ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.anim.durations.fast
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    MouseArea {
                        id: volMouse

                        function updateVol(me) {
                            VolumeSliderState.setSystemVolume(Math.max(0, Math.min(me.x / width, 1)));
                            VolumeSliderState.restartAutoClose();
                        }

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressedChanged: VolumeSliderState.draggingSystem = pressed
                        onPositionChanged: (mouse) => {
                            if (pressed)
                                updateVol(mouse);

                        }
                        onPressed: (mouse) => {
                            updateVol(mouse);
                        }
                    }

                }

                Item {
                    id: percentLabel

                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    height: 26

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -4
                        text: Math.round(sliderArea.v * 100)
                        color: WalColors.color4
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeTitle
                        font.features: Theme.tabular
                        font.bold: true
                    }

                    Text {
                        anchors.left: parent.horizontalCenter
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 4
                        text: "%"
                        color: WalColors.withAlpha(WalColors.color4, 0.5)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                    }

                }

            }

        }

        Item {
            id: closeStrip

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: popup.cornerR
            anchors.rightMargin: popup.cornerR
            height: 6

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: VolumeSliderState.close()
            }

        }

        HoverHandler {
            id: panelHover

            // Scene coordinates: the popup slides up when opening, the position in the panel changes
            // meanwhile even with a resting mouse
            property point restAt
            property bool resting: false

            onHoveredChanged: {
                resting = false;
                if (!hovered)
                    VolumeSliderState.hovered = false;

            }
            onPointChanged: {
                if (!hovered)
                    return ;

                const p = point.scenePosition;
                if (!resting) {
                    restAt = p;
                    resting = true;
                } else if (Math.hypot(p.x - restAt.x, p.y - restAt.y) > 3) {
                    VolumeSliderState.hovered = true;
                }
            }
        }

        Connections {
            // When closing no leave event comes anymore, so start over
            function onOpenChanged() {
                panelHover.resting = false;
            }

            target: VolumeSliderState
        }

    }

    mask: Region {
        item: panelBody
    }

    // Open and close with the same curve (like the bar, see MainBar barSlide): reacts right away, eases out softly
    Behavior on shown {
        NumberAnimation {
            duration: 360
            easing.type: Easing.OutCubic
        }

    }

    Behavior on expandT {
        NumberAnimation {
            duration: VolumeSliderState.expanded ? 460 : 320
            easing.type: VolumeSliderState.expanded ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 0.9
        }

    }

    Behavior on listHeight {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutCubic
        }

    }

}
