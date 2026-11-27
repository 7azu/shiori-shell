pragma ComponentBehavior: Bound

import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Context menu of a tray program: a small rectangle of its own just below the bar, opened by a
// right-click on the program's icon in the tray drawer (bar/TrayDrawer -> TrayState.openMenu). Two lines,
// Open and Exit; the program's whole menu is in the tray panel (bar/TrayPanel).
// It stays until one of the two is chosen, Esc, or a click anywhere else, and it has the keyboard meanwhile.
// The window is always there (mapping it anew would play Hyprland's layer animation); closed it is
// transparent and lets every click through. It spans the whole top of the screen and never moves:
// moving a layer surface makes Hyprland slide it (the menu "flew in" whenever another icon was clicked
// than last time). Only the rectangle inside goes to the icon, so the opening is always the same:
// it grows out of the icon with a soft spring (Appearance.anim.curves.springSoft).
PanelWindow {
    id: win

    readonly property bool open: TrayState.menuOpen
    readonly property var program: TrayState.menuProgram
    // Room around the rectangle for its shadow
    readonly property real pad: 26
    readonly property real menuW: 148
    // Below the bar (40 high), with a little air: not attached to it
    readonly property real menuTop: 46
    // Middle of the icons in the bar (40 high): the point the menu grows out of and shrinks back into
    readonly property real iconY: 20
    property int index: 0
    // Opening: grow = size (spring, overshoots briefly), fade = opacity (short, no overshoot)
    property real grow: 0
    property real fade: 0
    readonly property var actions: [{
        "id": "open",
        "label": "Open",
        "glyph": "\u{F03CC}",
        "enabled": true
    }, {
        "id": "exit",
        "label": "Exit",
        "glyph": "\u{F0156}",
        // Only where the program itself offers a way to quit
        "enabled": program !== null && TrayState.canExit(program)
    }]

    function playOpen() {
        closeAnim.stop();
        openAnim.restart();
    }

    function choose(i) {
        const a = actions[i];
        if (!a || !a.enabled || !program)
            return ;

        const target = program;
        TrayState.closeMenu();
        if (a.id === "open")
            TrayState.show(target);
        else
            TrayState.exit(target);
    }

    implicitHeight: menuTop + box.height + pad
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:tray-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onOpenChanged: {
        if (open) {
            index = 0;
            box.forceActiveFocus();
            playOpen();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }
    onProgramChanged: index = 0

    anchors {
        top: true
        left: true
        right: true
    }

    // Opened on another icon while open (no close in between): grow out of the new one
    Connections {
        function onMenuXChanged() {
            if (win.open)
                win.playOpen();

        }

        target: TrayState
    }

    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: win
            property: "grow"
            from: 0
            to: 1
            duration: Appearance.anim.durations.springSoft
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.springSoft
        }

        NumberAnimation {
            target: win
            property: "fade"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }

    }

    // Back into the icon, quicker and accelerating
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: win
            property: "grow"
            to: 0
            duration: 170
            easing.type: Easing.InCubic
        }

        NumberAnimation {
            target: win
            property: "fade"
            to: 0
            duration: 150
            easing.type: Easing.InCubic
        }

    }

    // Closed: no clicks at all; open: only the rectangle
    mask: Region {
        item: win.open ? box : null
    }

    // A click anywhere else closes it
    HyprlandFocusGrab {
        windows: [win]
        active: win.open
        onCleared: TrayState.closeMenu()
    }

    // Rectangle and shadow scale together, around the middle of the icon (above the rectangle)
    Item {
        id: body

        // Starts a little left of the icon's middle, like a menu at the mouse; kept on the screen
        x: Math.round(Math.max(4, Math.min(TrayState.menuX - 18, win.width - win.menuW - 4)))
        y: win.menuTop
        width: win.menuW
        height: box.height
        opacity: win.fade
        visible: opacity > 0.01

        transform: Scale {
            readonly property real s: 0.2 + 0.8 * win.grow

            origin.x: TrayState.menuX - body.x
            origin.y: win.iconY - win.menuTop
            xScale: s
            yScale: s
        }

        RectangularShadow {
            anchors.fill: box
            radius: box.radius
            offset: Qt.vector2d(0, 4)
            blur: 20
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Rectangle {
            id: box

            width: win.menuW
            height: column.implicitHeight
            radius: Theme.radiusM
            color: WalColors.color0
            border.width: 1
            border.color: Theme.stroke
            focus: win.open
            Keys.onPressed: (event) => {
                event.accepted = true;
                switch (event.key) {
                case Qt.Key_Escape:
                    TrayState.closeMenu();
                    break;
                case Qt.Key_Up:
                case Qt.Key_Backtab:
                    win.index = 0;
                    break;
                case Qt.Key_Down:
                case Qt.Key_Tab:
                    if (win.actions[1].enabled)
                        win.index = 1;

                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    win.choose(win.index);
                    break;
                default:
                    event.accepted = false;
                }
            }

            Column {
                id: column

                x: 5
                width: parent.width - 10
                topPadding: 5
                bottomPadding: 5
                spacing: 2

                Repeater {
                    model: win.actions

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool current: win.index === index && modelData.enabled

                        width: column.width
                        height: Theme.px(32)
                        radius: Theme.radiusS
                        color: current ? WalColors.withAlpha(WalColors.color4, 0.16) : "transparent"
                        opacity: modelData.enabled ? 1 : 0.35

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.glyph
                                color: row.current ? Theme.accent : Theme.textDim
                                font.family: Theme.font
                                font.pixelSize: Theme.sizeLead + 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.label
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeLabel
                                font.weight: Font.Medium
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: row.modelData.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: win.index = row.index
                            onClicked: win.choose(row.index)
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                    }

                }

            }

        }

    }

}
