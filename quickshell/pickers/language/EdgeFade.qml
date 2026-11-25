import "../../services"
import QtQuick

// Soft edge of a horizontally scrolling strip (panel color -> transparent)
Rectangle {
    property bool rightSide: false

    width: 28

    gradient: Gradient {
        orientation: Gradient.Horizontal

        GradientStop {
            position: 0
            color: parent.rightSide ? "transparent" : WalColors.withAlpha(WalColors.color0, 0.97)
        }

        GradientStop {
            position: 1
            color: parent.rightSide ? WalColors.withAlpha(WalColors.color0, 0.97) : "transparent"
        }

    }

}
