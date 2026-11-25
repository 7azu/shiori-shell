import "../../common"
import "../../services"
import QtQuick

// Small pill switch (Read tab)
Rectangle {
    id: tc

    required property var picker

    property string label: ""
    property bool on: false
    property bool jpLabel: false

    signal clicked()

    width: tcText.implicitWidth + 24 + (star ? 16 : 0)
    height: 28
    radius: height / 2
    color: on ? WalColors.withAlpha(WalColors.color4, tcArea.containsMouse ? 0.32 : 0.22) : WalColors.withAlpha(WalColors.color7, tcArea.containsMouse ? 0.1 : 0.06)
    border.width: 1
    border.color: on ? WalColors.withAlpha(WalColors.color4, 0.45) : "transparent"
    scale: tcArea.pressed ? 0.94 : 1

    // star: state as a symbol of the visual language before the text (off = hollow dot, on = sparkle). If the
    // switch is turned on by a click, the star fires (star birth); if it is already on (e.g. a read chapter
    // opened), it stands calmly.
    property bool star: false
    property bool igniting: false

    onOnChanged: {
        if (!on)
            igniting = false;
    }

    Item {
        id: tcMark

        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        visible: tc.star

        Rectangle {
            anchors.centerIn: parent
            width: 5
            height: 5
            radius: 2.5
            color: "transparent"
            border.width: 1
            border.color: WalColors.withAlpha(WalColors.color7, tcArea.containsMouse ? 0.7 : 0.45)
            visible: !tc.on
        }

        Sparkle {
            anchors.centerIn: parent
            size: 4
            rays: 1.8
            color: WalColors.color4
            glowColor: WalColors.vividAccent
            twinkle: 0.8
            visible: tc.on && !tc.igniting
        }

        StarBurst {
            anchors.centerIn: parent
            size: 4
            rays: 1.8
            color: WalColors.color4
            active: tc.on && tc.igniting
            visible: tc.on && tc.igniting
        }

    }

    Text {
        id: tcText

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: tc.star ? 8 : 0
        text: tc.label
        font.family: tc.jpLabel ? picker.jp : picker.mono
        font.pixelSize: tc.jpLabel ? 12 : 11
        font.bold: tc.on
        color: tc.on ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.6)
    }

    MouseArea {
        id: tcArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: tc.enabled
        onClicked: {
            // Turned on by a click: the star should fire
            if (tc.star && !tc.on)
                tc.igniting = true;
            tc.clicked();
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.fast
        }

    }

    Behavior on scale {
        Springy {
        }

    }

}
