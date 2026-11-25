import "../services"
import QtQuick
import Quickshell

// Round buttons for suspend / reboot / shutdown. Reboot and shutdown need a second click
// within 3 s (an accidental click on the lock screen should not turn anything off).
Row {
    id: root

    property int armed: -1
    readonly property var actions: [{
        "glyph": "",
        "label": "Sleep",
        "confirm": false,
        "cmd": ["systemctl", "suspend"]
    }, {
        "glyph": "",
        "label": "Reboot",
        "confirm": true,
        "cmd": ["systemctl", "reboot"]
    }, {
        "glyph": "",
        "label": "Shut down",
        "confirm": true,
        "cmd": ["systemctl", "poweroff"]
    }]

    spacing: Theme.px(10)
    layoutDirection: Qt.RightToLeft

    Timer {
        id: disarm

        interval: 3000
        onTriggered: root.armed = -1
    }

    // Order right to left: shutdown at the very outside
    Repeater {
        model: root.actions.length

        delegate: Rectangle {
            id: btn

            required property int index
            readonly property var action: root.actions[root.actions.length - 1 - index]
            readonly property int realIndex: root.actions.length - 1 - index
            readonly property bool isArmed: root.armed === realIndex

            height: Theme.px(40)
            width: isArmed ? label.implicitWidth + height + Theme.px(8) : height
            radius: height / 2
            color: isArmed ? WalColors.withAlpha(Theme.bad, 0.22) : (mouse.containsMouse ? Theme.cardHover : WalColors.withAlpha(WalColors.color0, 0.45))
            border.width: 1
            border.color: isArmed ? WalColors.withAlpha(Theme.bad, 0.6) : Theme.stroke
            clip: true

            Text {
                id: glyph

                x: (btn.height - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                text: btn.action.glyph
                font.family: Theme.font
                font.pixelSize: Theme.px(15)
                color: btn.isArmed ? Theme.bad : (mouse.containsMouse ? Theme.text : Theme.textDim)
            }

            Text {
                id: label

                x: btn.height - Theme.px(4)
                anchors.verticalCenter: parent.verticalCenter
                text: "Click again to " + btn.action.label.toLowerCase()
                opacity: btn.isArmed ? 1 : 0
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeBody
                font.weight: Font.Medium
                color: Theme.bad
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (btn.action.confirm && !btn.isArmed) {
                        root.armed = btn.realIndex;
                        disarm.restart();
                        return ;
                    }
                    root.armed = -1;
                    Quickshell.execDetached(btn.action.cmd);
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.anim.curves.outQuint
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 160
                }

            }

        }

    }

}
