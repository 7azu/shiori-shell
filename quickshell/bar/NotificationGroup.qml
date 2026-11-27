import "../common"
import "../services"
import QtQuick
import Quickshell

// The notifications of one app in the center (delegate of the list in bar/NotificationPanel).
// One notification: just its card. Several: a small head (app, count, show all, clear) and a stack:
// the newest card in front, the edges of two more peek out below it. A click on the stack (or the
// head) fans it out: the cards glide down from behind the front one, the edges fade; "Show less"
// folds them back. Under the pointer the folded stack lifts a little and its edges spread.
Item {
    id: group

    // App name = key of the group (the list's model is the list of keys)
    required property string modelData
    required property int index
    // The panel (bar/NotificationPanel): holds which groups are open, the intro counter and "clear all".
    // Not called "panel": the delegate's own property would shadow the panel's id there.
    required property var host
    readonly property var entries: host.groupItems(modelData)
    readonly property int count: entries.length
    readonly property bool stacked: count > 1
    readonly property bool open: stacked && host.openGroups[modelData] === true
    // Heights of the cards (they differ with the length of the text)
    property var heights: []
    readonly property real gap: 8
    // How far each edge of the folded stack looks out below the front card
    readonly property real peek: stackHover.hovered && !open ? 9 : 7
    readonly property real headH: stacked ? 30 : 0
    readonly property real frontH: heights.length > 0 ? (heights[0] || 0) : 0
    readonly property real bodyH: {
        if (!stacked)
            return frontH;

        if (!open)
            return frontH + peek * Math.min(2, count - 1);

        let sum = 0;
        for (let i = 0; i < count; i++) sum += (heights[i] || 0)
        return sum + gap * (count - 1);
    }

    function setHeight(i, h) {
        if (heights[i] === h)
            return ;

        const next = heights.slice();
        next[i] = h;
        heights = next;
    }

    // Where card i stands: fanned out one below the other, or folded behind the front card
    function yOf(i) {
        if (!open || i === 0)
            return headH;

        let y = headH;
        for (let j = 0; j < i; j++) y += (heights[j] || 0) + gap
        return y;
    }

    width: parent ? parent.width : 0
    height: headH + bodyH

    Behavior on height {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutCubic
        }

    }

    // ---------- Head of a stack ----------
    Item {
        id: head

        width: parent.width
        height: 30
        opacity: group.stacked ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }

        }

        Row {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -3
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: group.modelData.toUpperCase()
                color: headMouse.containsMouse ? WalColors.color7 : WalColors.withAlpha(WalColors.color7, 0.6)
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeMicro
                font.bold: true
                font.letterSpacing: 1.4

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: countText.implicitWidth + 10
                height: 16
                radius: height / 2
                color: WalColors.withAlpha(WalColors.color4, 0.16)

                Text {
                    id: countText

                    anchors.centerIn: parent
                    text: group.count
                    color: WalColors.color4
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.features: Theme.tabular
                    font.bold: true
                }

            }

        }

        MouseArea {
            id: headMouse

            anchors.fill: parent
            anchors.rightMargin: 34
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: group.host.toggleGroup(group.modelData)
        }

        // "Show all" / "Show less" with a turning chevron, then the cross that clears the group
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -3
            spacing: 12

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                CrossText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 62
                    horizontalAlignment: Text.AlignRight
                    text: group.open ? "Show less" : "Show all"
                    color: headMouse.containsMouse ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.45)
                    font.pixelSize: Theme.sizeSmall

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅀"
                    color: headMouse.containsMouse ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.45)
                    font.family: Theme.font
                    font.pixelSize: 13
                    rotation: group.open ? 180 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅖"
                color: clearMouse.containsMouse ? WalColors.color1 : WalColors.withAlpha(WalColors.color7, 0.4)
                font.family: Theme.font
                font.pixelSize: 12
                scale: clearMouse.containsMouse ? 1.2 : 1

                MouseArea {
                    id: clearMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationState.dismissApp(group.modelData)
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.anim.durations.fast
                    }

                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                    }

                }

            }

        }

    }

    // ---------- The edges of the folded stack ----------
    Repeater {
        model: 2

        delegate: Item {
            id: edge

            required property int index
            readonly property int k: index + 1
            readonly property bool shown: group.stacked && !group.open && group.count > k

            // Only the part below the front card (or the edge before it) is drawn, so nothing shows
            // through the see-through cards
            y: group.headH + group.frontH + group.peek * index
            width: group.width
            height: group.peek
            clip: true
            z: -k
            opacity: shown ? (k === 1 ? 1 : 0.6) : 0
            visible: opacity > 0.01

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - height
                width: group.width * (1 - 0.07 * edge.k)
                height: 28
                radius: 14
                color: WalColors.withAlpha(WalColors.color7, edge.k === 1 ? 0.06 : 0.04)
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 260
                }

            }

            Behavior on y {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    // ---------- The cards ----------
    Repeater {
        id: cards

        model: ScriptModel {
            values: group.entries
        }

        delegate: NotificationCard {
            id: card

            readonly property bool front: index === 0
            readonly property bool showsUp: front || group.open

            width: group.width
            introRun: group.host.introRun
            clearing: group.host.clearing
            z: group.count - index
            y: group.yOf(index)
            // Folded, the cards behind the front one are hidden (a taller one would stick out below it);
            // fanning out they slide down from under it, covered by the cards in front (opaque faces)
            opacity: showsUp ? 1 : 0
            visible: opacity > 0.01
            enabled: showsUp
            // The folded stack lifts a little under the pointer
            scale: front && group.stacked && !group.open && stackHover.hovered ? 1.012 : 1
            onHeightChanged: group.setHeight(index, height)
            onIndexChanged: group.setHeight(index, height)
            Component.onCompleted: group.setHeight(index, height)

            Behavior on y {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: card.showsUp ? 120 : 300
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    // The folded stack as a whole: hover lifts it, a click fans it out (the front card's own
    // buttons only work when it is open, as with a stack on a phone)
    Item {
        y: group.headH
        width: group.width
        height: group.bodyH
        z: group.count + 1
        visible: group.stacked && !group.open

        HoverHandler {
            id: stackHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: group.host.toggleGroup(group.modelData)
        }

    }

}
