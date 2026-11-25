import "../../common"
import "../../services"
import QtQuick
import Quickshell.Widgets

// Search results (YouTube) in the list tab of the language picker.
// Part of LanguagePicker.qml (picker = core).
Item {
    id: searchView

    required property var picker
    property alias searchList: searchList

    x: Math.round((parent.width - width) / 2)
    width: picker.listenWidth - 2 * picker.pad
    height: picker.searchH
    opacity: (picker.filter === "library" ? picker.searchProgress * (picker.switching ? 1 : picker.morphGate) : picker.searchProgress) * (picker.choosing ? 0 : 1)
    visible: opacity > 0.01

    readonly property real rowH: 64
    readonly property real headH: 40

    // Header: number of hits on the left, on the right the hint that it always downloads as a video
    Text {
        x: 12
        y: 12
        text: LanguageAudioState.isSearching && !LanguageAudioState.isLoadingMore ? "SEARCHING YOUTUBE" : "YOUTUBE  ·  " + picker.results.length
        color: Theme.textFaint
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeMicro
        font.weight: Font.DemiBold
        font.letterSpacing: Theme.microSpacing
        font.features: Theme.tabular
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 12
        text: LanguageAudioState.languageCode !== "" ? "Downloads as video with subtitles" : "Downloads as video"
        color: Theme.textFaint
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeSmall
    }

    ListView {
        id: searchList

        anchors.top: parent.top
        anchors.topMargin: searchView.headH
        width: parent.width
        height: Math.min(picker.results.length * searchView.rowH + picker.moreH, 448)
        model: picker.results
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: false

        NumberAnimation {
            id: searchScroll

            target: searchList
            property: "contentY"
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.outQuint
        }

        SelectionPill {
            picker: searchView.picker
            view: searchList
            listName: "youtube"
            stride: searchView.rowH
            rowH: searchView.rowH
        }

        delegate: Item {
            id: searchRow

            required property var modelData
            required property int index
            readonly property bool hot: picker.kbList === "youtube" && picker.kbIndex === index

            width: searchList.width
            height: searchView.rowH

            ClippingRectangle {
                id: thumb

                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 82
                height: 46
                radius: 9
                color: Theme.groupFill

                Image {
                    anchors.fill: parent
                    source: searchRow.modelData.thumbnail
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }

            }

            Column {
                anchors.left: thumb.right
                anchors.leftMargin: 14
                anchors.right: dlBtn.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    width: parent.width
                    text: searchRow.modelData.title
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                    font.weight: Font.Medium
                }

                Text {
                    width: parent.width
                    text: [searchRow.modelData.uploader, searchRow.modelData.duration].filter(Boolean).join("  ·  ")
                    color: Theme.textFaint
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    font.features: Theme.tabular
                }

            }

            MouseArea {
                id: searchMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onPositionChanged: (mouse) => {
                    picker.hoverSelect(searchMouse, mouse, "youtube", searchRow.index);
                }
            }

            // Download: glass button, in the accent color when selected (Enter does the same)
            Rectangle {
                id: dlBtn

                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: height / 2
                opacity: LanguageAudioState.isDownloading ? 0.35 : 1
                color: dlMouse.containsMouse ? Theme.accent : searchRow.hot ? Theme.glassHover : Theme.glass

                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF01DA)
                    color: dlMouse.containsMouse ? Theme.onAccent : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                }

                MouseArea {
                    id: dlMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: LanguageAudioState.isDownloading ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (!LanguageAudioState.isDownloading)
                            LanguageAudioState.downloadVideo(searchRow.modelData.url, searchRow.modelData.title);

                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

        }

        footer: Item {
            width: searchList.width
            height: picker.moreH
            visible: height > 0

            Rectangle {
                anchors.centerIn: parent
                width: moreText.implicitWidth + 36
                height: 34
                radius: height / 2
                color: moreMouse.containsMouse && !LanguageAudioState.isLoadingMore ? Theme.glassHover : Theme.glass

                Text {
                    id: moreText

                    anchors.centerIn: parent
                    text: LanguageAudioState.isLoadingMore ? "Loading…" : "Load more"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                    font.weight: Font.Medium
                    color: LanguageAudioState.isLoadingMore ? Theme.textFaint : Theme.text
                }

                MouseArea {
                    id: moreMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: LanguageAudioState.isLoadingMore ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: LanguageAudioState.loadMoreResults()
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

        }

    }

    // Mouse wheel: one notch = exactly one hit, as in the list tab. Own
    // MouseArea next to the list that only takes the wheel; without it Qt scrolled with momentum and stopped in the
    // middle of rows. Touchpad: 60 px of travel = one hit.
    MouseArea {
        property real pending: 0

        anchors.fill: searchList
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            const touchpad = wheel.phase !== Qt.NoScrollPhase;
            const d = touchpad ? wheel.pixelDelta.y : wheel.angleDelta.y;
            const unit = touchpad ? 60 : 120;
            if (d === 0)
                return ;

            if (pending !== 0 && Math.sign(pending) !== Math.sign(d))
                pending = 0;

            pending += d;
            const steps = Math.trunc(pending / unit);
            if (steps === 0)
                return ;

            pending -= steps * unit;
            const stride = searchView.rowH;
            const base = (searchScroll.running ? searchScroll.to : searchList.contentY) - searchList.originY;
            const maxY = Math.max(0, searchList.contentHeight - searchList.height);
            const to = searchList.originY + Math.max(0, Math.min(maxY, (Math.round(base / stride) - steps) * stride));
            searchScroll.stop();
            if (Math.abs(to - searchList.contentY) < 0.5)
                return ;

            searchScroll.to = to;
            searchScroll.start();
        }
    }

    transform: Translate {
        y: (1 - picker.searchProgress) * 8
    }

}
