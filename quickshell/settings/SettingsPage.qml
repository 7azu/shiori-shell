pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick

// A page of the settings window, drawn from its description (SettingsState.sections): head (group,
// title in the display font, one sentence), behind it the page's seal as a faint watermark, below the
// groups with their rows (SettingRow). Pages with their own layout (page: "system" | "sync") load
// their file instead of rows. The search result is the same page with made-up groups.
Item {
    id: page

    required property var section
    readonly property bool searching: section.searching === true
    readonly property real pad: Theme.px(40)
    readonly property real colW: Math.min(width - 2 * pad, Theme.px(720))

    function toTop() {
        flick.contentY = 0;
    }

    // Seal of the page, large and barely there, next to the head (it must not reach into the rows)
    Text {
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(34)
        anchors.verticalCenter: head.verticalCenter
        text: page.section.seal
        color: Theme.tint(Theme.text, 0.05)
        font.family: Theme.fontDisplay
        font.pixelSize: Theme.px(92)
    }

    Column {
        id: head

        x: page.pad
        y: Theme.px(30)
        // Room for the seal on the right
        width: page.colW - Theme.px(120)
        spacing: Theme.px(7)

        Row {
            spacing: Theme.px(14)

            Text {
                text: page.searching ? "SEARCH" : "0" + (page.section.group + 1) + "   " + SettingsState.groups[page.section.group].toUpperCase()
                color: Theme.accent
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeMicro
                font.bold: true
                font.letterSpacing: 2
            }

            // Values of this page belong to this machine and are not synced. Hollow dot: the shell's
            // sign for "apart / not on"
            Row {
                visible: page.section.local === true
                spacing: Theme.px(5)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.px(6)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.textFaint
                }

                Text {
                    text: "THIS MACHINE ONLY"
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.bold: true
                    font.letterSpacing: Theme.microSpacing
                }

            }

        }

        Text {
            width: parent.width
            text: page.section.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.fontDisplay
            font.pixelSize: Theme.px(34)
        }

        Text {
            width: parent.width
            text: page.section.blurb
            wrapMode: Text.WordWrap
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLead
            lineHeight: 1.2
        }

    }

    Flickable {
        id: flick

        anchors.top: head.bottom
        anchors.topMargin: Theme.px(22)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        contentHeight: body.height + Theme.px(28)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body

            x: page.pad
            width: page.colW
            spacing: Theme.px(22)

            Loader {
                width: body.width
                active: !!page.section.page
                visible: active
                source: page.section.page === "system" ? "SystemPage.qml" : (page.section.page === "sync" ? "SyncPage.qml" : "")
            }

            Repeater {
                model: SettingsState.groupsOf(page.section)

                IosGroup {
                    id: group

                    required property var modelData
                    readonly property var rows: modelData.rows.filter((r) => {
                        return page.searching || SettingsState.shownRow(r);
                    })

                    width: body.width
                    visible: rows.length > 0
                    title: modelData.title
                    footer: modelData.footer || ""
                    // Search: the group is a page, the action leads there
                    actionText: page.searching ? "Open page" : ""
                    onActionClicked: SettingsState.jump(modelData.target, "")

                    Repeater {
                        model: group.rows

                        SettingRow {
                            required property var modelData
                            required property int index

                            row: modelData
                            first: index === 0
                        }

                    }

                }

            }

        }

    }

    // Thin scroll mark
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(8)
        y: flick.y + flick.visibleArea.yPosition * flick.height
        width: Theme.px(3)
        height: flick.visibleArea.heightRatio * flick.height
        radius: width / 2
        visible: flick.visibleArea.heightRatio < 1
        color: Theme.tint(Theme.text, flick.moving ? 0.3 : 0.14)

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.normal
            }

        }

    }

}
