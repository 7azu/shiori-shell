import "../services"
import QtQuick
import Quickshell
import Quickshell.Wayland

// "Identify" on the Displays page (services/DisplayState.identifying): every monitor shows its name
// big in the middle for a moment, so the tiles on the page can be matched to the real screens.
// Takes no input; only mapped while it shows.
Scope {
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win

            required property var modelData
            property real k: DisplayState.identifying ? 1 : 0

            screen: modelData
            visible: k > 0.01
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            color: "transparent"
            WlrLayershell.namespace: "quickshell:identify"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region {
            }

            Column {
                anchors.centerIn: parent
                spacing: Theme.px(6)
                opacity: win.k
                scale: 0.92 + 0.08 * win.k

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.modelData.name
                    color: Theme.text
                    style: Text.Outline
                    styleColor: WalColors.withAlpha(WalColors.color0, 0.6)
                    font.family: Theme.fontDisplay
                    font.pixelSize: Theme.px(120)
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (win.modelData.model || "") + "  ·  " + win.modelData.width + " × " + win.modelData.height
                    color: Theme.accent
                    style: Text.Outline
                    styleColor: WalColors.withAlpha(WalColors.color0, 0.6)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.px(20)
                    font.bold: true
                    font.letterSpacing: 1.5
                }

            }

            Behavior on k {
                NumberAnimation {
                    duration: 360
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

}
