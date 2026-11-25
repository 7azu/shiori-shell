import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// One shared window for all dropdowns.
// - Nothing open -> hover: normal opening (height grows)
// - Open -> hover on another icon: the shell morphs over (width/X/height)
// - Nothing hovered: normal closing (shrinks from the bottom up)
PanelWindow {
    id: host

    readonly property real cornerRadius: 20
    readonly property real edgePadding: 8
    // Opening + switching between dropdowns spring slightly (MD3 Expressive as in Caelestia),
    // the crossfade of the content runs calmly without overshoot. Closing stays without a bounce.
    readonly property int morphDuration: Appearance.anim.durations.expressiveDefaultSpatial
    readonly property var morphCurve: Appearance.anim.curves.expressiveDefaultSpatial
    readonly property int fadeDuration: Appearance.anim.durations.expressiveDefaultEffects
    readonly property int closeDuration: 340
    readonly property int reopenDuration: 220
    property bool expanded: false
    property bool heightAnimOn: false
    property bool morphOn: false // true = page switch with the window open
    property real closeFactor: 1
    property string shownId: ""
    // Actual window width (logical pixels, already rotated for rotated monitors).
    // screen.width only as a fallback while the window is not configured yet.
    readonly property real winW: width > 0 ? width : screen.width
    readonly property var slots: ({
        "audio": audioLoader,
        "stats": statsLoader,
        "vpn": vpnLoader,
        "claude": claudeLoader,
        "battery": batteryLoader,
        "screen": screenLoader,
        "sync": syncLoader
    })
    readonly property var shownItem: slots[shownId] ? slots[shownId].item : null
    readonly property real targetW: (shownItem ? shownItem.menuWidth : 220) + 2 * cornerRadius
    readonly property real targetH: shownItem ? shownItem.implicitHeight : 0
    readonly property real targetX: Math.max(edgePadding, Math.min(DropdownState.anchorX - targetW / 2, winW - targetW - edgePadding))
    // Animated values: snap when opening fresh, glide when morphing
    property real shellW: targetW
    property real shellX: targetX
    property real fullH: targetH
    // When opening, the content glides out with the bottom edge (as in Caelestia) instead of just being
    // uncovered; on the height overshoot it slides a few pixels further and springs back.
    // Rounded: text snaps to whole pixels, rectangles do not -> at subpixel positions
    // the parts of the content shift against each other and look jittery.
    readonly property real contentY: Math.round(container.height - fullH)

    // Left edge of a content with width w at its END position (target shell), rounded in absolute
    // window coordinates. The content stands still during the switch, only the shell morphs around it and
    // uncovers it; if it moved with the shell, it would move a few pixels including the spring-back.
    function restX(w) {
        return Math.round(targetX + (targetW - w) / 2);
    }

    // Switch movement of the content: a short glide in the switch direction, without spring-back (only
    // the shell does that). switchT 0 -> 1; at rest 1 = no offset.
    readonly property real switchTravel: 28
    property int switchDir: 1
    property real switchT: 1

    NumberAnimation {
        id: switchAnim

        target: host
        property: "switchT"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.emphasizedDecelerate
    }

    // High enough for the highest dropdown (VPN ~540) + shadow. Fixed instead of just targetH,
    // otherwise the window would shrink right away when morphing to a smaller dropdown
    // and cut off the still animating shape. The window is transparent, only the shape takes clicks.
    implicitHeight: Math.max(660, targetH + 24)
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.keyboardFocus: DropdownState.current === "sync" && SyncState.inputEntry !== null ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: 40
    }

    Connections {
        function onCurrentChanged() {
            const id = DropdownState.current;
            if (id !== "") {
                closeAnim.stop();
                if (!host.expanded) {
                    // open fresh: normal, without a morph
                    host.morphOn = false;
                    host.shownId = id;
                    host.heightAnimOn = true;
                    host.expanded = true;
                } else {
                    // already open: morph over. Direction = where the middle moves (fallback: to the right)
                    const oldCenter = host.shellX + host.shellW / 2;
                    host.morphOn = true;
                    host.shownId = id;
                    const delta = host.targetX + host.targetW / 2 - oldCenter;
                    host.switchDir = Math.abs(delta) < 1 ? 1 : Math.sign(delta);
                    switchAnim.restart();
                }
                if (host.closeFactor !== 1)
                    reopenAnim.restart();

            } else if (host.expanded) {
                reopenAnim.stop();
                closeAnim.restart();
            }
        }

        target: DropdownState
    }

    NumberAnimation {
        id: reopenAnim

        target: host
        property: "closeFactor"
        to: 1
        duration: host.reopenDuration
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: closeAnim

        NumberAnimation {
            target: host
            property: "closeFactor"
            to: 0
            duration: host.closeDuration
            easing.type: Easing.InOutCubic
        }

        ScriptAction {
            script: {
                host.heightAnimOn = false;
                host.morphOn = false;
                host.expanded = false;
                host.closeFactor = 1;
                host.shownId = "";
            }
        }

    }

    // For testing/designing without hover:  qs ipc call dropdown open audio  |  ... close
    // open() returns the screen geometry "x,y wxh" (fits grim -g directly)
    IpcHandler {
        function open(id: string): string {
            DropdownState.anchorX = host.winW / 2;
            DropdownState.current = id;
            return Math.round(host.screen.x + host.targetX) + "," + (host.screen.y + 40) + " " + Math.round(host.targetW) + "x" + Math.round(host.targetH);
        }

        function close(): void {
            DropdownState.current = "";
        }

        // Pin/unpin the open dropdown (like the pin in the header)
        function pin(): void {
            DropdownState.togglePin();
        }

        target: "dropdown"
    }

    // Soft shadow under the dropdown (as in Caelestia), grows along when opening/closing.
    // Before, a layer + MultiEffect on the whole container: then on every animation in the content
    // (VPN pulse, satellite, live graph ...) the whole dropdown was rendered into a texture and
    // blurred. RectangularShadow is a single shader without an intermediate texture.
    // Extended by cornerRadius on top, so no round shadow corners become visible there.
    RectangularShadow {
        readonly property real shownH: Math.min(container.height, body.height)

        x: container.x + host.cornerRadius
        y: -host.cornerRadius
        width: container.width - 2 * host.cornerRadius
        height: shownH + host.cornerRadius
        visible: shownH > 0.5
        radius: host.cornerRadius
        offset: Qt.vector2d(0, 3)
        blur: 19
        color: Qt.rgba(0, 0, 0, 0.5)
    }

    Item {
        id: container

        x: host.shellX
        width: host.shellW
        height: host.expanded ? host.fullH : 0
        clip: true

        Item {
            id: body

            // Shape = clip: grows along when opening (incl. overshoot), otherwise equal to fullH
            readonly property real openH: container.height

            width: parent.width
            height: openH * host.closeFactor
            clip: true

            RoundedDropShape {
                anchors.top: parent.top
                cornerRadius: host.cornerRadius
                menuWidth: host.shellW - 2 * host.cornerRadius
                menuHeight: Math.max(2 * host.cornerRadius, body.openH * host.closeFactor)
            }

            HoverHandler {
                onHoveredChanged: {
                    DropdownState.dropdownHovered = hovered;
                    DropdownState.updateCloseTimer();
                }
            }

            // Only show content inside the dark part of the shape. body is wider than the background by the ears on top
            // (one cornerRadius each left/right): when switching to a wider
            // dropdown the new content already stood at its final position and stuck out sideways over the
            // still growing background.
            Item {
                id: contentClip

                x: host.cornerRadius
                width: Math.max(0, parent.width - 2 * host.cornerRadius)
                height: parent.height
                clip: true

                Slot {
                    id: audioLoader

                    slotId: "audio"

                    sourceComponent: AudioContent {
                    }

                }

                Slot {
                    id: statsLoader

                    slotId: "stats"

                    sourceComponent: StatsContent {
                    }

                }

                Slot {
                    id: vpnLoader

                    slotId: "vpn"

                    sourceComponent: VpnContent {
                    }

                }

                Slot {
                    id: claudeLoader

                    slotId: "claude"

                    sourceComponent: AiUsageContent {
                    }

                }

                Slot {
                    id: batteryLoader

                    slotId: "battery"

                    sourceComponent: BatteryContent {
                    }

                }

                Slot {
                    id: screenLoader

                    slotId: "screen"

                    sourceComponent: ScreenContent {
                    }

                }

                Slot {
                    id: syncLoader

                    slotId: "sync"

                    sourceComponent: SyncContent {
                    }

                }

            }

        }

        // Normal opening: the height grows animated (as with the old dropdowns).
        // When morphing, fullH takes over the animation, so it is off there. Likewise while a content animates its height
        // itself (resizing, e.g. expanding sync rows): otherwise this animation would restart every frame,
        // and the content slid as a whole instead of just expanding.
        Behavior on height {
            enabled: host.heightAnimOn && !host.morphOn && !(host.shownItem && host.shownItem.resizing === true)

            Anim {
                duration: host.morphDuration
                easing.bezierCurve: host.morphCurve
            }

        }

    }

    // The window always stays mapped (no visible toggle), otherwise Hyprland plays
    // its layer animation (slide from the side) on map/unmap.
    // When closed the container has height 0 -> empty mask -> clicks go through.
    mask: Region {
        item: container
    }

    Behavior on shellW {
        enabled: host.morphOn

        Anim {
            duration: host.morphDuration
            easing.bezierCurve: host.morphCurve
        }

    }

    Behavior on shellX {
        enabled: host.morphOn

        Anim {
            duration: host.morphDuration
            easing.bezierCurve: host.morphCurve
        }

    }

    Behavior on fullH {
        enabled: host.morphOn

        Anim {
            duration: host.morphDuration
            easing.bezierCurve: host.morphCurve
        }

    }

    // One dropdown content. Loads while it is current or still fading out.
    component Slot: Loader {
        id: slot

        required property string slotId
        readonly property bool isCurrent: host.shownId === slotId
        // Final position while this content is current; frozen afterwards -> fades out in place
        property real absX: 0

        // The new content comes from the old one's side, the old one glides on in the switch direction.
        // As a texture during the movement: this way everything glides with subpixel precision instead of text
        // snapping to whole pixels and jittering against the rectangles. Drawn normally (sharp) at rest.
        // relative to contentClip (lies cornerRadius to the right of the shell)
        x: absX - host.shellX - host.cornerRadius + host.switchDir * host.switchTravel * (isCurrent ? host.switchT - 1 : host.switchT)
        layer.enabled: host.switchT < 1 && opacity > 0.01
        layer.smooth: true
        y: host.contentY
        active: isCurrent || opacity > 0.01
        opacity: isCurrent ? 1 : 0

        Binding on absX {
            when: slot.isCurrent
            value: host.restX(slot.width)
            restoreMode: Binding.RestoreNone
        }

        Behavior on opacity {
            enabled: host.morphOn

            Anim {
                duration: host.fadeDuration
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultEffects
            }

        }

    }

}
