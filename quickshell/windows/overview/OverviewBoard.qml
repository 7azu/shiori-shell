import "../../common"
import "../../services"
import QtQuick

Item {
    id: board

    required property Item view
    readonly property int columns: view.width >= view.height * 1.33 ? 5 : 2
    readonly property int rows: Math.ceil(view.slotIds.length / columns)
    readonly property real inset: MachineConfig.px(columns === 5 ? 26 : 20)
    readonly property real gap: MachineConfig.px(12)
    readonly property real headerHeight: MachineConfig.px(64)
    readonly property real footerHeight: MachineConfig.px(33)
    readonly property real screenMargin: Math.max(12, Math.round(Math.min(view.width, view.height) * 0.045))
    readonly property real previewAspect: columns === 5 ? 1.75 : 1.25
    readonly property real cardWidth: {
        const cap = MachineConfig.px(columns === 5 ? 1760 : 840);
        const widthLimit = Math.min(view.width - 2 * screenMargin, cap) - 2 * inset;
        const heightLimit = view.height - 2 * screenMargin - headerHeight - inset;
        const byWidth = (widthLimit - (columns - 1) * gap) / columns;
        const byHeight = ((heightLimit - (rows - 1) * gap) / rows - footerHeight) * previewAspect;
        return Math.max(1, Math.floor(Math.min(byWidth, byHeight)));
    }
    readonly property real previewHeight: Math.floor(cardWidth / previewAspect)
    readonly property real cardHeight: previewHeight + footerHeight
    readonly property real cornerRadius: MachineConfig.px(30)
    readonly property bool interactive: view.phase === "open"
    readonly property var previewOrder: view.slotIds.includes(view.originWorkspaceId)
        ? [view.originWorkspaceId].concat(view.slotIds.filter(id => id !== view.originWorkspaceId))
        : view.slotIds

    function cardFor(wsId) {
        return cards.itemAt(view.slotIds.indexOf(wsId));
    }

    function workspaceAt(point) {
        const local = mapFromItem(view, point.x, point.y);
        const x = local.x - inset;
        const y = local.y - headerHeight;
        if (x < 0 || y < 0)
            return -1;

        const column = Math.floor(x / (cardWidth + gap));
        const row = Math.floor(y / (cardHeight + gap));
        if (column >= columns || row >= rows || x % (cardWidth + gap) > cardWidth
            || y % (cardHeight + gap) > cardHeight)
            return -1;
        return view.slotIds[row * columns + column] ?? -1;
    }

    width: 2 * inset + columns * cardWidth + (columns - 1) * gap
    height: headerHeight + rows * cardHeight + (rows - 1) * gap + inset
    x: Math.round((view.width - width) / 2)
    y: Math.round((view.height - height) / 2) + (1 - view.reveal) * MachineConfig.px(46)
    scale: 0.94 + 0.06 * view.reveal
    opacity: Math.min(1, view.reveal * 1.06)
    visible: view.shown && view.reveal > 0
    // The render layer stays the same from fading in to closing.
    layer.enabled: view.shown && GraphicsInfo.api !== GraphicsInfo.Software
    layer.sourceRect: Qt.rect(-16, -16, width + 32, height + 36)
    layer.smooth: true

    SoftShadow {
        radius: board.cornerRadius
        raised: true
    }

    Rectangle {
        anchors.fill: parent
        radius: board.cornerRadius
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color7, 0.19)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.15)) }
            GradientStop { position: 1; color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.075)) }
        }
    }

    // The workspace area catches clicks in the gaps.
    MouseArea {
        anchors.fill: parent
        enabled: board.interactive
    }

    Text {
        x: board.inset + 2
        anchors.top: parent.top
        anchors.topMargin: Math.round((board.headerHeight - implicitHeight) / 2)
        text: qsTr("Workspaces")
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: MachineConfig.px(26)
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: closeButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Math.round((board.headerHeight - height) / 2)
        anchors.rightMargin: board.inset
        width: MachineConfig.px(32)
        height: width
        radius: height / 2
        color: hit.containsMouse ? Theme.glassHover : Theme.glass
        scale: hit.pressed ? 0.9 : 1

        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Close workspace overview")
        Accessible.onPressAction: board.view.dismiss()

        Text {
            anchors.centerIn: parent
            text: "×"
            font.family: Theme.fontUi
            font.pixelSize: MachineConfig.px(22)
            color: Theme.text
        }

        MouseArea {
            id: hit
            anchors.fill: parent
            enabled: board.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: board.view.dismiss()
        }

        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    Repeater {
        id: cards
        model: board.view.slotIds

        delegate: WorkspaceCard {
            view: board.view
            previewsEnabled: board.previewOrder.indexOf(wsId) < board.view.previewSlots
            previewHeight: board.previewHeight
            width: board.cardWidth
            height: board.cardHeight
            x: board.inset + (index % board.columns) * (width + board.gap)
            y: board.headerHeight + Math.floor(index / board.columns) * (height + board.gap)
        }
    }
}
