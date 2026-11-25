import "../../services"
import QtQuick

// ISBN hit: book data (NDL / OpenLibrary) and what you can do with it
Rectangle {
    id: ic

    required property var picker

    property var info: null
    readonly property bool free: !!(LanguageReadingState.results && LanguageReadingState.results.free && LanguageReadingState.results.free.length > 0)

    height: Math.max(icCover.height, icCol.implicitHeight) + 28
    radius: 18
    color: WalColors.withAlpha(WalColors.color7, 0.05)
    border.width: 1
    border.color: WalColors.withAlpha(WalColors.color7, 0.06)

    Rectangle {
        id: icCover

        x: 14
        y: 14
        width: 74
        height: 106
        radius: 8
        clip: true
        color: WalColors.withAlpha(WalColors.color4, 0.12)

        Image {
            id: icImg

            anchors.fill: parent
            source: ic.info ? LanguageAudioState.fileUrl(ic.info.cover) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Text {
            anchors.centerIn: parent
            visible: icImg.status !== Image.Ready
            text: "󰂺"
            font.family: picker.mono
            font.pixelSize: 26
            color: WalColors.withAlpha(WalColors.color4, 0.6)
        }

    }

    Column {
        id: icCol

        anchors.left: icCover.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 14
        spacing: 4

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: ic.info ? ic.info.title : ""
            font.family: picker.jp
            font.pixelSize: 15
            font.bold: true
            color: WalColors.color7
        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: ic.info ? [ic.info.author, ic.info.publisher, ic.info.year].filter((x) => {
                return !!x;
            }).join(" · ") : ""
            font.family: picker.jp
            font.pixelSize: 11
            color: WalColors.withAlpha(WalColors.color7, 0.55)
        }

        Text {
            text: ic.info ? "ISBN " + ic.info.isbn + " · " + ic.info.source : ""
            font.family: picker.mono
            font.pixelSize: 9
            color: WalColors.withAlpha(WalColors.color7, 0.35)
        }

        Text {
            width: parent.width
            topPadding: 6
            wrapMode: Text.Wrap
            text: ic.free ? "Public domain – full text available on Aozora Bunko:" : "No free full text (still under copyright). Do you have it as a DRM-free EPUB, e.g. bought? Put the file into " + Settings.shortPath(Settings.folder("books")) + " and it gets imported with furigana and rōmaji."
            font.family: picker.mono
            font.pixelSize: 10
            color: ic.free ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.6)
        }

        Row {
            topPadding: 4
            spacing: 6
            visible: !ic.free

            ToggleChip {
                picker: ic.picker
                label: "󰉋 Open import folder"
                onClicked: LanguageReadingState.openImportDir()
            }

            ToggleChip {
                picker: ic.picker
                visible: !!ic.info && !!ic.info.url
                label: "Catalog ↗"
                onClicked: Qt.openUrlExternally(ic.info.url)
            }

        }

    }

}
