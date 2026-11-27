pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Preview below the logo of the bar while the mouse rests on it: what each click opens.
//   left click    the picker drawer, with its real icons (the same DrawerSlots, in the bar's order)
//   right click   the tray drawer, with the icons of the programs in the tray
//   middle click  arranging the icons
// Each line has a small mouse with that button lit. Purely a picture: takes no input at all.
// Like TrayContextMenu the window is always mapped (mapping anew would play Hyprland's layer
// animation) and only transparent while hidden. Part of MainBar (mainBar = core, logoHint, logoHintX).
PanelWindow {
    id: win

    required property var mainBar
    property real shown: mainBar.logoHint ? 1 : 0
    // Room around the card for its shadow
    readonly property real pad: 26
    readonly property var drawerIds: BarIcons.orderOf("left", mainBar.groupIds("left")).filter((id) => {
        switch (id) {
        case "bluetooth":
            return BarIcons.shown(id) && BluetoothState.available;
        case "wifi":
            return BarIcons.shown(id) && WifiState.available;
        case "media":
            return BarIcons.shown(id) && Addons.media;
        case "monitor":
            return BarIcons.shown(id) && Quickshell.screens.length > 1;
        }
        return BarIcons.shown(id);
    })
    readonly property var trayItems: TrayState.enabled ? TrayState.items.slice(0, 9) : []

    // Each part comes a little after the one before it (0..1 from `shown`)
    function stage(i) {
        return Math.max(0, Math.min(1, shown * 1.5 - i * 0.12));
    }

    implicitWidth: card.width + 2 * pad
    implicitHeight: card.height + 2 * pad
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:logo-hint"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
    }

    // Below the bar with a little air, starting at the logo
    margins {
        top: Math.round(win.mainBar.logoHintY + 8 - win.pad)
        left: Math.round(Math.max(0, win.mainBar.logoHintX - 10 - win.pad))
    }

    mask: Region {
    }

    RectangularShadow {
        anchors.fill: card
        offset.y: 6
        radius: card.radius
        blur: 22
        color: WalColors.withAlpha(WalColors.color0, 0.55)
        opacity: card.opacity
        scale: card.scale
        transformOrigin: Item.TopLeft
    }

    Rectangle {
        id: card

        x: win.pad
        y: win.pad - 6 * (1 - win.shown)
        width: Math.max(Theme.px(220), lines.implicitWidth + Theme.px(28))
        height: lines.implicitHeight + Theme.px(24)
        radius: Theme.px(16)
        color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.06))
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color7, 0.1)
        opacity: win.shown
        scale: 0.94 + 0.06 * win.shown
        transformOrigin: Item.TopLeft
        visible: opacity > 0.01

        Column {
            id: lines

            x: Theme.px(14)
            y: Theme.px(12)
            spacing: Theme.px(10)

            Line {
                button: "left"
                label: "Pickers"
                k: win.stage(0)

                Row {
                    spacing: 0

                    Repeater {
                        model: win.drawerIds

                        delegate: Item {
                            id: peek

                            required property string modelData
                            required property int index
                            readonly property real r: Math.max(0, Math.min(1, win.shown * 1.7 - 0.2 - index * 0.06))

                            width: icon.width * 0.8
                            height: 26

                            Loader {
                                id: icon

                                anchors.centerIn: parent
                                scale: 0.8
                                sourceComponent: peek.modelData === "monitor" ? monitorIcon : slotIcon
                            }

                            Component {
                                id: slotIcon

                                DrawerSlot {
                                    enabled: false
                                    icon: peek.modelData === "ja" ? "language" : peek.modelData
                                    mark: peek.modelData === "ja" ? LanguageAudioState.markOf(LanguageAudioState.language) : ""
                                    linked: peek.modelData === "wifi" ? WifiState.connected : (peek.modelData === "bluetooth" && BluetoothState.connectedCount > 0)
                                    dimmed: (peek.modelData === "wifi" && !WifiState.enabled) || (peek.modelData === "bluetooth" && !BluetoothState.enabled)
                                    reveal: peek.r
                                }

                            }

                            Component {
                                id: monitorIcon

                                MonitorSwitchButton {
                                    enabled: false
                                    reveal: peek.r
                                }

                            }

                        }

                    }

                }

            }

            Line {
                visible: TrayState.enabled
                button: "right"
                label: "Tray"
                k: win.stage(1)

                Row {
                    height: 26
                    spacing: Theme.px(9)

                    Repeater {
                        model: win.trayItems

                        delegate: TrayIcon {
                            required property var modelData
                            required property int index
                            readonly property real r: Math.max(0, Math.min(1, win.shown * 1.7 - 0.35 - index * 0.06))

                            y: 5
                            size: 16
                            icon: modelData.icon || ""
                            opacity: r * (TrayState.isHidden(modelData) ? 0.45 : 0.9)
                            scale: 0.6 + 0.4 * r
                        }

                    }

                    Text {
                        visible: win.trayItems.length === 0
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                        text: "Nothing running in the tray"
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                }

            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.separator
                opacity: win.stage(2)
            }

            Line {
                button: "middle"
                label: "Arrange icons"
                faint: true
                k: win.stage(2)
            }

        }

    }

    // One line: the mouse with its button lit, the name, and what that click will show
    component Line: Row {
        id: line

        property string button: "left"
        property string label: ""
        property bool faint: false
        property real k: 1
        default property alias preview: slot.data

        spacing: Theme.px(10)
        opacity: k
        transform: Translate {
            x: -8 * (1 - line.k)
        }

        MouseGlyph {
            anchors.verticalCenter: parent.verticalCenter
            button: line.button
            faint: line.faint
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(84)
            text: line.label
            color: line.faint ? Theme.textDim : Theme.text
            font.family: Theme.fontUi
            font.pixelSize: line.faint ? Theme.sizeSmall : Theme.sizeBody
        }

        Item {
            id: slot

            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: Math.max(childrenRect.height, 1)
        }

    }

    // A small mouse: body, the split between the buttons, the lit button (or the wheel)
    component MouseGlyph: Item {
        id: m

        property string button: "left"
        property bool faint: false
        readonly property color lit: faint ? Theme.tint(Theme.accent, 0.7) : Theme.accent

        width: 13
        height: 19

        Rectangle {
            anchors.fill: parent
            radius: 6.5
            color: "transparent"
            border.width: 1.4
            border.color: Theme.tint(Theme.text, m.faint ? 0.35 : 0.55)
        }

        // The lit button: the top left or right quarter, rounded like the body
        Item {
            visible: m.button !== "middle"
            x: m.button === "left" ? 0 : m.width / 2
            width: m.width / 2
            height: m.height * 0.45
            clip: true

            Rectangle {
                x: m.button === "left" ? 0 : -m.width / 2
                width: m.width
                height: m.height
                radius: 6.5
                color: m.lit
            }

        }

        Rectangle {
            x: m.width / 2 - 0.5
            y: 2
            width: 1
            height: m.height * 0.45 - 2
            color: Theme.tint(Theme.text, 0.55)
            visible: m.button === "middle"
        }

        // Wheel
        Rectangle {
            visible: m.button === "middle"
            x: m.width / 2 - 1.5
            y: 3.5
            width: 3
            height: 5
            radius: 1.5
            color: m.lit
        }

        Rectangle {
            x: 1.4
            y: m.height * 0.45
            width: m.width - 2.8
            height: 1
            color: Theme.tint(Theme.text, m.faint ? 0.25 : 0.4)
        }

    }

    Behavior on shown {
        NumberAnimation {
            duration: win.mainBar.logoHint ? 380 : 160
            easing.type: Easing.OutCubic
        }

    }

}
