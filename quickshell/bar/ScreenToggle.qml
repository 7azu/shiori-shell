import "../services"
import QtQuick

// Bar icon for the screen dropdown (dropdowns/ScreenContent): night light (services/NightLight) and keep
// awake (services/KeepAwake). A sun while the colors are untouched, a moon while they are warm; a dot
// below it while keep awake is on. Left click = night light off, or back to what it was before.
BarIcon {
    id: root

    contentWidth: glyph.implicitWidth
    acceptedButtons: Qt.LeftButton
    onClicked: {
        if (NightLight.available)
            NightLight.toggle();

    }

    BarGlyph {
        id: glyph

        anchors.centerIn: parent
        text: NightLight.warm ? "\u{F0594}" : "\u{F05A8}"
        font.pixelSize: 15
        hot: root.hovered
    }

    // Keep awake is on: the screen will not lock by itself, so it should be seen at a glance
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 13
        width: 4
        height: 4
        radius: 2
        color: Theme.accent
        opacity: KeepAwake.active ? 1 : 0
        scale: KeepAwake.active ? 1 : 0.4

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.fast
                easing.type: Easing.OutCubic
            }

        }

    }

}
