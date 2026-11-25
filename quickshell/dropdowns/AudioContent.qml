import "../services"
import "../common/Format.js" as Fmt
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets

// Audio dropdown: header with the source, cover with a cava ring, title (marquee),
// controls incl. shuffle/repeat and volume.
// Playing time: progress arc on the record's rim (drag = seek, the record turns along),
// times in the free corners below the ring.
Item {
    id: dropdown

    readonly property bool isCurrent: DropdownState.current === "audio"
    property bool heightAnimOn: isCurrent
    readonly property real cornerRadius: 20
    readonly property real menuWidth: 270
    readonly property real innerW: menuWidth - 2 * Theme.padX
    readonly property real coverSize: 120
    // ---- Visualizer (data: CavaService, runs permanently while music plays) ----
    readonly property int cavaBars: CavaService.bars
    readonly property int barCount: cavaBars * 2
    readonly property real barWidth: 3.5
    readonly property real barGap: 3
    readonly property real barMinLen: 4 // resting ring: bars never disappear completely (no "bald spot")
    readonly property real barMaxLen: 36
    // Ring slides in/out only when opening/closing the dropdown (pause leaves the resting ring standing)
    // Starts at 0; the binding only comes after loading (otherwise the start value would not be animated)
    property real vizIn: 0
    // ---- Lower part ----
    readonly property var player: AudioState.activePlayer
    // Average loudness from cava (0..1): lets the play button breathe along
    readonly property real energy: {
        const l = CavaService.levels || [];
        if (!AudioState.isPlaying || l.length === 0)
            return 0;

        let s = 0;
        for (let i = 0; i < l.length; i++) s += l[i]
        return Math.min(1, s / l.length * 1.6);
    }
    // Source: name + symbol of the player
    readonly property string sourceName: {
        if (!player)
            return "";

        const id = (player.identity || "").toLowerCase();
        if (AudioState.isMpd)
            return "Music";

        if (AudioState.siteName !== "")
            return AudioState.siteName;

        return player.identity || "Player";
    }
    readonly property string sourceGlyph: {
        const n = sourceName.toLowerCase();
        if (n === "music")
            return "󰝚";

        if (n.indexOf("spotify") >= 0)
            return "󰓇";

        if (n === "youtube")
            return "󰗃";

        if (n === "twitch")
            return "󰕃";

        if (n.indexOf("firefox") >= 0 || n.indexOf("zen") >= 0)
            return "󰈹";

        if (n.indexOf("chrom") >= 0)
            return "";

        return "󰎆";
    }
    // Fade in when opening: sections one after another
    property real intro: 0
    // Switching between players: cover + title glide out to the side and back in from the other edge
    readonly property real slideDist: 36
    property real slideX: 0
    property real slideFade: 1
    property int slideDir: 1
    property bool switching: false
    // When the dropdown opened: do not glide when opening, simply show the current player
    property double shownAt: Date.now()
    // ---- Playing time on the record's rim ----
    readonly property real rimRadius: coverSize / 2 - 3 // middle of the rim between cover and record
    property bool scrubbing: false // the rim is being dragged
    property bool scrubHover: false // the mouse lies on the rim
    property real scrubFrac: 0 // position under the mouse (0..1)
    // After release/mouse wheel: hold the target position until the player reports it (otherwise the arc jumps back)
    property real holdFrac: -1
    readonly property real playFrac: AudioState.length > 0 ? Math.max(0, Math.min(1, AudioState.position / AudioState.length)) : 0
    readonly property real shownFrac: scrubbing ? scrubFrac : (holdFrac >= 0 ? holdFrac : playFrac)
    // The arc glides between the 250 ms reports; while dragging it follows the mouse directly
    property real arcFrac: shownFrac
    // 0..1: rim highlighted (hover/drag) -> thicker arc, handle + time visible in the cover
    property real scrubK: (scrubbing || scrubHover) && AudioState.canSeek ? 1 : 0
    // Right time: total length or (after a click) remaining time
    property bool showRemaining: false

    function fmtTime(sec) {
        return Fmt.clock(sec);
    }

    function seekToFrac(f) {
        holdFrac = Math.max(0, Math.min(1, f));
        holdTimer.restart();
        AudioState.seekTo(holdFrac * AudioState.length);
    }

    // Arrow clicked: out -> switch the player -> in
    function switchPlayer(dir) {
        if (AudioState.players.length < 2)
            return ;

        slideDir = dir;
        switching = true;
        slideInAnim.stop();
        slideAnim.restart();
    }

    function stagger(i) {
        return Math.max(0, Math.min(1, intro * 4 - i * 0.45));
    }

    // The player changed by itself (another one starts playing): only glide in.
    // Not right after opening (there the player reports itself once as "changed" while building)
    onPlayerChanged: {
        if (!switching && isCurrent && !slideAnim.running && Date.now() - shownAt > 600)
            slideInAnim.restart();

    }
    onIsCurrentChanged: {
        if (!isCurrent)
            return ;

        shownAt = Date.now();
        holdFrac = -1;
        slideAnim.stop();
        slideInAnim.stop();
        switching = false;
        slideX = 0;
        slideFade = 1;
    }
    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight
    Component.onCompleted: {
        vizIn = Qt.binding(() => {
            return isCurrent ? 1 : 0;
        });
        introAnim.start();
    }

    Timer {
        id: holdTimer

        interval: 700
        onTriggered: dropdown.holdFrac = -1
    }

    Behavior on arcFrac {
        enabled: !dropdown.scrubbing

        NumberAnimation {
            duration: 250
        }

    }

    Behavior on scrubK {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }

    }

    NumberAnimation {
        id: introAnim

        target: dropdown
        property: "intro"
        from: 0
        to: 1
        duration: 800
        easing.type: Easing.OutCubic
    }

    Column {
        id: content

        width: dropdown.innerW
        spacing: Theme.gap
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        // ---------- Header: source with a mini equalizer ----------
        DropdownHeader {
            glyph: "󰝚"
            title: "Now playing"

            Chip {
                visible: AudioState.hasPlayer
                glyph: dropdown.sourceGlyph
                text: dropdown.sourceName

                // Three bars that dance with the music (paused = flat)
                Row {
                    height: 10
                    spacing: 1.5

                    Repeater {
                        model: 3

                        delegate: Rectangle {
                            required property int index
                            readonly property real lvl: AudioState.isPlaying ? (CavaService.levels[[1, 5, 9][index] % Math.max(1, CavaService.bars)] ?? 0) : 0

                            anchors.bottom: parent.bottom
                            width: 2
                            height: 3 + 7 * lvl
                            radius: 1
                            color: Theme.accent
                        }

                    }

                }

            }

        }

        // Cover with ring; if several players play, arrows left/right to switch
        Item {
            width: dropdown.innerW
            height: coverArea.outerSize
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
                id: coverArea

                readonly property real outerSize: coverSize + 2 * (dropdown.barGap + dropdown.barMaxLen)

                width: outerSize
                height: outerSize
                anchors.centerIn: parent
                opacity: dropdown.slideFade
                transform: Translate {
                    x: dropdown.slideX
                }

                Item {
                    id: visualizerLayer

                    anchors.fill: parent
                    visible: AudioState.hasPlayer
                    // Without layer + 4x MSAA: the bars smooth their edges themselves (antialiasing), so the ring
                    // did not have to be rendered into an intermediate texture in every cava frame

                    Repeater {
                        model: dropdown.barCount

                        delegate: Item {
                            // Mirrored: right half = bands 0..n, left half mirrored
                            readonly property real level: CavaService.levels[index < dropdown.cavaBars ? index : dropdown.barCount - 1 - index] ?? 0

                            x: coverArea.outerSize / 2
                            y: coverArea.outerSize / 2
                            width: 0
                            height: 0
                            rotation: 180 + (index + 0.5) * 360 / dropdown.barCount

                            Rectangle {
                                anchors.bottom: parent.top
                                anchors.bottomMargin: coverSize / 2 + dropdown.barGap
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: dropdown.barWidth
                                // No animation needed: 60 fps frames, cava + monstercat do the smoothing (CavaService)
                                height: (dropdown.barMinLen + parent.level * (dropdown.barMaxLen - dropdown.barMinLen)) * dropdown.vizIn
                                radius: width / 2
                                antialiasing: true
                                color: Theme.accent
                                opacity: (0.4 + 0.6 * parent.level) * Math.min(1, dropdown.vizIn * 1.5)

                            }

                        }

                    }

                }

                Item {
                    id: artContainer

                    width: coverSize
                    height: coverSize
                    anchors.centerIn: parent

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: WalColors.color0
                    }

                    // Round cover (turns like a record). ClippingRectangle rounds with a shader;
                    // OpacityMask needed two intermediate textures that were created anew on every rotation
                    ClippingRectangle {
                        id: coverMask

                        anchors.centerIn: parent
                        width: coverSize * 0.9
                        height: width
                        radius: width / 2
                        color: "transparent"
                        visible: AudioState.coverSource !== "" && !AudioState.showWebsiteIcon

                        Image {
                            anchors.fill: parent
                            source: AudioState.coverSource
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(200, 200)
                        }

                    }

                    Image {
                        anchors.centerIn: parent
                        width: coverSize * 0.5
                        height: width
                        source: AudioState.showWebsiteIcon ? AudioState.websiteIconSource : ""
                        visible: AudioState.showWebsiteIcon && AudioState.websiteIconSource !== ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        sourceSize: Qt.size(96, 96)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: (AudioState.showWebsiteIcon && AudioState.websiteIconSource === "") || (!AudioState.showWebsiteIcon && AudioState.coverSource === "")
                        text: "󰝚"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 28
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 10
                        height: 10
                        radius: height / 2
                        color: WalColors.color0
                        visible: AudioState.coverSource !== "" && !AudioState.showWebsiteIcon
                    }

                    // While seeking: darken the cover and show the target time big in the middle (does not turn along)
                    Rectangle {
                        anchors.centerIn: parent
                        width: coverSize * 0.9
                        height: width
                        radius: width / 2
                        color: WalColors.withAlpha(WalColors.color0, 0.72)
                        opacity: dropdown.scrubK
                        visible: opacity > 0.01

                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            scale: 0.9 + 0.1 * dropdown.scrubK

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: dropdown.fmtTime(dropdown.scrubFrac * AudioState.length)
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.features: Theme.tabular
                                font.pixelSize: Theme.sizeTitleLarge
                                font.bold: true
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: dropdown.scrubbing ? "RELEASE TO SEEK" : "DRAG TO SEEK"
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeMicro - 2
                                font.bold: true
                                font.letterSpacing: Theme.microSpacing
                            }

                        }

                    }

                    // Progress as an arc on the record's rim, starting on top, clockwise
                    Shape {
                        anchors.fill: parent
                        visible: AudioState.length > 0
                        opacity: dropdown.stagger(1)
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: Theme.tint(Theme.accent, 0.2 + 0.1 * dropdown.scrubK)
                            strokeWidth: 2 + 1.5 * dropdown.scrubK

                            PathAngleArc {
                                centerX: coverSize / 2
                                centerY: coverSize / 2
                                radiusX: dropdown.rimRadius
                                radiusY: dropdown.rimRadius
                                startAngle: 0
                                sweepAngle: 360
                            }

                        }

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: Theme.accent
                            strokeWidth: 3 + 1.5 * dropdown.scrubK
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: coverSize / 2
                                centerY: coverSize / 2
                                radiusX: dropdown.rimRadius
                                radiusY: dropdown.rimRadius
                                startAngle: -90
                                // Never fully 0: otherwise the round cap at the start disappears too
                                sweepAngle: Math.max(0.01, 360 * dropdown.arcFrac)
                            }

                        }

                    }

                    // Position under the mouse (hover only): faint dot on the rim
                    Item {
                        anchors.centerIn: parent
                        rotation: 360 * dropdown.scrubFrac
                        visible: dropdown.scrubHover && !dropdown.scrubbing && AudioState.canSeek

                        Rectangle {
                            x: -width / 2
                            y: -dropdown.rimRadius - height / 2
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.text
                            opacity: 0.55
                        }

                    }

                    // Handle at the end of the arc, grows on hover/drag
                    Item {
                        anchors.centerIn: parent
                        rotation: 360 * dropdown.arcFrac
                        visible: AudioState.length > 0

                        Rectangle {
                            x: -width / 2
                            y: -dropdown.rimRadius - height / 2
                            width: 11
                            height: 11
                            radius: width / 2
                            color: Theme.text
                            border.width: 2
                            border.color: Theme.accent
                            scale: dropdown.scrubK * (dropdown.scrubbing ? 1.2 : 1)

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 160
                                    easing.type: Easing.OutBack
                                }

                            }

                        }

                    }

                    // Seeking: grab the rim and drag in a circle (the record turns along), mouse wheel = 5 s
                    MouseArea {
                        id: scrub

                        readonly property real c: width / 2
                        property real lastAngle: 0

                        function dist(x, y) {
                            return Math.hypot(x - c, y - c);
                        }

                        // Angle in degrees, 0 = top, clockwise
                        function angle(x, y) {
                            const a = Math.atan2(x - c, c - y) * 180 / Math.PI;
                            return a < 0 ? a + 360 : a;
                        }

                        function onRim(x, y) {
                            const d = dist(x, y);
                            return d >= coverSize / 2 - 18 && d <= c;
                        }

                        anchors.centerIn: parent
                        width: coverSize + 16
                        height: width
                        enabled: AudioState.canSeek
                        hoverEnabled: true
                        cursorShape: dropdown.scrubHover || pressed ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEnabledChanged: {
                            dropdown.scrubHover = false;
                            dropdown.scrubbing = false;
                        }
                        onExited: dropdown.scrubHover = false
                        onPressed: (mouse) => {
                            if (!onRim(mouse.x, mouse.y)) {
                                mouse.accepted = false;
                                return ;
                            }
                            lastAngle = angle(mouse.x, mouse.y);
                            dropdown.scrubFrac = lastAngle / 360;
                            dropdown.holdFrac = -1;
                            dropdown.scrubbing = true;
                        }
                        onPositionChanged: (mouse) => {
                            const a = angle(mouse.x, mouse.y);
                            if (!pressed) {
                                dropdown.scrubHover = onRim(mouse.x, mouse.y);
                                if (dropdown.scrubHover)
                                    dropdown.scrubFrac = a / 360;

                                return ;
                            }
                            // Turn the record along (shortest way over the 0 degree seam)
                            const delta = ((a - lastAngle + 540) % 360) - 180;
                            lastAngle = a;
                            coverMask.rotation = (coverMask.rotation + delta + 360) % 360;
                            // Do not jump from end to start over the seam on top: stay at the nearer end
                            let f = a / 360;
                            if (Math.abs(f - dropdown.scrubFrac) > 0.5)
                                f = dropdown.scrubFrac > 0.5 ? 1 : 0;

                            dropdown.scrubFrac = f;
                        }
                        onReleased: (mouse) => {
                            if (!dropdown.scrubbing)
                                return ;

                            dropdown.seekToFrac(dropdown.scrubFrac);
                            dropdown.scrubbing = false;
                            dropdown.scrubHover = onRim(mouse.x, mouse.y);
                        }
                        onCanceled: dropdown.scrubbing = false
                        onWheel: (wheel) => {
                            if (dist(wheel.x, wheel.y) > c) {
                                wheel.accepted = false;
                                return ;
                            }
                            const step = (wheel.angleDelta.y > 0 ? 5 : -5) / AudioState.length;
                            dropdown.seekToFrac(dropdown.shownFrac + step);
                        }
                    }

                }

            }

            SwitchArrow {
                dir: -1
                anchors.left: parent.left
                anchors.leftMargin: -6
                anchors.verticalCenter: parent.verticalCenter
            }

            SwitchArrow {
                dir: 1
                anchors.right: parent.right
                anchors.rightMargin: -6
                anchors.verticalCenter: parent.verticalCenter
            }

            // Playing time in the free corners below the ring: elapsed on the left, length on the right (click: remaining time)
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.bottom: parent.bottom
                visible: AudioState.positionKnown
                opacity: dropdown.stagger(1) * dropdown.slideFade
                text: dropdown.fmtTime(AudioState.length > 0 ? dropdown.shownFrac * AudioState.length : AudioState.position)
                color: dropdown.scrubbing ? Theme.accent : Theme.text
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeBody
                font.bold: true

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.bottom: parent.bottom
                visible: AudioState.length > 0
                opacity: dropdown.stagger(1) * dropdown.slideFade
                text: dropdown.showRemaining ? "-" + dropdown.fmtTime(AudioState.length - dropdown.shownFrac * AudioState.length) : dropdown.fmtTime(AudioState.length)
                color: remainMouse.containsMouse ? Theme.text : Theme.textDim
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeBody

                MouseArea {
                    id: remainMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dropdown.showRemaining = !dropdown.showRemaining
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

        }

        // ---------- Title (marquee if too long) + artist · album ----------
        Column {
            width: dropdown.innerW
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3
            opacity: dropdown.stagger(0) * dropdown.slideFade
            transform: Translate {
                x: dropdown.slideX
                y: (1 - dropdown.stagger(0)) * 8
            }

            Item {
                id: marquee

                readonly property real overflow: Math.max(0, titleText.implicitWidth - width)

                width: parent.width
                // Fixed height from the UI font: titles with characters from a fallback font (Japanese,
                // Korean, emoji) are taller and otherwise shifted everything below and the dropdown
                height: Math.ceil(titleMetrics.height) + 2
                clip: true

                FontMetrics {
                    id: titleMetrics

                    font: titleText.font
                }

                Text {
                    id: titleText

                    x: marquee.overflow > 0 ? 0 : (marquee.width - implicitWidth) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: AudioState.hasPlayer ? (AudioState.title || "Unknown title") : "Nothing playing"
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeTitle
                    font.bold: true
                }

                // Scroll back and forth, with pauses at the ends
                SequentialAnimation {
                    running: marquee.overflow > 0 && dropdown.isCurrent
                    loops: Animation.Infinite

                    PropertyAction {
                        target: titleText
                        property: "x"
                        value: 0
                    }

                    PauseAnimation {
                        duration: 1600
                    }

                    NumberAnimation {
                        target: titleText
                        property: "x"
                        to: -marquee.overflow
                        duration: Math.max(1200, marquee.overflow * 35)
                        easing.type: Easing.InOutSine
                    }

                    PauseAnimation {
                        duration: 1400
                    }

                    NumberAnimation {
                        target: titleText
                        property: "x"
                        to: 0
                        duration: Math.max(1200, marquee.overflow * 35)
                        easing.type: Easing.InOutSine
                    }

                }

            }

            // The row stays even without an artist (same height for every title)
            Text {
                id: artistText

                width: parent.width
                height: Math.ceil(artistMetrics.height)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.StyledText
                text: {
                    const a = AudioState.artist;
                    const al = dropdown.player ? (dropdown.player.trackAlbum || "") : "";
                    const esc = (s) => {
                        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
                    };
                    if (a && al)
                        return esc(a) + "<font color='" + Theme.textFaint + "'>  ·  " + esc(al) + "</font>";

                    return esc(a || al);
                }
                color: Theme.accent
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeBody

                FontMetrics {
                    id: artistMetrics

                    font: artistText.font
                }

            }

        }

        // ---------- Controls: shuffle · back · play · next · repeat ----------
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            opacity: dropdown.stagger(3)
            transform: Translate {
                y: (1 - dropdown.stagger(3)) * 8
            }

            CtrlButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 30
                glyph: dropdown.player && dropdown.player.shuffle ? "󰒝" : "󰒞"
                available: dropdown.player !== null && dropdown.player.shuffleSupported
                active: dropdown.player !== null && dropdown.player.shuffle
                onClicked: dropdown.player.shuffle = !dropdown.player.shuffle
            }

            CtrlButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 36
                glyphSize: 19
                glyph: "󰒮"
                available: dropdown.player !== null && dropdown.player.canGoPrevious
                onClicked: AudioState.previous()
            }

            // Play/pause: filled circle, breathes with the music
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                height: 52

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: width
                    radius: width / 2
                    color: Theme.accent
                    opacity: 0.25
                    scale: 1 + 0.28 * dropdown.energy

                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                        }

                    }

                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.accent
                    scale: playMouse.pressed ? 0.92 : (playMouse.containsMouse ? 1.06 : 1)

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: AudioState.isPlaying ? 0 : 2
                        text: AudioState.isPlaying ? "󰏤" : "󰐊"
                        color: Theme.onAccent
                        font.family: Theme.font
                        font.pixelSize: 24
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.6
                        }

                    }

                }

                MouseArea {
                    id: playMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AudioState.togglePlay()
                }

            }

            CtrlButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 36
                glyphSize: 19
                glyph: "󰒭"
                available: dropdown.player !== null && dropdown.player.canGoNext
                onClicked: AudioState.next()
            }

            // Repeat: off -> playlist -> track
            CtrlButton {
                readonly property int ls: dropdown.player ? dropdown.player.loopState : MprisLoopState.None

                anchors.verticalCenter: parent.verticalCenter
                size: 30
                glyph: ls === MprisLoopState.Track ? "󰑘" : (ls === MprisLoopState.Playlist ? "󰑖" : "󰑗")
                available: dropdown.player !== null && dropdown.player.loopSupported
                active: ls !== MprisLoopState.None
                onClicked: dropdown.player.loopState = ls === MprisLoopState.None ? MprisLoopState.Playlist : (ls === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None)
            }

        }

        // ---------- Volume ----------
        PillSlider {
            readonly property bool muted: value <= 0.01

            width: parent.width
            visible: AudioState.hasPlayer
            opacity: dropdown.stagger(4)
            value: Math.max(0, Math.min(AudioState.volume, 1))
            glyph: muted ? "󰖁" : (value < 0.5 ? "󰕿" : "󰕾")
            // Muted only dimmed instead of red: the crossed-out symbol already shows it
            glyphColor: muted ? Theme.textFaint : Theme.text
            label: "volume"
            onMoved: (v) => {
                return AudioState.setVolume(v);
            }
            onStepped: (d) => {
                return AudioState.setVolume(Math.max(0, Math.min(1, value + d)));
            }
            onIconClicked: AudioState.setVolume(muted ? 0.5 : 0)
        }

    }

    SequentialAnimation {
        id: slideAnim

        ParallelAnimation {
            NumberAnimation {
                target: dropdown
                property: "slideX"
                to: -dropdown.slideDir * dropdown.slideDist
                duration: 140
                easing.type: Easing.InCubic
            }

            NumberAnimation {
                target: dropdown
                property: "slideFade"
                to: 0
                duration: 140
                easing.type: Easing.InCubic
            }

        }

        ScriptAction {
            script: AudioState.cyclePlayer(dropdown.slideDir)
        }

        PropertyAction {
            target: dropdown
            property: "slideX"
            value: dropdown.slideDir * dropdown.slideDist
        }

        ParallelAnimation {
            NumberAnimation {
                target: dropdown
                property: "slideX"
                to: 0
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: dropdown
                property: "slideFade"
                to: 1
                duration: 240
                easing.type: Easing.OutCubic
            }

        }

        ScriptAction {
            script: dropdown.switching = false
        }

    }

    SequentialAnimation {
        id: slideInAnim

        PropertyAction {
            target: dropdown
            property: "slideX"
            value: dropdown.slideDist
        }

        PropertyAction {
            target: dropdown
            property: "slideFade"
            value: 0
        }

        ParallelAnimation {
            NumberAnimation {
                target: dropdown
                property: "slideX"
                to: 0
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: dropdown
                property: "slideFade"
                to: 1
                duration: 240
                easing.type: Easing.OutCubic
            }

        }

    }

    // The cover turns while music plays (45 degrees/s) and stops on pause.
    // FrameAnimation runs at the frame rate; the 16 ms timer before ran beside the frame timing and stuttered slightly.
    FrameAnimation {
        running: AudioState.isPlaying && dropdown.isCurrent && coverMask.visible && !dropdown.scrubbing
        onTriggered: coverMask.rotation = (coverMask.rotation + 45 * frameTime) % 360
    }

    // Opening: grow out softly; closing: back into the cover quickly
    Behavior on vizIn {
        NumberAnimation {
            duration: dropdown.isCurrent ? 520 : 240
            easing.type: dropdown.isCurrent ? Easing.OutCubic : Easing.InCubic
        }

    }

    // Arrow next to the ring to switch the player (only visible if there are several)
    component SwitchArrow: Item {
        id: sa

        property int dir: 1

        width: 26
        height: 48
        visible: AudioState.players.length > 1
        opacity: dropdown.stagger(1)

        Rectangle {
            anchors.fill: parent
            radius: 13
            color: Theme.accent
            opacity: saMouse.containsMouse ? 0.14 : 0
            scale: saMouse.containsMouse ? 1 : 0.75

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutBack
                }

            }

        }

        Text {
            anchors.centerIn: parent
            // On hover move a bit in the arrow direction
            anchors.horizontalCenterOffset: saMouse.containsMouse ? sa.dir * 2 : 0
            text: sa.dir > 0 ? "󰅂" : "󰅁"
            color: saMouse.containsMouse ? Theme.accent : Theme.textDim
            font.family: Theme.font
            font.pixelSize: 20
            scale: saMouse.pressed ? 0.8 : 1

            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutBack
                }

            }

        }

        MouseArea {
            id: saMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dropdown.switchPlayer(sa.dir)
        }

    }

    // Small round control button; available=false -> faint and without click, active -> accent color + dot
    component CtrlButton: Item {
        id: cb

        property real size: 34
        property real glyphSize: 15
        property string glyph: ""
        property bool available: true
        property bool active: false

        signal clicked()

        width: size
        height: size
        opacity: available ? 1 : 0.3

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.accent
            opacity: cbMouse.containsMouse && cb.available ? 0.16 : 0
            scale: cbMouse.containsMouse ? 1 : 0.7

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutBack
                }

            }

        }

        Text {
            anchors.centerIn: parent
            text: cb.glyph
            color: cb.active || (cbMouse.containsMouse && cb.available) ? Theme.accent : Theme.textDim
            font.family: Theme.font
            font.pixelSize: cb.glyphSize
            scale: cbMouse.pressed && cb.available ? 0.85 : 1

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutBack
                }

            }

        }

        // Active dot below the symbol
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            width: 4
            height: 4
            radius: 2
            color: Theme.accent
            scale: cb.active ? 1 : 0

            Behavior on scale {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutBack
                }

            }

        }

        MouseArea {
            id: cbMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: cb.available
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.clicked()
        }

    }

}
