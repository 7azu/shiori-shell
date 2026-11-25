import "../../common"
import "../../services"
import QtQuick

// Cover for books without an image: color from the book ID, title vertical (縦書き) as on a book spine,
// English/author subtitle at the bottom
Rectangle {
    id: cov

    required property var picker

    property var book: null
    readonly property var coverColors: [WalColors.color1, WalColors.color2, WalColors.color3, WalColors.color4, WalColors.color5, WalColors.color6]
    readonly property color tint: {
        const id = book ? String(book.id) : "";
        let h = 0;
        for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) % 9973
        return coverColors[h % coverColors.length];
    }
    // Vertically set characters: long vowel/brackets/punctuation in their vertical forms
    readonly property var chars: {
        const map = {
            "ー": "丨",
            "「": "﹁",
            "」": "﹂",
            "『": "﹃",
            "』": "﹄",
            "、": "︑",
            "。": "︒",
            "・": "・",
            "（": "︵",
            "）": "︶",
            "：": "︰",
            " ": "",
            "　": ""
        };
        const t = Array.from(LanguageReadingState.plainText(book ? book.title : "")).map((c) => {
            return map[c] !== undefined ? map[c] : c;
        }).filter((c) => {
            return c !== "";
        });
        return t.length > 11 ? t.slice(0, 10).concat(["︙"]) : t;
    }

    radius: 12
    gradient: Gradient {
        GradientStop {
            position: 0
            color: Qt.tint(WalColors.color0, WalColors.withAlpha(cov.tint, 0.42))
        }

        GradientStop {
            position: 1
            color: Qt.tint(WalColors.color0, WalColors.withAlpha(cov.tint, 0.16))
        }

    }

    // Book spine edge
    Rectangle {
        x: 10
        width: 2
        height: parent.height
        color: WalColors.withAlpha(cov.tint, 0.35)
    }

    // Title vertical, starting at the top right as on a book cover. Fixed line height per character
    // (otherwise the CJK font brings ~1.45 em line spacing)
    readonly property real glyph: Math.round(Math.min(width * 0.17, (height - 70) / (Math.max(5, chars.length) * 1.06)))

    Column {
        anchors.right: parent.right
        anchors.rightMargin: Math.round(parent.width * 0.12)
        y: 34
        spacing: 0

        Repeater {
            model: cov.chars

            delegate: Text {
                required property string modelData

                anchors.horizontalCenter: parent.horizontalCenter
                height: Math.round(cov.glyph * 1.06)
                verticalAlignment: Text.AlignVCenter
                text: modelData
                font.family: picker.jp
                font.pixelSize: cov.glyph
                font.bold: true
                color: WalColors.color7
            }

        }

    }

    // small seal at the bottom left + subtitle
    Column {
        x: 22
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        width: parent.width * 0.5
        spacing: 6

        Rectangle {
            width: 18
            height: 18
            radius: 4
            color: WalColors.withAlpha(cov.tint, 0.85)

            Text {
                anchors.centerIn: parent
                text: cov.book && cov.book.kind === "cards" ? "練" : "読"
                font.family: picker.jp
                font.pixelSize: 11
                font.bold: true
                color: WalColors.color0
            }

        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: cov.book ? cov.book.subtitle || "" : ""
            font.family: picker.mono
            font.pixelSize: 9
            lineHeight: 1.1
            color: WalColors.withAlpha(WalColors.color7, 0.6)
        }

    }

}
