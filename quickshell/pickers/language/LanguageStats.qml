import "../../common"
import "../../dropdowns" as Dropdowns
import "../../services"
import QtQuick

// Stats tab of the language picker: listening time of the period as a big serif number, the goal as a fine line,
// three key figures and an activity map of the last weeks (one field per day, opacity = listening time).
// Part of LanguagePicker.qml (picker = core), data from LanguageAudioState.stats ({"yyyy-MM-dd": seconds}).
Item {
    id: statsView

    required property var picker
    readonly property var stats: LanguageAudioState.stats || ({
    })

    // ── Dimensions ──
    readonly property real cell: 13
    readonly property real cellGap: 4
    readonly property int weeks: Math.max(8, Math.floor((width + cellGap) / (cell + cellGap)))
    readonly property real gridW: weeks * (cell + cellGap) - cellGap
    readonly property real gridH: 7 * (cell + cellGap) - cellGap

    implicitHeight: heat.y + heat.height + 10
    x: Math.round((parent.width - width) / 2)
    width: picker.narrowWidth - 2 * picker.pad
    height: picker.statsH
    opacity: (picker.filter === "stats" ? Math.min(1, picker.statsProgress * 2.5) * (picker.switching ? 1 : picker.morphGate) : picker.statsProgress) * (picker.choosing ? 0 : 1)
    visible: opacity > 0.01

    readonly property real allTimeSecs: {
        let t = 0;
        for (const k in stats) t += stats[k]
        return t;
    }
    readonly property int activeDays: {
        let n = 0;
        for (const k in stats) if (stats[k] > 0)
            n++

        return n;
    }

    function hm(mins) {
        const t = Math.round(mins);
        if (t < 60)
            return t + " min";

        return Math.floor(t / 60) + " h" + (t % 60 ? " " + (t % 60) + " min" : "");
    }

    function dayKey(d) {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    // Monday of the current week, 0:00: the last column of the map
    readonly property date thisMonday: {
        const d = new Date();
        d.setHours(0, 0, 0, 0);
        d.setDate(d.getDate() - (d.getDay() + 6) % 7);
        return d;
    }

    // Fields of the map (column = week, row = weekday), newest week on the right
    readonly property var cells: {
        const out = [];
        const today = new Date();
        today.setHours(23, 59, 59, 0);
        for (let w = 0; w < weeks; w++) {
            for (let d = 0; d < 7; d++) {
                const date = new Date(thisMonday);
                date.setDate(thisMonday.getDate() - (weeks - 1 - w) * 7 + d);
                const key = dayKey(date);
                out.push({
                    "w": w,
                    "d": d,
                    "date": date,
                    "secs": stats[key] || 0,
                    "future": date > today,
                    "today": key === dayKey(new Date())
                });
            }
        }
        return out;
    }

    // Month names above the column in which a new month begins
    readonly property var months: {
        const out = [];
        let last = -1;
        for (let w = 0; w < weeks; w++) {
            const date = new Date(thisMonday);
            date.setDate(thisMonday.getDate() - (weeks - 1 - w) * 7);
            if (date.getMonth() !== last) {
                // Only label the first column if the month also begins there (otherwise half a month at the edge)
                if (last !== -1 || date.getDate() <= 7)
                    out.push({
                    "w": w,
                    "label": Qt.formatDate(date, "MMM")
                });

                last = date.getMonth();
            }
        }
        return out;
    }

    readonly property real rangeSecs: {
        let t = 0;
        for (let i = 0; i < cells.length; i++) t += cells[i].secs
        return t;
    }

    property var hoverCell: null
    // Fields fade in column by column from the left when opening (opacity only: do not scale fine elements)
    property real sweep: picker.filter === "stats" && !picker.choosing ? 1 : 0

    Behavior on sweep {
        NumberAnimation {
            duration: statsView.sweep < 0.5 ? 900 : 120
            easing.type: Easing.OutCubic
        }

    }

    // ═══════════ Period ═══════════
    Dropdowns.Tabs {
        id: tabBar

        x: -14
        width: 4 * 68
        showLine: false
        opacity: picker.stage(picker.statsProgress, 0)
        current: picker.activePeriod
        model: [{
            "key": "day",
            "label": "Today"
        }, {
            "key": "week",
            "label": "Week"
        }, {
            "key": "month",
            "label": "Month"
        }, {
            "key": "year",
            "label": "Year"
        }]
        onSelected: (key) => {
            picker.activePeriod = key;
        }
    }

    // ═══════════ Big number + goal ═══════════
    Item {
        id: hero

        readonly property real st: picker.stage(picker.statsProgress, 0.1)
        readonly property int mins: Math.floor(picker.listenStats.heroMinutes)

        y: tabBar.height + 20
        width: parent.width
        height: 58
        opacity: st

        Row {
            id: bigNum

            anchors.bottom: parent.bottom
            spacing: 4

            Text {
                id: hText

                visible: hero.mins >= 60
                text: Math.floor(hero.mins / 60)
                color: Theme.text
                font.family: Theme.fontDisplay
                font.pixelSize: 54
                font.features: Theme.tabular
            }

            Text {
                visible: hero.mins >= 60
                anchors.baseline: hText.baseline
                rightPadding: 10
                text: "h"
                color: Theme.textFaint
                font.family: Theme.fontDisplay
                font.pixelSize: 22
                font.italic: true
            }

            Text {
                id: mText

                text: hero.mins % 60
                color: Theme.text
                font.family: Theme.fontDisplay
                font.pixelSize: 54
                font.features: Theme.tabular
            }

            Text {
                anchors.baseline: mText.baseline
                text: "min"
                color: Theme.textFaint
                font.family: Theme.fontDisplay
                font.pixelSize: 22
                font.italic: true
            }

        }

        Column {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            spacing: 2

            Text {
                anchors.right: parent.right
                text: picker.listenStats.progress >= 1 ? "GOAL REACHED" : Math.round(picker.listenStats.progress * 100) + " %"
                color: picker.listenStats.progress >= 1 ? Theme.accent : Theme.text
                font.family: Theme.fontUi
                font.pixelSize: picker.listenStats.progress >= 1 ? Theme.sizeMicro : Theme.sizeLead
                font.weight: Font.DemiBold
                font.letterSpacing: picker.listenStats.progress >= 1 ? Theme.microSpacing : 0
                font.features: Theme.tabular
            }

            Text {
                anchors.right: parent.right
                text: "of " + statsView.hm(picker.listenStats.maxMinutes) + " " + (picker.activePeriod === "day" ? "daily" : picker.activePeriod === "week" ? "weekly" : picker.activePeriod === "month" ? "monthly" : "yearly") + " goal"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
            }

        }

        transform: Translate {
            y: (1 - hero.st) * 10
        }

    }

    Rectangle {
        id: goalLine

        y: hero.y + hero.height + 14
        width: parent.width
        height: 4
        radius: 2
        color: Theme.track
        opacity: hero.st

        Rectangle {
            width: Math.round(parent.width * Math.min(1, picker.listenStats.heroProgress))
            height: parent.height
            radius: 2
            color: Theme.accent
        }

    }

    // ═══════════ Key figures ═══════════
    Row {
        id: figures

        readonly property real st: picker.stage(picker.statsProgress, 0.25)

        y: goalLine.y + goalLine.height + 26
        width: parent.width
        opacity: st

        Repeater {
            model: [{
                "label": "STREAK",
                "value": picker.listenStats.streak + (picker.listenStats.streak === 1 ? " day" : " days")
            }, {
                "label": "DAILY AVERAGE",
                "value": statsView.hm(picker.listenStats.weekAvgMinutes),
                "note": "last 7 days"
            }, {
                "label": "ALL TIME",
                "value": statsView.hm(statsView.allTimeSecs / 60),
                "note": statsView.activeDays + (statsView.activeDays === 1 ? " day" : " days")
            }]

            delegate: Column {
                id: fig

                required property var modelData

                width: figures.width / 3
                spacing: 5

                Text {
                    text: fig.modelData.label
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.microSpacing
                }

                Row {
                    spacing: 8

                    Text {
                        text: fig.modelData.value
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeTitle
                        font.weight: Font.Medium
                        font.features: Theme.tabular
                    }

                    Text {
                        anchors.baseline: parent.children[0].baseline
                        visible: !!fig.modelData.note
                        text: fig.modelData.note || ""
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                }

            }

        }

        transform: Translate {
            y: (1 - figures.st) * 10
        }

    }

    // ═══════════ Activity ═══════════
    Item {
        id: heat

        readonly property real st: picker.stage(picker.statsProgress, 0.35)

        y: figures.y + 46 + 30
        width: parent.width
        height: 16 + 22 + statsView.gridH
        opacity: st

        Text {
            text: "ACTIVITY"
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.weight: Font.DemiBold
            font.letterSpacing: Theme.microSpacing
        }

        // Right: when pointing at a field its day, otherwise the sum over the shown weeks
        Text {
            anchors.right: parent.right
            text: {
                const c = statsView.hoverCell;
                if (c)
                    return Qt.formatDate(c.date, "ddd, MMM d") + "  ·  " + (c.secs > 0 ? statsView.hm(c.secs / 60) : "nothing");

                return statsView.hm(statsView.rangeSecs / 60) + " in " + statsView.weeks + " weeks";
            }
            color: statsView.hoverCell ? Theme.text : Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeSmall
            font.features: Theme.tabular
        }

        Item {
            id: grid

            x: Math.round((parent.width - statsView.gridW) / 2)
            y: 16 + 22
            width: statsView.gridW
            height: statsView.gridH

            Repeater {
                model: statsView.months

                Text {
                    id: monthLabel

                    required property var modelData

                    x: modelData.w * (statsView.cell + statsView.cellGap)
                    y: -18
                    text: monthLabel.modelData.label
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                }

            }

            Repeater {
                model: statsView.cells

                Rectangle {
                    id: c

                    required property var modelData
                    readonly property real mins: modelData.secs / 60
                    readonly property bool hovered: statsView.hoverCell === modelData

                    x: modelData.w * (statsView.cell + statsView.cellGap)
                    y: modelData.d * (statsView.cell + statsView.cellGap)
                    width: statsView.cell
                    height: statsView.cell
                    radius: 3
                    visible: !modelData.future
                    opacity: Math.max(0, Math.min(1, statsView.sweep * (statsView.weeks + 6) - modelData.w))
                    color: modelData.secs <= 0 ? Theme.track : WalColors.withAlpha(WalColors.color4, mins < 5 ? 0.3 : mins < 15 ? 0.5 : mins < 30 ? 0.72 : 1)
                    border.width: modelData.today || hovered ? 1.5 : 0
                    border.color: hovered ? Theme.text : WalColors.withAlpha(WalColors.color7, 0.6)

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -statsView.cellGap / 2
                        hoverEnabled: true
                        onEntered: statsView.hoverCell = c.modelData
                        onExited: {
                            if (statsView.hoverCell === c.modelData)
                                statsView.hoverCell = null;

                        }
                    }

                }

            }

        }

        transform: Translate {
            y: (1 - heat.st) * 10
        }

    }

}
