import "../../common"
import "../../services"
import QtQuick

// Aozora work in the search results
// Selection pill of the lists: the same as in clipboard/trash/task manager (accent 0.13,
// radius 16, glides springy to the row). Lies in the contentItem behind the rows and scrolls along.
Rectangle {
    id: pill

    required property var picker

    required property ListView view
    required property string listName
    required property real stride
    required property real rowH
    readonly property bool active: picker.kbList === listName && picker.kbIndex >= 0
    readonly property int index: picker.kbIndex

    // On "nothing selected" (-1, e.g. while typing) stay and only fade out
    onIndexChanged: {
        if (index >= 0)
            y = index * stride;

    }
    parent: view.contentItem
    z: -1
    width: view.width
    height: rowH
    radius: 16
    color: WalColors.withAlpha(WalColors.color4, 0.13)
    opacity: active ? 1 : 0
    visible: opacity > 0.01

    // Invisible (nothing selected yet): jump straight to the row instead of gliding in from the top
    Behavior on y {
        enabled: pill.opacity > 0.01

        Springy {
        }

    }

    Behavior on opacity {
        NumberAnimation {
            duration: 160
        }

    }

}
