import "../../common"
import "../../services"
import QtQuick

// Read tab: the shelf. Header with the book count, the status line of imports, the grid of books (last slot:
// add books) and the results of a search (ISBN card, Aozora Bunko list).
// Part of LanguageReader.qml (view = the Read tab, picker = core).
Item {
    id: shelf

    required property var picker
    required property var view
    property alias bookGrid: bookGrid
    property alias resultList: resultList

    anchors.fill: parent
    opacity: shelf.view.st * (1 - shelf.view.readerK)
    visible: opacity > 0.01
    transform: Translate {
        x: -shelf.view.readerK * 24
    }

    // ── Kopfzeile ──
    Item {
        id: shelfHead

        y: 12
        width: parent.width
        height: 34

        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: shelf.view.showResults ? (LanguageReadingState.results && LanguageReadingState.results.kind === "isbn" ? "ISBN" : "AOZORA BUNKO") : "LIBRARY"
                font.family: picker.mono
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
                color: WalColors.withAlpha(WalColors.color7, 0.5)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: shelf.view.showResults ? (LanguageReadingState.searching ? "searching …" : LanguageReadingState.resultsQuery) : shelf.view.shelfBooks.length + (shelf.view.shelfBooks.length === 1 ? " book" : " books")
                font.family: LanguageReadingState.resultsQuery !== "" && shelf.view.showResults ? picker.jp : picker.mono
                font.pixelSize: 11
                color: WalColors.withAlpha(WalColors.color7, 0.35)
            }

        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            ToggleChip {
                picker: shelf.picker
                visible: shelf.view.showResults
                label: "✕ Close"
                onClicked: LanguageReadingState.clearResults()
            }

            ToggleChip {
                picker: shelf.picker
                label: "󰉋 Import folder"
                onClicked: {
                    LanguageReadingState.openImportDir();
                    LanguageReadingState.scan();
                }
            }

        }

    }

    // ── Status (import, errors) ──
    Rectangle {
        id: shelfStatus

        readonly property bool failed: LanguageReadingState.error !== ""
        readonly property string msg: failed ? LanguageReadingState.error : LanguageReadingState.busy ? (LanguageReadingState.status || "Updating library …") : LanguageReadingState.status
        readonly property bool shown: msg !== "" && !(LanguageReadingState.busyWhat === "scan" && LanguageReadingState.status === "")

        anchors.top: shelfHead.bottom
        anchors.topMargin: shown ? 8 : 0
        width: parent.width
        height: shown ? statusText.implicitHeight + 16 : 0
        radius: 12
        clip: true
        color: failed ? WalColors.withAlpha(WalColors.color1, 0.12) : WalColors.withAlpha(WalColors.color4, 0.1)
        visible: height > 0.5

        Text {
            id: statusText

            x: 14
            y: 8
            width: parent.width - 50
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: (LanguageReadingState.busy ? "⟳  " : shelfStatus.failed ? "!  " : "✓  ") + shelfStatus.msg
            font.family: picker.mono
            font.pixelSize: 11
            color: shelfStatus.failed ? WalColors.color1 : WalColors.color4
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 8
            visible: !LanguageReadingState.busy
            text: "✕"
            font.pixelSize: 11
            color: WalColors.withAlpha(WalColors.color7, 0.5)

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    LanguageReadingState.error = "";
                    LanguageReadingState.status = "";
                }
            }

        }

        Behavior on height {
            Smooth {
            }

        }

    }

    // ── Books ──
    GridView {
        id: bookGrid

        anchors.top: shelfStatus.bottom
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
        width: parent.width
        // Columns by width (~190 px), card = cover in book format + title lines
        readonly property int columns: Math.max(3, Math.round(width / 190))

        cellWidth: Math.floor(width / columns)
        cellHeight: Math.round((cellWidth - 20) * 1.42) + 84
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: !shelf.view.showResults
        // last slot: import hint
        model: shelf.view.shelfBooks.concat([{
            "id": "",
            "add": true
        }])

        delegate: Item {
            id: cell

            required property var modelData
            required property int index

            width: bookGrid.cellWidth
            height: bookGrid.cellHeight

            BookCard {
                picker: shelf.picker
                anchors.fill: parent
                anchors.margins: 10
                book: cell.modelData
                visible: !cell.modelData.add
                cellIndex: cell.index
                selected: picker.kbList === "shelf" && picker.kbIndex === cell.index
            }

            AddCard {
                picker: shelf.picker
                anchors.fill: parent
                anchors.margins: 10
                visible: !!cell.modelData.add
                cellIndex: cell.index
                selected: picker.kbList === "shelf" && picker.kbIndex === cell.index
            }

        }

    }

    // ── Search results ──
    // Header (ISBN card, hints) outside the list: a ListView header slides
    // up and away if it only gets its height after the results
    Column {
        id: resultHead

        readonly property var res: LanguageReadingState.results
        readonly property bool isbn: !!res && res.kind === "isbn"
        readonly property int count: !res ? 0 : isbn ? (res.free || []).length : (res.results || []).length

        anchors.top: shelfStatus.bottom
        anchors.topMargin: 10
        width: parent.width
        spacing: 10
        visible: shelf.view.showResults

        Text {
            visible: LanguageReadingState.searching
            x: 14
            text: "Searching …"
            font.family: picker.mono
            font.pixelSize: 12
            color: WalColors.withAlpha(WalColors.color7, 0.45)
        }

        IsbnCard {
            picker: shelf.picker
            visible: resultHead.isbn
            width: parent.width
            info: resultHead.isbn ? resultHead.res.book : null
        }

        Text {
            visible: !!resultHead.res && resultHead.count === 0 && !resultHead.isbn
            x: 14
            width: parent.width - 28
            wrapMode: Text.Wrap
            text: "Nothing found in the Aozora catalog. Aozora Bunko only has public-domain works (mostly before 1970). For an ISBN book, enter the 10- or 13-digit number."
            font.family: picker.mono
            font.pixelSize: 11
            color: WalColors.withAlpha(WalColors.color7, 0.5)
        }

    }

    ListView {
        id: resultList

        anchors.top: resultHead.bottom
        anchors.topMargin: resultHead.implicitHeight > 0 ? 10 : 0
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        visible: shelf.view.showResults
        model: !resultHead.res ? [] : resultHead.isbn ? resultHead.res.free : resultHead.res.results

        SelectionPill {
            picker: shelf.picker
            view: resultList
            listName: "aozora"
            stride: 62
            rowH: 58
        }

        delegate: AozoraRow {
            picker: shelf.picker
            required property int index

            width: resultList.width
            rowIndex: index
            selected: picker.kbList === "aozora" && picker.kbIndex === index
        }

    }

}
