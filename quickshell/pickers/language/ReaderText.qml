import "../../common"
import "../../services"
import QtQuick

// Read tab, reader: a book chapter as running text, one row per paragraph (clickable words, below them the
// reading and the translation when switched on).
// The chapter header is the first row of the model (no ListView header: it slides
// up and away when its height changes, e.g. when the English title fades in)
// Part of LanguageReader.qml (view = the Read tab, picker = core).
ListView {
    id: flowList

    required property var picker
    required property var view

    width: parent.width
    clip: true
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    visible: flowList.view.flow
    model: flowList.view.flow && flowList.view.current && flowList.view.contentReady ? [{
        "head": true
    }].concat(flowList.view.current.paras || []).concat([{
        "foot": true
    }]) : []
    opacity: flowList.view.swapK
    // do not prebuild too much invisibly: every paragraph is hundreds of elements
    cacheBuffer: 300

    NumberAnimation {
        id: flowListScroll

        target: flowList
        property: "contentY"
        duration: 280
        easing.type: Easing.OutCubic
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            return flowList.view.wheelScroll(flowList, flowListScroll, event);
        }
    }

    onMovementStarted: {
        flowListScroll.stop();
        flowList.view.pickedWord = null;
        flowList.view.pickIdx = -1;
    }

    // Limit the line length (~42 characters), column centered
    readonly property real side: Math.round(Math.max(14, (width - (picker.readBig ? 1150 : 900)) / 2))

    delegate: Item {
        id: paraItem

        required property var modelData
        required property int index
        // Paragraph arrays arrive as sequence wrappers (Array.isArray is false for them)
        readonly property bool isPara: !modelData.head && !modelData.foot
        readonly property bool hasEn: isPara && modelData.some((s) => {
            return !!s.en;
        })

        width: flowList.width
        height: isPara ? paraCol.implicitHeight + 24 : modelData.head ? flowTitle.implicitHeight + 26 : 56
        // remember the last height: only the change is reported (see heightDelta)
        property real lastH: -1
        Component.onCompleted: lastH = height
        onHeightChanged: {
            if (lastH >= 0)
                flowList.view.heightDelta(flowList, paraItem, index, height - lastH);

            lastH = height;
        }

        transform: Translate {
            y: (1 - flowList.view.swapK) * (10 + Math.min(paraItem.index, 6) * 5)
        }

        Column {
            id: flowTitle

            x: flowList.side
            width: parent.width - 2 * flowList.side
            spacing: 4
            visible: !!paraItem.modelData.head

            Text {
                text: flowList.view.book ? LanguageReadingState.plainText(flowList.view.book.title) + "  ·  " + (LanguageReadingState.currentIndex + 1) + " / " + LanguageReadingState.chapters.length : ""
                font.family: picker.jp
                font.pixelSize: 11
                color: WalColors.withAlpha(WalColors.color7, 0.4)
            }

            Ruby {
                picker: flowList.picker
                width: parent.width
                text: flowList.view.current ? flowList.view.current.title : ""
                size: 24
                bold: true
            }

            Reveal {
                picker: flowList.picker
                shown: LanguageReadingState.showTranslation && !!flowList.view.current && !!flowList.view.current.en
                text: flowList.view.current && flowList.view.current.en ? flowList.view.current.en : ""
                pixelSize: 11
                color: WalColors.withAlpha(WalColors.color7, 0.5)
            }

            Text {
                visible: !!flowList.view.book && !!flowList.view.book.note
                width: parent.width
                wrapMode: Text.Wrap
                text: flowList.view.book && flowList.view.book.note ? "ⓘ " + flowList.view.book.note : ""
                font.family: picker.mono
                font.pixelSize: 10
                color: WalColors.withAlpha(WalColors.color3, 0.8)
            }

            Text {
                visible: !!flowList.view.current && flowList.view.current.loading === true
                text: "Loading chapter …"
                font.family: picker.mono
                font.pixelSize: 11
                color: WalColors.withAlpha(WalColors.color7, 0.45)
            }

        }

        Column {
            id: paraCol

            x: flowList.side
            width: parent.width - 2 * flowList.side
            // 0: columns skip elements with height 0 together with the spacing - otherwise the kana/English row
            // caused a 2 px jump per paragraph when expanding/collapsing (the spacing is inside the Reveal)
            spacing: 0
            visible: paraItem.isPara

            WordFlow {
                view: flowList.view
                picker: flowList.picker
                width: parent.width
                size: picker.readBig ? 26 : 22
                para: paraItem.isPara ? paraItem.modelData : []
                key: "p" + paraItem.index
            }

            // Sentence as reading (hiragana, katakana words stay katakana) or, in other languages, as
            // Latin transliteration (sentences joined with spaces there)
            Reveal {
                picker: flowList.picker
                shown: LanguageReadingState.showKana && paraItem.isPara && flowList.view.hasReading
                text: paraItem.isPara ? paraItem.modelData.map((s) => {
                    return LanguageReadingState.readingOf(s);
                }).join(LanguageReadingState.isJapanese ? "" : " ") : ""
                family: picker.jp
                pixelSize: picker.readBig ? 15 : 13
                color: WalColors.withAlpha(WalColors.color4, 0.85)
            }

            Reveal {
                picker: flowList.picker
                shown: LanguageReadingState.showTranslation && paraItem.hasEn
                text: paraItem.isPara ? paraItem.modelData.map((s) => {
                    return s.en || "";
                }).join(" ") : ""
                pixelSize: 12
                color: WalColors.withAlpha(WalColors.color7, 0.6)
            }

        }

        Text {
            anchors.centerIn: parent
            visible: !!paraItem.modelData.foot && flowList.count > 3
            text: LanguageReadingState.currentIndex < LanguageReadingState.chapters.length - 1 ? "— End of chapter · “Next ›” marks it as read —" : "— End of book —"
            font.family: picker.mono
            font.pixelSize: 10
            color: WalColors.withAlpha(WalColors.color7, 0.3)
        }

    }

}
