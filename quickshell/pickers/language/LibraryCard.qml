import "../../common"
import "../../services"
import QtQuick

// Listen tab: one video of the library grid. Big 16:9 preview (duration, remembered position, level meter while
// it plays), selection ring, title and date; a click watches, the small button on the image only listens.
// Delegate in LanguageLibrary.qml (view = the Listen tab, picker = core; modelData = {file, entry}).
Item {
    id: card

    required property var picker
    required property var view

    required property var modelData
    readonly property string file: modelData.file
    readonly property int entry: modelData.entry
    readonly property var m: card.view.info(file)
    readonly property bool current: LanguageAudioState.mediaActive && LanguageAudioState.currentFile === file && LanguageAudioState.playLanguage === LanguageAudioState.language
    readonly property bool hot: card.picker.kbList === "audio" && card.picker.kbIndex === entry
    readonly property real resume: card.view.resumeFrac(file)

    width: card.view.cardW
    height: card.view.cardH

    RoundedClip {
        id: thumb

        width: parent.width
        height: card.view.thumbH
        radius: 12
        color: Theme.groupFill

        Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: card.view.gVideo
            color: Theme.textFaint
            font.family: Theme.font
            font.pixelSize: 22
        }

        // Selected: the image zooms slightly in the frame (the card itself stays still)
        Image {
            id: img

            anchors.fill: parent
            source: LanguageAudioState.fileUrl(card.m.thumb)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 560
            scale: card.hot ? 1.06 : 1
            opacity: status === Image.Ready ? 1 : 0

            Behavior on scale {
                NumberAnimation {
                    duration: 520
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.outQuint
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 220
                }

            }

        }

        // Dark gradient at the bottom, so duration and progress stay readable on bright images
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * 0.4

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "transparent"
                }

                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0.45)
                }

            }

        }

        // Running: darkened + level meter
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
            opacity: card.current ? 1 : 0
            visible: opacity > 0.01

            Row {
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: 4

                    Rectangle {
                        id: bar

                        required property int index
                        property real level: 0.4

                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: Math.round(5 + 16 * level)
                        radius: 1.5
                        color: "white"

                        SequentialAnimation on level {
                            running: card.current && LanguageAudioState.isPlaying
                            loops: Animation.Infinite

                            NumberAnimation {
                                to: [0.9, 0.5, 1, 0.7][bar.index]
                                duration: 280 + bar.index * 70
                                easing.type: Easing.InOutSine
                            }

                            NumberAnimation {
                                to: [0.25, 0.95, 0.35, 0.2][bar.index]
                                duration: 320 + bar.index * 50
                                easing.type: Easing.InOutSine
                            }

                        }

                    }

                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }

            }

        }

        // Selected: play hint in the middle (click = watch)
        Rectangle {
            anchors.centerIn: parent
            width: 46
            height: 46
            radius: 23
            color: Qt.rgba(0, 0, 0, 0.45)
            opacity: card.hot && !card.current ? 1 : 0
            visible: opacity > 0.01

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 2
                text: card.view.gPlay
                color: "white"
                font.family: Theme.font
                font.pixelSize: 17
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }

            }

        }

        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 10
            anchors.bottomMargin: card.resume > 0 ? 10 : 7
            visible: (card.m.duration || 0) > 0 && !card.current
            text: card.picker.formatTime(card.m.duration || 0)
            color: "white"
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
            font.weight: Font.DemiBold
            font.features: Theme.tabular
        }

        // Gemerkter Stand
        Rectangle {
            visible: card.resume > 0 && !card.current
            anchors.bottom: parent.bottom
            width: parent.width
            height: 3
            color: Qt.rgba(1, 1, 1, 0.22)

            Rectangle {
                width: Math.round(parent.width * card.resume)
                height: parent.height
                color: Theme.accent
            }

        }

    }

    // Selection ring (like the cards of the other pickers, without enlarging the card)
    Rectangle {
        anchors.fill: thumb
        radius: thumb.radius
        color: "transparent"
        border.width: 2
        border.color: WalColors.color4
        opacity: card.hot ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 140
            }

        }

    }

    MouseArea {
        id: hit

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: (mouse) => {
            return card.picker.hoverSelect(hit, mouse, "audio", card.entry);
        }
        onClicked: LanguageAudioState.watchVideo(card.file)
    }

    // Listen only: small button at the top right of the image (on selection or while playing)
    CircleButton {
        anchors.right: thumb.right
        anchors.top: thumb.top
        anchors.margins: 8
        size: 30
        dark: true
        opacity: card.hot || card.current ? 1 : 0
        visible: opacity > 0.01
        glyph: card.current && LanguageAudioState.isPlaying ? card.view.gPause : card.view.gHead
        onClicked: LanguageAudioState.play(card.file)

        Behavior on opacity {
            NumberAnimation {
                duration: 140
            }

        }

    }

    Column {
        y: card.view.thumbH + 10
        width: parent.width
        spacing: 3

        Text {
            width: parent.width
            text: LanguageAudioState.stemOf(card.file)
            color: card.current ? Theme.accent : Theme.text
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLabel
            font.weight: Font.Medium
        }

        Text {
            width: parent.width
            text: [card.view.dateLabel(card.m.mtime), LanguageAudioState.hasSubs(card.file) ? "字幕" : ""].filter(Boolean).join("  ·  ")
            color: Theme.textFaint
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
        }

    }

}
