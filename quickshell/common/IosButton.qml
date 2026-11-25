import "../services"
import QtQuick

// Big button like on iOS: "filled" = main action in the accent color, "tinted" = tinted, "plain" = text only.
// dimmed: visible, but without effect right now.
Rectangle {
    id: btn

    property string text: ""
    property string glyph: ""
    property string kind: "filled"
    property color tone: Theme.accent
    property bool dimmed: false
    readonly property bool hovered: mouse.containsMouse
    readonly property color labelColor: kind === "filled" ? Theme.onAccent : tone

    // Confirmation after work is done (e.g. saved): a star fires with a short text above the label,
    // fades out softly after a good second (visual language: star = done)
    property string confirmText: ""
    property real confirmK: 0
    property bool confirming: false

    signal clicked()

    function confirm(label) {
        confirmText = label || "Done";
        confirmSeq.stop();
        confirming = false;
        confirming = true;
        confirmSeq.start();
    }

    height: Theme.px(42)
    radius: Theme.px(12)
    color: {
        if (kind === "filled")
            return hovered && !dimmed ? Qt.lighter(tone, 1.1) : tone;

        if (kind === "tinted")
            return Theme.tint(tone, hovered && !dimmed ? 0.24 : 0.16);

        return hovered && !dimmed ? Theme.groupFill : "transparent";
    }
    // Fully visible during the confirmation, even if the button is dimmed afterwards (e.g. nothing left to save)
    opacity: dimmed ? 0.4 + 0.6 * confirmK : 1
    scale: mouse.pressed && !dimmed ? 0.97 : 1

    Row {
        anchors.centerIn: parent
        spacing: Theme.px(8)
        // Crossfade split: the label only in the lower half of confirmK, the confirmation only in the upper half,
        // otherwise both texts stand on top of each other briefly
        opacity: Math.max(0, 1 - 2 * btn.confirmK)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.glyph !== ""
            text: btn.glyph
            color: btn.labelColor
            font.family: Theme.font
            font.pixelSize: Theme.sizeLead
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.labelColor
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLead
            font.weight: Font.DemiBold
        }

    }

    Row {
        anchors.centerIn: parent
        spacing: Theme.px(9)
        opacity: Math.max(0, 2 * btn.confirmK - 1)
        visible: opacity > 0.01

        StarBurst {
            anchors.verticalCenter: parent.verticalCenter
            size: Theme.px(5)
            color: btn.labelColor
            glowColor: btn.kind === "filled" ? btn.labelColor : WalColors.vividAccent
            active: btn.confirming
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.confirmText
            color: btn.labelColor
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLead
            font.weight: Font.DemiBold
        }

    }

    SequentialAnimation {
        id: confirmSeq

        NumberAnimation { target: btn; property: "confirmK"; to: 1; duration: 220; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 1200 }
        NumberAnimation { target: btn; property: "confirmK"; to: 0; duration: 650; easing.type: Easing.InOutSine }
        PropertyAction { target: btn; property: "confirming"; value: false }
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
