import "../../services"
import QtQuick

// Japanese text with furigana: {kanji|reading} gets the reading small above it.
// Kana one by one, so Flow can break anywhere; space = small gap
Flow {
    id: ruby

    required property var picker

    property string text: ""
    property real size: 20
    property bool bold: false

    spacing: 0

    Repeater {
        model: LanguageReadingState.tokens(ruby.text)

        delegate: Item {
            id: tok

            required property var modelData
            readonly property bool hasRuby: modelData.r !== ""

            // Width always incl. the reading (also when hidden): otherwise the text rewraps in every frame
            // when switching and words jump sideways. Height not rounded -> even movement.
            width: modelData.gap ? ruby.size * 0.35 : Math.max(base.implicitWidth, hasRuby ? rubyText.implicitWidth : 0)
            // Room for furigana always reserved: switching is a pure show/hide (no layout)
            height: Math.round(ruby.size * 0.55) + base.implicitHeight

            Text {
                id: rubyText

                visible: tok.hasRuby && picker.furiK > 0.01
                anchors.horizontalCenter: parent.horizontalCenter
                y: (1 - picker.furiK) * 6
                text: tok.modelData.r
                font.family: picker.jp
                font.pixelSize: Math.max(9, Math.round(ruby.size * 0.46))
                color: WalColors.withAlpha(WalColors.color4, 0.9)
                opacity: picker.furiK
            }

            Text {
                id: base

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                text: tok.modelData.t
                font.family: picker.jp
                font.pixelSize: ruby.size
                font.bold: ruby.bold
                color: WalColors.color7
            }

        }

    }

}
