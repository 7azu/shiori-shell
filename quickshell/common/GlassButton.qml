import "../services"
import QtQuick

// Round symbol button made of "glass" (like the buttons over photos and videos on iOS): arrows, close,
// fullscreen, undo. prominent = bright full surface (play button), active = tinted in the accent color.
Rectangle {
    id: btn

    property string glyph: ""
    property real size: Theme.px(34)
    property bool prominent: false
    property bool active: false
    property bool dimmed: false
    property real glyphScale: 0.4
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    width: size
    height: size
    radius: size / 2
    color: {
        if (prominent)
            return hovered ? Theme.knob : Theme.tint(Theme.text, 0.88);

        if (active)
            return Theme.tint(Theme.accent, hovered ? 0.32 : 0.22);

        return hovered && !dimmed ? Theme.glassHover : Theme.glass;
    }
    opacity: dimmed ? 0.35 : 1
    scale: mouse.pressed && !dimmed ? 0.9 : 1

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.prominent ? WalColors.color0 : (btn.active ? Theme.accent : Theme.text)
        font.family: Theme.font
        font.pixelSize: Math.round(btn.size * btn.glyphScale)
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: {
            if (!btn.dimmed)
                btn.clicked();

        }
    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.fast
        }

    }

    Behavior on scale {
        NumberAnimation {
            duration: 120
        }

    }

}
