import "../services"
import QtQuick

// Subtitle box of the language tool: current line with furigana, every word clickable (pauses and
// shows reading, base form, part of speech, meanings from JMdict above it, looked up in advance in scripts/jp_subs.py).
// On the left repeat the line, on the right translate the line (backend from scripts/jp_translate.py, stored;
// the button is hidden when translation is off and the line has no translation yet).
// Used by the video player (windows/LanguageVideoPlayer.qml, below the image) and by the bar in
// list mode (windows/LanguageSubtitles.qml). A click beside closes the explanation: the host
// catches that (popupOpen -> close()), because only it knows the whole area.
Item {
    id: box

    readonly property string jp: "Noto Sans CJK JP"
    readonly property var cues: LanguageSubtitleState.cues
    readonly property int idx: LanguageSubtitleState.cueIndex
    readonly property var cue: idx >= 0 && idx < cues.length ? cues[idx] : null
    // The last shown line stays during speech pauses (dimmed) instead of jumping to empty
    property var shownCue: null
    // Clicked word: {cue: index, w: index} or null
    property var picked: null
    readonly property var pickedWord: picked && cues[picked.cue] ? cues[picked.cue].w[picked.w] : null
    readonly property bool popupOpen: pickedWord !== null && pickedWord !== undefined
    // Host: shown fades in/out, fillWidth = always maxWidth wide (player), otherwise as wide as
    // the line (bar)
    property bool shown: true
    property bool fillWidth: false
    property real maxWidth: 800
    property color boxColor: WalColors.withAlpha(WalColors.color0, 0.86)
    property real textSize: Theme.px(26)
    readonly property alias barItem: bar
    readonly property real sidePad: Theme.px(64)
    // 1 = line visible; follows "speaking right now" softly (Behavior), so speech pauses do not flicker
    property real lineK: cue !== null || popupOpen ? 1 : 0
    // Entrance of the new line (0 -> 1)
    property real enterK: 1
    // ── The word being spoken (karaoke) ──
    // Start character of every word (without spaces, like the word times "k" from jp_subs.py)
    readonly property var wordStarts: {
        const out = [];
        let p = 0;
        for (const w of (shownCue ? shownCue.w : [])) {
            out.push(p);
            p += w.t.replace(/\s+/g, "").length;
        }
        out.push(p);
        return out;
    }
    // Character the speaker is at. YouTube's word times (k) are support points, in between it runs
    // on evenly; after the last one it runs on until the end of the line (= start of the next one, see
    // LanguageSubtitleState.clipCues). Some sections have only ONE mark at the start of the line - without running on
    // the highlight got stuck there at the first word. Without word times the start of the line is the only support
    // point. After the end: line normal (n).
    // A fixed speed (5 characters/s, 13 letters/s) was too fast for slow speakers: the highlight reached the end
    // seconds early (measured with whisper on a Russian A2 podcast: 4 s of highlight for 7 s of speech). So the
    // line's own duration sets the speed; only after a long pause it may not get slower than this per character.
    // Japanese packs a syllable or a whole word into one character
    readonly property real maxSecPerChar: LanguageAudioState.playLanguage === "Japanese" ? 0.35 : 0.15
    readonly property real spokenChar: {
        const c = cue;
        if (!c || c !== shownCue)
            return -1;

        const t = LanguageAudioState.currentPosition;
        const n = wordStarts[wordStarts.length - 1];
        const marks = c.k && c.k.length > 0 ? c.k : [[0, c.s]];
        if (t < marks[0][1])
            return -1;

        let i = 0;
        while (i + 1 < marks.length && marks[i + 1][1] <= t)i++
        const c0 = marks[i][0];
        const t0 = marks[i][1];
        const last = i + 1 >= marks.length;
        const c1 = last ? n : marks[i + 1][0];
        const t1 = last ? Math.min(c.e, t0 + (n - c0) * maxSecPerChar) : marks[i + 1][1];
        if (t >= t1)
            return last ? n : c1;

        return c0 + (c1 - c0) * (t - t0) / Math.max(0.01, t1 - t0);
    }
    readonly property int activeWord: {
        if (spokenChar < 0)
            return -1;

        for (let i = 0; i + 1 < wordStarts.length; i++) {
            if (spokenChar >= wordStarts[i] && spokenChar < wordStarts[i + 1])
                return i;

        }
        return -1;
    }

    Behavior on lineK {
        NumberAnimation {
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.standard
        }

    }

    NumberAnimation {
        id: lineEnter

        target: box
        property: "enterK"
        from: 0
        to: 1
        duration: 320
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    // {住|す}んでいました -> [{t: "住", r: "す"}, {t: "んでいました", r: ""}]
    function segments(word) {
        const src = word.f || word.t;
        const out = [];
        const re = /\{([^|}]+)\|([^}]+)\}/g;
        let last = 0;
        let m;
        while ((m = re.exec(src)) !== null) {
            if (m.index > last)
                out.push({
                "t": src.slice(last, m.index),
                "r": ""
            });

            out.push({
                "t": m[1],
                "r": m[2]
            });
            last = re.lastIndex;
        }
        if (last < src.length)
            out.push({
            "t": src.slice(last),
            "r": ""
        });

        return out;
    }

    function pick(wi) {
        if (picked && picked.cue === idx && picked.w === wi) {
            close();
            return ;
        }
        if (!picked)
            LanguageAudioState.holdForLookup();

        picked = {
            "cue": idx,
            "w": wi
        };
    }

    function close() {
        if (!picked)
            return ;

        picked = null;
        LanguageAudioState.releaseLookup();
    }

    function replay() {
        if (!cue)
            return ;

        picked = null;
        LanguageAudioState.seekTo(cue.s);
    }

    function translate() {
        if (cue && !cue.en)
            LanguageSubtitleState.translateCue(idx);

    }

    width: bar.width
    height: bar.height
    // New line: once softly in from below (lineEnter); when a line ends, it fades out (lineK),
    // but stays standing until the next one comes
    onCueChanged: {
        if (cue && cue !== shownCue) {
            shownCue = cue;
            lineEnter.restart();
        }
    }
    // New line (playing on, jumping): close the explanation of the old word
    onIdxChanged: {
        if (picked && picked.cue !== idx)
            picked = null;

    }
    onShownChanged: {
        if (!shown)
            close();
        else
            Qt.callLater(words.measure); // widths measured while hidden are outdated
    }
    // Bigger font (fullscreen) / another width: measure the word widths again, otherwise the line wraps
    onTextSizeChanged: Qt.callLater(words.measure)
    // Another file: do not leave the old line standing
    // New list: another file (old line gone) or only one line translated (keep showing the same
    // line - before, it was reset and not highlighted until the next line change)
    onCuesChanged: {
        shownCue = cue;
        if (picked && !cue)
            picked = null;

    }

    Rectangle {
        id: bar

        readonly property var line: box.shownCue

        width: box.fillWidth ? box.maxWidth : Math.min(box.maxWidth, Math.max(Theme.px(360), Math.max(words.naturalW, trText.implicitWidth) + 2 * box.sidePad))
        height: Math.max(content.implicitHeight + 2 * Theme.px(14), box.fillWidth ? box.textSize * 2.6 : 0)
        radius: Theme.radiusL
        color: box.boxColor
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color4, 0.18)
        opacity: box.shown ? 1 : 0
        visible: opacity > 0.01

        Column {
            id: content

            anchors.centerIn: parent
            width: parent.width - 2 * box.sidePad
            spacing: Theme.px(6)
            opacity: box.lineK * box.enterK

            transform: Translate {
                y: (1 - box.enterK) * Theme.px(10)
            }

            Flow {
                id: words

                // Flow knows no centering: measure the width of the words ourselves (after creation)
                property real naturalW: 0

                function measure() {
                    let w = 0;
                    for (let i = 0; i < repeater.count; i++) {
                        const it = repeater.itemAt(i);
                        if (it)
                            w += it.width + spacing;

                    }
                    naturalW = Math.max(0, w - spacing);
                }

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, naturalW + 1)
                spacing: 0

                Repeater {
                    id: repeater

                    model: bar.line ? bar.line.w : []
                    onItemAdded: Qt.callLater(words.measure)
                    onItemRemoved: Qt.callLater(words.measure)

                    delegate: Rectangle {
                        id: wordBox

                        required property var modelData
                        required property int index
                        readonly property bool clickable: modelData.d !== undefined
                        readonly property bool isPicked: box.picked !== null && box.picked.cue === box.idx && box.picked.w === index
                        readonly property bool isActive: index === box.activeWord && !box.popupOpen
                        // Not spoken yet: dimmed (only while the line runs)
                        readonly property bool upcoming: box.activeWord >= 0 && index > box.activeWord && !box.popupOpen
                        readonly property color ink: isPicked || isActive ? WalColors.color4 : (upcoming ? WalColors.withAlpha(WalColors.color7, 0.5) : Theme.text)

                        // No spacing between words (Japanese has no spaces); the borders
                        // are only shown by the hover background. Other languages bring " " items
                        // between their words (scripts/jp_subs.py plain_words)
                        width: segRow.implicitWidth + Theme.px(2)
                        height: segRow.implicitHeight + Theme.px(4)
                        // The width changes (font loads, fullscreen) -> measure the line width again
                        onWidthChanged: Qt.callLater(words.measure)
                        radius: Theme.radiusXS
                        color: isPicked ? WalColors.withAlpha(WalColors.color4, 0.3) : (wordMouse.containsMouse && clickable ? WalColors.withAlpha(WalColors.color4, 0.15) : (isActive ? WalColors.withAlpha(WalColors.color4, 0.1) : "transparent"))

                        Row {
                            id: segRow

                            anchors.centerIn: parent

                            Repeater {
                                model: box.segments(wordBox.modelData)

                                delegate: Column {
                                    required property var modelData

                                    // As wide as the word itself: longer furigana (男 -> おとこ) stick out
                                    // to the sides instead of pushing gaps between the words
                                    width: baseText.implicitWidth

                                    // Furigana above the kanji; without a reading an equally high gap, so all
                                    // words stand on one base line
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: parent.modelData.r || " "
                                        font.family: box.jp
                                        font.pixelSize: Math.round(box.textSize * 0.46)
                                        color: wordBox.isPicked || wordBox.isActive ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, wordBox.upcoming ? 0.35 : 0.6)

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 140
                                            }

                                        }

                                    }

                                    Text {
                                        id: baseText

                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: parent.modelData.t
                                        font.family: box.jp
                                        font.pixelSize: box.textSize
                                        color: wordBox.ink

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 140
                                            }

                                        }

                                    }

                                }

                            }

                        }

                        MouseArea {
                            id: wordMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: wordBox.clickable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: box.pick(wordBox.index)
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                    }

                }

            }

            // Translation of the line (on a button press, stored)
            Text {
                id: trText

                readonly property bool busy: LanguageSubtitleState.translatingIdx === box.idx && box.idx >= 0

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, implicitWidth)
                visible: text !== ""
                text: busy ? "Translating…" : (box.cue && box.cue.en ? box.cue.en : "")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLead
                color: busy ? Theme.textFaint : Theme.textDim
            }

        }

        BoxButton {
            anchors.left: parent.left
            anchors.leftMargin: Theme.px(12)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰑖"
            enabled: box.cue !== null
            onClicked: box.replay()
        }

        BoxButton {
            anchors.right: parent.right
            anchors.rightMargin: Theme.px(12)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰗊"
            visible: LanguageReadingState.translator !== "" || (box.cue !== null && !!box.cue.en)
            on: box.cue !== null && !!box.cue.en
            enabled: box.cue !== null && !box.cue.en && LanguageSubtitleState.translatingIdx < 0
            onClicked: box.translate()
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.standard
            }

        }

    }

    // ═══════════ Explanation of the clicked word (above the box) ═══════════
    Rectangle {
        id: popup

        readonly property var word: box.pickedWord

        x: (bar.width - width) / 2
        y: -height - Theme.px(12) + (1 - opacity) * 10
        width: Theme.px(420)
        height: card.implicitHeight + 2 * Theme.px(18)
        radius: Theme.radiusL
        // opaque, like the word card in the Read tab
        color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.04))
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color4, 0.3)
        opacity: box.popupOpen ? 1 : 0
        scale: box.popupOpen ? 1 : 0.97
        visible: opacity > 0.01

        // Clicks on the card itself should not close it
        MouseArea {
            anchors.fill: parent
        }

        LanguageWordCard {
            id: card

            x: Theme.px(20)
            y: Theme.px(18)
            width: parent.width - 2 * Theme.px(20)
            word: popup.word
            hint: "Click anywhere to continue"
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.emphasizedDecelerate
            }

        }

    }

    // Round button in the box (Nerd Font glyph), like the small buttons in the pickers
    component BoxButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool on: false

        signal clicked()

        width: Theme.px(34)
        height: width
        radius: height / 2
        color: on ? WalColors.withAlpha(WalColors.color4, 0.22) : (btnMouse.containsMouse && enabled ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, 0.06))
        opacity: enabled || on ? 1 : 0.4
        scale: btnMouse.pressed ? 0.92 : 1

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: Theme.font
            font.pixelSize: Theme.px(15)
            color: btn.on || btnMouse.containsMouse ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.6)
        }

        MouseArea {
            id: btnMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.enabled)
                    btn.clicked();

            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

        Behavior on scale {
            Springy {
            }

        }

    }

}
