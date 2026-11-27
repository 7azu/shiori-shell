import "../common"
import "../services"
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Calendar panel of the bar. Sits in the morphing shape of the MainBar.
Item {
    id: calClip

    // The bar the panel belongs to: state and logic (morph, selection ...) live there
    required property var mainBar
    // Current height of the morphing shape (the panel is clipped to it)
    property real shapeHeight: 0
    // Natural height of the content (decides how far the shape opens)
    readonly property real contentHeight: calColumn.implicitHeight

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    width: mainBar.calBodyWidth
    height: shapeHeight
    clip: true
    opacity: mainBar.calContentOpacity
    visible: opacity > 0.01
    enabled: mainBar.calendarOpen
    focus: mainBar.calendarOpen
    Keys.onPressed: (event) => {
        event.accepted = true;
        switch (event.key) {
        case Qt.Key_Escape:
            mainBar.closePanels();
            break;
        case Qt.Key_Left:
        case Qt.Key_PageUp:
            mainBar.shiftMonth(-1);
            break;
        case Qt.Key_Right:
        case Qt.Key_PageDown:
            mainBar.shiftMonth(1);
            break;
        case Qt.Key_Home:
            mainBar.goToday();
            break;
        default:
            event.accepted = false;
        }
    }

    Column {
        id: calColumn

        readonly property int sec: mainBar.now.getSeconds()

        width: mainBar.calBodyWidth - 2 * mainBar.calPad
        topPadding: 14
        spacing: 0

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        // A board of cards: clock and month on the left, the weather cards beside them
        Item {
            width: parent.width
            height: leftCol.height

            Column {
                id: leftCol

                width: mainBar.calMonthWidth
                spacing: mainBar.calGap

                // ---- Card: the clock on the left, the selected day on the right. The clock is the only
                // eye-catcher in the serif (Fraunces), everything functional stays grotesque.
                // Display cut (opsz 144) without the wonky forms, slightly soft -> fits the round grotesque.
                // The colon pulses every second ----
                Item {
                    id: clockCard

                    scale: 1 + 0.018 * lift
                    // 0..1 under the pointer: the whole card, with all that stands on it, grows a little
                    // (all four cards alike)
                    property real lift: clockHover.hovered ? 1 : 0

                    Behavior on lift {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutCubic
                        }

                    }

                    width: parent.width
                    height: 96

                    HoverHandler {
                        id: clockHover
                    }

                    // The surface of the card; its edge turns brighter under the pointer
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusCard + 4
                        color: Theme.card
                        border.width: 1
                        border.color: clockHover.hovered ? Theme.tint(Theme.text, 0.16) : Theme.stroke

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 220
                            }

                        }

                    }

                    Column {
                        x: 22
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -1
                        spacing: 0

                        Row {
                            id: clockRow

                            readonly property var serifAxes: ({
                                "opsz": 144,
                                "WONK": 0,
                                "SOFT": 50,
                                "wght": 340
                            })

                            spacing: 2

                            Text {
                                id: hourText

                                text: Qt.formatTime(mainBar.now, "hh")
                                color: Theme.text
                                font.family: Theme.fontDisplay
                                font.pixelSize: 48
                                font.weight: 340
                                font.variableAxes: clockRow.serifAxes
                                font.features: {
                                    "tnum": 1,
                                    "lnum": 1
                                }
                            }

                            Text {
                                anchors.baseline: hourText.baseline
                                text: ":"
                                color: Theme.accent
                                opacity: calColumn.sec % 2 === 0 ? 1 : 0.3
                                font.family: Theme.fontDisplay
                                font.pixelSize: 48
                                font.weight: 340
                                font.variableAxes: clockRow.serifAxes

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 450
                                        easing.type: Easing.InOutSine
                                    }

                                }

                            }

                            Text {
                                text: Qt.formatTime(mainBar.now, "mm")
                                color: Theme.text
                                font.family: Theme.fontDisplay
                                font.pixelSize: 48
                                font.weight: 340
                                font.variableAxes: clockRow.serifAxes
                                font.features: {
                                    "tnum": 1,
                                    "lnum": 1
                                }
                            }

                        }

                        // Seconds as a hairline below the clock: fills once per minute
                        Rectangle {
                            x: 4
                            width: clockRow.width - 8
                            height: 2
                            radius: 1
                            color: Theme.track

                            Rectangle {
                                id: secFill

                                height: parent.height
                                radius: 1
                                width: parent.width * (calColumn.sec + 1) / 60
                                color: Theme.accent

                                // Do not animate backwards on the jump 59 -> 0
                                Behavior on width {
                                    enabled: calColumn.sec !== 0

                                    NumberAnimation {
                                        duration: 1000
                                    }

                                }

                            }

                        }

                    }

                    // The selected day in words (today, unless another day is picked in the month).
                    // Both lines change softly, right-aligned in a place of fixed width, so a longer
                    // name grows to the left and nothing jumps
                    Column {
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        width: 220
                        spacing: 5

                        CrossText {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: mainBar.weekdayLong[mainBar.selectedDate.getDay()]
                            color: Theme.text
                            travel: 0.22
                            duration: 460
                            font.pixelSize: 17
                            font.weight: Font.Medium
                            font.variableAxes: {
                                "wght": 500
                            }
                            font.letterSpacing: -0.2
                        }

                        CrossText {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: (mainBar.monthNames[mainBar.selectedDate.getMonth()] + " " + mainBar.selectedDate.getDate() + "  ·  Week " + mainBar.isoWeek(mainBar.selectedDate)).toUpperCase()
                            color: Theme.textFaint
                            travel: 0.2
                            duration: 460
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 1.4
                            font.features: Theme.tabular
                        }

                    }

                }

                // ---- Card: month + grid as their own unit, clearly separated from the clock ----
                Item {
                    id: monthCard

                    scale: 1 + 0.018 * lift
                    // 0..1 under the pointer: the whole card, with all that stands on it, grows a little
                    // (all four cards alike)
                    property real lift: monthHover.hovered ? 1 : 0

                    Behavior on lift {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutCubic
                        }

                    }

                    width: parent.width
                    height: cardColumn.implicitHeight

                    HoverHandler {
                        id: monthHover
                    }

                    // The surface of the card; its edge turns brighter under the pointer
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusCard + 4
                        color: Theme.card
                        border.width: 1
                        border.color: monthHover.hovered ? Theme.tint(Theme.text, 0.16) : Theme.stroke

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 220
                            }

                        }

                    }

                    Column {
                        id: cardColumn

                        x: mainBar.calCardPad
                        width: parent.width - 2 * mainBar.calCardPad
                        topPadding: 10
                        bottomPadding: 8
                        spacing: 0

                        Item {
                            width: parent.width
                            height: 38

                            Repeater {
                                model: [-1, 1]

                                delegate: Rectangle {
                                    id: navBtn

                                    required property int modelData

                                    x: modelData < 0 ? 0 : parent.width - width
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28
                                    height: 28
                                    radius: 9
                                    color: navMouse.containsMouse ? Theme.accentSoft : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: navBtn.modelData < 0 ? "󰅁" : "󰅂"
                                        color: navMouse.containsMouse ? Theme.accent : Theme.textDim
                                        font.family: Theme.font
                                        font.pixelSize: 15

                                        // Leans the way it leads while the pointer is on it
                                        transform: Translate {
                                            x: navMouse.pressed ? navBtn.modelData * 4 : (navMouse.containsMouse ? navBtn.modelData * 2 : 0)

                                            Behavior on x {
                                                NumberAnimation {
                                                    duration: 180
                                                    easing.type: Easing.OutCubic
                                                }

                                            }

                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Appearance.anim.durations.fast
                                            }

                                        }
                                    }

                                    MouseArea {
                                        id: navMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainBar.shiftMonth(navBtn.modelData)
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.anim.durations.fast
                                        }

                                    }

                                }

                            }

                            Text {
                                anchors.centerIn: parent
                                textFormat: Text.StyledText
                                // Year dimmed, so the month carries the weight.
                                // Grotesque instead of serif: the serif is reserved for the clock, otherwise both compete.
                                // wght explicitly, because the variable grotesque does not always pick up font.weight alone
                                text: mainBar.monthNames[mainBar.viewMonth] + " <font color='" + Theme.textFaint + "'>" + mainBar.viewYear + "</font>"
                                color: titleMouse.containsMouse ? Theme.accent : Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: 20
                                font.weight: Font.Medium
                                font.variableAxes: {
                                    "wght": 500
                                }
                                font.letterSpacing: -0.2
                                opacity: 0.25 + 0.75 * mainBar.slideT
                                // Moved by whole pixels and drawn directly. As a texture moved by fractions
                                // (as before) the text went soft on the way and snapped sharp at the end,
                                // seen as a last jump in a recording; a texture would also turn soft when
                                // the card grows under the pointer.

                                transform: Translate {
                                    x: Math.round(mainBar.slideDir * 12 * (1 - mainBar.slideT))
                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                                // A click on the month jumps back to today
                                MouseArea {
                                    id: titleMouse

                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mainBar.goToday()
                                }

                            }

                        }

                        Item {
                            width: 1
                            height: 8
                        }

                        // ---- Weekdays: micro labels, the weekend in the second accent color ----
                        Row {
                            height: 18

                            Text {
                                width: mainBar.wkW
                                horizontalAlignment: Text.AlignHCenter
                                text: "WK"
                                color: Theme.textFaint
                                font.family: Theme.fontUi
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 1.4
                            }

                            Repeater {
                                model: mainBar.weekdayShort

                                delegate: Text {
                                    required property string modelData
                                    required property int index

                                    width: mainBar.cellW
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.toUpperCase()
                                    color: index >= 5 ? Theme.tint(Theme.accent2, 0.75) : Theme.textDim
                                    font.family: Theme.fontUi
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                }

                            }

                        }

                        Item {
                            id: dayGrid

                            width: parent.width
                            height: 6 * mainBar.cellH
                            clip: true

                            WheelHandler {
                                onWheel: (event) => {
                                    mainBar.shiftMonth(event.angleDelta.y > 0 ? -1 : 1);
                                }
                            }

                            // "cur" = shown month, "prev" = the previous one, only visible during the slide.
                            // Both glide a bit (not the full width) and crossfade meanwhile -> feels softer.
                            Repeater {
                                model: ["cur", "prev"]

                                delegate: Column {
                                    id: monthGrid

                                    required property string modelData
                                    readonly property bool isPrev: modelData === "prev"
                                    readonly property var gridCells: isPrev ? mainBar.prevCells : mainBar.cells
                                    readonly property var gridWeeks: isPrev ? mainBar.prevWeekNumbers : mainBar.weekNumbers
                                    // A short way: the crossfade does the rest. Over 40 % of the width the
                                    // grid moved in steps too large to read as gliding.
                                    readonly property real travel: 44
                                    readonly property real t: mainBar.slideT

                                    x: Math.round(isPrev ? -mainBar.slideDir * travel * t : mainBar.slideDir * travel * (1 - t))
                                    opacity: isPrev ? 1 - Math.min(1, t * 2.2) : Math.min(1, t * 1.5)
                                    visible: !isPrev || t < 1
                                    enabled: !isPrev
                                    // Whole pixels, no texture (see the month title): numbers and tiles stay
                                    // together and nothing changes its look when the slide ends

                                    Repeater {
                                        model: 6

                                        delegate: Row {
                                            id: weekRow

                                            required property int index

                                            Item {
                                                width: mainBar.wkW
                                                height: mainBar.cellH

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: monthGrid.gridWeeks[weekRow.index]
                                                    color: Theme.textFaint
                                                    font.family: Theme.fontUi
                                                    font.pixelSize: Theme.sizeSmall
                                                    font.weight: Font.Medium
                                                    font.features: {
                                                        "tnum": 1
                                                    }
                                                }

                                            }

                                            Repeater {
                                                model: 7

                                                delegate: Item {
                                                    id: dayCell

                                                    required property int index
                                                    readonly property var cell: monthGrid.gridCells[weekRow.index * 7 + index]
                                                    readonly property bool isToday: cell.key === mainBar.todayKey
                                                    readonly property bool isSelected: cell.key === mainBar.selectedKey
                                                    readonly property bool isWeekend: index >= 5

                                                    width: mainBar.cellW
                                                    height: mainBar.cellH

                                                    // Rounded square instead of a circle: looks calmer with the grotesque
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 34
                                                        height: 30
                                                        radius: 10
                                                        color: dayCell.isToday ? Theme.accent : (dayCell.isSelected ? Theme.accentSoft : (dayMouse.containsMouse ? Theme.cardHover : "transparent"))
                                                        border.width: dayCell.isSelected && !dayCell.isToday ? 1 : 0
                                                        border.color: Theme.tint(Theme.accent, 0.6)
                                                        scale: dayMouse.pressed ? 0.92 : (dayMouse.containsMouse && !dayCell.isToday ? 1.06 : 1)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: dayCell.cell.day
                                                            color: dayCell.isToday ? Theme.onAccent : (!dayCell.cell.inMonth ? Theme.tint(Theme.text, 0.22) : (dayCell.isWeekend ? Theme.accent2 : Theme.text))
                                                            font.family: Theme.fontUi
                                                            font.pixelSize: 13
                                                            font.weight: dayCell.isToday || dayCell.isSelected ? Font.Bold : Font.Medium
                                                            font.features: {
                                                                "tnum": 1
                                                            }
                                                        }

                                                        // Only animate for hover/selection, not on a month change: the cells
                                                        // are reused and only get new days -> the today box
                                                        // would otherwise fade out in the new grid and only fade in in the old one
                                                        Behavior on color {
                                                            enabled: !monthGrid.isPrev && mainBar.slideT >= 1

                                                            ColorAnimation {
                                                                duration: Appearance.anim.durations.fast
                                                            }

                                                        }

                                                        Behavior on scale {
                                                            NumberAnimation {
                                                                duration: 160
                                                                easing.type: Easing.OutCubic
                                                            }

                                                        }

                                                    }

                                                    MouseArea {
                                                        id: dayMouse

                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: mainBar.selectCell(dayCell.cell)
                                                    }

                                                }

                                            }

                                        }

                                    }

                                }

                            }

                        }

                    }

                }

            }

            // ---- Weather cards (hidden when the weather is turned off; the board is then narrower) ----
            WeatherColumn {
                x: mainBar.calMonthWidth + mainBar.calGap
                width: mainBar.calSideWidth
                height: leftCol.height
                topHeight: clockCard.height
                gap: mainBar.calGap
                mainBar: calClip.mainBar
            }

        }

    }

}
