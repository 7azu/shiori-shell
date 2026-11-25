import "../services"
import "Format.js" as Fmt
import QtQuick

// Header of the sidebar in the image and video editor (iOS style): on top the kind of file and buttons on the right
// (undo, close ... hang them in as children), below it the file name big, below that info
// as calm capsules.
Column {
    id: header

    property string kind: "" // "Image", "Video", "Screenshot"
    property string glyph: ""
    property string fileName: "" // with extension; empty = no file name (screenshot)
    property int index: -1 // 0-based; -1 = no folder to browse
    property int count: 0
    property int mediaW: 0
    property int mediaH: 0
    property real duration: 0 // seconds, 0 = no value (image)
    default property alias actions: actionRow.data

    readonly property int dot: fileName.lastIndexOf(".")
    readonly property string stem: dot > 0 ? fileName.substring(0, dot) : fileName
    readonly property string ext: dot > 0 ? fileName.substring(dot + 1).toUpperCase() : ""
    readonly property var facts: {
        const out = [];
        if (index >= 0 && count > 1)
            out.push((index + 1) + " of " + count);

        if (mediaW > 0 && mediaH > 0)
            out.push(mediaW + " × " + mediaH);

        if (duration > 0)
            out.push(Fmt.clock(Math.round(duration)));

        return out;
    }

    spacing: Theme.px(8)

    Item {
        width: header.width
        height: Math.max(kindRow.height, actionRow.height)

        Row {
            id: kindRow

            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(7)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: header.glyph
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.sizeBody + 1
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (header.kind + (header.ext !== "" ? "  ·  " + header.ext : "")).toUpperCase()
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }

        }

        Row {
            id: actionRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(8)
        }

    }

    Text {
        width: header.width
        visible: text !== ""
        // Long names without spaces (camera, downloads) should wrap anyway
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        text: header.stem
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeTitleLarge
        font.weight: Font.DemiBold
    }

    Flow {
        width: header.width
        visible: header.facts.length > 0
        spacing: Theme.px(6)

        Repeater {
            model: header.facts

            delegate: Rectangle {
                required property string modelData

                width: factText.implicitWidth + Theme.px(16)
                height: Theme.px(22)
                radius: height / 2
                color: Theme.groupFill

                Text {
                    id: factText

                    anchors.centerIn: parent
                    text: parent.modelData
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    font.weight: Font.Medium
                    font.features: Theme.tabular
                }

            }

        }

    }

}
