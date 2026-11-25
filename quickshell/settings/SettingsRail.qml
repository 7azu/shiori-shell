pragma ComponentBehavior: Bound

import "../common"
import "../pickers/parts"
import "../services"
import QtQuick
import QtQuick.Shapes

// Left side of the settings window: name, search, the pages in numbered groups and the switch for
// advanced rows. Each page carries its seal (Seal) on the right. The open page is marked by a pill
// that glides, and by a small bookmark ribbon in front of the name: shiori (栞) means bookmark.
Item {
    id: rail

    readonly property real pad: Theme.px(18)
    readonly property real rowH: Theme.px(36)
    readonly property real groupH: Theme.px(34)
    readonly property bool searching: SettingsState.query.trim() !== ""
    // Group titles and pages in one list, each with its place
    readonly property var items: {
        const out = [];
        let group = -1;
        let y = 0;
        for (const s of SettingsState.sections) {
            if (s.group !== group) {
                group = s.group;
                out.push({
                    "kind": "group",
                    "y": y,
                    "index": group,
                    "title": SettingsState.groups[group]
                });
                y += groupH;
            }
            out.push({
                "kind": "page",
                "y": y,
                "sec": s
            });
            y += rowH;
        }
        return out;
    }
    readonly property real selY: {
        const it = items.find((i) => {
            return i.kind === "page" && i.sec.id === SettingsState.section;
        });
        return it ? it.y : 0;
    }

    signal keyPressed(var event)

    function focusSearch() {
        search.input.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.tint(Theme.text, 0.025)
    }

    // Name
    Row {
        id: brand

        x: rail.pad
        y: Theme.px(22)
        spacing: Theme.px(11)

        Seal {
            kanji: "栞"
            active: true
            size: Theme.px(34)
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(1)

            Text {
                text: "shiori"
                color: Theme.text
                font.family: Theme.fontDisplay
                font.pixelSize: Theme.px(19)
            }

            Text {
                text: "SETTINGS"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeMicro
                font.bold: true
                font.letterSpacing: 2.2
            }

        }

    }

    SearchField {
        id: search

        x: rail.pad
        y: brand.y + brand.height + Theme.px(18)
        width: rail.width - 2 * rail.pad
        height: Theme.px(36)
        placeholder: "Search settings"
        placeholderElide: true
        onTextChanged: {
            if (SettingsState.query !== text)
                SettingsState.query = text;

        }
        onKeyPressed: (event) => {
            return rail.keyPressed(event);
        }
    }

    Connections {
        function onQueryChanged() {
            if (search.text !== SettingsState.query)
                search.text = SettingsState.query;

        }

        function onFocusSearch() {
            rail.focusSearch();
        }

        target: SettingsState
    }

    Item {
        id: list

        x: 0
        y: search.y + search.height + Theme.px(12)
        width: rail.width
        height: rail.items.length > 0 ? rail.items[rail.items.length - 1].y + rail.rowH : 0

        // Selection: the pill of all pickers ...
        Rectangle {
            x: rail.pad - Theme.px(6)
            y: rail.selY + Theme.px(2)
            width: rail.width - 2 * rail.pad + Theme.px(12)
            height: rail.rowH - Theme.px(4)
            radius: Theme.px(12)
            color: Theme.tint(Theme.accent, 0.13)
            opacity: rail.searching ? 0 : 1

            Behavior on y {
                Springy {
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        // ... and the bookmark ribbon, cut in at its lower end
        Shape {
            id: ribbon

            readonly property real w: Theme.px(7)
            readonly property real h: Theme.px(15)

            x: rail.pad + Theme.px(4)
            y: rail.selY + Math.round((rail.rowH - h) / 2)
            width: w
            height: h
            opacity: rail.searching ? 0 : 1
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Theme.accent
                startX: 0
                startY: 0

                PathLine {
                    x: ribbon.w
                    y: 0
                }

                PathLine {
                    x: ribbon.w
                    y: ribbon.h
                }

                PathLine {
                    x: ribbon.w / 2
                    y: ribbon.h - ribbon.w * 0.55
                }

                PathLine {
                    x: 0
                    y: ribbon.h
                }

                PathLine {
                    x: 0
                    y: 0
                }

            }

            Behavior on y {
                Springy {
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        Repeater {
            model: rail.items

            Item {
                id: entry

                required property var modelData
                readonly property bool isPage: modelData.kind === "page"
                readonly property bool selected: isPage && !rail.searching && modelData.sec.id === SettingsState.section

                y: modelData.y
                width: list.width
                height: isPage ? rail.rowH : rail.groupH

                // Group: number, title, a hairline to the edge
                Item {
                    visible: !entry.isPage
                    anchors.fill: parent

                    Text {
                        id: groupText

                        x: rail.pad
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Theme.px(7)
                        text: entry.isPage ? "" : "0" + (entry.modelData.index + 1) + "   " + entry.modelData.title.toUpperCase()
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.features: Theme.tabular
                        font.pixelSize: Theme.sizeMicro
                        font.bold: true
                        font.letterSpacing: Theme.microSpacing
                    }

                    Rectangle {
                        anchors.left: groupText.right
                        anchors.leftMargin: Theme.px(10)
                        anchors.right: parent.right
                        anchors.rightMargin: rail.pad
                        anchors.verticalCenter: groupText.verticalCenter
                        height: 1
                        color: Theme.separator
                    }

                }

                // Page: name, seal
                Item {
                    visible: entry.isPage
                    anchors.fill: parent

                    Text {
                        x: rail.pad + Theme.px(20)
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.isPage ? entry.modelData.sec.name : ""
                        color: entry.selected || pageMouse.containsMouse ? Theme.text : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeLead
                        font.weight: entry.selected ? Font.DemiBold : Font.Normal

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                    }

                    Seal {
                        anchors.right: parent.right
                        anchors.rightMargin: rail.pad + Theme.px(2)
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.px(21)
                        kanji: entry.isPage ? entry.modelData.sec.seal : ""
                        active: entry.selected
                    }

                    MouseArea {
                        id: pageMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SettingsState.jump(entry.modelData.sec.id, "")
                    }

                }

            }

        }

    }

    // Rows that are rarely needed
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: rail.pad
        anchors.rightMargin: rail.pad
        anchors.bottomMargin: Theme.px(16)
        height: Theme.px(28)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Advanced"
            color: SettingsState.advanced ? Theme.text : Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeBody
        }

        IosSwitch {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            scale: 0.85
            transformOrigin: Item.Right
            checked: SettingsState.advanced
            onToggled: SettingsState.advanced = !SettingsState.advanced
        }

    }

}
