pragma ComponentBehavior: Bound

import "../services"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// The programs in the tray (services/TrayState) as icons, right of the gear in the bar, always in view
// while the tray is on and not empty (until 2026-11-27 a drawer behind a right-click on the logo).
// They glide in one after another when the first program arrives, like the picker slots.
// Click = bring the program up (TrayState.open), right-click = a context menu below the icon with Open
// and Exit (bar/TrayContextMenu), middle click = the program's second action, wheel = whatever
// the program does with it (volume ...).
// Part of MainBar.qml (mainBar = core).
Item {
    id: drawer

    required property var mainBar
    readonly property real t: mainBar.trayRevealT
    // Index of the icon under the mouse (-1 = none), and of the one whose menu is open
    property int hoveredIndex: -1
    // An icon from the theme by name ("image://icon/<name>") only if the theme has it, else the name
    // without "-symbolic", else "" (the glyph shows). Pictures sent by the program itself stay as they are.
    function iconSource(icon) {
        const s = String(icon || "");
        if (!s.startsWith("image://icon/"))
            return s;

        const name = s.slice(13).split("?")[0];
        if (Quickshell.iconPath(name, true) !== "")
            return s;

        const plain = name.replace(/-symbolic$/, "");
        return plain !== name && Quickshell.iconPath(plain, true) !== "" ? "image://icon/" + plain : "";
    }

    property int openIndex: -1
    // The pill stays behind the icon with the open menu
    readonly property int markedIndex: hoveredIndex >= 0 ? hoveredIndex : openIndex
    readonly property real slotW: Math.round(16 + 16 * BarState.density)

    width: t * content.implicitWidth
    height: 32
    clip: true

    // Shared pill behind the icons; on hover it gathers behind that one (like in BarDrawer)
    Item {
        x: content.x
        width: content.implicitWidth
        height: content.height
        opacity: drawer.t

        Rectangle {
            readonly property bool focused: drawer.markedIndex >= 0
            readonly property real pillWidth: Math.round(18 + 16 * BarState.density)
            readonly property real fullW: content.implicitWidth - (content.rightPadding - content.leftPadding)

            x: focused ? content.leftPadding + drawer.markedIndex * (drawer.slotW + content.spacing) + drawer.slotW / 2 - pillWidth / 2 : 0
            y: (parent.height - height) / 2
            width: focused ? pillWidth : fullW
            height: 32
            radius: height / 2
            // At rest a faint pill behind all icons, on hover it gathers behind that one
            color: WalColors.withAlpha(WalColors.color4, focused ? 0.3 : 0.12)

            Behavior on x {
                NumberAnimation {
                    duration: 320
                    // No overshoot: the pill glides straight to its place
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on width {
                NumberAnimation {
                    duration: 320
                    // No overshoot: the pill glides straight to its place
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    Row {
        id: content

        x: drawer.width - implicitWidth
        height: parent.height
        // Same room left and right of the icons inside the pill
        leftPadding: 6
        // Gap to the window title (the pill ends leftPadding after the last icon, the rest is gap)
        rightPadding: leftPadding + Theme.gapSmall * 2 + 9
        spacing: Math.round(6 * BarState.density)
        opacity: drawer.t

        Repeater {
            model: TrayState.items

            Item {
                id: slot

                required property var modelData
                required property int index
                readonly property bool hovered: mouse.containsMouse
                // Its menu is open right now
                readonly property bool open: TrayState.menuOpen && TrayState.menuProgram === modelData
                // The icons come in one after another, like the picker slots
                readonly property real reveal: drawer.mainBar.clamp01(drawer.t * 1.6 - Math.min(0.6, index * 0.12))

                width: drawer.slotW
                height: 32
                opacity: reveal * (TrayState.isHidden(modelData) ? 0.45 : 1)
                scale: 0.6 + 0.4 * reveal
                onHoveredChanged: {
                    if (hovered)
                        drawer.hoveredIndex = index;
                    else if (drawer.hoveredIndex === index)
                        drawer.hoveredIndex = -1;
                }
                onOpenChanged: {
                    if (open)
                        drawer.openIndex = index;
                    else if (drawer.openIndex === index)
                        drawer.openIndex = -1;
                }

                IconImage {
                    id: trayIcon

                    anchors.centerIn: parent
                    implicitSize: 18
                    source: drawer.iconSource(slot.modelData.icon)
                    visible: source != ""
                    scale: slot.hovered ? 1.14 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.anim.durations.fast
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                // No icon for it in the icon theme (e.g. a fresh system without a full theme): a neutral
                // glyph instead of Qt's magenta "missing" square
                Text {
                    anchors.centerIn: parent
                    visible: !trayIcon.visible
                    text: String.fromCodePoint(0xf0614) // md-application_outline
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    scale: trayIcon.scale
                }

                // The program wants attention
                Rectangle {
                    x: parent.width / 2 + 5
                    y: 5
                    width: 6
                    height: 6
                    radius: 3
                    color: WalColors.color4
                    visible: slot.modelData.status === Status.NeedsAttention
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: (event) => {
                        const item = slot.modelData;
                        if (event.button === Qt.MiddleButton)
                            item.secondaryActivate();
                        else if (event.button === Qt.RightButton)
                            TrayState.openMenu(item, slot.mapToItem(null, slot.width / 2, 0).x);
                        else
                            TrayState.open(item);
                    }
                    onWheel: (wheel) => {
                        return slot.modelData.scroll(wheel.angleDelta.y, false);
                    }
                }

            }

        }

    }

}
