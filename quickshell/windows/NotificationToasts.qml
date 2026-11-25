import "../common"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// Small toasts in the top right corner. A click opens the notification center
// (the bar morphs there), hover pauses the remaining time, swiping/x dismisses.
PanelWindow {
    id: win

    readonly property real cardW: 400
    readonly property real gap: 14
    // The bar is 75% wide and reaches below the toasts -> with a visible bar below it
    readonly property real barH: 40
    property real topY: BarState.barVisible ? barH + gap : gap

    implicitWidth: cardW + 2 * gap + 40 // room for the shadow and gliding in
    implicitHeight: 520
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notification-toasts"

    anchors {
        top: true
        right: true
    }

    Item {
        id: stack

        readonly property bool hovered: stackHover.hovered

        x: parent.width - width - win.gap
        y: win.topY
        width: win.cardW
        height: list.count > 0 ? list.contentItem.childrenRect.height : 0

        HoverHandler {
            id: stackHover
        }

        ListView {
            id: list

            width: parent.width
            height: Math.max(1, contentItem.childrenRect.height)
            interactive: false
            spacing: 8

            model: ScriptModel {
                // While the center is open, it shows everything anyway
                values: NotificationState.centerOpen ? [] : NotificationState.popups
            }

            delegate: NotificationCard {
                width: list.width
                toast: true
                paused: stack.hovered
            }

            // Glide in from the right, overshoot slightly
            add: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "x"
                        from: win.cardW * 0.6
                        to: 0
                        duration: 460
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.1
                    }

                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 260
                    }

                }

            }

            remove: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "x"
                        to: win.cardW * 0.5
                        duration: 260
                        easing.type: Easing.InCubic
                    }

                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: 220
                    }

                }

            }

            // Always finish an interrupted glide-in (two toasts almost at the same time)
            displaced: Transition {
                NumberAnimation {
                    property: "y"
                    duration: 380
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    property: "x"
                    to: 0
                    duration: 200
                }

                NumberAnimation {
                    property: "opacity"
                    to: 1
                    duration: 200
                }

            }

        }

    }

    Behavior on topY {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }

    }

    // Only the cards take input
    mask: Region {
        item: stack
    }

}
