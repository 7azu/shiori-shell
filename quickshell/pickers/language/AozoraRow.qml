import "../../services"
import QtQuick

Rectangle {
    id: ar

    required property var picker

    property bool selected: false
    property int rowIndex: -1
    required property var modelData
    readonly property bool have: LanguageReadingState.hasBook("aozora-" + modelData.id)
    readonly property bool loading: LanguageReadingState.busyWhat === "import" && LanguageReadingState.busyBook === "aozora-" + modelData.id

    height: 58
    // Same radius as the selection pill behind it; hover/selection only shows the pill
    radius: 16
    color: WalColors.withAlpha(WalColors.color7, 0.03)

    MouseArea {
        id: arMouse

        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            picker.hoverSelect(arMouse, mouse, "aozora", ar.rowIndex);
        }
    }

    Column {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - arBtn.width - 44
        spacing: 3

        Row {
            spacing: 8

            Text {
                text: ar.modelData.title
                font.family: picker.jp
                font.pixelSize: 14
                font.bold: true
                color: WalColors.color7
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: ar.modelData.subtitle !== ""
                text: ar.modelData.subtitle
                font.family: picker.jp
                font.pixelSize: 11
                color: WalColors.withAlpha(WalColors.color7, 0.5)
            }

        }

        Text {
            text: ar.modelData.author + (ar.modelData.kids ? "  ·  children's literature" : "") + (ar.modelData.modern ? "" : "  ·  old spelling 旧仮名")
            font.family: picker.jp
            font.pixelSize: 10
            color: WalColors.withAlpha(ar.modelData.modern ? WalColors.color7 : WalColors.color3, 0.55)
        }

    }

    ToggleChip {
        picker: ar.picker
        id: arBtn

        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        label: ar.have ? "Read ›" : ar.loading ? "Loading …" : "Import"
        on: ar.have
        opacity: LanguageReadingState.busy && !ar.loading && !ar.have ? 0.4 : 1
        onClicked: {
            if (ar.have) {
                LanguageReadingState.clearResults();
                picker.clearSearchText();
                LanguageReadingState.openBook("aozora-" + ar.modelData.id);
            } else if (!LanguageReadingState.busy) {
                LanguageReadingState.importAozora(ar.modelData.id);
            }
        }
    }

}
