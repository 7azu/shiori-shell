import "../../common"
import "../../services"
import QtQuick

// Read tab, reader: the word card next to the clicked word.
// Below the word if there is room (otherwise above it); grows out of the word.
// It closes when scrolling (the word would otherwise move away under it).
// Part of LanguageReader.qml (view = the Read tab, picker = core).
Item {
    id: wordPop

    required property var picker
    required property var view
    // Room for the card: from the lower edge of the chapter row down to the sentence card (or the footer)
    required property real ceilY
    required property real floorY

    readonly property bool open: wordPop.view.pickedWord !== null
    readonly property rect r: wordPop.view.pickRect
    readonly property bool below: r.y + r.height + 10 + height <= floorY - 4
    property var shownWord: null

    z: 20
    width: Math.min(Theme.px(380), parent.width - 16)
    height: wpCard.implicitHeight + 2 * Theme.px(18)
    x: Math.max(8, Math.min(parent.width - width - 8, r.x + r.width / 2 - width / 2))
    y: below ? r.y + r.height + 8 : Math.max(ceilY, r.y - height - 8)
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.94
    transformOrigin: below ? Item.Top : Item.Bottom
    visible: opacity > 0.01
    onOpenChanged: {
        if (open)
            shownWord = wordPop.view.pickedWord;

    }

    Connections {
        function onPickedWordChanged() {
            if (wordPop.view.pickedWord)
                wordPop.shownWord = wordPop.view.pickedWord;

        }

        target: wordPop.view
    }

    SoftShadow {
        radius: Theme.radiusL
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusL
        // opaque: lies over running text, which would shine through otherwise
        color: Qt.tint(WalColors.color0, WalColors.withAlpha(WalColors.color7, 0.04))
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color4, 0.3)
    }

    MouseArea {
        anchors.fill: parent
    }

    LanguageWordCard {
        id: wpCard

        x: Theme.px(20)
        y: Theme.px(18)
        width: parent.width - 2 * Theme.px(20)
        word: wordPop.shownWord
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.anim.durations.fast
        }

    }

    Behavior on scale {
        NumberAnimation {
            duration: Appearance.anim.durations.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecelerate
        }

    }

}
