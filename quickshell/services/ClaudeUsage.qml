// Claude Code token usage (data from scripts/claude_usage.py).
// Read at start and then every few minutes; more often while the dropdown is open.

import QtQuick
import Quickshell
import Quickshell.Io
import "AiUsageFormat.js" as Format
pragma Singleton

Singleton {
    id: root

    property bool ok: false
    property bool loading: false
    property string error: ""
    property int updated: 0
    property int sessions: 0
    property var ranges: ({})
    property var days: []
    // Hidden bar icon (edit mode) = feature off: no polling at all
    readonly property bool featureOn: BarIcons.shown("claude") && AiUsageState.isInstalled("claude")
    readonly property bool active: featureOn && AiUsageState.selectedKey === "claude"
    readonly property bool dropdownOpen: active && DropdownState.current === "claude"
    readonly property string script: Qt.resolvedUrl("../scripts/claude_usage.py").toString().replace("file://", "")
    // ==== Plan limits (written by scripts/claude_statusline.sh as soon as Claude Code runs) ====
    readonly property string limitsFile: {
        let base = Quickshell.env("XDG_CACHE_HOME");
        if (!base)
            base = Quickshell.env("HOME") + "/.cache";

        return base + "/quickshell/claude-limits.json";
    }
    property real nowMs: Date.now()
    property real limitsUpdated: 0
    readonly property bool checkingLimits: limitsProc.running
    property bool limitFetchFailed: false
    property bool loginRequired: false
    property real nextLimitCheckMs: 0
    property bool accountSnapshot: false
    readonly property string limitStatus: !accountSnapshot ? "local snapshot" : (limitFetchFailed ? "cached" : "updated")
    property var fiveRaw: null
    property var weekRaw: null
    readonly property var five: Format.limitWindow(fiveRaw, nowMs, limitsUpdated)
    readonly property var week: Format.limitWindow(weekRaw, nowMs, limitsUpdated)
    readonly property bool hasLimits: five.known || week.known

    function applyLimits(raw) {
        try {
            const d = JSON.parse(raw && raw.length > 0 ? raw : "{}");
            const rl = d.rate_limits || {
            };
            limitsUpdated = d.updated || 0;
            accountSnapshot = d.source === "api";
            nowMs = Date.now();
            fiveRaw = rl.five_hour || null;
            weekRaw = rl.seven_day || null;
        } catch (e) {
            console.warn("ClaudeUsage: claude-limits.json invalid:", e);
        }
    }

    function refresh() {
        readLocal();
        fetchLimits();
    }

    function readLocal() {
        if (!proc.running)
            proc.running = true;
    }

    // Limits from the server (scripts/claude_limits.py) -> writes limitsFile, limitsView reads it again
    function fetchLimits() {
        nowMs = Date.now();
        if (limitsProc.running)
            return;
        if (nowMs < nextLimitCheckMs) {
            scheduleLimitRetry();
            return;
        }
        limitRetry.stop();
        nextLimitCheckMs = nowMs + 15000;
        limitsProc.running = true;
    }

    function scheduleLimitRetry() {
        if (!active)
            return;

        limitRetry.interval = Math.max(1, nextLimitCheckMs - Date.now());
        limitRetry.restart();

    }

    function range(key) {
        return ranges[key] || {
            "in": 0,
            "out": 0,
            "cw": 0,
            "cr": 0,
            "total": 0,
            "msgs": 0,
            "models": []
        };
    }

    onDropdownOpenChanged: {
        if (dropdownOpen)
            refresh();

    }
    onActiveChanged: {
        if (active)
            refresh();
        else
            limitRetry.stop();
    }
    // Shown again in edit mode: fetch right away instead of waiting for the next timer
    onFeatureOnChanged: {
        if (featureOn)
            refresh();

    }
    Component.onCompleted: refresh()

    FileView {
        id: limitsView

        path: root.limitsFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyLimits(text())
    }

    // Clock for the reset countdown (and to notice that a window has expired)
    Timer {
        interval: root.dropdownOpen ? 5000 : 30000
        running: root.featureOn
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    Timer {
        interval: root.dropdownOpen ? 15000 : 300000
        running: root.featureOn
        repeat: true
        onTriggered: root.readLocal()
    }

    Timer {
        interval: root.dropdownOpen ? 120000 : 300000
        running: root.active
        repeat: true
        onTriggered: root.fetchLimits()
    }

    Timer {
        id: limitRetry
        onTriggered: root.fetchLimits()
    }

    Process {
        id: limitsProc

        readonly property string script: Qt.resolvedUrl("../scripts/claude_limits.py").toString().replace("file://", "")

        command: ["python3", script]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.limitFetchFailed = !d.ok;
                    root.loginRequired = /not logged in|run \/login/.test(d.error || "");
                    if (!d.ok) {
                        const delay = Math.max(d.retryAfter || 0, d.error === "HTTP 429" ? 120 : 30);
                        root.nextLimitCheckMs = Date.now() + delay * 1000;
                        root.scheduleLimitRetry();
                        console.log("ClaudeUsage: limits not available:", d.error);
                    }

                } catch (e) {
                }
            }
        }

    }

    Process {
        id: proc

        command: ["python3", root.script]
        onRunningChanged: root.loading = running

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.ok = d.ok === true;
                    root.error = d.error || "";
                    if (root.ok) {
                        root.updated = d.updated;
                        root.sessions = d.sessions;
                        root.ranges = d.ranges;
                        root.days = d.days;
                    }
                } catch (e) {
                    root.ok = false;
                    root.error = "Invalid output";
                    console.warn("ClaudeUsage:", e, text);
                }
            }
        }

    }

}
