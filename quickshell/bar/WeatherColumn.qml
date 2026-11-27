import "../common"
import "../services"
import QtQuick

// Weather in the calendar panel, as two cards beside clock and month:
//   top    (as high as the clock card): now, or the selected day if the forecast covers it
//   below  (as high as the month card): the next six days, each with its range between low and high
// The cards follow the calendar: selecting a day there shows it on top and marks its row; a click on
// a row selects that day in the calendar (again: back to today). Resting the pointer on a row shows
// that day on top for as long as it stays there.
// Opening the calendar asks WeatherState for fresh data and lets the parts arrive one after another.
// The upper card changes softly: symbol, number and words each crossfade in a place of fixed width,
// so nothing is pushed aside. (A number that counted to its new value moved in visible jerks.)
Item {
    id: col

    required property var mainBar
    // Height of the upper card and the space between the two
    property real topHeight: 96
    property real gap: 12
    readonly property var wx: WeatherState.data
    readonly property bool has: wx !== null
    // The day under the pointer in the list below ("" = none); it goes first
    property string peekKey: ""
    // The day the upper card shows instead of "now": the one under the pointer, else the selected
    // day if it is not today. null where the forecast does not reach.
    readonly property var picked: {
        if (!has)
            return null;

        if (peekKey !== "")
            return WeatherState.dayFor(peekKey);

        return mainBar.selectedKey !== mainBar.todayKey ? WeatherState.dayFor(mainBar.selectedKey) : null;
    }
    readonly property bool shownAny: has
    readonly property int shownCode: !has ? 3 : (picked ? picked.code : wx.now.code)
    readonly property string shownKind: WeatherState.kindOf(shownCode)
    readonly property bool shownDay: !has || picked !== null || wx.now.day
    readonly property string shownWords: has ? WeatherState.textOf(shownCode) : ""
    readonly property string shownNote: !has ? "" : (picked ? "Low " + degrees(picked.min) : "Feels " + degrees(wx.now.feels))
    readonly property string shownLabel: !has ? "Weather" : (picked ? mainBar.weekdayLong[dateOf(picked.date).getDay()] : "Now")
    readonly property string shownTemp: !has ? "" : degrees(picked ? picked.max : wx.now.temp)
    // 0..1 while the cards fill after the calendar opened
    property real intro: 1
    // Coldest and warmest value of the whole forecast: the scale of the range lines
    readonly property real scaleLow: has ? Math.min(...wx.days.map((d) => {
        return d.min;
    })) : 0
    readonly property real scaleHigh: has ? Math.max(...wx.days.map((d) => {
        return d.max;
    })) : 1
    readonly property string status: {
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

    // Rounded, with a real minus sign
    function degrees(value) {
        const r = Math.round(value);
        return (r < 0 ? "−" + (-r) : String(r)) + "°";
    }

    // Part of the arrival: starts at `from` (0..1 of the intro) and takes `span` of it
    function part(from, span) {
        const k = Math.max(0, Math.min(1, (intro - from) / (span || 0.45)));
        return 1 - Math.pow(1 - k, 3);
    }

    function dateOf(dateKey) {
        const p = dateKey.split("-");
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    }

    function selectDay(dateKey) {
        if (dateKey === mainBar.selectedKey) {
            mainBar.goToday();
            return ;
        }
        const d = dateOf(dateKey);
        mainBar.selectCell({
            "key": dateKey,
            "year": d.getFullYear(),
            "month": d.getMonth(),
            "day": d.getDate(),
            "inMonth": d.getFullYear() === mainBar.viewYear && d.getMonth() === mainBar.viewMonth
        });
    }

    visible: WeatherState.enabled

    Connections {
        function onCalendarOpenChanged() {
            if (!col.mainBar.calendarOpen)
                return ;

            col.peekKey = "";
            WeatherState.refresh(false);
            introAnim.restart();
        }

        target: col.mainBar
    }

    NumberAnimation {
        id: introAnim

        target: col
        property: "intro"
        from: 0
        to: 1
        duration: 1100
    }

    // The pointer has to rest on a row for a moment before the upper card follows; moving on to the
    // next row changes at once, leaving the list goes back after a short wait (no flicker in between)
    Timer {
        id: peekTimer

        property string want: ""

        interval: col.peekKey === "" || want === "" ? 140 : 1
        onTriggered: col.peekKey = want
    }

    // ---------- Upper card: now or the selected day ----------
    Card {
        id: nowCard

        width: parent.width
        height: col.topHeight

        CrossText {
            x: 16
            y: 13
            width: 120
            text: col.shownLabel.toUpperCase()
            travel: 0.2
            duration: 460
            color: col.picked ? Theme.accent : Theme.textFaint
            font.pixelSize: 9
            font.weight: Font.Bold
            font.letterSpacing: 1.4
            font.features: Theme.tabular

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.normal
                }

            }

        }

        // The place; a click leads to its setting
        Caps {
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 13
            width: Math.min(implicitWidth, parent.width - 150)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: col.has ? col.wx.place : ""
            color: placeMouse.containsMouse ? Theme.accent : Theme.textFaint

            MouseArea {
                id: placeMouse

                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    col.mainBar.closePanels();
                    SettingsState.openAt("desktop");
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.anim.durations.fast
                }

            }

        }

        Item {
            id: nowBody

            readonly property real k: col.part(0, 0.4)

            x: 16
            y: 34
            width: parent.width - 32
            height: 46
            visible: col.shownAny
            opacity: k

            transform: Translate {
                y: (1 - nowBody.k) * 8
            }

            WeatherGlyph {
                anchors.verticalCenter: parent.verticalCenter
                size: 38
                kind: col.shownKind
                day: col.shownDay
                animated: col.mainBar.calendarOpen
            }

            // Number and words stand in places of fixed width: a wider number pushes nothing aside
            CrossText {
                x: 50
                width: 70
                anchors.verticalCenter: parent.verticalCenter
                text: col.shownTemp
                color: Theme.text
                travel: 0.3
                font.pixelSize: 32
                font.weight: Font.Light
                font.variableAxes: {
                    "wght": 320
                }
                font.features: Theme.tabular
                font.letterSpacing: -0.6
            }

            Column {
                x: 124
                width: parent.width - x
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                CrossText {
                    width: parent.width
                    text: col.shownWords
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                CrossText {
                    width: parent.width
                    text: col.shownNote.toUpperCase()
                    color: Theme.textFaint
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4
                    font.features: Theme.tabular
                }

            }

        }

        // Nothing to show: say why, quietly. A click leads to the setting
        Row {
            x: 16
            y: 34 + (46 - height) / 2
            spacing: 10
            visible: !col.shownAny
            opacity: col.part(0, 0.4)

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
                        running: WeatherState.loading && col.visible
                    }

                }

            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: col.status
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
                        col.mainBar.closePanels();
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

    }

    // ---------- Lower card: the next days ----------
    Card {
        id: daysCard

        readonly property real rowsTop: 36
        readonly property real rowH: (height - rowsTop - 8) / 6

        y: col.topHeight + col.gap
        width: parent.width
        height: parent.height - y

        Caps {
            x: 16
            y: 13
            text: "Next days"
        }

        Repeater {
            // Without data six quiet rows keep the place, so nothing jumps when the answer arrives
            model: col.has ? col.wx.days.slice(1, 7) : 6

            delegate: Item {
                id: dayRow

                required property var modelData
                required property int index
                readonly property bool real: col.has && typeof modelData === "object"
                readonly property bool selected: real && modelData.date === col.mainBar.selectedKey
                readonly property real k: col.part(0.12 + index * 0.07, 0.4)
                // The line fills a little after its row arrived
                readonly property real fillK: col.part(0.3 + index * 0.07, 0.45)
                readonly property real span: Math.max(1, col.scaleHigh - col.scaleLow)

                x: 6
                y: daysCard.rowsTop + index * daysCard.rowH
                width: daysCard.width - 12
                height: daysCard.rowH
                opacity: real ? k : 0.5 * k
                // The day under the pointer grows a little, with all that stands in its row
                scale: rowMouse.pressed ? 0.98 : (rowMouse.containsMouse ? 1.035 : 1)

                transform: Translate {
                    y: (1 - dayRow.k) * 8
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                }

                // Same look as a selected day in the month
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    radius: 10
                    color: dayRow.selected ? Theme.accentSoft : Theme.cardHover
                    border.width: dayRow.selected ? 1 : 0
                    border.color: Theme.tint(Theme.accent, 0.6)
                    opacity: dayRow.selected || rowMouse.containsMouse ? 1 : 0

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                    // The surface fades in and out instead of switching
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }

                    }

                }

                Caps {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: dayRow.real ? col.mainBar.weekdayShort[(col.dateOf(dayRow.modelData.date).getDay() + 6) % 7] : ""
                    color: dayRow.selected ? Theme.accent : (rowMouse.containsMouse ? Theme.text : Theme.textDim)

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.fast
                        }

                    }

                }

                WeatherGlyph {
                    id: rowGlyph

                    x: 38
                    anchors.verticalCenter: parent.verticalCenter
                    size: 19
                    visible: dayRow.real
                    kind: dayRow.real ? WeatherState.kindOf(dayRow.modelData.code) : "cloud"
                    // The cloud is filled with what is behind it: the row's surface where it shows
                    backdrop: dayRow.selected ? Qt.tint(rowGlyph.cardColor, Theme.accentSoft) : (rowMouse.containsMouse ? Qt.tint(rowGlyph.cardColor, Theme.cardHover) : rowGlyph.cardColor)

                    Behavior on backdrop {
                        ColorAnimation {
                            duration: 180
                        }

                    }
                    // Only the day under the pointer moves, the list stays calm
                    animated: rowMouse.containsMouse && col.mainBar.calendarOpen
                }

                Text {
                    x: 64
                    width: 30
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: dayRow.real ? col.degrees(dayRow.modelData.min) : ""
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                    font.features: Theme.tabular
                }

                // Range of the day on the scale of the whole forecast
                Rectangle {
                    id: track

                    x: 102
                    width: parent.width - x - 44
                    height: 3
                    radius: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.track

                    Rectangle {
                        readonly property real from: dayRow.real ? (dayRow.modelData.min - col.scaleLow) / dayRow.span : 0
                        readonly property real to: dayRow.real ? (dayRow.modelData.max - col.scaleLow) / dayRow.span : 0

                        x: from * track.width
                        width: Math.max(height, (to - from) * track.width) * dayRow.fillK
                        height: parent.height
                        radius: height / 2
                        visible: dayRow.real
                        color: dayRow.selected || rowMouse.containsMouse ? Theme.accent : Theme.tint(Theme.accent, 0.7)

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                    }

                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    width: 30
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: dayRow.real ? col.degrees(dayRow.modelData.max) : ""
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                    font.weight: Font.Medium
                    font.features: Theme.tabular
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: dayRow.real
                    cursorShape: Qt.PointingHandCursor
                    onClicked: col.selectDay(dayRow.modelData.date)
                    onContainsMouseChanged: {
                        if (containsMouse) {
                            peekTimer.want = dayRow.modelData.date;
                            peekTimer.restart();
                        } else if (peekTimer.want === dayRow.modelData.date) {
                            peekTimer.want = "";
                            peekTimer.restart();
                        }
                    }
                }

            }

        }

    }

    // Same surface as the clock and month cards
    component Card: Item {
        id: card

        // 0..1 under the pointer: the whole card, with all that stands on it, grows a little
        // (all four cards alike)
        scale: 1 + 0.018 * lift
        property real lift: cardHover.hovered ? 1 : 0

        Behavior on lift {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }

        }

        HoverHandler {
            id: cardHover
        }

        // The surface of the card; its edge turns brighter under the pointer
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusCard + 4
            color: Theme.card
            border.width: 1
            border.color: cardHover.hovered ? Theme.tint(Theme.text, 0.16) : Theme.stroke

            Behavior on border.color {
                ColorAnimation {
                    duration: 220
                }

            }

        }

    }

    // Small spaced capitals: card labels and side notes
    component Caps: Text {
        color: Theme.textFaint
        font.family: Theme.fontUi
        font.pixelSize: 9
        font.weight: Font.Bold
        font.letterSpacing: 1.4
        font.capitalization: Font.AllUppercase
        font.features: Theme.tabular
    }

}
