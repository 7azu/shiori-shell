pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather for the calendar panel (bar/WeatherStrip). The data comes from scripts/weather.py
// (Open-Meteo, no key): the weather right now and the next days at one place.
//
// Settings (settings.json, "weather"):
//   enabled  true | false      the strip in the calendar
//   place    "Tokyo"           a town or city; empty = the rough position of the night light (time zone)
//   unit     "c" | "f"
//
// Nothing is fetched in the background: refresh() is called when the calendar opens and only asks the
// network when the last answer is older than maxAge. Until the new answer is there the old one stays.
Singleton {
    id: root

    readonly property bool enabled: Settings.get("weather.enabled") !== false
    readonly property string place: String(Settings.get("weather.place") || "").trim()
    readonly property string unit: Settings.get("weather.unit") === "f" ? "f" : "c"
    // The last good answer of scripts/weather.py (see there), null until the first one
    property var data: null
    // "" or why the last request failed: "offline", "unknown place", "no place", "bad answer"
    property string error: ""
    readonly property bool loading: proc.running
    property real fetchedMs: 0
    readonly property int maxAge: 15 * 60 * 1000
    // What the request in flight asked for; an answer to an older question is dropped
    property string asked: ""
    readonly property string question: place + "\n" + unit

    function refresh(force) {
        if (!enabled || proc.running)
            return ;

        if (!force && data !== null && error === "" && Date.now() - fetchedMs < maxAge)
            return ;

        asked = question;
        proc.command = [Qt.resolvedUrl("../scripts/weather.py").toString().replace("file://", ""), "--place", place, "--unit", unit];
        proc.running = true;
    }

    // The entry of one day ("yyyy-MM-dd") in the forecast, or null
    function dayFor(key) {
        const days = data ? data.days : [];
        for (let i = 0; i < days.length; i++) {
            if (days[i].date === key)
                return days[i];

        }
        return null;
    }

    // WMO weather code -> the symbol bar/WeatherGlyph draws
    function kindOf(code) {
        if (code === 0 || code === 1)
            return "clear";

        if (code === 2)
            return "partly";

        if (code === 3)
            return "cloud";

        if (code === 45 || code === 48)
            return "fog";

        if (code >= 51 && code <= 57)
            return "drizzle";

        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "snow";

        if (code >= 95)
            return "thunder";

        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82))
            return "rain";

        return "cloud";
    }

    function textOf(code) {
        const words = {
            "0": "Clear",
            "1": "Mostly clear",
            "2": "Partly cloudy",
            "3": "Overcast",
            "45": "Fog",
            "48": "Freezing fog",
            "51": "Light drizzle",
            "53": "Drizzle",
            "55": "Heavy drizzle",
            "56": "Freezing drizzle",
            "57": "Freezing drizzle",
            "61": "Light rain",
            "63": "Rain",
            "65": "Heavy rain",
            "66": "Freezing rain",
            "67": "Freezing rain",
            "71": "Light snow",
            "73": "Snow",
            "75": "Heavy snow",
            "77": "Snow grains",
            "80": "Light showers",
            "81": "Showers",
            "82": "Heavy showers",
            "85": "Snow showers",
            "86": "Heavy snow showers",
            "95": "Thunderstorm",
            "96": "Thunderstorm, hail",
            "99": "Thunderstorm, hail"
        };
        return words[String(code)] || "";
    }

    // Another place or unit: the old numbers no longer fit, so the next opening asks again
    onQuestionChanged: fetchedMs = 0

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.asked !== root.question) {
                    // The setting changed while the request ran: ask again for what it says now
                    Qt.callLater(root.refresh, true);
                    return ;
                }
                let answer = null;
                try {
                    answer = JSON.parse(text);
                } catch (e) {
                }
                if (answer && answer.ok) {
                    root.data = answer;
                    root.error = "";
                    root.fetchedMs = Date.now();
                } else {
                    root.error = answer && answer.error ? answer.error : "bad answer";
                    // A place that does not exist must not keep showing the weather of the one before
                    if (root.error === "unknown place")
                        root.data = null;

                }
            }
        }

    }

}
