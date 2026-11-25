pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Night light: warmer screen colors in the evening (bar icon bar/ScreenToggle, dropdown dropdowns/ScreenContent).
// The colors are changed by hyprsunset (a small daemon of the Hyprland project); this service decides how
// warm the screen should be right now and tells it through `hyprctl hyprsunset`.
//
// Settings (settings.json, "night"):
//   mode         "off" | "auto" | "on"   auto follows the schedule
//   schedule     "sun" (sunset to sunrise at your place) | "custom" (from/until)
//   from, until  "20:00", "07:00"        the custom times; also used when the sun times are unknown
//   temperature  4000                    color temperature in Kelvin at full warmth, lower = warmer
//
// level is the warmth from 0 (untouched colors) to 1 (temperature). In auto mode it rises over
// rampMinutes after the start and falls over rampMinutes before the end, so the change is not seen.
// hyprsunset is only started once the screen has to turn warm.
//
// Every color change stalls Hyprland for about 40 ms (measured with three monitors: it waits for each of
// them), so the whole desktop stutters when many follow each other. That is why there is no fade when
// switching by hand (one change), the ramp moves in steps of rampStep Kelvin (one change every few
// minutes), and the slider and the mouse wheel only change the color once they rest (applyDelay).
Singleton {
    id: root

    // The feature is its bar icon: hidden (edit mode, settings) means off and neutral colors
    readonly property bool enabled: BarIcons.shown("screen")
    // hyprsunset is installed
    property bool available: false
    readonly property string mode: {
        const m = Settings.get("night.mode");
        return m === "auto" || m === "on" ? m : "off";
    }
    readonly property string schedule: Settings.get("night.schedule") === "custom" ? "custom" : "sun"
    readonly property int minTemperature: 2000
    readonly property int maxTemperature: 6000
    // Colors of an untouched screen in hyprsunset's scale; the fade starts here
    readonly property int neutral: 6500
    readonly property int rampMinutes: 30
    // Kelvin between two changes while the schedule ramps
    readonly property int rampStep: 200
    // The slider has to rest this long before the color follows
    readonly property int applyDelay: 140
    readonly property int savedTemperature: clampK(Number(Settings.get("night.temperature")) || 4000)
    // While the slider is dragged: the value under the mouse (0 = none), shown at full warmth
    property int draftTemperature: 0
    readonly property int temperature: draftTemperature > 0 ? draftTemperature : savedTemperature
    // {lat, lon, source} from scripts/tz_location.py; lat null = unknown
    property var place: null
    readonly property bool hasPlace: place !== null && typeof place.lat === "number" && typeof place.lon === "number"
    property date now: new Date()
    // Changes once a day: the sun times are only computed then
    readonly property string day: Qt.formatDate(now, "yyyy-MM-dd")
    readonly property real minuteOfDay: now.getHours() * 60 + now.getMinutes() + now.getSeconds() / 60
    // Today's warm time in minutes after midnight. sun = taken from sunset and sunrise.
    readonly property var span: {
        const custom = {
            "from": clockMinutes(Settings.get("night.from"), 20 * 60),
            "until": clockMinutes(Settings.get("night.until"), 7 * 60),
            "sun": false
        };
        if (schedule !== "sun" || !hasPlace || day === "")
            return custom;

        const s = sunTimes(now, place.lat, place.lon);
        // No sunset or sunrise today (far north or south): the custom times
        return s ? {
            "from": s.set,
            "until": s.rise,
            "sun": true
        } : custom;
    }
    readonly property real autoLevel: levelAt(minuteOfDay, span.from, span.until)
    readonly property real target: {
        if (!enabled || !available)
            return 0;

        if (draftTemperature > 0)
            return 1;

        return mode === "on" ? 1 : (mode === "auto" ? autoLevel : 0);
    }
    readonly property real level: target
    // Both lookups at the start are done (is hyprsunset there, where are we). Before that nothing is sent.
    property bool probed: false
    property bool placed: false
    readonly property bool ready: probed && placed
    readonly property bool warm: target > 0.001
    // Full warmth is the chosen temperature exactly; on the way there in steps of rampStep
    readonly property int kelvin: level >= 0.999 ? temperature : Math.round((neutral + (temperature - neutral) * level) / rampStep) * rampStep
    // Request for hyprsunset: "identity" = no change at all, otherwise "temperature <K>"
    readonly property string wanted: level <= 0.001 || kelvin >= neutral ? "identity" : "temperature " + kelvin
    property string sent: ""
    property string sending: ""
    property int failures: 0
    // hyprsunset was just started and does not answer yet. Until it does, only "identity" is asked
    // (changes nothing); the color follows with the first answer.
    property bool waking: false
    // hyprsunset did not answer although it should be running
    readonly property bool failed: failures >= 6
    // Line for the dropdown
    readonly property string statusText: {
        if (!available)
            return "hyprsunset is not installed";

        if (failed)
            return "hyprsunset does not answer";

        if (mode === "on")
            return "Always on";

        if (mode === "off")
            return "Off";

        if (autoLevel > 0)
            return (span.sun ? "Until sunrise, " : "Until ") + clockText(span.until);

        return (span.sun ? "From sunset, " : "From ") + clockText(span.from);
    }

    function clampK(k) {
        return Math.max(minTemperature, Math.min(maxTemperature, Math.round(k / 100) * 100));
    }

    // "20:30" -> 1230; anything else gives fallback
    function clockMinutes(text, fallback) {
        const m = /^\s*(\d{1,2})[:.](\d{2})\s*$/.exec(String(text || ""));
        if (!m || Number(m[1]) > 23 || Number(m[2]) > 59)
            return fallback;

        return Number(m[1]) * 60 + Number(m[2]);
    }

    function clockText(minutes) {
        const m = ((Math.round(minutes) % 1440) + 1440) % 1440;
        const h = Math.floor(m / 60);
        const r = m % 60;
        return (h < 10 ? "0" : "") + h + ":" + (r < 10 ? "0" : "") + r;
    }

    // Warmth at minute m for a warm time from..until (may run over midnight)
    function levelAt(m, from, until) {
        const length = (until - from + 1440) % 1440;
        const since = (m - from + 1440) % 1440;
        if (length <= 0 || since >= length)
            return 0;

        return Math.max(0, Math.min(1, since / rampMinutes, (length - since) / rampMinutes));
    }

    // Sunrise and sunset of the date's day in minutes after local midnight (NOAA's short formula,
    // good to a few minutes). null where the sun does not rise or set that day.
    function sunTimes(date, lat, lon) {
        const rad = Math.PI / 180;
        const start = new Date(date.getFullYear(), 0, 0);
        const dayOfYear = Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - start) / 8.64e+07);
        const g = 2 * Math.PI / 365 * (dayOfYear - 1);
        const eq = 229.18 * (7.5e-05 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
        const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g) + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
        // 90.833: the sun's upper edge at the horizon, with the bending of light in the air
        const cosH = Math.cos(90.833 * rad) / (Math.cos(lat * rad) * Math.cos(decl)) - Math.tan(lat * rad) * Math.tan(decl);
        if (cosH < -1 || cosH > 1)
            return null;

        const h = Math.acos(cosH) / rad;
        const offset = -date.getTimezoneOffset();
        const wrap = (v) => {
            return ((v % 1440) + 1440) % 1440;
        };
        return {
            "rise": wrap(720 - 4 * (lon + h) - eq + offset),
            "set": wrap(720 - 4 * (lon - h) - eq + offset)
        };
    }

    function setMode(m) {
        failures = 0;
        Settings.set("night.mode", m === "auto" || m === "on" ? m : "off");
        if (m !== "off")
            persist.lastMode = m;

    }

    // Bar icon and shortcut: off, or back to what it was before (auto unless it was "on")
    function toggle() {
        setMode(mode === "off" ? persist.lastMode : "off");
    }

    function setTemperature(k) {
        Settings.set("night.temperature", clampK(k));
    }

    // Mouse wheel: change the temperature by delta Kelvin. Shown at once, saved when the wheel rests
    // (every save makes the whole shell read its settings again).
    function nudge(delta) {
        draftTemperature = clampK((draftTemperature > 0 ? draftTemperature : savedTemperature) + delta);
        commitTimer.restart();
    }

    // Keep the value under the mouse or wheel and end the preview
    function commitDraft() {
        commitTimer.stop();
        if (draftTemperature <= 0)
            return ;

        setTemperature(draftTemperature);
        draftTemperature = 0;
    }

    // Send what is wanted, one request at a time; the newest value wins
    function push() {
        if (!ready || !available || applyProc.running || retry.running || (wanted === sent && !waking))
            return ;

        sending = waking ? "identity" : wanted;
        applyProc.command = ["hyprctl", "hyprsunset"].concat(sending.split(" "));
        applyProc.running = true;
    }

    onWantedChanged: {
        // While the slider or wheel moves, wait until it rests
        if (draftTemperature > 0)
            applyTimer.restart();
        else
            push();
    }
    onModeChanged: now = new Date()
    onReadyChanged: push()

    Timer {
        id: applyTimer

        interval: root.applyDelay
        onTriggered: root.push()
    }

    Timer {
        id: commitTimer

        interval: 700
        onTriggered: root.commitDraft()
    }

    PersistentProperties {
        id: persist

        property string lastMode: "auto"

        reloadableId: "nightLight"
    }

    // The schedule only needs the time now and then
    Timer {
        interval: 30000
        running: root.enabled && root.available && root.mode === "auto"
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    Process {
        id: applyProc

        onExited: (code) => {
            if (code === 0) {
                root.sent = root.sending;
                root.failures = 0;
                // It answers now: the color comes with the next request
                root.waking = false;
            } else if (root.sending === "identity" && !root.waking) {
                // hyprsunset is not running, so nothing is tinted: that is what was asked for
                root.sent = "identity";
                root.failures = 0;
            } else {
                // Not running: start it without a tint and ask until it answers
                root.failures++;
                if (root.failures === 1) {
                    root.waking = true;
                    Quickshell.execDetached(["sh", "-c", "pidof -q hyprsunset || exec hyprsunset --identity"]);
                }
                if (root.failed)
                    root.waking = false;
                else
                    retry.restart();
                return ;
            }
            // A Process does not start again from its own onExited
            Qt.callLater(root.push);
        }
    }

    Timer {
        id: retry

        interval: 500
        onTriggered: root.push()
    }

    Process {
        id: probe

        running: true
        command: ["sh", "-c", "command -v hyprsunset >/dev/null"]
        onExited: (code) => {
            root.available = code === 0;
            root.probed = true;
        }
    }

    Process {
        id: placeProc

        running: true
        command: [Qt.resolvedUrl("../scripts/tz_location.py").toString().replace("file://", "")]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.place = JSON.parse(text);
                } catch (e) {
                    root.place = null;
                }
                root.placed = true;
            }
        }

    }

}
