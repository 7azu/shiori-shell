import "../services"
import QtQuick
import Quickshell

// App icon with a uniform fallback: if the icon cannot be found or loaded, a rounded
// tile with the first letter of the app appears (as in the task manager).
// Do not load "image://icon/<name>" directly: for unknown names Qt returns a
// magenta-black checkerboard with status "Ready" there instead of an error.
Item {
    id: root

    // Theme icon name, absolute path or URL (Icon= from the .desktop file)
    property string icon: ""
    property string name: ""
    property bool highlighted: false
    readonly property string source: {
        const i = icon.trim();
        if (i === "")
            return "";

        if (i.startsWith("/"))
            return "file://" + i;

        if (i.includes("://"))
            return i;

        return Quickshell.iconPath(i, true);
    }
    readonly property bool failed: source === "" || img.status === Image.Error

    Image {
        id: img

        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.width * 2, root.height * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        visible: root.failed
        radius: width * 0.28
        color: WalColors.withAlpha(WalColors.color4, root.highlighted ? 0.28 : 0.16)
        border.width: Math.max(1, width / 30)
        border.color: WalColors.withAlpha(WalColors.color4, 0.4)

        Text {
            anchors.centerIn: parent
            text: root.name.length > 0 ? root.name.charAt(0).toUpperCase() : "?"
            font.family: Theme.font
            font.pixelSize: Math.round(root.height * 0.46)
            font.bold: true
            color: WalColors.color4
        }

        Behavior on color {
            ColorAnimation {
                duration: 100
            }

        }

    }

}
