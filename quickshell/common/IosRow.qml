import "../services"
import QtQuick

// Row in an IosGroup: symbol (glyph or image), title, optional subtitle, on the right value/symbol/
// chevron. tone = color of symbol and title (Theme.bad for destructive things, like the red iOS rows).
// progress >= 0 fills the row from the left (work in progress). divider = hairline on top (first row: false).
Item {
    id: row

    property string glyph: ""
    property url iconSource: ""
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property string trailingGlyph: ""
    property bool chevron: false
    property color tone: Theme.text
    property color glyphTone: tone === Theme.text ? Theme.accent : tone
    property bool divider: true
    property bool centered: false
    property bool dimmed: false // visible, but without effect right now (e.g. nothing to save)
    property real progress: -1
    readonly property bool hovered: mouse.containsMouse
    // Hang the right content (e.g. IosSwitch) in as a child
    default property alias trailingItems: trailingSlot.data

    signal clicked()

    width: parent ? parent.width : 0
    height: subtitle !== "" ? Theme.px(52) : Theme.rowHeight
    opacity: dimmed ? 0.4 : 1

    Rectangle {
        anchors.fill: parent
        color: mouse.pressed ? Theme.groupPressed : Theme.tint(Theme.text, 0.05)
        opacity: row.hovered && !row.dimmed ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, row.progress))
        height: parent.height
        visible: row.progress >= 0
        color: Theme.tint(Theme.accent, 0.16)

        Behavior on width {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    // Hairline, indented from the text like on iOS
    Rectangle {
        x: row.centered ? 0 : content.x + (lead.visible ? lead.width + content.spacing : 0)
        width: parent.width - x
        height: 1
        visible: row.divider
        color: Theme.separator
    }

    Row {
        id: content

        x: row.centered ? (parent.width - width) / 2 : Theme.px(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(10)

        Item {
            id: lead

            anchors.verticalCenter: parent.verticalCenter
            visible: row.glyph !== "" || row.iconSource.toString() !== ""
            width: Theme.px(row.iconSource.toString() !== "" ? 28 : 18)
            height: width

            Image {
                anchors.fill: parent
                visible: row.iconSource.toString() !== ""
                source: row.iconSource
                sourceSize: Qt.size(width * 2, height * 2)
                smooth: true
                mipmap: true
            }

            Text {
                anchors.centerIn: parent
                visible: row.iconSource.toString() === ""
                text: row.glyph
                color: row.glyphTone
                font.family: Theme.font
                font.pixelSize: Theme.sizeLead
            }

        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(1)

            Text {
                text: row.title
                color: row.tone
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLead
                font.weight: Font.Medium
            }

            Text {
                visible: row.subtitle !== ""
                text: row.subtitle
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                font.features: Theme.tabular
            }

        }

    }

    Row {
        id: trailingSlot

        anchors.right: parent.right
        anchors.rightMargin: Theme.px(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(8)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.trailing !== ""
            text: row.trailing
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
            font.features: Theme.tabular
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.trailingGlyph !== "" || row.chevron
            text: row.trailingGlyph !== "" ? row.trailingGlyph : ""
            color: Theme.textFaint
            font.family: Theme.font
            font.pixelSize: row.chevron && row.trailingGlyph === "" ? Theme.sizeSmall : Theme.sizeBody
        }

    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: row.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: {
            if (!row.dimmed)
                row.clicked();

        }
    }

}
