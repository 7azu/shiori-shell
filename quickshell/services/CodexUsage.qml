import QtQuick
import Quickshell
import Quickshell.Io
import "AiUsageFormat.js" as Format
pragma Singleton

Singleton {
    id: root

    // Hidden bar icon (edit mode) = feature off: no polling at all
    readonly property bool active: BarIcons.shown("claude") && AiUsageState.isInstalled("codex") && AiUsageState.selectedKey === "codex"
    readonly property bool dropdownOpen: active && DropdownState.current === "claude"
    property bool ready: false
    property var data: ({})
    property var accountLimits: ({})
    readonly property bool checkingLimits: limitsProc.running
    property bool accountLive: false
    property bool loginRequired: false
    property real nextLimitCheckMs: 0
    property int retryDelayMs: 10000
    property real nowMs: Date.now()
    readonly property var days: data.days || []
    readonly property var localLimits: data.limits || ({})
    readonly property bool accountWindowKnown: limitWindow(accountLimits.primary, nowMs, accountLimits.updated || 0).known
        || limitWindow(accountLimits.secondary, nowMs, accountLimits.updated || 0).known
    readonly property bool usingAccount: accountWindowKnown
        && (accountLive || (accountLimits.updated || 0) >= (localLimits.updated || 0))
    readonly property var limits: usingAccount ? accountLimits : localLimits
    readonly property real limitsUpdated: limits.updated || 0
    readonly property string limitStatus: !usingAccount ? "local snapshot" : (accountLive ? "account" : "cached")
    readonly property var five: limitWindow(limits.primary, nowMs, limitsUpdated)
    readonly property var week: limitWindow(limits.secondary, nowMs, limitsUpdated)
    readonly property bool hasLimits: five.known || week.known

    function limitWindow(window, now, updated) {
        return Format.limitWindow(window ? {
            used_percentage: window.used_percent,
            resets_at: window.resets_at
        } : null, now, updated);
    }

    function range(key) {
        return (data.ranges || {})[key] || { total: 0 };
    }

    function refresh() {
        readLocal();
        fetchLimits();
    }

    function readLocal() {
        nowMs = Date.now();
        if (!reader.running)
            reader.running = true;
    }

    function fetchLimits() {
        const now = Date.now();
        if (limitsProc.running)
            return;
        if (now < nextLimitCheckMs) {
            scheduleLimitRetry();
            return;
        }
        limitRetry.stop();
        nextLimitCheckMs = now + 1000;
        limitsProc.running = true;
    }

    function scheduleLimitRetry() {
        if (!active)
            return;

        limitRetry.interval = Math.max(1, nextLimitCheckMs - Date.now());
        limitRetry.restart();
    }

    function applyAccountLimits(limits) {
        if ((limits.updated || 0) > (accountLimits.updated || 0))
            accountLimits = limits;
    }

    onActiveChanged: {
        if (active)
            refresh();
        else
            limitRetry.stop();
    }
    onDropdownOpenChanged: {
        if (dropdownOpen)
            refresh();
    }
    Timer {
        interval: root.dropdownOpen ? 5000 : 30000
        running: root.active
        repeat: true
        onTriggered: root.readLocal()
    }

    Timer {
        interval: root.dropdownOpen ? 30000 : 300000
        running: root.active
        repeat: true
        onTriggered: root.fetchLimits()
    }

    Timer {
        id: limitRetry
        onTriggered: root.fetchLimits()
    }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/codex-limits.json"
        printErrors: false
        onLoaded: {
            try {
                root.applyAccountLimits(JSON.parse(text()));
            } catch (error) {
                console.warn("CodexUsage: Invalid limits cache", error);
            }
        }
    }

    Process {
        id: limitsProc
        command: ["python3", Qt.resolvedUrl("../scripts/codex_limits.py").toString().replace("file://", "")]

        stdout: StdioCollector {
            onStreamFinished: {
                let response;
                try {
                    response = JSON.parse(text);
                } catch (error) {
                    response = {ok: false, error: "Invalid limit response"};
                }
                root.nowMs = Date.now();
                root.loginRequired = response.error === "Codex account sign-in required";
                if (response.ok) {
                    root.applyAccountLimits(response.limits);
                    root.accountLive = true;
                    root.retryDelayMs = 10000;
                    limitRetry.stop();
                } else {
                    root.accountLive = false;
                    const delay = response.error === "Codex account rate limited"
                        ? 120000 : (root.loginRequired ? 60000 : root.retryDelayMs);
                    root.nextLimitCheckMs = root.nowMs + delay;
                    root.retryDelayMs = Math.min(60000, root.retryDelayMs * 2);
                    root.scheduleLimitRetry();
                    console.log("CodexUsage:", response.error);
                }
            }
        }
    }

    Process {
        id: reader
        command: ["python3", Qt.resolvedUrl("../scripts/codex_usage.py").toString().replace("file://", "")]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (text.trim())
                        root.data = JSON.parse(text);
                } catch (e) {
                    console.warn("CodexUsage: Invalid reader output", e);
                }
                root.ready = true;
            }
        }
    }
}
