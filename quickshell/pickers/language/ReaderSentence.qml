import "../../common"
import "../../services"
import QtQuick

// Read tab, reader: the selected sentence at the bottom, with its reading (kana, rōmaji or transliteration)
// and English. Grows out of the footer (k).
// Part of LanguageReader.qml (view = the Read tab, picker = core).
Rectangle {
    id: sentCard

    required property var picker
    required property var view

    readonly property var s: sentCard.view.selected
    property real k: s ? 1 : 0

    width: parent.width
    height: (cardCol.implicitHeight + 20) * k
    radius: 16
    clip: true
    visible: sentCard.view.flow && k > 0.01
    color: WalColors.withAlpha(WalColors.color4, 0.08)
    border.width: 1
    border.color: WalColors.withAlpha(WalColors.color4, 0.22)

    Column {
        id: cardCol

        x: 16
        y: 10 + (1 - sentCard.k) * 12
        width: parent.width - 52
        spacing: 4
        opacity: sentCard.k

        Ruby {
            picker: sentCard.picker
            width: parent.width
            text: sentCard.s ? sentCard.s.ja : ""
            size: 16
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            visible: text !== ""
            text: LanguageReadingState.readingOf(sentCard.s)
            font.family: picker.jp
            font.pixelSize: 13
            color: WalColors.withAlpha(WalColors.color4, 0.9)
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: sentCard.s ? (sentCard.s.en || (sentCard.view.translating ? "Translating …" : sentCard.view.canTranslate ? "No translation yet – use “→ English” below" : "No translation yet")) : ""
            font.family: picker.mono
            font.pixelSize: 12
            font.italic: !!sentCard.s && !sentCard.s.en
            color: WalColors.withAlpha(WalColors.color7, sentCard.s && sentCard.s.en ? 0.75 : 0.4)
        }

    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 10
        text: "✕"
        font.pixelSize: 12
        color: WalColors.withAlpha(WalColors.color7, 0.5)

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            onClicked: sentCard.view.closePick()
        }

    }

    Behavior on k {
        Smooth {
            duration: 260
        }

    }

}
