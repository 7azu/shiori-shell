import "../../common"
import "../../services"
import QtQuick

Rectangle {
    id: pill

    property string label: ""
    property bool primary: false

    signal clicked()

    width: pillText.implicitWidth + 30
    height: 34
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: primary ? (pillArea.containsMouse ? Qt.lighter(WalColors.color4, 1.1) : WalColors.color4) : WalColors.withAlpha(WalColors.color7, pillArea.containsMouse ? 0.14 : 0.08)
    scale: pillArea.pressed ? 0.95 : 1

    Text {
        id: pillText

        anchors.centerIn: parent
        text: pill.label
        font.family: Theme.font
        font.pixelSize: 12
        font.bold: pill.primary
        color: pill.primary ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.85)
    }

    MouseArea {
        id: pillArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            pill.clicked();
            PickerManager.requestFocus();
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: 140
        }

    }

    Behavior on scale {
        Springy {
        }

    }

}
