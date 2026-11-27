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

    // Intro clock in ms (on opening and on every page change). One clock instead of many animations:
    // every part takes its own slice (delay, length) of it, so a restart while running is clean.
    // The rail falls in from above; here the page comes in from the side, in layers: head lines glide
    // in from the right one after another, the seal follows slower (depth), then the groups rise.
    property real clock: 2000

    function toTop() {
        flick.contentY = 0;
    }

    function playIntro(startDelay) {
        intro.stop();
        intro.from = -(startDelay || 0);
        intro.start();
    }

    // Progress 0..1 of a part (ease out quint, as Appearance.anim.curves.outQuint)
    function k(delay, length) {
        const x = Math.max(0, Math.min(1, (clock - delay) / length));
        return 1 - Math.pow(1 - x, 5);
    }

    // Delay of group i (after the head)
    function groupDelay(i) {
        return 170 + Math.min(Math.max(0, i), 6) * 55;
    }

    NumberAnimation {
        id: intro

        target: page
        property: "clock"
        to: 1100
        duration: 1100 - intro.from
    }

    // Seal of the page, large and barely there, next to the head (it must not reach into the rows)
    Text {
        readonly property real e: page.k(40, 900)

        anchors.right: parent.right
        anchors.rightMargin: Theme.px(34) - Theme.px(46) * (1 - e)
        anchors.verticalCenter: head.verticalCenter
        opacity: e
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
            id: label

            readonly property real e: page.k(0, 520)

            spacing: Theme.px(14)
            opacity: e

            transform: Translate {
                x: Theme.px(26) * (1 - label.e)
            }

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
            id: title

            readonly property real e: page.k(50, 560)

            width: parent.width
            text: page.section.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.fontDisplay
            font.pixelSize: Theme.px(34)
            opacity: e

            transform: Translate {
                x: Theme.px(26) * (1 - title.e)
            }

        }

        Text {
            id: blurb

            readonly property real e: page.k(100, 560)

            opacity: e
            width: parent.width
            text: page.section.blurb
            wrapMode: Text.WordWrap
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLead
            lineHeight: 1.2

            transform: Translate {
                x: Theme.px(26) * (1 - blurb.e)
            }

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
                id: custom

                readonly property real e: page.k(page.groupDelay(0), 600)

                width: body.width
                active: !!page.section.page
                visible: active
                opacity: e
                transform: Translate {
                    y: Theme.px(18) * (1 - custom.e)
                }

                source: ({
                    "system": "SystemPage.qml",
                    "sync": "SyncPage.qml",
                    "displays": "DisplaysPage.qml",
                    "windows": "WindowsPreview.qml"
                })[page.section.page] || ""
            }

            Repeater {
                model: SettingsState.groupsOf(page.section)

                IosGroup {
                    id: group

                    required property var modelData
                    required property int index
                    readonly property var rows: modelData.rows.filter((r) => {
                        return page.searching || SettingsState.shownRow(r);
                    })
                    // A custom page (Loader above) takes the first slot
                    readonly property real e: page.k(page.groupDelay(index + (page.section.page ? 1 : 0)), 600)

                    width: body.width
                    visible: rows.length > 0
                    opacity: e
                    transform: Translate {
                        y: Theme.px(18) * (1 - group.e)
                    }

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
