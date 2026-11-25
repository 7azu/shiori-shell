import "../../common"
import "../../services"
import QtQuick

// Listen tab, stage: the subtitle sentence being spoken, under the controls. What was already said is bright,
// the rest faint; a new line flashes up briefly. A click opens the video.
// Part of LibraryStage.qml (view = the Listen tab, picker = core).
Item {
    id: cueStrip

    required property var picker
    required property var view
    // The video on the stage
    required property string file

    readonly property var cue: LanguageSubtitleState.cueIndex >= 0 && LanguageSubtitleState.cueIndex < LanguageSubtitleState.cues.length ? LanguageSubtitleState.cues[LanguageSubtitleState.cueIndex] : null
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

    y: cueStrip.view.stageBase
    width: parent.width
    height: cueStrip.view.cueH
    opacity: cueStrip.view.showCue ? 1 : 0
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
        font.family: cueStrip.picker.jp
        font.pixelSize: 19
    }

    // A new line flashes up briefly (opacity only)
    Connections {
        function onCueIndexChanged() {
            cueFade.restart();
        }

        target: LanguageSubtitleState
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
        onClicked: LanguageAudioState.watchVideo(cueStrip.file)
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 240
        }

    }

}
