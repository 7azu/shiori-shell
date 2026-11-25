import "../services"
import QtQuick
import Quickshell.Widgets

// Vertical preview column (image and video editor). The height fits whole rows exactly, scrolling
// goes row by row: this way no preview is ever cut off, not even the last one.
Item {
    id: strip

    property var paths: []
    property int currentIndex: -1
    property string currentPath: ""
    // Functions from the editor: path -> image URL ("" = none yet) or path -> unsaved?
    property var sourceFor: null
    property var unsavedFor: null
    // Final height the editor is animating to right now (big view on/off). The rows adjust
    // right away, while the visible section glides along with the card: otherwise the list jumped
    // row by row on the way and scrolled after every jump
    property real targetHeight: height

    signal picked(string path)

    width: 128

    ListView {
        id: thumbs

        readonly property int thumbW: 120
        readonly property int thumbH: 80
        readonly property int rowH: thumbH + spacing
        readonly property int rows: Math.max(1, Math.floor((strip.targetHeight + spacing) / rowH))
        // Rest below the last whole row; soft, so the height does not jump on a switch
        property real slack: strip.targetHeight - (rows * rowH - spacing)
        // Scrolling that triggers a size change runs in step with the card
        property bool resizing: false
        readonly property int maxFirst: Math.max(0, count - rows)
        property int first: 0
        property real wheelRest: 0

        function scrollTo(i) {
            first = Math.max(0, Math.min(maxFirst, i));
            contentY = originY + first * rowH;
        }

        // Only scroll as far as needed for the current element to be visible
        function reveal() {
            const i = strip.currentIndex;
            if (i < 0)
                scrollTo(first);
            else if (i < first)
                scrollTo(i);
            else if (i >= first + rows)
                scrollTo(i - rows + 1);
            else
                scrollTo(first);
        }

        width: thumbW
        height: Math.max(0, strip.height - slack)
        spacing: 8
        clip: true
        interactive: false
        model: strip.paths
        onCountChanged: Qt.callLater(reveal)
        onRowsChanged: {
            resizing = true;
            resizeTimer.restart();
            Qt.callLater(reveal);
        }

        Timer {
            id: resizeTimer

            interval: Appearance.anim.durations.normal
            onTriggered: thumbs.resizing = false
        }

        Behavior on slack {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }

        }

        Connections {
            function onCurrentIndexChanged() {
                thumbs.reveal();
            }

            target: strip
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                thumbs.wheelRest += event.angleDelta.y;
                const steps = Math.trunc(thumbs.wheelRest / 120);
                if (steps !== 0) {
                    thumbs.wheelRest -= steps * 120;
                    thumbs.scrollTo(thumbs.first - steps);
                }
            }
        }

        Behavior on contentY {
            NumberAnimation {
                duration: thumbs.resizing ? Appearance.anim.durations.normal : Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

        delegate: Item {
            id: thumb

            required property string modelData
            readonly property bool current: modelData === strip.currentPath

            width: thumbs.thumbW
            height: thumbs.thumbH

            ClippingRectangle {
                anchors.fill: parent
                radius: 10
                color: Theme.card
                opacity: thumb.current || thumbMouse.containsMouse ? 1 : 0.6

                Image {
                    anchors.fill: parent
                    source: strip.sourceFor ? strip.sourceFor(thumb.modelData) : ""
                    sourceSize.height: 160
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    autoTransform: true
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.width: thumb.current ? 2 : 1
                border.color: thumb.current ? Theme.accent : Theme.stroke
            }

            // Unsaved changes
            Rectangle {
                x: parent.width - 14
                y: 6
                width: 8
                height: 8
                radius: height / 2
                visible: strip.unsavedFor ? strip.unsavedFor(thumb.modelData) : false
                color: Theme.warn
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.5)
            }

            MouseArea {
                id: thumbMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: strip.picked(thumb.modelData)
            }

        }

    }

    // Shows that and how far the column can be scrolled
    Rectangle {
        x: thumbs.width + 4
        y: thumbs.count > 0 ? thumbs.first / thumbs.count * thumbs.height : 0
        width: 2
        height: thumbs.count > 0 ? thumbs.rows / thumbs.count * thumbs.height : 0
        radius: 1
        visible: thumbs.maxFirst > 0
        color: Theme.textFaint

        Behavior on y {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

    }

}
