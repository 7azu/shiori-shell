import "../../common"
import "../../services"
import QtQuick

// Read tab, reader: the row at the bottom. Switches for furigana, reading and translation (a click translates
// a chapter that has none yet), on the right the read chapters, "Read" and "Next".
// Part of LanguageReader.qml (view = the Read tab, picker = core).
Item {
    id: readFooter

    required property var picker
    required property var view

    anchors.bottom: parent.bottom
    anchors.bottomMargin: 6
    width: parent.width
    height: 34

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        ToggleChip {
            picker: readFooter.picker
            visible: LanguageReadingState.isJapanese
            label: "ふりがな"
            jpLabel: true
            on: LanguageReadingState.showFurigana
            onClicked: LanguageReadingState.toggle("showFurigana")
        }

        ToggleChip {
            picker: readFooter.picker
            visible: readFooter.view.hasReading
            label: LanguageReadingState.isJapanese ? "かな" : "Latin"
            jpLabel: LanguageReadingState.isJapanese
            on: LanguageReadingState.showKana
            onClicked: LanguageReadingState.toggle("showKana")
        }

        // Imported chapters without a translation: a click translates (backend from scripts/jp_translate.py)
        // and turns it on
        ToggleChip {
            picker: readFooter.picker
            label: !readFooter.view.flow ? "Translation" : readFooter.view.translating ? "Translating …" : readFooter.view.canTranslate ? "→ English" : "English"
            on: LanguageReadingState.showTranslation && !readFooter.view.canTranslate
            opacity: LanguageReadingState.busy && readFooter.view.canTranslate && !readFooter.view.translating ? 0.4 : 1
            onClicked: {
                if (readFooter.view.canTranslate) {
                    LanguageReadingState.translate();
                    if (!LanguageReadingState.showTranslation)
                        LanguageReadingState.toggle("showTranslation");

                } else {
                    LanguageReadingState.toggle("showTranslation");
                }
            }
        }

    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: LanguageReadingState.readCount + " / " + LanguageReadingState.chapters.length
            font.family: picker.mono
            font.pixelSize: 10
            color: WalColors.withAlpha(WalColors.color7, 0.4)
        }

        ToggleChip {
            picker: readFooter.picker
            label: "Read"
            star: true
            on: readFooter.view.currentRead
            onClicked: {
                if (LanguageReadingState.currentId !== "")
                    LanguageReadingState.setRead(LanguageReadingState.currentId, !readFooter.view.currentRead);

            }
        }

        ToggleChip {
            picker: readFooter.picker
            label: "Next ›"
            enabled: LanguageReadingState.currentIndex < LanguageReadingState.chapters.length - 1
            opacity: enabled ? 1 : 0.35
            onClicked: {
                if (readFooter.view.flow && !readFooter.view.currentRead)
                    LanguageReadingState.setRead(LanguageReadingState.currentId, true);

                LanguageReadingState.step(1);
            }
        }

    }

}
