import "../../common"
import "../../services"
import QtQuick

// Read tab, reader: the row above the text. Back to the shelf, the chapters as chips (the current one is kept in
// the middle), the size button and the reading progress in the chapter as a thin line below.
// Part of LanguageReader.qml (view = the Read tab, picker = core).
Item {
    id: chapterBar

    required property var picker
    required property var view

    width: parent.width
    // Down to the lower edge of the chips: the text starts below it
    height: textList.y + textList.height

    // ── Back + chapter choice ──
    ToggleChip {
        picker: chapterBar.picker
        id: backChip

        y: 15
        label: "‹ Shelf"
        onClicked: LanguageReadingState.closeBook()
    }

    // Window even bigger (almost the whole screen, bigger font); the reading position stays
    ToggleChip {
        picker: chapterBar.picker
        id: bigChip

        anchors.right: parent.right
        y: 15
        label: LanguageReadingState.big ? "󰊔 Smaller" : "󰊓 Bigger"
        on: LanguageReadingState.big
        onClicked: {
            const l = chapterBar.view.activeList;
            chapterBar.view.keepIdx = l.indexAt(l.width / 2, l.contentY + 1);
            LanguageReadingState.toggle("big");
            keepTimer.restart();
        }
    }

    // after rewrapping to the new width back to the same paragraph (invisible while the
    // panel is still growing: morphGate)
    Timer {
        id: keepTimer

        interval: 60
        onTriggered: {
            if (chapterBar.view.keepIdx > 0)
                chapterBar.view.activeList.positionViewAtIndex(chapterBar.view.keepIdx, ListView.Beginning);

        }
    }

    // Flickable + Row instead of ListView: all chips are there, the width is exact
    // (ListView estimates it and could not fully show the last chip)
    Flickable {
        id: textList

        // Bring the current chip to the middle (at the edge the strip stays at its stop)
        function showCurrent() {
            const c = chipRepeater.itemAt(LanguageReadingState.currentIndex);
            if (!c)
                return ;

            const max = Math.max(0, contentWidth - width);
            contentX = Math.max(0, Math.min(max, c.x + c.width / 2 - width / 2));
        }

        anchors.left: backChip.right
        anchors.leftMargin: 8
        anchors.right: bigChip.left
        anchors.rightMargin: 8
        y: 12
        height: 34
        contentWidth: chipsRow.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onContentWidthChanged: Qt.callLater(showCurrent)
        onWidthChanged: Qt.callLater(showCurrent)

        Connections {
            function onCurrentIndexChanged() {
                Qt.callLater(textList.showCurrent);
            }

            target: LanguageReadingState
        }

        Behavior on contentX {
            enabled: !textList.moving

            Smooth {
                duration: 360
            }

        }

        Row {
            id: chipsRow

            spacing: 8

            Repeater {
                id: chipRepeater

                model: LanguageReadingState.chapters

                delegate: Rectangle {
                    id: chip

                    required property var modelData
                    required property int index
                    readonly property bool active: index === LanguageReadingState.currentIndex
                    readonly property bool done: LanguageReadingState.readIds[LanguageReadingState.chapterId(chapterBar.view.book, index)] !== undefined

                    width: chipRow.implicitWidth + 26
                    height: 34
                    radius: height / 2
                    color: active ? WalColors.withAlpha(WalColors.color4, 0.2) : WalColors.withAlpha(WalColors.color7, chipMouse.containsMouse ? 0.1 : 0.05)
                    border.width: 1
                    border.color: active ? WalColors.withAlpha(WalColors.color4, 0.5) : "transparent"

                    Row {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: 7

                        // Read: small sparkle (visual language) instead of a check mark
                        Sparkle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: chip.done
                            size: 3.5
                            rays: 1.7
                            color: WalColors.color4
                            glowColor: WalColors.vividAccent
                            twinkle: 0.8
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !chip.done && !!chip.modelData.fromNotes
                            text: "󰠮"
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.bold: true
                            color: chip.done ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.45)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 200)
                            elide: Text.ElideRight
                            text: LanguageReadingState.plainText(chip.modelData.title)
                            font.family: picker.jp
                            font.pixelSize: 13
                            color: chip.active ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.65)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: text !== ""
                            text: String(chip.modelData.level || "").toUpperCase()
                            font.family: picker.mono
                            font.pixelSize: 8
                            font.bold: true
                            font.letterSpacing: 1
                            color: WalColors.withAlpha(chip.active ? WalColors.color4 : WalColors.color7, 0.5)
                        }

                    }

                    MouseArea {
                        id: chipMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LanguageReadingState.select(chip.index)
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

            }

        }

    }

    EdgeFade {
        anchors.left: textList.left
        y: textList.y
        height: textList.height
        visible: textList.contentX > 1
    }

    EdgeFade {
        anchors.right: textList.right
        y: textList.y
        height: textList.height
        rightSide: true
        visible: textList.contentWidth - textList.contentX - textList.width > 1
    }

    // ── Reading progress in the chapter: thin line below the chapter chips ──
    Rectangle {
        id: progressTrack

        readonly property var l: chapterBar.view.activeList
        readonly property real p: l && l.contentHeight > l.height + 1 ? Math.max(0, Math.min(1, (l.contentY - l.originY) / (l.contentHeight - l.height))) : 0

        anchors.top: textList.bottom
        anchors.topMargin: 5
        width: parent.width
        height: 2
        radius: 1
        color: WalColors.withAlpha(WalColors.color7, 0.06)
        opacity: l && l.contentHeight > l.height + 1 ? 1 : 0

        Rectangle {
            width: Math.max(height, parent.width * progressTrack.p)
            height: parent.height
            radius: 1
            color: WalColors.withAlpha(WalColors.color4, 0.7)
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
            }

        }

    }

}
