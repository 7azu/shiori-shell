import "../services"
import "../services/AiUsageFormat.js" as Format
import QtQuick
import "../common/Format.js" as Fmt

// Limits and local token usage for the selected provider.
// On top: two rings "remaining" (5h window, week) with a reset countdown.
// Below: used tokens (today/week/total) and 7-day bars.
Item {
    id: dropdown

    readonly property var provider: AiUsageState.provider
    // No supported AI CLI installed: only the header and a hint
    readonly property bool none: !AiUsageState.hasProviders
    readonly property var usage: provider.usage()
    readonly property real cornerRadius: 20
    readonly property real menuWidth: 460
    readonly property real innerW: menuWidth - 2 * Theme.padX
    readonly property var dayShort: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    readonly property var chartDays: {
        const days = usage.days.slice(-7);
        const peak = days.reduce((highest, day) => Math.max(highest, day.total), 0);
        const scaled = days.map((day) => ({
            date: day.date,
            total: day.total,
            fraction: peak > 0 ? day.total / peak : 0
        }));
        return Array(7 - scaled.length).fill(null).concat(scaled);
    }
    property int hoveredDay: -1
    readonly property var hoveredData: hoveredDay >= 0 ? chartDays[hoveredDay] : null
    onProviderChanged: hoveredDay = -1

    function dayOf(iso) {
        const p = iso.split("-");
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
    }

    function ago(ts) {
        if (!ts)
            return "never";

        return Fmt.ago(Math.max(0, Math.round(dropdown.usage.nowMs / 1000 - ts)), {
            "now": "just now",
            "suffix": " ago"
        });
    }

    implicitWidth: menuWidth + 2 * cornerRadius
    implicitHeight: content.implicitHeight

    Column {
        id: content

        width: dropdown.innerW
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gap
        topPadding: Theme.padTop
        bottomPadding: Theme.padBottom

        DropdownHeader {
            glyph: dropdown.none ? "󰚩" : dropdown.provider.glyph
            title: dropdown.none ? "AI usage" : dropdown.provider.title

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (dropdown.none)
                        return "";
                    if (dropdown.usage.checkingLimits)
                        return "checking account…";
                    if (dropdown.usage.loginRequired)
                        return dropdown.usage.hasLimits ? "login required · cached" : "login required";
                    if (dropdown.usage.hasLimits)
                        return dropdown.usage.limitStatus + " · " + dropdown.ago(dropdown.usage.limitsUpdated);
                    return dropdown.provider.scope;
                }
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeSmall
            }

        }

        // Tabs only when there is something to choose
        Tabs {
            width: parent.width
            visible: AiUsageState.availableProviders.length > 1
            model: AiUsageState.availableProviders
            current: AiUsageState.selectedKey
            onSelected: (key) => AiUsageState.select(key)
        }

        Card {
            width: parent.width
            height: noneHint.implicitHeight + 28
            visible: dropdown.none

            Column {
                id: noneHint

                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No AI tools installed"
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody + 2
                    font.bold: true
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Install " + AiUsageState.providers.map((entry) => entry.title.split(" · ").pop()).join(" or ") + " to see your limits and token usage here."
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                }

            }

        }

        // Same height with or without limits, also during the account query.
        Item {
            width: parent.width
            visible: !dropdown.none
            height: limitRow.implicitHeight

            Row {
                id: limitRow

                width: parent.width
                opacity: dropdown.usage.hasLimits ? 1 : 0

                LimitRing {
                    width: parent.width / 2
                    label: "5-hour window"
                    win: dropdown.usage.five
                }

                LimitRing {
                    width: parent.width / 2
                    label: "Weekly"
                    win: dropdown.usage.week
                }

            }

            // No limit data yet: a short hint instead of empty rings
            Card {
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                height: hint.implicitHeight + 28
                visible: !dropdown.usage.hasLimits

                Column {
                    id: hint

                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dropdown.usage.checkingLimits ? "Checking account limits…" : "No current limit data"
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody + 2
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: dropdown.usage.loginRequired
                            ? "Open " + dropdown.provider.title + " to renew your login."
                            : dropdown.provider.emptyMessage
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                }

            }
        }

        // ---------- Used ----------
        Row {
            width: parent.width
            visible: !dropdown.none
            spacing: Theme.gapSmall

            Repeater {
                model: [{
                    "key": "today",
                    "label": "today"
                }, {
                    "key": "week",
                    "label": "7 days"
                }, {
                    "key": "all",
                    "label": "all time"
                }]

                delegate: Stat {
                    required property var modelData

                    width: (dropdown.innerW - 2 * Theme.gapSmall) / 3
                    value: Format.fmt(dropdown.usage.range(modelData.key).total)
                    label: modelData.label + " · tokens"
                }

            }

        }

        // ---------- Last 7 days ----------
        Card {
            width: parent.width
            visible: !dropdown.none
            height: chartCol.implicitHeight + 24

            Column {
                id: chartCol

                anchors.centerIn: parent
                width: parent.width - 24
                spacing: Theme.gapSmall

                Item {
                    width: parent.width
                    height: chartTitle.implicitHeight

                    Text {
                        id: chartTitle

                        text: "LAST 7 DAYS"
                        color: Theme.textFaint
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                        font.bold: true
                        font.letterSpacing: Theme.microSpacing
                    }

                    // Hover value of the bar (instead of a tooltip, which would be cut off at the dropdown edge)
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: chartTitle.verticalCenter
                        text: {
                            const d = dropdown.hoveredData;
                            if (!d)
                                return "";

                            const dt = dropdown.dayOf(d.date);
                            return dropdown.dayShort[dt.getDay()] + " " + dt.getDate() + "." + (dt.getMonth() + 1) + ".  ·  " + Format.fmt(d.total);
                        }
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.features: Theme.tabular
                        font.pixelSize: Theme.sizeSmall
                        font.bold: true
                    }

                }

                Row {
                    id: chart

                    readonly property real chartH: 40
                    readonly property real slotW: width / 7

                    width: parent.width
                    height: chartH + 16

                    Repeater {
                        model: 7

                        delegate: Item {
                            id: daySlot

                            required property int index
                            readonly property var day: dropdown.chartDays[index]
                            readonly property bool isToday: index === 6
                            readonly property bool hot: dayMouse.containsMouse
                            readonly property real barH: day && day.fraction > 0 ? Math.max(3, chart.chartH * day.fraction) : 0

                            width: chart.slotW
                            height: chart.height
                            opacity: day ? 1 : 0

                            // Base line (2px gap between the columns)
                            Rectangle {
                                x: 1
                                y: chart.chartH
                                width: parent.width - 2
                                height: 1
                                color: Theme.stroke
                            }

                            // Bars: rounded on top, straight at the bottom on the base line
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: chart.chartH - height
                                width: 16
                                height: daySlot.barH
                                opacity: daySlot.hot || daySlot.isToday ? 1 : 0.45

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: Theme.accent
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.min(parent.height, 4)
                                    color: Theme.accent
                                }

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 420
                                        easing.type: Easing.OutCubic
                                    }

                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Appearance.anim.durations.fast
                                    }

                                }

                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: chart.chartH + 4
                                text: daySlot.day ? dropdown.dayShort[dropdown.dayOf(daySlot.day.date).getDay()] : ""
                                color: daySlot.isToday || daySlot.hot ? Theme.text : Theme.textFaint
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeMicro
                                font.bold: daySlot.isToday
                            }

                            // Hit area = whole column, bigger than the bar
                            MouseArea {
                                id: dayMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: daySlot.day !== null
                                onContainsMouseChanged: {
                                    if (containsMouse)
                                        dropdown.hoveredDay = daySlot.index;
                                    else if (dropdown.hoveredDay === daySlot.index)
                                        dropdown.hoveredDay = -1;
                                }
                            }

                        }

                    }

                }

            }

        }

    }

    // Ring "remaining": full ring = 100% free, shrinks with usage
    component LimitRing: Column {
        id: limit

        property string label: ""
        property var win: ({})

        spacing: Theme.gapSmall

        Ring {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 124
            progress: limit.win.left / 100
            tone: Theme.levelTone(limit.win.left)
            caption: "left"
            value: limit.win.known ? Math.round(shown * 100) + "%" : "–"
            valueSize: Theme.sizeDisplay - 4
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: limit.label
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeBody
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !limit.win.known ? "unknown" : (limit.win.resetMs > 0 ? "resets in " + Format.resetIn(limit.win.resetMs, dropdown.usage.nowMs) : "fresh window")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.features: Theme.tabular
                font.pixelSize: Theme.sizeSmall
            }

        }

    }

}
