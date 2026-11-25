import "../../common"
import "../../services"
import QtQuick

// Listen tab of the language picker (only videos; listening in the background works with them too).
// On top the stage of the playing (or started) video: blurred preview image as a glow, sharp
// image, title, seek line, controls and - while listening - the subtitle sentence being spoken, colored
// character by character. Below it the library as a grid of big 16:9 previews without card surfaces.
// The order comes from the picker (picker.entries), so the keyboard index and grid stay the same.
// This file: grid layout, which video the stage shows, heights and scrolling. Surfaces: LibraryStage
// (+ LibraryCue), LibraryCard and CircleButton, which get this object as view.
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
    readonly property bool showCue: live && LanguageSubtitleState.cues.length > 0
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
    LibraryStage {
        id: stage

        picker: lib.picker
        view: lib
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

                delegate: LibraryCard {
                    picker: lib.picker
                    view: lib
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

}
