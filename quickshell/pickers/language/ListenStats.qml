import "../../services"
import QtQuick

// Listening time of the chosen language in numbers, for the stats tab and the header: the chosen period against
// its goal, the last seven days, today and the streak. Service of LanguagePicker.qml (picker = core); the chosen
// period (activePeriod) and the fade-in of the tab (statsProgress) stay in the core.
QtObject {
    id: stats

    required property var picker

    readonly property var currentStats: parseTime(LanguageAudioState.getStatsForPeriod(picker.activePeriod))
    readonly property real currentMinutes: (parseInt(currentStats.h) * 60) + parseInt(currentStats.m)
    readonly property real maxMinutes: {
        switch (picker.activePeriod) {
        case "day":
            return 60;
        case "week":
            return 300;
        case "month":
            return 1200;
        case "year":
            return 14400;
        }
        return 60;
    }
    readonly property string goalLabel: Math.round(maxMinutes / 60) + "h"
    readonly property real progress: Math.min(1, currentMinutes / maxMinutes)
    property real shownMinutes: currentMinutes
    property real displayProgress: progress
    readonly property real introK: picker.stage(picker.statsProgress, 0.1)
    readonly property real heroMinutes: shownMinutes * introK
    readonly property real heroProgress: displayProgress * introK
    readonly property var weekData: {
        const s = LanguageAudioState.stats || ({
        });
        const out = [];
        for (let i = 6; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            out.push({
                "label": Qt.formatDate(d, "ddd"),
                "secs": s[Qt.formatDate(d, "yyyy-MM-dd")] || 0,
                "today": i === 0
            });
        }
        return out;
    }
    readonly property real weekMaxSecs: {
        let m = 1;
        for (let i = 0; i < weekData.length; i++) m = Math.max(m, weekData[i].secs)
        return m;
    }
    readonly property real weekAvgMinutes: {
        let t = 0;
        for (let i = 0; i < weekData.length; i++) t += weekData[i].secs
        return t / 7 / 60;
    }
    // Header: listening time today against the daily goal (the same goal as "Day" in the stats tab)
    readonly property real dailyGoal: 60
    readonly property real todayMinutes: ((LanguageAudioState.stats || ({}))[Qt.formatDate(new Date(), "yyyy-MM-dd")] || 0) / 60
    readonly property int streak: {
        const s = LanguageAudioState.stats || ({
        });
        let n = 0;
        for (let i = 0; i < 3650; i++) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const v = s[Qt.formatDate(d, "yyyy-MM-dd")] || 0;
            if (v > 0)
                n++;
            else if (i > 0)
                break;
        }
        return n;
    }

    function parseTime(str) {
        const h = str.match(/(\d+)h/);
        const m = str.match(/(\d+)m/);
        return {
            "h": h ? h[1] : "0",
            "m": m ? m[1] : "0"
        };
    }

    function formatMinutes(mins) {
        const t = Math.round(mins);
        if (t < 60)
            return t + "m";

        return Math.floor(t / 60) + "h " + (t % 60) + "m";
    }

    Behavior on displayProgress {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }

    }

    Behavior on shownMinutes {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }

    }

}
