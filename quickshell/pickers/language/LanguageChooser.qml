import "../../common"
import "../../services"
import QtQuick

// Language choice when opening, built like the category choice of the media picker (add-on) and with the same tile
// (common/ChooserTile): one per language (character, name, native name, number of audio/video, listening time of the week)
// and a plus tile.
// Plus = form (LanguageAddForm: name, symbol, image) instead of the tiles; creating goes right into it.
// Keys: <-/->/Tab or hjkl move, Up/Down = row, 1-9 directly, Enter opens, Esc closes.
// At most two rows are shown (5 languages + plus); more rows scroll, one whole row per wheel notch, and the
// keyboard selection scrolls along. Rows outside the view fade out (via the tile's enter) and are clipped.
// Part of the language picker (pickers/language/LanguagePicker.qml); access via picker.
Item {
    id: chooser

    required property var picker
    readonly property var langs: LanguageAudioState.languages
    // Tiles = languages + plus
    readonly property int count: langs.length + 1
    // Exactly like the media picker's category choice: three tiles per row, 300 high, 14 apart
    // (more languages -> more rows, an incomplete last row stands centered)
    readonly property int columns: 3
    readonly property real gap: 14
    // Width of the full chooser (from the picker); the tile size comes from it, so it stays the same
    property real fullWidth: 1100
    readonly property real tileW: Math.floor((fullWidth - (columns - 1) * gap) / columns)
    // Only as wide as the used columns: with few languages there would be empty space left/right otherwise
    readonly property int usedColumns: Math.min(columns, count)
    implicitWidth: usedColumns * tileW + (usedColumns - 1) * gap
    readonly property real tileH: 300
    readonly property real titleH: 0
    readonly property int rows: Math.ceil(count / columns)
    // Rows on screen; with more the panel keeps this height and the rows scroll
    readonly property int maxRows: 2
    readonly property int visibleRows: Math.min(rows, maxRows)
    readonly property real stride: tileH + gap
    readonly property bool scrolls: rows > maxRows
    // First row on screen; scrollY follows it smoothly (instantScroll: jump, e.g. when the choice opens)
    property int firstRow: 0
    property bool instantScroll: false
    property real scrollY: firstRow * stride
    // The form is one row high
    implicitHeight: adding ? tileH : titleH + visibleRows * tileH + (visibleRows - 1) * gap
    property int index: 0
    property bool adding: false
    // 0 = tiles, 1 = form (crossfade)
    property real formK: adding ? 1 : 0
    // 0 -> 1 on appearing (tiles staggered)
    property real enterT: 0
    property alias keys: chooserKeys

    function reset() {
        adding = false;
        index = Math.max(0, langs.indexOf(LanguageAudioState.language));
        instantScroll = true;
        firstRow = 0;
        showRow(Math.floor(index / columns));
        instantScroll = false;
        enterT = 0;
        enterAnim.restart();
    }

    // Scroll as little as needed so that row r is on screen
    function showRow(r) {
        if (r < firstRow)
            firstRow = r;
        else if (r >= firstRow + visibleRows)
            firstRow = r - visibleRows + 1;
        firstRow = Math.max(0, Math.min(rows - visibleRows, firstRow));
    }

    // Wheel: whole rows. The selection stays in its column but moves into the view, so Enter never opens
    // a tile that is scrolled away
    function scrollRows(d) {
        const before = firstRow;
        firstRow = Math.max(0, Math.min(rows - visibleRows, firstRow + d));
        if (firstRow === before)
            return ;

        const r = Math.floor(index / columns);
        const target = Math.max(firstRow, Math.min(firstRow + visibleRows - 1, r));
        if (target !== r)
            index = Math.min(count - 1, target * columns + index % columns);

    }

    onIndexChanged: showRow(Math.floor(index / columns))
    onRowsChanged: showRow(Math.floor(index / columns))

    function move(d) {
        if (adding || picker.switching)
            return ;

        index = Math.max(0, Math.min(count - 1, index + d));
    }

    function activate(i) {
        if (picker.switching)
            return;
        if (i < langs.length)
            picker.enterLanguage(langs[i]);
        else
            startAdding();
    }

    // Focus where you are right now. The picker calls this late (Qt.callLater, PickerWindow while loading
    // other pickers): without the check it pulled the focus back out of the form -> typing went nowhere
    function focusCurrent() {
        if (adding)
            addForm.refocus();
        else
            chooserKeys.forceActiveFocus();
    }

    // Image from the folder browser (LanguagePicker.openImageBrowser) -> into the form
    function imageChosen(path) {
        addForm.setImage(path);
    }

    function startAdding() {
        index = count - 1;
        adding = true;
        addForm.open();
    }

    function cancelAdding() {
        adding = false;
        chooserKeys.forceActiveFocus();
    }

    // Form submitted: back to the tiles, the picker goes in as soon as the folder is there
    function finishAdding() {
        adding = false;
        chooserKeys.forceActiveFocus();
    }

    function fmtTime(secs) {
        const m = Math.round(secs / 60);
        return m < 60 ? m + "m" : Math.floor(m / 60) + "h " + (m % 60) + "m";
    }

    NumberAnimation {
        id: enterAnim

        target: chooser
        property: "enterT"
        from: 0
        to: 1
        duration: 760
    }

    Item {
        id: chooserKeys

        Keys.onPressed: (event) => {
            const key = PickerManager.navKey(event);
            if (key === Qt.Key_Left || key === Qt.Key_H || key === Qt.Key_Backtab)
                chooser.move(-1);
            else if (key === Qt.Key_Right || key === Qt.Key_L || key === Qt.Key_Tab)
                chooser.move(1);
            else if (key === Qt.Key_Down)
                chooser.move(chooser.columns);
            else if (key === Qt.Key_Up)
                chooser.move(-chooser.columns);
            else if (key >= Qt.Key_1 && key <= Qt.Key_9 && key - Qt.Key_1 < chooser.count)
                chooser.activate(key - Qt.Key_1);
            else if (key === Qt.Key_Return || key === Qt.Key_Enter)
                chooser.activate(chooser.index);
            else if (key === Qt.Key_Escape)
                LanguageAudioState.close();
            else
                return ;
            event.accepted = true;
        }
    }

    Behavior on scrollY {
        enabled: !chooser.instantScroll

        Smooth {
            duration: 360
        }

    }

    Behavior on formK {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.standard
        }

    }

    // ── Tiles (like MediaChooser/CategoryTile) ──
    // Clip area = the panel around the chooser (its margin), so the lifted, tilted selection and its shadow keep
    // their room; only clips when rows scroll.
    Item {
        id: tileClip

        readonly property real margin: chooser.picker.chooserMargin

        x: -margin
        y: -margin
        width: chooser.width + 2 * margin
        height: chooser.height + 2 * margin
        clip: chooser.scrolls

        Item {
            id: tilesLayer

            x: tileClip.margin
            y: tileClip.margin
            width: chooser.width
            height: chooser.height
            opacity: 1 - chooser.formK
            visible: opacity > 0.01
            enabled: !chooser.adding
            scale: 1 - 0.03 * chooser.formK

            Repeater {
                model: chooser.count

                delegate: ChooserTile {
                    id: tile

                    required property int index
                    readonly property bool isAdd: index === chooser.langs.length
                    readonly property string name: isAdd ? "" : chooser.langs[index]
                    readonly property var info: LanguageAudioState.languageInfo[name] || ({
                    })
                    readonly property string mark: isAdd ? String.fromCodePoint(0xF067) : LanguageAudioState.markOf(name)
                    readonly property bool latin: /^[A-Za-z]/.test(mark)
                    // Incomplete last row centered
                    readonly property int row: Math.floor(index / chooser.columns)
                    readonly property int inRow: row === chooser.rows - 1 ? chooser.count - row * chooser.columns : chooser.columns
                    // Position in the view and how far it sticks out of the shown rows -> fade (1 inside, 0 half a tile out)
                    readonly property real viewY: row * chooser.stride - chooser.scrollY
                    readonly property real outside: Math.max(0, -viewY, viewY - (chooser.visibleRows - 1) * chooser.stride)
                    readonly property real inView: tile.clamp01(1 - outside / (chooser.tileH * 0.5))

                    x: (chooser.width - (inRow * chooser.tileW + (inRow - 1) * chooser.gap)) / 2 + (index % chooser.columns) * (chooser.tileW + chooser.gap)
                    y: chooser.titleH + viewY
                    width: chooser.tileW
                    height: chooser.tileH
                    selected: chooser.index === index
                    // Appearing (staggered) and fading at the edge of the view; below 1 the tile also takes no hover/click
                    enter: {
                        const t = tile.clamp01(chooser.enterT * 1.7 - (row - chooser.firstRow) * chooser.columns * 0.25 - index % chooser.columns * 0.25);
                        return (1 - Math.pow(1 - t, 3)) * inView;
                    }
                    visible: inView > 0.01
                    leave: chooser.picker.choosing ? chooser.picker.switchOut : 0
                    side: index < chooser.index ? -1 : (index > chooser.index ? 1 : 0)
                    glyph: mark
                    glyphFont: isAdd ? Theme.font : latin ? Theme.fontUi : chooser.picker.jp
                    glyphSize: isAdd ? 36 : latin ? 34 : 40
                    label: isAdd ? "Add Language" : name
                    // Image: cover.jpg in the language folder or ~/.config/shiori-shell/language-covers/<Name>.jpg (scripts/lang_media.py)
                    cover: LanguageAudioState.fileUrl(info.cover)
                    // The image itself is the icon here (e.g. a Japan logo): no character above it
                    showGlyph: !info.cover
                    onHoverEntered: {
                        if (!chooser.adding && !chooser.picker.switching)
                            chooser.index = index;

                    }
                    onClicked: chooser.activate(index)

                }

            }

            // Wheel: one notch (touchpad: 60 px) = one row. On top of the tiles, but it takes neither hover nor clicks
            MouseArea {
                property real pending: 0

                anchors.fill: parent
                z: 10
                enabled: chooser.scrolls
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
                    chooser.scrollRows(-steps);
                }
            }

        }

    }

    LanguageAddForm {
        id: addForm

        host: chooser
        width: parent.width
        height: chooser.tileH
        opacity: chooser.formK
        visible: opacity > 0.01
        enabled: chooser.adding
        scale: 0.97 + 0.03 * chooser.formK
    }

}
