import "../services"
import QtQuick

// Weather in the calendar panel: on the left the symbol, the temperature and the place, on the right
// the next four days. Without a frame, it stands between the date line and the month.
// It follows the calendar: a selected day that the forecast covers is shown instead of "now", and a
// click on one of the four days selects it in the calendar (again: back to today).
// Opening the calendar asks WeatherState for fresh data and lets the parts glide in one after another.
Item {
    id: strip

    required property var mainBar
    readonly property var wx: WeatherState.data
    readonly property bool has: wx !== null
    // The selected day, if it is not today and the forecast has it
    readonly property var picked: has && mainBar.selectedKey !== mainBar.todayKey ? WeatherState.dayFor(mainBar.selectedKey) : null
    // What should be shown; changes go through the swap below (old out, new in)
    readonly property string wantKey: !has ? "" : (picked ? picked.date + "|" + picked.code + "|" + picked.max + "|" + picked.min : "now|" + wx.now.code + "|" + wx.now.day)
    readonly property real wantTemp: !has ? 0 : (picked ? picked.max : wx.now.temp)
    property string shownKind: "cloud"
    property bool shownDay: true
    property string shownWords: ""
    property string shownLow: ""
    property string shownNote: ""
    property bool shownAny: false
    // The number rolls to its new value instead of jumping
    property real shownTemp: 0
    // 0..1 while the strip arrives after the calendar opened
    property real intro: 1
    // 1 = the left part is fully there, 0 = faded out for a swap
    property real face: 1
    readonly property string status: {
        if (has)
            return "";

        if (WeatherState.error === "unknown place")
            return "Place not found";

        if (WeatherState.error === "offline")
            return "No connection";

        if (WeatherState.error === "no place")
            return "No place set";

        if (WeatherState.error !== "")
            return "Weather unavailable";

        return "Loading weather";
    }

    function apply() {
        if (!has) {
            shownAny = false;
            return ;
        }
        const code = picked ? picked.code : wx.now.code;
        shownKind = WeatherState.kindOf(code);
        shownDay = picked ? true : wx.now.day;
        shownWords = WeatherState.textOf(code);
        shownLow = picked ? degrees(picked.min) : "";
        shownNote = picked ? "High and low" : "Feels " + degrees(wx.now.feels);
        shownAny = true;
    }

    // Rounded, with a real minus sign
    function degrees(value) {
        const r = Math.round(value);
        return (r < 0 ? "−" + (-r) : String(r)) + "°";
    }

    // Part of the arrival: starts at `from` (0..1 of the intro) and takes 0.45 of it
    function part(from) {
        const k = Math.max(0, Math.min(1, (intro - from) / 0.45));
        return 1 - Math.pow(1 - k, 3);
    }

    function weekdayOf(dateKey) {
        const p = dateKey.split("-");
        // weekdayShort starts on Monday, getDay() on Sunday
        return mainBar.weekdayShort[(new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])).getDay() + 6) % 7];
    }

    function selectDay(dateKey) {
        if (dateKey === mainBar.selectedKey) {
            mainBar.goToday();
            return ;
        }
        const p = dateKey.split("-");
        const year = Number(p[0]), month = Number(p[1]) - 1;
        mainBar.selectCell({
            "key": dateKey,
            "year": year,
            "month": month,
            "day": Number(p[2]),
            "inMonth": year === mainBar.viewYear && month === mainBar.viewMonth
        });
    }

    implicitHeight: 56
    height: implicitHeight
    visible: WeatherState.enabled
    onWantTempChanged: shownTemp = wantTemp
    onWantKeyChanged: {
        // The first answer simply appears; later changes swap
        if (!shownAny || !has) {
            apply();
            face = 1;
        } else {
            swap.restart();
        }
    }
    Component.onCompleted: {
        shownTemp = wantTemp;
        apply();
    }

    Connections {
        function onCalendarOpenChanged() {
            if (!strip.mainBar.calendarOpen)
                return ;

            WeatherState.refresh(false);
            introAnim.restart();
        }

        target: strip.mainBar
    }

    NumberAnimation {
        id: introAnim

        target: strip
        property: "intro"
        from: 0
        to: 1
        duration: 900
    }

    SequentialAnimation {
        id: swap

        NumberAnimation {
            target: strip
            property: "face"
            to: 0
            duration: 110
            easing.type: Easing.InCubic
        }

        ScriptAction {
            script: strip.apply()
        }

        NumberAnimation {
            target: strip
            property: "face"
            to: 1
            duration: 280
            easing.type: Easing.OutCubic
        }

    }

    Behavior on shownTemp {
        enabled: strip.shownAny

        NumberAnimation {
            duration: 520
            easing.type: Easing.OutCubic
        }

    }

    // ---------- Left: symbol, temperature, words ----------
    Item {
        id: left

        readonly property real k: strip.part(0)

        anchors.left: parent.left
        anchors.right: days.left
        anchors.rightMargin: 12
        height: parent.height
        visible: strip.shownAny
        opacity: k

        transform: Translate {
            y: (1 - left.k) * 8
        }

        WeatherGlyph {
            id: glyph

            x: 2
            anchors.verticalCenter: parent.verticalCenter
            size: 40
            kind: strip.shownKind
            day: strip.shownDay
            animated: strip.mainBar.calendarOpen
            opacity: strip.face

            transform: Translate {
                y: (1 - strip.face) * 5
            }

        }

        Text {
            id: temp

            x: 56
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1
            text: strip.degrees(strip.shownTemp)
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: 32
            font.weight: Font.Light
            font.variableAxes: {
                "wght": 320
            }
            font.features: Theme.tabular
            font.letterSpacing: -0.6
        }

        // Low of a forecast day, small beside the high
        Text {
            id: low

            anchors.left: temp.right
            anchors.leftMargin: 2
            anchors.baseline: temp.baseline
            text: strip.shownLow
            visible: text !== ""
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: 15
            font.features: Theme.tabular
            opacity: strip.face
        }

        Column {
            anchors.left: low.visible ? low.right : temp.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            opacity: strip.face

            transform: Translate {
                y: (1 - strip.face) * 5
            }

            Text {
                width: parent.width
                text: strip.shownWords
                color: Theme.text
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Text {
                width: parent.width
                text: ((strip.has ? strip.wx.place : "") + (strip.shownNote !== "" ? "  ·  " + strip.shownNote : "")).toUpperCase()
                color: Theme.textFaint
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1.4
                font.features: Theme.tabular
            }

        }

    }

    // ---------- Nothing to show: say why, quietly. A click leads to the setting ----------
    Row {
        anchors.centerIn: parent
        spacing: 10
        visible: !strip.shownAny
        opacity: strip.part(0)

        // A circling dot while the answer is on its way, a hollow one when there is none
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14

            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: "transparent"
                border.width: 1.2
                border.color: Theme.textFaint
                visible: !WeatherState.loading
            }

            Item {
                anchors.fill: parent
                visible: WeatherState.loading

                Rectangle {
                    x: parent.width / 2 - 2
                    y: 0
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.accent
                }

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1100
                    loops: Animation.Infinite
                    running: WeatherState.loading && strip.visible
                }

            }

        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherState.loading ? "Loading weather" : strip.status
            color: statusMouse.containsMouse && !WeatherState.loading ? Theme.accent : Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeLabel

            MouseArea {
                id: statusMouse

                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                enabled: !WeatherState.loading
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    strip.mainBar.closePanels();
                    SettingsState.openAt("desktop");
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

    }

    // ---------- Right: the next four days ----------
    Row {
        id: days

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        visible: strip.shownAny

        Repeater {
            model: strip.has ? strip.wx.days.slice(1, 5) : []

            delegate: Item {
                id: dayCol

                required property var modelData
                required property int index
                readonly property bool selected: modelData.date === strip.mainBar.selectedKey
                readonly property real k: strip.part(0.2 + index * 0.1)

                width: 40
                height: 52
                opacity: k

                transform: Translate {
                    y: (1 - dayCol.k) * 8
                }

                // Same look as a selected day in the month below
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: dayCol.selected ? Theme.accentSoft : (dayMouse.containsMouse ? Theme.cardHover : "transparent")
                    border.width: dayCol.selected ? 1 : 0
                    border.color: Theme.tint(Theme.accent, 0.6)
                    scale: dayMouse.pressed ? 0.94 : 1

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                        }

                    }

                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 5
                    text: strip.weekdayOf(dayCol.modelData.date).toUpperCase()
                    color: dayCol.selected ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4
                }

                WeatherGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 16
                    size: 19
                    kind: WeatherState.kindOf(dayCol.modelData.code)
                    // Only the day under the pointer moves, the row stays calm
                    animated: dayMouse.containsMouse && strip.mainBar.calendarOpen
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 37
                    spacing: 3

                    Text {
                        text: strip.degrees(dayCol.modelData.max)
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                        font.weight: Font.Medium
                        font.features: Theme.tabular
                    }

                    Text {
                        text: strip.degrees(dayCol.modelData.min)
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                        font.features: Theme.tabular
                    }

                }

                MouseArea {
                    id: dayMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.selectDay(dayCol.modelData.date)
                }

            }

        }

    }

}
