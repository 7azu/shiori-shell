import "../services"
import QtQuick

// Overlay for edit mode: click = icon on/off, drag = move.
// Dims icons that are off and shows the state at the top right.
MouseArea {
    id: badge

    required property var mainBar
    property string iconId: ""
    property string group: "" // "left" | "right"
    // What is moved (normally the icon itself) and the Row it lies in
    property Item dragItem: parent
    readonly property Item row: dragItem ? dragItem.parent : null
    readonly property bool on: BarIcons.shown(iconId)
    property bool dragging: false
    property bool moved: false
    property real pressX: 0
    property real grabX: 0
    property real pointerX: 0
    // Preview offset while reordering (sets mainBar.dragTo)
    property real previewDx: 0
    // Dragged: follows the pointer. Otherwise: preview place, glides there.
    property Translate shift

    shift: Translate {
        x: badge.dragging ? badge.pointerX - badge.grabX - badge.dragItem.x : badge.previewDx

        Behavior on x {
            enabled: !badge.dragging && !mainBar.reorderSnap

            NumberAnimation {
                duration: 240
                easing.type: Easing.OutCubic
            }

        }

    }

    anchors.fill: parent
    anchors.leftMargin: (dragItem as BarIcon)?.sideGap ?? 0
    anchors.rightMargin: anchors.leftMargin
    z: 100
    visible: mainBar.editMode
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    Component.onCompleted: {
        if (dragItem)
            dragItem.transform = shift;

        mainBar.editBadges[iconId] = badge;
    }
    onPressed: (mouse) => {
        pressX = mouse.x;
        moved = false;
    }
    onPositionChanged: (mouse) => {
        if (!pressed || group === "" || !row || mouse.buttons !== Qt.LeftButton)
            return ;

        if (!dragging && Math.abs(mouse.x - pressX) > 6) {
            // Commit the not yet applied order of a previous drag first
            if (mainBar.commitTimer.running) {
                mainBar.commitTimer.stop();
                mainBar.commitTimer.triggered();
            }
            grabX = badge.mapToItem(dragItem, pressX, 0).x;
            moved = true;
            dragging = true;
            dragItem.z = 10;
        }
        if (dragging) {
            pointerX = badge.mapToItem(row, mouse.x, 0).x;
            mainBar.dragTo(group, iconId, pointerX);
        }
    }
    onReleased: {
        if (!dragging)
            return ;

        dragging = false;
        dragItem.z = 0;
        mainBar.finishDrag();
    }
    onClicked: {
        // No toggle after dragging
        if (moved) {
            moved = false;
            return ;
        }
        BarIcons.toggle(iconId);
    }
    // Lifted icon while dragging
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, 34) + 6
        height: Math.min(parent.height, 32) + 4
        radius: height / 2
        color: WalColors.withAlpha(WalColors.color4, 0.22)
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color4, 0.6)
        opacity: badge.dragging ? 1 : 0
        scale: badge.dragging ? 1 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: 140
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
            }

        }

    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, 34)
        height: Math.min(parent.height, 32)
        radius: height / 2
        color: WalColors.withAlpha(WalColors.color0, 0.7)
        opacity: badge.on ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }

        }

    }

    Rectangle {
        x: parent.width - width
        y: Math.max(0, (parent.height - 32) / 2)
        width: 13
        height: 13
        radius: height / 2
        color: badge.on ? WalColors.color4 : WalColors.color0
        border.width: 1.2
        border.color: badge.on ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.5)
        scale: badge.pressed ? 0.8 : 1

        Text {
            anchors.centerIn: parent
            text: badge.on ? "󰄬" : "󰅖"
            color: badge.on ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.8)
            font.family: Theme.font
            font.pixelSize: 9
            font.bold: true
        }

        Behavior on color {
            ColorAnimation {
                duration: 160
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutBack
            }

        }

    }

}
