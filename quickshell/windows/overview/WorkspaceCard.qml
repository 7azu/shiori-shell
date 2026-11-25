import "../../services"
import "../../common/WorkspaceNumbers.js" as WorkspaceNumbers
import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: card

    required property var view
    required property int index
    required property int modelData
    required property real previewHeight
    required property bool previewsEnabled

    readonly property int wsId: modelData
    readonly property var ws: view.workspaceById(wsId)
    readonly property var monitor: ws?.monitor ?? view.monitor
    readonly property var geom: view.monitorGeom(monitor)
    readonly property bool current: wsId === view.originWorkspaceId
    readonly property bool activeElsewhere: !!ws?.active && !current
    readonly property bool foreign: !!ws?.monitor && !!view.monitor && ws.monitor.name !== view.monitor.name
    readonly property bool selected: view.selectedId === wsId
    readonly property bool dropTarget: view.dropTargetId === wsId
    readonly property bool interactive: view.phase === "open"
    readonly property real previewInset: MachineConfig.px(4)
    readonly property real monitorAspect: geom ? geom.w / geom.h : view.width / Math.max(1, view.height)
    readonly property color surfaceColor: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.055))
    readonly property string label: qsTr("Workspace %1").arg(wsId)

    // Unchanged window lists keep their screencopy session and their mouse grab.
    readonly property string winKey: view.windowsOn(wsId).map(win => win.address).join(",")
    property var wins: []
    onWinKeyChanged: wins = view.windowsOn(wsId)
    Component.onCompleted: wins = view.windowsOn(wsId)

    function normRect(ipc, position, count) {
        if (geom && ipc?.at && ipc?.size && ipc.size[0] > 0 && ipc.size[1] > 0)
            return {
                x: (ipc.at[0] - geom.x) / geom.w,
                y: (ipc.at[1] - geom.y) / geom.h,
                w: ipc.size[0] / geom.w,
                h: ipc.size[1] / geom.h
            };

        const columns = Math.max(1, Math.ceil(Math.sqrt(count)));
        const rows = Math.max(1, Math.ceil(count / columns));
        const gap = 0.055;
        const width = (1 - gap * (columns + 1)) / columns;
        const height = (1 - gap * (rows + 1)) / rows;
        return {
            x: gap + position % columns * (width + gap),
            y: gap + Math.floor(position / columns) * (height + gap),
            w: width,
            h: height
        };
    }

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: view.go(wsId, null)

    scale: hit.pressed ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: MachineConfig.px(18)
        color: card.selected
            ? Qt.tint(card.surfaceColor, WalColors.withAlpha(Theme.accent, 0.15))
            : Qt.tint(card.surfaceColor, WalColors.withAlpha(WalColors.color7, 0.045))

        Behavior on color { ColorAnimation { duration: 160 } }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        enabled: card.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.view.go(card.wsId, null)
        onPositionChanged: (mouse) => card.view.pointerMoved(mapToItem(card.view, mouse.x, mouse.y), card.wsId)
    }

    Rectangle {
        id: preview
        x: card.previewInset
        y: card.previewInset
        width: Math.max(1, card.width - 2 * card.previewInset)
        height: Math.max(1, card.previewHeight - card.previewInset)
        radius: MachineConfig.px(14)
        color: card.surfaceColor

        Text {
            anchors.centerIn: parent
            text: WorkspaceNumbers.kanjiNumber(card.wsId)
            visible: card.wins.length === 0
            color: WalColors.withAlpha(WalColors.color7, 0.18)
            font.family: Theme.fontDisplay
            font.pixelSize: Math.max(8, Math.round(preview.height * 0.5))
        }
    }

    Rectangle {
        id: previewMask
        anchors.fill: preview
        radius: preview.radius
        visible: false
    }

    Item {
        anchors.fill: preview
        layer.enabled: card.wins.length > 0 && card.previewsEnabled && GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: OpacityMask { maskSource: previewMask }

        Item {
            id: screenArea
            anchors.centerIn: parent
            width: Math.max(0, Math.min(parent.width, parent.height * card.monitorAspect))
            height: width / Math.max(0.01, card.monitorAspect)
            clip: true

            Repeater {
                id: thumbs
                readonly property Item host: card
                model: card.wins

                delegate: WindowThumb {
                    card: thumbs.host
                }
            }
        }
    }

    Item {
        y: card.previewHeight
        width: card.width
        height: card.height - y

        Row {
            id: titleGroup
            anchors.left: parent.left
            anchors.leftMargin: MachineConfig.px(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: MachineConfig.px(6)

            Rectangle {
                width: MachineConfig.px(6)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: card.current ? Theme.accent : Theme.textFaint
                visible: card.current || card.activeElsewhere
            }

            Text {
                width: Math.min(implicitWidth, Math.max(1, titleGroup.parent.width - titleGroup.x
                    - (monitorLabel.visible ? monitorLabel.width + 14 : 8)
                    - (card.current || card.activeElsewhere ? MachineConfig.px(12) : 0)))
                anchors.verticalCenter: parent.verticalCenter
                text: card.width < MachineConfig.px(155) ? String(card.wsId) : card.label
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeBody
                font.weight: card.selected || card.current ? Font.DemiBold : Font.Medium
                color: card.current || card.selected ? Theme.text : Theme.textDim
            }

        }

        Text {
            id: monitorLabel
            anchors.right: parent.right
            anchors.rightMargin: MachineConfig.px(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.26)
            visible: card.foreign
            text: card.monitor?.name ?? ""
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: surface.radius
        color: "transparent"
        border.width: card.selected || card.dropTarget ? 2 : 1
        border.color: card.dropTarget ? Theme.accent2
            : card.selected ? WalColors.withAlpha(Theme.accent, 0.8)
            : WalColors.withAlpha(WalColors.color7, 0.12)
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }
}
