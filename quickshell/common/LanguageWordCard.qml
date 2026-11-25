import "../services"
import QtQuick

// Explanation of a Japanese word (video subtitles and Read tab): reading, headword, the form from
// the sentence, part of speech as a chip and meanings from JMdict (looked up in advance in scripts/jp_subs.py).
// word = {t, f?, d?: {w, r, p, g[]}}. Only the content; the host does surface, position and animation.
Column {
    id: card

    property var word: null
    property string hint: ""
    readonly property var d: word && word.d ? word.d : null
    readonly property string jp: "Noto Sans CJK JP"

    spacing: Theme.px(10)

    Row {
        spacing: Theme.px(12)

        Column {
            Text {
                visible: text !== ""
                text: card.d ? card.d.r : ""
                font.family: card.jp
                font.pixelSize: Theme.sizeBody
                color: WalColors.color4
            }

            Text {
                text: card.d ? card.d.w : (card.word ? card.word.t : "")
                font.family: card.jp
                font.pixelSize: Theme.px(30)
                color: Theme.text
            }

        }

        // Conjugated in the text -> the base form stands on top, the form from the sentence here next to it
        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.px(6)
            visible: !!card.word && !!card.d && card.word.t !== card.d.w
            text: card.word ? "← " + card.word.t : ""
            font.family: card.jp
            font.pixelSize: Theme.sizeLead
            color: Theme.textFaint
        }

    }

    // Part of speech as a chip
    Rectangle {
        visible: !!card.d && card.d.p !== ""
        width: posText.implicitWidth + Theme.px(16)
        height: Theme.chipHeight
        radius: height / 2
        color: WalColors.withAlpha(WalColors.color4, 0.14)

        Text {
            id: posText

            anchors.centerIn: parent
            text: card.d ? card.d.p.toUpperCase() : ""
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.letterSpacing: 0.6
            color: WalColors.color4
        }

    }

    Repeater {
        model: card.d ? card.d.g : []

        delegate: Row {
            required property var modelData
            required property int index

            width: card.width
            spacing: Theme.px(10)

            Text {
                id: num

                text: (parent.index + 1) + "."
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeBody
                font.features: Theme.tabular
                color: Theme.textFaint
            }

            Text {
                width: parent.width - num.width - parent.spacing
                text: parent.modelData
                wrapMode: Text.WordWrap
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLabel
                color: parent.index === 0 ? Theme.text : Theme.textDim
            }

        }

    }

    Text {
        visible: !!card.word && !card.d
        text: "No dictionary entry"
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeBody
        color: Theme.textFaint
    }

    Text {
        visible: card.hint !== ""
        text: card.hint
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeSmall
        color: Theme.textFaint
    }

}
