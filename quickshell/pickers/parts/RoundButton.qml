import "../../common"
import "../../services"
import QtQuick

Rectangle {
    id: rb

    property string glyph: ""
    property bool lit: false
    property bool danger: false

    signal clicked()

    width: 34
    height: 34
    radius: height / 2
    color: {
        const c = danger ? Theme.bad : WalColors.color4;
        if (lit)
            return WalColors.withAlpha(c, rbArea.containsMouse ? 0.32 : 0.22);

        return rbArea.containsMouse ? WalColors.withAlpha(c, 0.18) : WalColors.withAlpha(WalColors.color7, 0.07);
    }
    scale: rbArea.pressed ? 0.9 : 1

    Text {
        anchors.centerIn: parent
        text: rb.glyph
        font.family: Theme.font
        font.pixelSize: 16
        color: (rb.lit || rbArea.containsMouse) ? (rb.danger ? Theme.bad : WalColors.color4) : WalColors.withAlpha(WalColors.color7, 0.6)
    }

    MouseArea {
        id: rbArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            rb.clicked();
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
