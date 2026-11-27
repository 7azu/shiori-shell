pragma ComponentBehavior: Bound

import "../common"
import "../services"
import QtQuick
import Quickshell
import Quickshell.Widgets

// Tray panel of the bar: the list of the programs in the tray (services/TrayState), for the keyboard
// ("Tray" in the launcher, or a shortcut). With the mouse the icons in the tray drawer are the way
// (bar/TrayDrawer). Sits in the morphing shape of the MainBar, like the monitor panel.
// Two levels: the programs (Enter = bring the program up, Right = its whole menu), then the menu of
// one (common/TrayMenu; Left = back).
// Keys in the list: Up/Down (Ctrl+K/J) move, Enter/Space choose, Right/Tab open the menu, H hides a
// program or brings it back, Esc closes.
Item {
    id: trayClip

    // The bar the panel belongs to: state and morph live there
    required property var mainBar
    // Current height of the morphing shape (the panel is clipped to it)
    property real shapeHeight: 0
    // Natural height of the content (decides how far the shape opens)
    readonly property real contentHeight: column.implicitHeight
    readonly property real rowH: 40
    readonly property real maxListH: 440
    // The program whose menu is shown; null = the list of programs
    property var owner: null
    readonly property bool inMenu: owner !== null
    property int index: 0
    readonly property var items: TrayState.items

    function step(dir) {
        index = Math.max(0, Math.min(items.length - 1, index + dir));
    }

    function openMenu(item) {
        if (item && item.hasMenu)
            owner = item;

    }

    // Back in the list: on the program whose menu it was
    function closeMenu() {
        const at = items.indexOf(owner);
        owner = null;
        index = at >= 0 ? at : 0;
    }

    function choose(i) {
        const item = items[i];
        if (!item)
            return ;

        index = i;
        TrayState.open(item);
        mainBar.closePanels();
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    width: mainBar.trayBodyWidth
    height: shapeHeight
    clip: true
    opacity: mainBar.trayContentOpacity
    visible: opacity > 0.01
    enabled: mainBar.trayOpen
    focus: mainBar.trayOpen
    // A program quit: stay inside the list, and leave a menu that is gone
    onItemsChanged: {
        if (owner && TrayState.all.indexOf(owner) === -1)
            owner = null;

        if (index >= items.length)
            index = Math.max(0, items.length - 1);

    }
    Keys.onPressed: (event) => {
        if (inMenu) {
            event.accepted = menu.handleKey(event);
            return ;
        }
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        event.accepted = true;
        switch (event.key) {
        case Qt.Key_Escape:
            mainBar.closePanels();
            break;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            step(-1);
            break;
        case Qt.Key_Down:
            step(1);
            break;
        case Qt.Key_K:
            if (ctrl)
                step(-1);

            break;
        case Qt.Key_J:
            if (ctrl)
                step(1);

            break;
        case Qt.Key_Right:
        case Qt.Key_Tab:
            openMenu(items[index]);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            choose(index);
            break;
        case Qt.Key_H:
            if (!ctrl && items[index])
                TrayState.setHidden(items[index], !TrayState.isHidden(items[index]));

            break;
        default:
            event.accepted = false;
        }
    }

    // Every opening starts at the list of programs
    Connections {
        function onTrayOpenChanged() {
            if (!trayClip.mainBar.trayOpen)
                return ;

            trayClip.owner = null;
            trayClip.index = 0;
            TrayState.showHidden = false;
        }

        target: trayClip.mainBar
    }

    Column {
        id: column

        width: trayClip.mainBar.trayBodyWidth - 2 * trayClip.mainBar.calPad
        topPadding: 14
        spacing: 10

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        // Header: "Tray" or, inside a menu, back to the list
        Item {
            width: parent.width
            height: 36

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Back
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: trayClip.inMenu
                    text: "\u{F0141}"
                    color: backMouse.containsMouse ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.6)
                    font.family: Theme.font
                    font.pixelSize: Theme.sizeHeading + 2

                    MouseArea {
                        id: backMouse

                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menu.back()
                    }

                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: trayClip.inMenu ? TrayState.nameOf(trayClip.owner) : "Tray"
                        textFormat: Text.PlainText
                        color: WalColors.color2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeHeading
                        font.bold: true
                    }

                    Text {
                        text: trayClip.inMenu ? "Enter chooses  ·  Left goes back" : "Enter opens  ·  Right shows the menu"
                        color: WalColors.withAlpha(WalColors.color7, 0.55)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                }

            }

            // Hidden programs: show them (dimmed) to bring one back
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: !trayClip.inMenu && TrayState.hiddenCount > 0
                height: 22
                radius: height / 2
                width: hiddenText.implicitWidth + 18
                color: WalColors.withAlpha(WalColors.color4, TrayState.showHidden || hiddenMouse.containsMouse ? 0.24 : 0.14)

                Text {
                    id: hiddenText

                    anchors.centerIn: parent
                    text: TrayState.hiddenCount + " hidden"
                    color: WalColors.color4
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    font.features: Theme.tabular
                    font.bold: true
                }

                MouseArea {
                    id: hiddenMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: TrayState.showHidden = !TrayState.showHidden
                }

            }

        }

        // Nothing in the tray
        Text {
            width: parent.width
            height: 48
            visible: !trayClip.inMenu && trayClip.items.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "No program is in the tray"
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLabel
        }

        // The programs
        ListView {
            id: list

            width: parent.width
            height: Math.min(trayClip.maxListH, contentHeight)
            visible: !trayClip.inMenu && trayClip.items.length > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: trayClip.items
            currentIndex: trayClip.index
            highlightMoveDuration: 140
            highlightResizeDuration: 0

            highlight: Rectangle {
                radius: 12
                color: WalColors.withAlpha(WalColors.color4, 0.13)
            }

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: trayClip.rowH
                opacity: TrayState.isHidden(modelData) ? 0.5 : 1

                // Asks for the menu already now, so its entries are there when it is opened
                QsMenuOpener {
                    menu: trayClip.mainBar.trayOpen && row.modelData.hasMenu ? row.modelData.menu : null
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: more.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    TrayIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 22
                        icon: row.modelData.icon || ""
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 34
                        spacing: 1

                        Text {
                            width: parent.width
                            text: TrayState.nameOf(row.modelData)
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeLead
                            font.weight: Font.Medium
                        }

                        Text {
                            readonly property string detail: TrayState.detailOf(row.modelData)

                            width: parent.width
                            visible: detail !== ""
                            text: detail
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeSmall
                        }

                    }

                }

                // To the menu of the program
                Text {
                    id: more

                    visible: row.modelData.hasMenu
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0142}"
                    color: moreMouse.containsMouse ? WalColors.color4 : Theme.textFaint
                    font.family: Theme.font
                    font.pixelSize: Theme.sizeHeading + 2
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    // Hover is the selection, as in the pickers
                    onPositionChanged: trayClip.index = row.index
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton)
                            trayClip.openMenu(row.modelData);
                        else
                            trayClip.choose(row.index);
                    }
                }

                // The arrow opens the menu, a click elsewhere the program
                MouseArea {
                    id: moreMouse

                    visible: more.visible
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 40
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: trayClip.index = row.index
                    onClicked: trayClip.openMenu(row.modelData)
                }

            }

        }

        // The menu of one program
        TrayMenu {
            id: menu

            width: parent.width
            visible: trayClip.inMenu
            height: trayClip.inMenu ? implicitHeight : 0
            program: trayClip.owner
            maxListH: trayClip.maxListH
            onDone: trayClip.mainBar.closePanels()
            onLeave: trayClip.closeMenu()
        }

        // Air below the list (the shape adds the rest)
        Item {
            width: 1
            height: 2
        }

    }

}
