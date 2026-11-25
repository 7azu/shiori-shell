import "../services"
import QtQuick

// Icon group on the right (sync, Claude, VPN, audio, stats, battery) with a shared pill: hover opens the icon's
// dropdown. The power icon has none and therefore stands on its own at the far right (MainBar.qml, after the clock).
// Part of MainBar.qml (mainBar = core).
Item {
    id: iconGroup

    required property var mainBar
    property alias clBtn: clBtn
    property alias vpnBtn: vpnBtn
    property alias atBtn: atBtn
    property alias stBtn: stBtn
    property alias batBtn: batBtn
    property alias syBtn: syBtn
    property int hoveredIndex: -1
    // Index = position in dropdownIds (fixed, independent of the order in the bar)
    readonly property var icons: [atBtn, stBtn, vpnBtn, clBtn, batBtn, syBtn]
    readonly property var dropdownIds: ["audio", "stats", "vpn", "claude", "battery", "sync"]
    readonly property real reveal: Math.max(syBtn.reveal, clBtn.reveal, vpnBtn.reveal, atBtn.reveal, stBtn.reveal, batBtn.reveal)
    readonly property real pillWidth: Math.round(18 + 16 * BarState.density)
    readonly property int lockedIndex: dropdownIds.indexOf(DropdownState.current)
    readonly property string hoveredId: hoveredIndex >= 0 ? dropdownIds[hoveredIndex] : ""
    readonly property int effectiveIndex: hoveredIndex >= 0 ? hoveredIndex : lockedIndex
    readonly property bool focused: effectiveIndex >= 0
    function pillGeometry(index) {
        const icon = icons[index];
        if (!icon)
            return {x: 0, width: width};

        const w = icon.visible ? Math.max(pillWidth, icon.buttonWidth + icon.pillExtra) : pillWidth;
        return {x: innerRow.x + icon.x + (icon.width - w) / 2, width: w};
    }

    function iconCenterX(i) {
        const c = icons[i];
        if (!c)
            return 0;

        return iconGroup.mapToItem(null, innerRow.x + c.x + c.width / 2, 0).x;
    }

    anchors.verticalCenter: parent.verticalCenter
    height: parent.height
    // The first and last tile each bring half a spacing.
    width: innerRow.implicitWidth + (Math.round(28 * BarState.density) - innerRow.itemGap) * reveal
    visible: reveal > 0
    onHoveredIdChanged: {
        // No dropdowns in edit mode
        if (mainBar.editMode)
            return ;

        if (hoveredId !== "")
            DropdownState.enter(hoveredId, iconCenterX(hoveredIndex));
        else
            DropdownState.leave(DropdownState.hoveredIcon);
    }

    Rectangle {
        id: morphPill

        property int targetIndex: -1
        readonly property var targetGeometry: iconGroup.pillGeometry(targetIndex)
        property real slide: 1
        property real offsetX: 0
        property real offsetWidth: 0

        // Animate the focus change, take layout changes along directly.
        function moveTo(index) {
            const previousX = x;
            const previousWidth = width;
            moveAnimation.stop();
            targetIndex = index;
            offsetX = previousX - targetGeometry.x;
            offsetWidth = previousWidth - targetGeometry.width;
            slide = 0;
            moveAnimation.start();
        }

        Component.onCompleted: targetIndex = iconGroup.effectiveIndex
        Connections {
            target: iconGroup
            function onEffectiveIndexChanged() {
                morphPill.moveTo(iconGroup.effectiveIndex);
            }
        }

        anchors.verticalCenter: parent.verticalCenter
        height: 32
        radius: height / 2
        opacity: iconGroup.reveal
        color: WalColors.withAlpha(WalColors.color4, iconGroup.focused ? 0.3 : 0.12)
        x: targetGeometry.x + offsetX * (1 - slide)
        width: targetGeometry.width + offsetWidth * (1 - slide)

        NumberAnimation {
            id: moveAnimation
            target: morphPill
            property: "slide"
            to: 1
            duration: 320
            easing.type: Easing.OutBack
            easing.overshoot: 1.08
        }

        Behavior on color {
            ColorAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }

        }

    }

    Row {
        id: innerRow

        readonly property real itemGap: Math.round(10 * BarState.density)

        anchors.centerIn: parent
        height: parent.height
        Component.onCompleted: Qt.callLater(() => {
            return mainBar.applyOrder("right");
        })

        SyncToggle {
            id: syBtn

            // Only with sync entries in the settings (services/SyncState)
            enabled: SyncState.hasEntries && mainBar.iconShown("sync")
            reveal: !SyncState.hasEntries ? 0 : (BarIcons.shown("sync") ? 1 : mainBar.editReveal)
            itemGap: innerRow.itemGap

            EditBadge {
                mainBar: iconGroup.mainBar
                iconId: "sync"
                group: "right"
            }

        }

        AiUsageToggle {
            id: clBtn

            enabled: mainBar.iconShown("claude")
            reveal: BarIcons.shown("claude") ? 1 : mainBar.editReveal
            itemGap: innerRow.itemGap

            EditBadge {
                mainBar: iconGroup.mainBar
                iconId: "claude"
                group: "right"
            }

        }

        VpnToggle {
            id: vpnBtn

            enabled: mainBar.iconShown("vpn")
            reveal: BarIcons.shown("vpn") ? 1 : mainBar.editReveal
            itemGap: innerRow.itemGap

            EditBadge {
                mainBar: iconGroup.mainBar
                iconId: "vpn"
                group: "right"
            }

        }

        AudioToggle {
            id: atBtn

            enabled: mainBar.iconShown("audio")
            reveal: BarIcons.shown("audio") ? 1 : mainBar.editReveal
            itemGap: innerRow.itemGap

            EditBadge {
                mainBar: iconGroup.mainBar
                iconId: "audio"
                group: "right"
            }

        }

        Stats {
            id: stBtn

            enabled: mainBar.iconShown("stats")
            reveal: BarIcons.shown("stats") ? 1 : mainBar.editReveal
            itemGap: innerRow.itemGap

            EditBadge {
                mainBar: iconGroup.mainBar
                iconId: "stats"
                group: "right"
            }

        }

        BatteryToggle {
            id: batBtn

            enabled: mainBar.iconShown("battery")
            reveal: BarIcons.shown("battery") ? 1 : mainBar.editReveal
            itemGap: innerRow.itemGap

            EditBadge {
                mainBar: iconGroup.mainBar
                iconId: "battery"
                group: "right"
            }

        }

    }

    HoverHandler {
        id: groupHover

        onPointChanged: {
            const px = point.position.x;
            let found = -1;
            const kids = iconGroup.icons;
            for (let i = 0; i < kids.length; i++) {
                const c = kids[i];
                if (!c || !c.visible)
                    continue;

                const cx = innerRow.x + c.x + c.sideGap;
                if (c.enabled && px >= cx && px <= cx + c.buttonWidth) {
                    found = i;
                    break;
                }
            }
            if (iconGroup.hoveredIndex !== found)
                iconGroup.hoveredIndex = found;

        }
        onHoveredChanged: {
            if (!hovered)
                iconGroup.hoveredIndex = -1;

        }
    }

}
