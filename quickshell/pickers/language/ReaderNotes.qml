import "../../common"
import "../../services"
import QtQuick

// Read tab, reader: a text from the notes as sentence cards (number, sentence, reading and translation on a
// click or with the switches), below them the vocabulary of the text.
// Part of LanguageReader.qml (view = the Read tab, picker = core).
ListView {
    id: sentenceList

    required property var picker
    required property var view

    width: parent.width
    clip: true
    spacing: 2
    boundsBehavior: Flickable.StopAtBounds
    visible: !sentenceList.view.flow
    model: !sentenceList.view.flow && sentenceList.view.current && sentenceList.view.contentReady ? sentenceList.view.current.sentences : []
    opacity: sentenceList.view.swapK

    NumberAnimation {
        id: sentenceListScroll

        target: sentenceList
        property: "contentY"
        duration: 280
        easing.type: Easing.OutCubic
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            return sentenceList.view.wheelScroll(sentenceList, sentenceListScroll, event);
        }
    }

    onMovementStarted: {
        sentenceListScroll.stop();
        sentenceList.view.pickedWord = null;
        sentenceList.view.pickIdx = -1;
    }
    // The header is only measured correctly after the build -> then to the start
    onModelChanged: Qt.callLater(positionViewAtBeginning)
    onVisibleChanged: {
        if (visible)
            Qt.callLater(positionViewAtBeginning);

    }

    header: Item {
        width: sentenceList.width
        height: titleCol.implicitHeight + 14

        Column {
            id: titleCol

            x: 14
            width: parent.width - 28
            spacing: 4

            Ruby {
                picker: sentenceList.picker
                width: parent.width
                text: sentenceList.view.current ? sentenceList.view.current.title : ""
                size: 24
                bold: true
            }

            Text {
                text: sentenceList.view.current && sentenceList.view.current.sentences ? sentenceList.view.current.titleDe + " · " + sentenceList.view.current.sentences.length + (sentenceList.view.current.fromNotes ? " entries from your notes" : " sentences") : ""
                font.family: picker.mono
                font.pixelSize: 10
                color: WalColors.withAlpha(WalColors.color7, 0.45)
            }

        }

    }

    delegate: Rectangle {
        id: sent

        required property var modelData
        required property int index
        property bool open: false
        readonly property bool showRo: LanguageReadingState.showKana || open
        readonly property bool showDe: (LanguageReadingState.showTranslation || open) && !!modelData.de

        width: sentenceList.width
        height: sentCol.implicitHeight + 18
        radius: 16
        // remember the last height: only the change is reported (see heightDelta)
        property real lastH: -1
        Component.onCompleted: lastH = height
        onHeightChanged: {
            if (lastH >= 0)
                sentenceList.view.heightDelta(sentenceList, sent, index, height - lastH);

            lastH = height;
        }
        color: open ? WalColors.withAlpha(WalColors.color4, 0.08) : WalColors.withAlpha(WalColors.color7, sentMouse.containsMouse ? 0.05 : 0)

        transform: Translate {
            y: (1 - sentenceList.view.swapK) * (10 + sent.index * 4)
        }

        Rectangle {
            id: badge

            x: 12
            y: 9 + 22 * 0.55
            width: 24
            height: 24
            radius: height / 2
            color: WalColors.withAlpha(WalColors.color4, sent.open ? 0.28 : 0.14)

            Text {
                anchors.centerIn: parent
                text: sent.modelData.sp || (sent.index + 1)
                font.family: picker.mono
                font.pixelSize: 10
                font.bold: true
                color: WalColors.color4
            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        Column {
            id: sentCol

            x: 48
            y: 9
            width: parent.width - 60
            spacing: 0

            WordFlow {
                view: sentenceList.view
                picker: sentenceList.picker
                width: parent.width
                para: [sent.modelData]
                key: "c" + sent.index
                size: 22
                passClicks: true
            }

            Reveal {
                picker: sentenceList.picker
                shown: sent.showRo
                text: LanguageReadingState.kanaText(sent.modelData.ja)
                family: picker.jp
                pixelSize: 13
                color: WalColors.withAlpha(WalColors.color4, 0.85)
            }

            Reveal {
                picker: sentenceList.picker
                shown: sent.showDe
                text: sent.modelData.de || ""
                pixelSize: 12
                color: WalColors.withAlpha(WalColors.color7, 0.6)
            }

        }

        MouseArea {
            id: sentMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sent.open = !sent.open
        }

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    // Vocabulary for the text
    footer: Item {
        id: wordsFooter

        readonly property var words: sentenceList.view.current && sentenceList.view.current.words ? sentenceList.view.current.words : []

        width: sentenceList.width
        height: words.length > 0 ? wordsCol.implicitHeight + 24 : 8
        visible: words.length > 0

        Column {
            id: wordsCol

            x: 14
            y: 14
            width: parent.width - 28
            spacing: 8

            Text {
                text: "WORDS"
                font.family: picker.mono
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.5
                color: WalColors.withAlpha(WalColors.color7, 0.4)
            }

            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: wordsFooter.words

                    delegate: Rectangle {
                        required property var modelData

                        width: wordRow.implicitWidth + 20
                        height: 30
                        radius: 10
                        color: WalColors.withAlpha(WalColors.color7, 0.05)
                        border.width: 1
                        border.color: WalColors.withAlpha(WalColors.color7, 0.06)

                        Row {
                            id: wordRow

                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: LanguageReadingState.plainText(modelData.ja)
                                font.family: picker.jp
                                font.pixelSize: 13
                                color: WalColors.color7
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: text !== LanguageReadingState.plainText(modelData.ja)
                                text: LanguageReadingState.kanaText(modelData.ja)
                                font.family: picker.jp
                                font.pixelSize: 11
                                color: WalColors.withAlpha(WalColors.color4, 0.85)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.de
                                font.family: picker.mono
                                font.pixelSize: 10
                                color: WalColors.withAlpha(WalColors.color7, 0.55)
                            }

                        }

                    }

                }

            }

        }

    }

}
