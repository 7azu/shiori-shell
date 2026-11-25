import "../../common"
import "../../services"
import QtQuick

// Running YouTube download as a slim row above the content: status in small capitals, title,
// below it a fine line (waiting/converting: a gliding piece instead of a percentage).
// Part of LanguagePicker.qml (picker = core).
Item {
    id: dlCard

    required property var picker
    readonly property bool failed: LanguageDownloadState.downloadError !== "" && !LanguageDownloadState.isDownloading
    readonly property bool converting: LanguageDownloadState.isConverting
    readonly property bool waiting: LanguageDownloadState.isDownloading && (converting || LanguageDownloadState.isPreparingSubs || LanguageDownloadState.downloadProgress < 0.005)
    readonly property color tone: failed ? Theme.bad : Theme.accent
    property real dlValue: LanguageDownloadState.downloadProgress

    width: parent.width
    height: picker.showDl ? (failed ? 74 : 62) : 0
    opacity: picker.showDl ? 1 : 0
    visible: height > 0.5
    clip: true

    Text {
        id: status

        x: 12
        y: 4
        text: dlCard.failed ? "DOWNLOAD FAILED" : LanguageDownloadState.isPreparingSubs ? "PREPARING SUBTITLES" : dlCard.converting ? "CONVERTING" : (LanguageDownloadState.downloadMode === "video" ? "DOWNLOADING VIDEO" : "DOWNLOADING") + (dlCard.waiting ? "" : "  ·  " + Math.round(dlCard.dlValue * 100) + " %")
        color: dlCard.tone
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeMicro
        font.weight: Font.DemiBold
        font.letterSpacing: Theme.microSpacing
        font.features: Theme.tabular
    }

    Text {
        x: 12
        anchors.top: status.bottom
        anchors.topMargin: 5
        width: parent.width - x - 52
        text: dlCard.failed ? LanguageDownloadState.downloadError : LanguageDownloadState.downloadTitle
        color: dlCard.failed ? Theme.textDim : Theme.text
        elide: Text.ElideRight
        wrapMode: dlCard.failed ? Text.Wrap : Text.NoWrap
        maximumLineCount: dlCard.failed ? 2 : 1
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeLabel
        font.weight: Font.Medium
    }

    // Cancel
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 4
        width: 28
        height: 28
        radius: height / 2
        color: cancelArea.containsMouse ? Theme.glassHover : Theme.glass
        opacity: LanguageDownloadState.isDownloading ? 1 : 0
        visible: opacity > 0.01
        scale: cancelArea.pressed ? 0.9 : 1

        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF00D)
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 11
        }

        MouseArea {
            id: cancelArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: LanguageDownloadState.cancelDownload()
        }

        Behavior on scale {
            Springy {
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 120
            }

        }

    }

    Rectangle {
        id: line

        x: 12
        y: 46
        width: parent.width - 24
        height: 3
        radius: 1.5
        visible: !dlCard.failed
        color: Theme.track
        clip: true

        Rectangle {
            visible: !dlCard.waiting
            width: Math.round(parent.width * dlCard.dlValue)
            height: parent.height
            radius: 1.5
            color: dlCard.tone
        }

        // Indeterminate: a piece glides through (only x animated)
        Rectangle {
            id: runner

            visible: dlCard.waiting
            width: Math.round(parent.width * 0.22)
            height: parent.height
            radius: 1.5
            color: dlCard.tone

            NumberAnimation on x {
                running: dlCard.waiting && dlCard.visible
                from: -runner.width
                to: line.width
                duration: 1300
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }

        }

    }

    Behavior on height {
        Smooth {
        }

    }

    Behavior on opacity {
        Smooth {
            duration: 220
        }

    }

    Behavior on dlValue {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }

    }

}
