import "../parts"
import "../../common"
import "../../services"
import QtQuick
import QtQuick.Effects

// List tab of the language picker (only videos; listening in the background works with them too).
// On top the stage of the playing (or started) video: blurred preview image as a glow, sharp
// image, title, seek line, controls and - while listening - the subtitle sentence being spoken, colored
// character by character. Below it the library as a grid of big 16:9 previews without card surfaces.
// The order comes from the picker (picker.entries), so the keyboard index and grid stay the same.
Item {
    id: lib

    required property var picker
    readonly property var meta: LanguageAudioState.meta
    property real maxHeight: 600

    // ── Glyphs (Nerd Font as a code point: PUA characters get lost when copying otherwise) ──
    readonly property string gPlay: String.fromCodePoint(0xF04B)
    readonly property string gPause: String.fromCodePoint(0xF04C)
    readonly property string gBack: String.fromCodePoint(0xF0E2)
    readonly property string gFwd: String.fromCodePoint(0xF01E)
    readonly property string gHead: String.fromCodePoint(0xF02CB)
    readonly property string gVideo: String.fromCodePoint(0xF0567)
    readonly property string gExpand: String.fromCodePoint(0xF065)

    // ── Raster ──
    readonly property int cols: width >= 640 ? 3 : 2
    readonly property real hGap: 18
    readonly property real vGap: 20
    readonly property real cardW: Math.floor((width - (cols - 1) * hGap) / cols)
    readonly property real thumbH: Math.round(cardW * 9 / 16)
    readonly property real cardH: thumbH + 60
    readonly property real stride: cardH + vGap
    readonly property real toolbarH: 34
    readonly property var gridRows: {
        const out = [];
        const e = picker.entries;
        for (let i = 0; i < e.length; i += cols) {
            const r = [];
            for (let j = i; j < Math.min(e.length, i + cols); j++) r.push({
                "file": e[j],
                "entry": j
            })
            out.push(r);
        }
        return out;
    }
    readonly property real contentH: Math.max(0, gridRows.length * stride - vGap)

    // Interface to the core: arrow up/down = one row, left/right is done by the core (+-1)
    function verticalStep(index, direction) {
        if (index < 0)
            return direction;

        const to = index + direction * cols;
        return to >= 0 && to < picker.entries.length ? direction * cols : 0;
    }

    function positionViewAtIndex(index, mode) {
        const top = Math.floor(index / cols) * stride;
        let y = listView.contentY;
        if (top < y)
            y = top;
        else if (top + cardH > y + listView.height)
            y = top + cardH - listView.height;
        scrollTo(y);
    }

    function scrollTo(y) {
        const maxY = Math.max(0, lib.contentH - listView.height);
        const to = Math.max(0, Math.min(maxY, y));
        scrollAnim.stop();
        if (Math.abs(to - listView.contentY) < 0.5)
            return ;

        scrollAnim.to = to;
        scrollAnim.start();
    }

    function info(f) {
        return meta[f] || ({
        });
    }

    // "Today", "Yesterday", weekday, otherwise "Oct 17" (like iOS)
    function dateLabel(sec) {
        if (!sec)
            return "";

        const d = new Date(sec * 1000);
        const now = new Date();
        const day = 86400000;
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (d.getTime() >= start)
            return "Today";

        if (d.getTime() >= start - day)
            return "Yesterday";

        if (d.getTime() >= start - 6 * day)
            return Qt.formatDate(d, "dddd");

        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "MMM d" : "MMM d, yyyy");
    }

    // "3 videos · 36 min"
    readonly property string totalLabel: {
        const e = picker.entries;
        let sec = 0;
        for (let i = 0; i < e.length; i++) sec += info(e[i]).duration || 0
        const n = e.length + (e.length === 1 ? " video" : " videos");
        if (sec <= 0)
            return n;

        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        return n + "  ·  " + (h > 0 ? h + " h " + m + " min" : m + " min");
    }

    function resumeFrac(f) {
        const at = LanguageAudioState.videoPositions[f] || 0;
        const d = info(f).duration || 0;
        return at > 0 && d > 0 ? Math.min(1, at / d) : 0;
    }

    // ── Stage: the playing video, otherwise the newest started one (remembered position), otherwise the newest
    // one at all as a suggestion (without a stage the tab looked empty) ──
    // Only a video of THIS language: one of another language keeps playing in the background, but its stage
    // here showed a foreign title, a foreign subtitle line and no thumbnail (looked up in this language's data)
    readonly property bool live: LanguageAudioState.currentFile !== "" && LanguageAudioState.mediaActive && LanguageAudioState.isVideo(LanguageAudioState.currentFile) && LanguageAudioState.playLanguage === LanguageAudioState.language
    // First the last started one (if not watched to the end yet), otherwise the newest started one
    readonly property string resumeFile: {
        const e = picker.entries;
        const pos = LanguageAudioState.videoPositions;
        const last = LanguageAudioState.lastVideos[LanguageAudioState.language] || "";
        if (last !== "" && (pos[last] || 0) > 0 && e.indexOf(last) >= 0)
            return last;

        for (let i = 0; i < e.length; i++) {
            if ((pos[e[i]] || 0) > 0)
                return e[i];
        }
        return "";
    }
    // Only without search text: when filtering "the newest video" would otherwise be a random hit
    readonly property string freshFile: picker.terms.length === 0 && picker.entries.length > 0 ? picker.entries[0] : ""
    readonly property string stageFile: live ? LanguageAudioState.currentFile : (resumeFile || freshFile)
    readonly property bool showCue: live && LanguageAudioState.cues.length > 0
    readonly property real stageBase: 158
    readonly property real cueH: 64
    readonly property real stageFull: stageBase + (showCue ? cueH : 0)
    property real stageH: stageFile !== "" ? stageFull + 18 : 0
    // While the language changes (or the language choice covers the list) the height follows the new list at
    // once: the picker's panel itself animates to it. With the delays below it first aimed at the OLD language's
    // height (Japanese with 7 videos -> Russian with 1: the panel overshot by almost half and shrank back).
    readonly property bool snapHeight: picker.switching || picker.choosing

    Behavior on stageH {
        enabled: !lib.snapHeight

        Smooth {
            duration: 360
        }

    }

    // ── Height: the grid grows up to maxHeight, shrinks only after the rows that drop out have faded ──
    readonly property real emptyH: 170
    readonly property real listFit: {
        const available = Math.max(0, maxHeight - stageH - toolbarH);
        return Math.min(available, gridRows.length ? contentH : emptyH);
    }
    property real listFitLag: listFit
    readonly property real wanted: stageH + toolbarH + listFitLag

    onListFitChanged: {
        if (listFit >= listFitLag || snapHeight) {
            shrinkTimer.stop();
            listFitLag = listFit;
        } else {
            shrinkTimer.restart();
        }
    }

    Timer {
        id: shrinkTimer

        interval: 140
        onTriggered: lib.listFitLag = lib.listFit
    }

    // ═══════════ Stage ═══════════
    Item {
        id: stage

        readonly property string file: lib.stageFile
        readonly property var m: lib.info(file)
        readonly property real dur: lib.live && LanguageAudioState.currentDuration > 0 ? LanguageAudioState.currentDuration : (m.duration || 0)
        readonly property real frac: lib.live ? (dur > 0 ? Math.min(1, LanguageAudioState.currentPosition / dur) : 0) : lib.resumeFrac(file)
        readonly property real shownFrac: seek.pressed ? seek.dragFrac : frac
        readonly property bool playing: lib.live && LanguageAudioState.isPlaying

        width: parent.width
        height: lib.stageH
        clip: true
        opacity: file !== "" ? 1 : 0
        visible: height > 0.5

        RoundedClip {
            id: stageCard

            width: parent.width
            height: lib.stageFull
            radius: 20
            color: Theme.groupFill

            // Glow: the same image heavily blurred and enlarged (no hard edges), breathes softly
            // while playing (opacity only)
            Image {
                id: ambient

                property real glow: 0.42

                anchors.centerIn: parent
                width: parent.width * 1.25
                height: parent.height * 1.6
                source: LanguageAudioState.fileUrl(stage.m.thumb)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 320
                opacity: status === Image.Ready ? glow : 0
                layer.enabled: true

                SequentialAnimation on glow {
                    running: stage.playing && stage.visible
                    loops: Animation.Infinite
                    onRunningChanged: {
                        if (!running)
                            ambient.glow = 0.42;

                    }

                    NumberAnimation {
                        to: 0.55
                        duration: 2600
                        easing.type: Easing.InOutSine
                    }

                    NumberAnimation {
                        to: 0.36
                        duration: 2600
                        easing.type: Easing.InOutSine
                    }

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                    }

                }

                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1
                    blurMax: 64
                    saturation: 0.15
                }

            }

            // Darken toward the panel color: right (text) calmer than left (image)
            Rectangle {
                anchors.fill: parent

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: WalColors.withAlpha(WalColors.color0, 0.35)
                    }

                    GradientStop {
                        position: 1
                        color: WalColors.withAlpha(WalColors.color0, 0.72)
                    }

                }

            }

            // ── Image ──
            RoundedClip {
                id: stageThumb

                x: 16
                y: Math.round((lib.stageBase - height) / 2)
                height: lib.stageBase - 32
                width: Math.round(height * 16 / 9)
                radius: 12
                color: WalColors.withAlpha(WalColors.color0, 0.5)

                Text {
                    anchors.centerIn: parent
                    visible: stageImg.status !== Image.Ready
                    text: lib.gVideo
                    color: Theme.textFaint
                    font.family: Theme.font
                    font.pixelSize: 22
                }

                Image {
                    id: stageImg

                    anchors.fill: parent
                    source: LanguageAudioState.fileUrl(stage.m.thumb)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 480
                }

                // Watch hint on hover
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.35)
                    opacity: thumbMouse.containsMouse ? 1 : 0

                    Text {
                        anchors.centerIn: parent
                        text: lib.gExpand
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: 18
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                        }

                    }

                }

                MouseArea {
                    id: thumbMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LanguageAudioState.watchVideo(stage.file)
                }

            }

            // ── Title, seek line, controls ──
            Item {
                anchors.left: stageThumb.right
                anchors.leftMargin: 20
                anchors.right: parent.right
                anchors.rightMargin: 18
                height: lib.stageBase

                Row {
                    id: stageStatus

                    y: 20
                    spacing: 8

                    // Small level meter: only moves while playing
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: lib.live
                        spacing: 2

                        Repeater {
                            model: 3

                            Rectangle {
                                id: lvl

                                required property int index
                                property real level: 0.4

                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: Math.round(3 + 7 * level)
                                radius: 1
                                color: Theme.accent

                                SequentialAnimation on level {
                                    running: stage.playing && stage.visible
                                    loops: Animation.Infinite

                                    NumberAnimation {
                                        to: [0.9, 0.5, 1][lvl.index]
                                        duration: 300 + lvl.index * 70
                                        easing.type: Easing.InOutSine
                                    }

                                    NumberAnimation {
                                        to: [0.2, 0.95, 0.35][lvl.index]
                                        duration: 340 + lvl.index * 50
                                        easing.type: Easing.InOutSine
                                    }

                                }

                            }

                        }

                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: !lib.live ? (lib.resumeFile !== "" ? "CONTINUE WATCHING" : "START WATCHING") : LanguageAudioState.isPlaying ? (LanguageAudioState.watching ? "NOW WATCHING" : "LISTENING IN THE BACKGROUND") : "PAUSED"
                        color: stage.playing ? Theme.accent : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                        font.weight: Font.DemiBold
                        font.letterSpacing: Theme.microSpacing
                    }

                }

                Text {
                    anchors.top: stageStatus.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    text: LanguageAudioState.stemOf(stage.file)
                    color: Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 1.1
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeTitle
                    font.weight: Font.Medium
                }

                // Seek line (drag = jump, only for the playing video)
                Item {
                    id: seekLine

                    anchors.bottom: controls.top
                    anchors.bottomMargin: 8
                    width: parent.width
                    height: 12

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: seek.containsMouse || seek.pressed ? 5 : 3
                        radius: height / 2
                        color: WalColors.withAlpha(WalColors.color7, 0.16)

                        Rectangle {
                            width: Math.round(parent.width * stage.shownFrac)
                            height: parent.height
                            radius: height / 2
                            color: Theme.accent
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    MouseArea {
                        id: seek

                        property real dragFrac: 0

                        anchors.fill: parent
                        anchors.topMargin: -4
                        anchors.bottomMargin: -4
                        enabled: lib.live && stage.dur > 0
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: (mouse) => {
                            dragFrac = Math.max(0, Math.min(1, mouse.x / width));
                        }
                        onPositionChanged: (mouse) => {
                            if (pressed)
                                dragFrac = Math.max(0, Math.min(1, mouse.x / width));

                        }
                        onReleased: LanguageAudioState.seekToFraction(dragFrac)
                    }

                }

                Row {
                    id: controls

                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    spacing: 6

                    RoundBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 36
                        primary: true
                        glyph: stage.playing ? lib.gPause : lib.gPlay
                        glyphShift: stage.playing ? 0 : 1.5
                        // Play = audio in the background (watch via the image or the button on the right)
                        onClicked: LanguageAudioState.play(stage.file)
                    }

                    RoundBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: lib.live
                        flat: true
                        glyph: lib.gBack
                        onClicked: LanguageAudioState.seekRelative(-10)
                    }

                    RoundBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: lib.live
                        flat: true
                        glyph: lib.gFwd
                        onClicked: LanguageAudioState.seekRelative(10)
                    }

                    RoundBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        flat: true
                        glyph: lib.gExpand
                        onClicked: LanguageAudioState.watchVideo(stage.file)
                    }

                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: controls.verticalCenter
                    text: lib.picker.formatTime(stage.shownFrac * stage.dur) + "  /  " + lib.picker.formatTime(stage.dur)
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    font.features: Theme.tabular
                }

            }

            // ── Spoken sentence: subtitle of the current position, what was already said bright, the rest faint ──
            Item {
                id: cueStrip

                readonly property var cue: LanguageAudioState.cueIndex >= 0 && LanguageAudioState.cueIndex < LanguageAudioState.cues.length ? LanguageAudioState.cues[LanguageAudioState.cueIndex] : null
                // How many characters have been spoken: support points k = [[char, second], ...], linear in
                // between; without k ~5 characters/s from the start of the line (like the subtitle box in the player)
                readonly property int spoken: {
                    const c = cue;
                    if (!c)
                        return 0;

                    const pos = LanguageAudioState.currentPosition;
                    const len = c.t.length;
                    const k = c.k || [];
                    if (k.length === 0)
                        return Math.max(0, Math.min(len, Math.floor((pos - c.s) * 5)));

                    let j = -1;
                    for (let i = 0; i < k.length; i++) {
                        if (k[i][1] <= pos)
                            j = i;
                        else
                            break;
                    }
                    if (j < 0)
                        return 0;

                    const next = j + 1 < k.length ? k[j + 1] : [len, c.e];
                    const span = Math.max(0.001, next[1] - k[j][1]);
                    return Math.max(0, Math.min(len, Math.floor(k[j][0] + (next[0] - k[j][0]) * Math.min(1, (pos - k[j][1]) / span))));
                }
                readonly property color litColor: Theme.text
                readonly property color dimColor: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.42))

                function esc(t) {
                    return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                }

                y: lib.stageBase
                width: parent.width
                height: lib.cueH
                opacity: lib.showCue ? 1 : 0
                visible: opacity > 0.01

                Rectangle {
                    x: 16
                    width: parent.width - 32
                    height: 1
                    color: WalColors.withAlpha(WalColors.color7, 0.1)
                }

                Text {
                    id: cueText

                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -2
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: {
                        const c = cueStrip.cue;
                        if (!c)
                            return "<font color=\"" + cueStrip.dimColor + "\">…</font>";

                        const t = c.t;
                        return "<font color=\"" + cueStrip.litColor + "\">" + cueStrip.esc(t.slice(0, cueStrip.spoken)) + "</font>" + "<font color=\"" + cueStrip.dimColor + "\">" + cueStrip.esc(t.slice(cueStrip.spoken)) + "</font>";
                    }
                    font.family: lib.picker.jp
                    font.pixelSize: 19
                }

                // A new line flashes up briefly (opacity only)
                Connections {
                    function onCueIndexChanged() {
                        cueFade.restart();
                    }

                    target: LanguageAudioState
                }

                NumberAnimation {
                    id: cueFade

                    target: cueText
                    property: "opacity"
                    from: 0.25
                    to: 1
                    duration: 260
                    easing.type: Easing.OutCubic
                }

                // Click: watch the video (there are word cards and translation there)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LanguageAudioState.watchVideo(stage.file)
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 240
                    }

                }

            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }

        }

    }

    // ═══════════ Library header ═══════════
    Item {
        id: toolbar

        y: lib.stageH
        width: parent.width
        height: lib.toolbarH

        Text {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -4
            text: "LIBRARY"
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.weight: Font.DemiBold
            font.letterSpacing: Theme.microSpacing
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -4
            text: lib.totalLabel
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
            font.features: Theme.tabular
        }

    }

    // ═══════════ Raster ═══════════
    ListView {
        id: listView

        y: lib.stageH + lib.toolbarH
        width: parent.width
        height: lib.listFitLag
        model: lib.gridRows
        spacing: lib.vGap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: false

        NumberAnimation {
            id: scrollAnim

            target: listView
            property: "contentY"
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.outQuint
        }

        delegate: Row {
            id: gridRow

            required property var modelData

            spacing: lib.hGap

            Repeater {
                model: gridRow.modelData

                delegate: Item {
                    id: card

                    required property var modelData
                    readonly property string file: modelData.file
                    readonly property int entry: modelData.entry
                    readonly property var m: lib.info(file)
                    readonly property bool current: LanguageAudioState.mediaActive && LanguageAudioState.currentFile === file && LanguageAudioState.playLanguage === LanguageAudioState.language
                    readonly property bool hot: lib.picker.kbList === "audio" && lib.picker.kbIndex === entry
                    readonly property real resume: lib.resumeFrac(file)

                    width: lib.cardW
                    height: lib.cardH

                    RoundedClip {
                        id: thumb

                        width: parent.width
                        height: lib.thumbH
                        radius: 12
                        color: Theme.groupFill

                        Text {
                            anchors.centerIn: parent
                            visible: img.status !== Image.Ready
                            text: lib.gVideo
                            color: Theme.textFaint
                            font.family: Theme.font
                            font.pixelSize: 22
                        }

                        // Selected: the image zooms slightly in the frame (the card itself stays still)
                        Image {
                            id: img

                            anchors.fill: parent
                            source: LanguageAudioState.fileUrl(card.m.thumb)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 560
                            scale: card.hot ? 1.06 : 1
                            opacity: status === Image.Ready ? 1 : 0

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 520
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.anim.curves.outQuint
                                }

                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 220
                                }

                            }

                        }

                        // Dark gradient at the bottom, so duration and progress stay readable on bright images
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * 0.4

                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: "transparent"
                                }

                                GradientStop {
                                    position: 1
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                }

                            }

                        }

                        // Running: darkened + level meter
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.45)
                            opacity: card.current ? 1 : 0
                            visible: opacity > 0.01

                            Row {
                                anchors.centerIn: parent
                                spacing: 3

                                Repeater {
                                    model: 4

                                    Rectangle {
                                        id: bar

                                        required property int index
                                        property real level: 0.4

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 3
                                        height: Math.round(5 + 16 * level)
                                        radius: 1.5
                                        color: "white"

                                        SequentialAnimation on level {
                                            running: card.current && LanguageAudioState.isPlaying
                                            loops: Animation.Infinite

                                            NumberAnimation {
                                                to: [0.9, 0.5, 1, 0.7][bar.index]
                                                duration: 280 + bar.index * 70
                                                easing.type: Easing.InOutSine
                                            }

                                            NumberAnimation {
                                                to: [0.25, 0.95, 0.35, 0.2][bar.index]
                                                duration: 320 + bar.index * 50
                                                easing.type: Easing.InOutSine
                                            }

                                        }

                                    }

                                }

                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                }

                            }

                        }

                        // Selected: play hint in the middle (click = watch)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 46
                            height: 46
                            radius: 23
                            color: Qt.rgba(0, 0, 0, 0.45)
                            opacity: card.hot && !card.current ? 1 : 0
                            visible: opacity > 0.01

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 2
                                text: lib.gPlay
                                color: "white"
                                font.family: Theme.font
                                font.pixelSize: 17
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 160
                                }

                            }

                        }

                        Text {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 10
                            anchors.bottomMargin: card.resume > 0 ? 10 : 7
                            visible: (card.m.duration || 0) > 0 && !card.current
                            text: lib.picker.formatTime(card.m.duration || 0)
                            color: "white"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeSmall
                            font.weight: Font.DemiBold
                            font.features: Theme.tabular
                        }

                        // Gemerkter Stand
                        Rectangle {
                            visible: card.resume > 0 && !card.current
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 3
                            color: Qt.rgba(1, 1, 1, 0.22)

                            Rectangle {
                                width: Math.round(parent.width * card.resume)
                                height: parent.height
                                color: Theme.accent
                            }

                        }

                    }

                    // Selection ring (like the cards of the other pickers, without enlarging the card)
                    Rectangle {
                        anchors.fill: thumb
                        radius: thumb.radius
                        color: "transparent"
                        border.width: 2
                        border.color: WalColors.color4
                        opacity: card.hot ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                            }

                        }

                    }

                    MouseArea {
                        id: hit

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: (mouse) => {
                            return lib.picker.hoverSelect(hit, mouse, "audio", card.entry);
                        }
                        onClicked: LanguageAudioState.watchVideo(card.file)
                    }

                    // Listen only: small button at the top right of the image (on selection or while playing)
                    RoundBtn {
                        anchors.right: thumb.right
                        anchors.top: thumb.top
                        anchors.margins: 8
                        size: 30
                        dark: true
                        opacity: card.hot || card.current ? 1 : 0
                        visible: opacity > 0.01
                        glyph: card.current && LanguageAudioState.isPlaying ? lib.gPause : lib.gHead
                        onClicked: LanguageAudioState.play(card.file)

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                            }

                        }

                    }

                    Column {
                        y: lib.thumbH + 10
                        width: parent.width
                        spacing: 3

                        Text {
                            width: parent.width
                            text: LanguageAudioState.stemOf(card.file)
                            color: card.current ? Theme.accent : Theme.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeLabel
                            font.weight: Font.Medium
                        }

                        Text {
                            width: parent.width
                            text: [lib.dateLabel(card.m.mtime), LanguageAudioState.hasSubs(card.file) ? "字幕" : ""].filter(Boolean).join("  ·  ")
                            color: Theme.textFaint
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeSmall
                        }

                    }

                }

            }

        }

        // Mouse wheel: one notch = one row; touchpad: 60 px of travel = one row
        MouseArea {
            property real pending: 0

            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (wheel) => {
                const touchpad = wheel.phase !== Qt.NoScrollPhase;
                const d = touchpad ? wheel.pixelDelta.y : wheel.angleDelta.y;
                const unit = touchpad ? 60 : 120;
                if (d === 0)
                    return ;

                if (pending !== 0 && Math.sign(pending) !== Math.sign(d))
                    pending = 0;

                pending += d;
                const steps = Math.trunc(pending / unit);
                if (steps === 0)
                    return ;

                pending -= steps * unit;
                const base = scrollAnim.running ? scrollAnim.to : listView.contentY;
                lib.scrollTo((Math.round(base / lib.stride) - steps) * lib.stride);
            }
        }

    }

    // Soft edge at the bottom, only if something more comes there
    Rectangle {
        y: listView.y + listView.height - height
        width: listView.width
        height: 36
        opacity: lib.contentH - listView.contentY - listView.height > 1 ? 1 : 0
        visible: opacity > 0.01

        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }

            GradientStop {
                position: 1
                color: WalColors.withAlpha(WalColors.color0, 0.97)
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }

        }

    }

    // ═══════════ Empty ═══════════
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: lib.stageH + lib.toolbarH + 30
        visible: lib.gridRows.length === 0
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: lib.gVideo
            color: Theme.textFaint
            font.family: Theme.font
            font.pixelSize: 28
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: lib.picker.searchQuery !== "" ? "No matches" : "No videos yet"
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLead
            font.weight: Font.Medium
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: lib.picker.searchQuery === "" ? "Paste a YouTube link above or type and press Enter" : "Press Enter to search YouTube"
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
        }

    }

    // ───────────────────────── Building blocks ─────────────────────────

    // Round button: glass, flat = only the symbol (glass only on hover), primary = bright play button,
    // dark = dark glass for buttons on images
    component RoundBtn: Rectangle {
        id: rb

        property string glyph: ""
        property real size: 32
        property real glyphShift: 0
        property bool primary: false
        property bool flat: false
        property bool dark: false

        signal clicked()

        width: size
        height: size
        radius: size / 2
        color: primary ? (rbMouse.containsMouse ? Qt.rgba(1, 1, 1, 1) : Theme.knob) : dark ? Qt.rgba(0, 0, 0, rbMouse.containsMouse ? 0.7 : 0.5) : rbMouse.containsMouse ? Theme.glassHover : flat ? WalColors.withAlpha(WalColors.color7, 0) : Theme.glass
        scale: rbMouse.pressed ? 0.9 : 1

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: rb.glyphShift
            text: rb.glyph
            color: rb.primary ? WalColors.color0 : rb.dark ? "white" : Theme.text
            font.family: Theme.font
            font.pixelSize: rb.primary ? 15 : 13
        }

        MouseArea {
            id: rbMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }

        Behavior on scale {
            Springy {
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 120
            }

        }

    }

}
