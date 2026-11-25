import "../services"
import QtQuick

// Bar icon for the settings window (settings/SettingsWindow.qml, state services/SettingsState): the gear
// on the left of the bar, between the logo (with its drawer) and the shortcuts button (MainBar.qml).
// It opens no dropdown but a window, so it is not part of an icon group and draws its own tile, the same
// as the shortcuts button next to it. Lit while the window is open.
// Hover: the gear gets a push and then keeps turning slowly. When the mouse leaves it runs out and stops
// on a tooth (the gear looks the same every 60°), so the resting picture never changes.
BarIcon {
    id: root

    // Edge length of the tile; the click area is exactly as wide
    readonly property int size: Theme.px(32)
    readonly property bool active: SettingsState.open
    // Hover spin, in degrees and degrees per second. brake: how fast it slows down while running out.
    property real spin: 0
    property real speed: 0
    property real brake: 0
    readonly property real push: 540
    readonly property real cruise: 110

    objectName: "settingsBarButton"
    contentWidth: size - Math.round(padding * BarState.density)
    Accessible.role: Accessible.Button
    Accessible.name: "Settings"
    Accessible.onPressAction: SettingsState.toggle()
    onClicked: SettingsState.toggle()
    onHoveredChanged: {
        if (hovered) {
            speed = Math.max(speed, push);
            return ;
        }
        if (speed <= 0)
            return ;

        // Way to the tooth it stops on: not so short that it would stop with a jerk
        let rest = 60 - (spin % 60);
        while (rest < Math.max(20, speed * 0.2))rest += 60
        brake = speed * speed / (2 * rest);
    }

    FrameAnimation {
        running: root.speed > 0
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            if (root.hovered) {
                // The push fades into the slow turning
                root.speed += (root.cruise - root.speed) * (1 - Math.exp(-dt / 0.3));
                root.spin = (root.spin + root.speed * dt) % 360;
                return ;
            }
            const left = root.speed / root.brake;
            if (left <= dt) {
                root.speed = 0;
                root.spin = 0;
                return ;
            }
            root.spin += root.speed * dt - root.brake * dt * dt / 2;
            root.speed -= root.brake * dt;
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.buttonWidth
        height: root.size
        radius: Theme.radiusS
        color: root.active || root.hovered ? Theme.accentSoft : Theme.card
        border.color: Theme.stroke

        Behavior on color {
            ColorAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    // Where the ink of the gear really is: the symbol does not sit in the middle of its text box
    TextMetrics {
        id: ink

        font: gear.font
        text: gear.text
    }

    BarGlyph {
        id: gear

        // A quarter turn when the window opens or closes, on top of it the hover spin
        property real turn: root.active ? 90 : 0

        anchors.centerIn: parent
        text: "\u{F0493}"
        font.pixelSize: Theme.px(16)
        hot: root.hovered

        // Turns around the middle of the gear, not of the text box: otherwise it wobbles while spinning
        transform: Rotation {
            origin.x: ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2
            origin.y: gear.baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2
            angle: gear.turn + root.spin
        }

        Behavior on turn {
            NumberAnimation {
                duration: Appearance.anim.durations.slow
                easing.type: Easing.OutCubic
            }

        }

    }

}
