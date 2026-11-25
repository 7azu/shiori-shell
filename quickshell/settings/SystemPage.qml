pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick

// First page of the settings window: this machine, the versions, which optional programs are there
// (sparkle = installed, hollow dot = missing, the shell's usual pair) and the files behind the settings.
// The facts come from scripts/settings_probe.py (SettingsState.probe).
Column {
    id: page

    readonly property var info: SettingsState.probe.info || ({
    })
    readonly property var optional: SettingsState.probe.optional || []
    readonly property int missingCount: optional.filter((o) => {
        return !o.ok;
    }).length

    spacing: Theme.px(22)

    component Fact: Item {
        property string label: ""
        property string value: ""
        property bool first: false

        width: parent ? parent.width : 0
        height: Theme.rowHeight

        Rectangle {
            x: Theme.px(14)
            width: parent.width - x
            height: 1
            visible: !parent.first
            color: Theme.separator
        }

        Text {
            x: Theme.px(14)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLead
            font.weight: Font.Medium
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.px(14)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value !== "" ? parent.value : "unknown"
            color: Theme.textDim
            font.family: Theme.fontUi
            font.features: Theme.tabular
            font.pixelSize: Theme.sizeBody
        }

    }

    IosGroup {
        width: page.width
        title: "This machine"

        Fact {
            first: true
            label: "Name"
            value: page.info.host || ""
        }

        Fact {
            label: "shiori-shell"
            value: page.info.shell || ""
        }

        Fact {
            label: "Quickshell"
            value: page.info.quickshell || ""
        }

        Fact {
            label: "Hyprland"
            value: page.info.hyprland || ""
        }

    }

    IosGroup {
        width: page.width
        title: "Optional programs"
        inset: Theme.px(14)
        footer: page.missingCount === 0 ? "Everything optional is installed." : "A feature whose program is missing is hidden, not broken."

        Flow {
            width: parent.width
            spacing: 0

            Repeater {
                model: page.optional

                Item {
                    id: cell

                    required property var modelData

                    width: Math.floor(parent.width / 2)
                    height: Theme.px(30)

                    // Installed: the sparkle; missing: the hollow dot
                    Item {
                        id: mark

                        width: Theme.px(16)
                        height: parent.height

                        Sparkle {
                            anchors.centerIn: parent
                            visible: cell.modelData.ok
                            size: 3
                            color: Theme.text
                            glowColor: Theme.accent
                            twinkle: 0.7
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            visible: !cell.modelData.ok
                            width: Theme.px(6)
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.warn
                        }

                    }

                    Text {
                        id: cmd

                        anchors.left: mark.right
                        anchors.leftMargin: Theme.px(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: cell.modelData.cmd
                        color: cell.modelData.ok ? Theme.text : Theme.warn
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.left: cmd.right
                        anchors.leftMargin: Theme.px(8)
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.px(10)
                        anchors.baseline: cmd.baseline
                        text: cell.modelData.what
                        elide: Text.ElideRight
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                }

            }

        }

    }

    IosGroup {
        width: page.width
        title: "Files"
        footer: "The window writes these files. You can still edit them by hand, changes show up here at once."

        IosRow {
            divider: false
            glyph: "\u{F09EE}"
            title: "settings.json"
            subtitle: "Your settings, the same on all your machines"
            chevron: true
            onClicked: SettingsState.openPath(Settings.userFile)
        }

        IosRow {
            glyph: "\u{F0256}"
            title: "quickshell-local"
            subtitle: "Bar monitor, scale and bar icons of this machine"
            chevron: true
            onClicked: SettingsState.openPath(MachineConfig.dir)
        }

        IosRow {
            glyph: "\u{F0256}"
            title: "icons"
            subtitle: "Pictures for your own app icons"
            chevron: true
            onClicked: SettingsState.openPath(Settings.configHome + "/shiori-shell/icons")
        }

    }

}
