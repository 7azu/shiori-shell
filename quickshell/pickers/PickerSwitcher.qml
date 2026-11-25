import "../services"
import QtQuick
import Quickshell

// Icons for switching between the tab pickers (right in the search field). Hover behavior like the
// icon group at the top right of the MainBar: ONE pill, without hover a capsule behind all icons,
// on hover it contracts onto the icon under the mouse; icons grow on hover.
// Values (colors, curves, sizes) deliberately taken 1:1 from MainBar/iconGroup.
Item {
    id: root

    // Optional: the search field that should get the focus again
    // after a click. The parent sets it by binding.
    property Item focusTarget: null
    // Icons for the pickers. The order comes from PickerManager.tabPickers (the same as for Tab /
    // Shift+Tab); add new tab pickers there and only add their icon here.
    readonly property var icons: ({
        "app": "󰀻",
        "music": "󰝚",
        "wallpaper": "󰋩"
    })
    readonly property var items: PickerManager.tabPickers.map((name) => {
        return {
            "name": name,
            "icon": icons[name] || "?"
        };
    })

    // Shared hover state of all instances (reason in PickerManager.switcherHover)
    readonly property int hoveredIndex: PickerManager.switcherHover
    readonly property int activeIndex: {
        for (let i = 0; i < items.length; i++) {
            if (PickerManager.isOpen(items[i].name))
                return i;

        }
        return -1;
    }
    // As in the MainBar: without hover the pill lies as a big capsule behind all icons and only
    // contracts onto the hovered icon. The active picker is shown by the icon brightness.
    readonly property int effectiveIndex: hoveredIndex
    readonly property bool focused: effectiveIndex >= 0
    readonly property real pillWidth: Math.round(18 + 16 * BarState.density)
    // Fixed padding instead of a centered row: this way the position of the icons is a constant and the
    // pill cannot land next to the icon if the width still changes after opening
    readonly property real pad: Math.round(14 * BarState.density)
    readonly property real pillX: {
        // builtItems as a dependency: itemAt() alone does not trigger a recompute
        // if the delegates are only created after the first evaluation
        const c = (focused && root.builtItems > 0) ? repeater.itemAt(effectiveIndex) : null;
        return c ? pad + c.x + c.width / 2 - pillWidth / 2 : 0;
    }
    // Only animate after the first layout: otherwise the pill morphs visibly once while loading
    property bool animate: false
    // Which icon is SHOWN as active (slightly enlarged, fully bright). Deliberately lags behind
    // activeIndex: every tab picker has its own bar, in which the new picker would already be active.
    // So on appearing it starts in the state of the previous picker and then animates to the
    // new one -> when switching with Tab (or a click) you see the old icon shrink and the new one grow.
    property int shownActive: activeIndex
    // Counts created icons: in the asynchronous Loader the Repeater reports count BEFORE the delegates
    // exist -> itemAt() returns null and bindings on it would never be re-evaluated
    property int builtItems: 0
    // On appearing jump to the start state instead of animating (otherwise the underline starts
    // from its outdated position and is redirected 40 ms later -> stutters)
    property bool jump: false

    function indexOfPicker(name) {
        for (let i = 0; i < items.length; i++) {
            if (items[i].name === name)
                return i;

        }
        return -1;
    }

    implicitWidth: row.implicitWidth + 2 * pad
    implicitHeight: 32
    Component.onCompleted: Qt.callLater(() => {
        root.animate = true;
    })
    // enabled = this picker is the active one right now (PickerSlot.enabled: shown)
    onEnabledChanged: {
        if (!enabled)
            return ;

        jump = true;
        shownActive = indexOfPicker(PickerManager.previousPicker);
        jump = false;
        activateTimer.restart();
    }
    onActiveIndexChanged: {
        if (enabled)
            activateTimer.restart();

    }

    // A few frames in the old state, so the animation really starts visibly
    Timer {
        id: activateTimer

        interval: 40
        onTriggered: root.shownActive = root.activeIndex
    }

    Rectangle {
        id: morphPill

        anchors.verticalCenter: parent.verticalCenter
        height: 32
        radius: height / 2
        // Without hover: capsule over the whole group (0.12), hovered: pill on the icon (0.3)
        color: WalColors.withAlpha(WalColors.color4, root.focused ? 0.3 : 0.12)
        x: root.focused ? root.pillX : 0
        width: root.focused ? root.pillWidth : root.width

        Behavior on x {
            enabled: root.animate

            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.08
            }

        }

        Behavior on width {
            enabled: root.animate

            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.08
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }

        }

    }

    Row {
        id: row

        x: root.pad
        spacing: Math.round(10 * BarState.density)
        height: parent.height

        Repeater {
            id: repeater

            model: root.items
            onItemAdded: root.builtItems++
            onItemRemoved: root.builtItems--

            delegate: Item {
                id: btn

                required property var modelData
                required property int index
                readonly property bool isHovered: root.hoveredIndex === index
                readonly property bool isActive: root.shownActive === index

                width: iconText.implicitWidth + Math.round(16 * BarState.density)
                height: row.height

                Text {
                    id: iconText

                    anchors.centerIn: parent
                    text: btn.modelData.icon
                    // Foreground color instead of color2: depending on the wallpaper color2 is a muted
                    // middle tone and hardly readable on a laptop with low brightness
                    color: Theme.text
                    // the active picker full and slightly enlarged, the others toned down a bit;
                    // hovered 1.3 as in the MainBar. Do not tone down too far: on a laptop with
                    // low brightness 0.55 was hardly visible
                    opacity: (btn.isActive || btn.isHovered) ? 1 : 0.85
                    font.family: Theme.font
                    font.pixelSize: 16
                    // As soon as any icon is hovered, the active one gives up its enlargement:
                    // then only the hovered one is big (as in the bar)
                    scale: btn.isHovered ? 1.3 : ((btn.isActive && root.hoveredIndex < 0) ? 1.15 : 1)

                    // Hover as fast as in the bar, the change of the active picker a bit
                    // slower and springy, so it stands out next to the slide on a tab switch
                    Behavior on opacity {
                        enabled: !root.jump

                        NumberAnimation {
                            duration: root.hoveredIndex >= 0 ? 150 : 260
                        }

                    }

                    Behavior on scale {
                        enabled: !root.jump

                        NumberAnimation {
                            duration: root.hoveredIndex >= 0 ? 150 : 320
                            easing.type: root.hoveredIndex >= 0 ? Easing.OutCubic : Easing.OutBack
                            easing.overshoot: 1.6
                        }

                    }

                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        PickerManager.open(btn.modelData.name);
                        if (root.focusTarget)
                            root.focusTarget.forceActiveFocus();

                    }
                }

            }

        }

    }

    // Underline under the active picker: brightness/size alone are hard to tell apart on a laptop with
    // low brightness. Follows shownActive (not activeIndex), so on a tab switch it glides
    // from the old to the new picker together with the shrinking/growing of the icons.
    Rectangle {
        id: activeMark

        // builtItems as a dependency, so the line also appears on the very first opening
        readonly property Item target: (root.shownActive >= 0 && root.builtItems > 0) ? repeater.itemAt(root.shownActive) : null
        readonly property real targetX: target ? row.x + target.x + target.width / 2 - width / 2 : -1

        // Only set x if there is a target: when hiding (no active picker) the line
        // stays instead of sliding to the left during the fade-out
        onTargetXChanged: {
            if (targetX >= 0)
                x = targetX;

        }
        Component.onCompleted: {
            if (targetX >= 0)
                x = targetX;

        }
        width: 12
        height: 3
        radius: height / 2
        y: root.height - 6
        color: Theme.text
        opacity: target ? 1 : 0

        Behavior on x {
            // Invisible (freshly opened) or when appearing: jump straight to the place
            enabled: root.animate && !root.jump && activeMark.opacity > 0.01

            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.08
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    // Hover over the whole group (like groupHover in the MainBar): in the gaps between the
    // icons there is no hit, there the pill becomes a capsule again. Only the instance of the active
    // picker may write (enabled, see PickerSlot): the old picker fading out after a click
    // loses its hover and would otherwise reset the shared state.
    HoverHandler {
        onPointChanged: {
            if (!root.enabled)
                return ;

            const px = point.position.x;
            let found = -1;
            for (let i = 0; i < repeater.count; i++) {
                const c = repeater.itemAt(i);
                if (!c)
                    continue;

                const cx = row.x + c.x;
                if (px >= cx && px <= cx + c.width) {
                    found = i;
                    break;
                }
            }
            if (PickerManager.switcherHover !== found)
                PickerManager.switcherHover = found;

        }
        onHoveredChanged: {
            if (!hovered && root.enabled)
                PickerManager.switcherHover = -1;

        }
    }

}
