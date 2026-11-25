import "../../common"
import "../../services"
import QtQuick

// Paragraph (or one sentence of a card) as words with furigana. Hover highlights the word, a click
// opens the word card (readView.pickWord) and selects the sentence (kana + English at the bottom). A click on
// a punctuation mark only selects the sentence; in cards it is passed on to the card (expand).
// One MouseArea for the whole paragraph (childAt) instead of one per word: chapters have thousands of words.
Item {
    id: wf

    required property var picker
    // Read view (LanguageReader): selection of word/sentence
    required property var view

    property var para: []
    // unique per paragraph/card, for selection and highlighting
    property string key: ""
    property real size: 20
    // Cards: a click next to a word expands the card (pass it on to the card)
    property bool passClicks: false
    // Words of this paragraph there? Depends on the whole word list, but is cheap. The words themselves
    // (items) are only rebuilt when THAT changes - before, every delivery (for
    // any chapter) rebuilt all visible paragraphs -> hang when opening
    readonly property bool wordsReady: {
        const w = LanguageReadingState.words;
        for (const sn of para) if (w[sn.ja] === undefined)
            return false;
        return true;
    }
    property var items: []

    function rebuild() {
        items = picker.wordItems(para);
    }

    onParaChanged: rebuild()
    onWordsReadyChanged: rebuild()
    Component.onCompleted: rebuild()
    property int hoverIdx: -1
    readonly property int pickIdx: view.pickKey === key ? view.pickIdx : -1
    readonly property int pickSi: view.pickKey === key ? view.pickSi : -1

    function idxAt(x, y) {
        const c = wfFlow.childAt(x, y);
        return c && c.index !== undefined ? c.index : -1;
    }

    implicitHeight: wfFlow.implicitHeight

    Flow {
        id: wfFlow

        width: parent.width
        spacing: 0

        Repeater {
            id: wfRep

            model: wf.items

            delegate: Item {
                id: wtok

                required property var modelData
                required property int index
                readonly property bool clickable: modelData.word !== null
                readonly property bool picked: index === wf.pickIdx
                readonly property bool inSentence: modelData.si === wf.pickSi
                readonly property bool hov: index === wf.hoverIdx && clickable
                // Room for furigana always reserved: switching only shows/hides them. Before,
                // every word was laid out again in every frame (thousands) -> hang
                readonly property real rubyH: Math.round(wf.size * 0.55)

                width: modelData.gap ? wf.size * 0.35 : wRow.implicitWidth + 2
                height: rubyH + Math.round(wf.size * 1.42) + 6

                // Background only behind the text (not behind the furigana)
                Rectangle {
                    x: 0
                    y: wtok.rubyH + 1
                    width: parent.width
                    height: Math.round(wf.size * 1.42)
                    radius: Theme.radiusXS
                    color: wtok.picked ? WalColors.withAlpha(WalColors.color4, 0.26) : wtok.hov ? WalColors.withAlpha(WalColors.color4, 0.13) : wtok.inSentence ? WalColors.withAlpha(WalColors.color4, 0.06) : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                        }

                    }

                }

                Row {
                    id: wRow

                    x: 1
                    y: 0

                    // Punctuation before/after is a normal part without a reading (fewer elements per word)
                    Repeater {
                        model: wtok.modelData.gap ? [] : (wtok.modelData.head ? [{
                            "t": wtok.modelData.head,
                            "r": ""
                        }] : []).concat(picker.segs(wtok.modelData.f, wtok.modelData.t)).concat(wtok.modelData.tail ? [{
                            "t": wtok.modelData.tail,
                            "r": ""
                        }] : [])

                        delegate: Item {
                            id: seg

                            required property var modelData

                            // Furigana may widen the word, but never stick out over neighbors. The width also applies
                            // with hidden furigana: otherwise the paragraph rewraps in every frame when switching
                            // and words jump sideways
                            width: Math.max(base.implicitWidth, modelData.r !== "" ? rubyT.implicitWidth : 0)
                            height: wtok.rubyH + base.implicitHeight

                            Text {
                                id: rubyT

                                visible: seg.modelData.r !== "" && picker.furiK > 0.01
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (1 - picker.furiK) * 6
                                text: seg.modelData.r
                                font.family: picker.jp
                                font.pixelSize: Math.max(9, Math.round(wf.size * 0.46))
                                color: wtok.picked ? WalColors.color4 : WalColors.withAlpha(WalColors.color4, 0.85)
                                opacity: picker.furiK
                            }

                            Text {
                                id: base

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: wtok.rubyH
                                text: seg.modelData.t
                                font.family: picker.jp
                                font.pixelSize: wf.size
                                color: wtok.picked ? WalColors.color4 : WalColors.color7
                            }

                        }

                    }

                }

            }

        }

    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: wf.passClicks
        cursorShape: wf.hoverIdx >= 0 && wf.items[wf.hoverIdx] && wf.items[wf.hoverIdx].word ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPositionChanged: (mouse) => {
            wf.hoverIdx = wf.idxAt(mouse.x, mouse.y);
        }
        onExited: wf.hoverIdx = -1
        onClicked: (mouse) => {
            const i = wf.idxAt(mouse.x, mouse.y);
            const it = i >= 0 ? wf.items[i] : null;
            if (it && it.word) {
                view.pickWord(wf.key, i, wfRep.itemAt(i), it.word, wf.para[it.si], it.si);
            } else if (wf.passClicks) {
                view.closePick();
                mouse.accepted = false;
            } else if (it) {
                view.pickSentence(wf.key, wf.para[it.si], it.si);
            }
        }
    }

}
