import "../services"
import QtQuick
import Quickshell
import Quickshell.Widgets

// Icon of a tray program (bar/TrayDrawer, bar/TrayPanel, bar/LogoHint). A theme icon by name is only used
// if the icon theme has it (else the name without "-symbolic"); without one a neutral glyph stands in for
// Qt's magenta "missing" square (fresh systems without a full icon theme, e.g. fcitx5's keyboard).
// Pictures the program sends itself are shown as they are.
Item {
    id: root

    // The item's icon (SystemTrayItem.icon)
    property string icon: ""
    property real size: 18
    readonly property string source: {
        const s = root.icon;
        if (!s.startsWith("image://icon/"))
            return s;

        const name = s.slice(13).split("?")[0];
        if (Quickshell.iconPath(name, true) !== "")
            return s;

        const plain = name.replace(/-symbolic$/, "");
        return plain !== name && Quickshell.iconPath(plain, true) !== "" ? "image://icon/" + plain : "";
    }

    implicitWidth: size
    implicitHeight: size

    IconImage {
        anchors.centerIn: parent
        implicitSize: root.size
        source: root.source
        visible: root.source !== ""
    }

    Text {
        anchors.centerIn: parent
        visible: root.source === ""
        text: String.fromCodePoint(0xf0614) // md-application_outline
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Math.round(root.size * 0.9)
    }

}
