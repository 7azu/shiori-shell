import "../../common"
import "../../services"
import QtQuick

// Last slot on the shelf: how books get added
Item {
    id: addCard

    required property var picker

    // Selection on the shelf, as in BookCard
    property bool selected: false
    property int cellIndex: -1

    Rectangle {
        width: parent.width
        height: Math.round(width * 1.42)
        radius: 12
        scale: (addCard.selected ? 1.05 : 1) * (addMouse.pressed ? 0.96 : 1)
        color: WalColors.withAlpha(WalColors.color7, addCard.selected ? 0.06 : 0.02)
        border.width: addCard.selected ? 2 : 1.5
        border.color: addCard.selected ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.1)

        Behavior on scale {
            Springy {
            }

        }

        Behavior on border.color {
            ColorAnimation {
                duration: 180
            }

        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 28
            spacing: 10

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "＋"
                font.pixelSize: 34
                color: WalColors.withAlpha(WalColors.color7, addCard.selected ? 0.8 : 0.45)
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Add a book"
                font.family: picker.mono
                font.pixelSize: 12
                font.bold: true
                color: WalColors.withAlpha(WalColors.color7, 0.7)
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "Choose EPUB, TXT or PDF files in yazi, they are copied into " + Settings.shortPath(LanguageReadingState.importDir) + (LanguageReadingState.isJapanese ? "\n\nor type an ISBN / title above + Enter" : "")
                font.family: picker.mono
                font.pixelSize: 9
                lineHeight: 1.15
                color: WalColors.withAlpha(WalColors.color7, 0.4)
            }

        }

        MouseArea {
            id: addMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: (mouse) => {
                picker.hoverSelect(addMouse, mouse, "shelf", addCard.cellIndex);
            }
            onClicked: LanguageReadingState.pickBooks()
        }

    }

}
