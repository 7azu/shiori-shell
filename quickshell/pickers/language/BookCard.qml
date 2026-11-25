import "../../common"
import "../../services"
import QtQuick
import Quickshell.Widgets

// Book on the shelf: cover in book format (real image or GenCover), below it title and progress.
// Imported books can be deleted (a second click confirms).
Item {
    id: bc

    required property var picker

    property var book: ({
    })
    readonly property int total: book && book.chapters ? book.chapters.length : 0
    readonly property int done: book && book.chapters ? LanguageReadingState.bookReadCount(book) : 0
    readonly property string plainTitle: LanguageReadingState.plainText(book ? book.title : "")
    readonly property bool hasCover: !!book && !!book.cover && coverImg.status === Image.Ready
    readonly property bool hovered: bcMouse.containsMouse || delMouse.containsMouse
    // Selection on the shelf (picker.kbIndex; hover selects too, as in the other pickers). The
    // delete button deliberately still only depends on the real hover, not on the keyboard selection
    property bool selected: false
    property int cellIndex: -1
    readonly property bool lit: selected
    property bool confirm: false

    Item {
        id: coverWrap

        width: parent.width
        height: Math.round(width * 1.42)
        // like the cards in clipboard/task manager: selected 1.05, pressed 0.96
        scale: (bc.selected ? 1.05 : 1) * (bcMouse.pressed ? 0.96 : 1)

        // Shadow
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6
            anchors.leftMargin: 3
            anchors.rightMargin: -3
            anchors.bottomMargin: -6
            radius: 12
            color: "#000000"
            opacity: bc.lit ? 0.35 : 0.22
        }

        GenCover {
            picker: bc.picker
            anchors.fill: parent
            visible: !bc.hasCover
            book: bc.book
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            visible: bc.hasCover

            Image {
                id: coverImg

                anchors.fill: parent
                source: bc.book ? LanguageAudioState.fileUrl(bc.book.cover) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 360
            }

        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, 0.1)
        }

        // Selection ring as in clipboard/task manager (2 px, full accent color)
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.width: 2
            border.color: WalColors.color4
            opacity: bc.selected ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                }

            }

        }

        // Level + finished reading
        Row {
            x: 8
            y: 8
            spacing: 4

            Repeater {
                model: bc.book ? [bc.book.level || "", bc.book.imported ? String(bc.book.source || "").toUpperCase() : bc.book.kind === "cards" ? "Cards" : ""].filter((x) => {
                    return x !== "" && x !== "?";
                }) : []

                delegate: Rectangle {
                    required property var modelData

                    width: badgeText.implicitWidth + 12
                    height: 18
                    radius: height / 2
                    color: WalColors.withAlpha(WalColors.color0, 0.82)

                    Text {
                        id: badgeText

                        anchors.centerIn: parent
                        text: modelData
                        font.family: picker.mono
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 0.5
                        color: WalColors.color4
                    }

                }

            }

        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 8
            y: 8
            visible: bc.total > 0 && bc.done === bc.total && !bc.hovered
            width: 22
            height: 22
            radius: height / 2
            color: WalColors.color4

            // Finished reading: sparkle instead of a check mark (visual language: star = done)
            Sparkle {
                anchors.centerIn: parent
                size: 5
                rays: 1.4
                color: WalColors.color0
                glowColor: WalColors.color0
                twinkle: 1
            }

        }

        MouseArea {
            id: bcMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: (mouse) => {
                picker.hoverSelect(bcMouse, mouse, "shelf", bc.cellIndex);
            }
            onClicked: LanguageReadingState.openBook(bc.book.id)
            onExited: bc.confirm = false
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 8
            y: 8
            visible: !!bc.book && !!bc.book.imported && bc.hovered
            width: bc.confirm ? delLabel.implicitWidth + 16 : 24
            height: 24
            radius: height / 2
            color: bc.confirm || delMouse.containsMouse ? WalColors.color1 : WalColors.withAlpha(WalColors.color0, 0.82)

            Text {
                id: delLabel

                anchors.centerIn: parent
                text: bc.confirm ? "Delete?" : "✕"
                font.family: picker.mono
                font.pixelSize: 10
                font.bold: true
                color: bc.confirm || delMouse.containsMouse ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.75)
            }

            MouseArea {
                id: delMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (bc.confirm)
                        LanguageReadingState.deleteBook(bc.book.id);
                    else
                        bc.confirm = true;
                }
            }

        }

        Behavior on scale {
            Springy {
            }

        }

    }

    Column {
        anchors.top: coverWrap.bottom
        anchors.topMargin: 12
        width: parent.width
        spacing: 3

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: bc.plainTitle
            font.family: picker.jp
            font.pixelSize: 14
            font.bold: true
            color: bc.lit ? WalColors.color4 : WalColors.color7

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: bc.book ? bc.book.subtitle || "" : ""
            font.family: picker.mono
            font.pixelSize: 10
            color: WalColors.withAlpha(WalColors.color7, 0.5)
        }

        Item {
            width: parent.width
            height: 14

            Rectangle {
                anchors.left: parent.left
                anchors.right: countText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 3
                radius: 2
                color: WalColors.withAlpha(WalColors.color7, 0.1)

                Rectangle {
                    width: bc.total > 0 ? parent.width * bc.done / bc.total : 0
                    height: parent.height
                    radius: 2
                    color: WalColors.color4

                    Behavior on width {
                        Smooth {
                        }

                    }

                }

            }

            Text {
                id: countText

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: bc.done + "/" + bc.total
                font.family: picker.mono
                font.pixelSize: 9
                color: WalColors.withAlpha(WalColors.color7, 0.45)
            }

        }

    }

}
