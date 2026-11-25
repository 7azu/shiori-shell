import "../services"
import QtQuick

Item {
    id: root

    readonly property real level: Math.max(0, Math.min(VolumeSliderState.systemVolume, 1))
    readonly property bool muted: VolumeSliderState.systemMuted
    readonly property bool hot: mouseArea.containsMouse
    readonly property bool expanded: VolumeSliderState.expanded
    // Shown level: follows level softly at the frame rate (exponentially). Before, Behavior on width:
    // every mouse move while dragging restarted the animation, and the size snapped to half pixels
    // while centering -> the core grew jerkily
    property real shownLevel: level

    signal clicked()
    signal rightClicked()

    width: 40
    height: 40

    FrameAnimation {
        running: Math.abs(root.level - root.shownLevel) > 0.001
        onTriggered: {
            const d = root.level - root.shownLevel;
            root.shownLevel = Math.abs(d) < 0.001 ? root.level : root.shownLevel + d * (1 - Math.exp(-frameTime * 18));
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width + 8
        height: parent.height + 8
        radius: width / 2
        color: root.muted ? WalColors.color1 : WalColors.color4
        opacity: 0.05 + 0.15 * root.level
        layer.enabled: true
        layer.samples: 4

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }

        }

    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 2
        height: parent.height - 2
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: WalColors.color1
        opacity: root.muted ? 0.5 : 0
        visible: opacity > 0.01
        scale: root.muted ? 1 : 0.85

        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: root.muted

            NumberAnimation {
                to: 1.15
                duration: 1400
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                to: 1
                duration: 100
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.normal
            }

        }

    }

    Item {
        anchors.centerIn: parent
        width: parent.width - 4
        height: parent.height - 4

        // At the frame rate instead of a 30 ms timer (that did not run in sync with the screen and stuttered);
        // muted: stays
        NumberAnimation on rotation {
            from: 0
            to: 360
            duration: 30000
            loops: Animation.Infinite
            paused: root.muted
        }

        Repeater {
            model: 8

            delegate: Rectangle {
                readonly property real angleRad: index * Math.PI / 4
                readonly property real r: parent.width / 2 - 1

                x: parent.width / 2 + r * Math.cos(angleRad) - width / 2
                y: parent.height / 2 + r * Math.sin(angleRad) - height / 2
                width: 3
                height: 1.2
                radius: height / 2
                color: root.muted ? WalColors.color1 : WalColors.color4
                opacity: root.muted ? 0.5 : 0.35 + 0.35 * root.level

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }

                }

            }

        }

    }

    Item {
        anchors.centerIn: parent
        width: parent.width - 14
        height: parent.height - 14

        NumberAnimation on rotation {
            from: 0
            to: -360
            duration: 20000
            loops: Animation.Infinite
            paused: root.muted
        }

        Repeater {
            model: 6

            delegate: Rectangle {
                readonly property real angleRad: index * Math.PI / 3
                readonly property real r: parent.width / 2 - 1

                x: parent.width / 2 + r * Math.cos(angleRad) - width / 2
                y: parent.height / 2 + r * Math.sin(angleRad) - height / 2
                width: 2.5
                height: 1.2
                radius: height / 2
                color: root.muted ? WalColors.color1 : WalColors.color4
                opacity: root.muted ? 0.55 : 0.45 + 0.35 * root.level

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }

                }

            }

        }

    }

    // Core: fixed size (12 px = full level), the level only scales it -> no recompute
    // of the geometry, no snapping to pixels
    Rectangle {
        id: core

        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 12
        height: 12
        radius: height / 2
        color: root.muted ? WalColors.color1 : WalColors.color4
        transform: Scale {
            origin.x: 6
            origin.y: 6
            xScale: (5 + 7 * root.shownLevel) / 12
            yScale: xScale
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.45
            height: width
            radius: width / 2
            color: WalColors.color0
            opacity: 0.6
        }

        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: !root.muted

            NumberAnimation {
                to: 1.15
                duration: 900
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                to: 1
                duration: 900
                easing.type: Easing.InOutSine
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: 200
            }

        }

    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 2
        height: parent.height - 2
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: WalColors.color4
        opacity: root.hot ? 0.4 : 0
        scale: root.hot ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }

        }

    }

    // Small expand indicator when expanded
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 2
        text: "⌃"
        color: WalColors.withAlpha(WalColors.color4, 0.6)
        font.family: Theme.font
        font.pixelSize: 9
        rotation: root.expanded ? 180 : 0
        visible: root.hot || root.expanded
        opacity: (root.hot || root.expanded) ? 1 : 0

        Behavior on rotation {
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }

        }

    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
    }

}
