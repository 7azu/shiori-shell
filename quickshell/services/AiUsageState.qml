import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    // Every provider delivers the same display model via usage().
    readonly property var providers: [{
        key: "claude",
        label: "Claude",
        title: "Claude Code",
        glyph: "󰚩",
        icon: Qt.resolvedUrl("../common/ClaudeLogo.qml"),
        hoverRotation: 45,
        scope: "Claude Code only",
        emptyMessage: "Send a message in Claude Code to load your limits.",
        usage: () => ClaudeUsage
    }, {
        key: "codex",
        label: "Codex",
        title: "ChatGPT · Codex",
        glyph: "󰆍",
        icon: Qt.resolvedUrl("../common/CodexLogo.qml"),
        hoverRotation: 25,
        scope: "Codex sessions only",
        emptyMessage: "Run a Codex turn to refresh the limits from your local sessions.",
        usage: () => CodexUsage
    }]
    // Installed CLIs ({claude: bool, codex: bool}), checked at start and whenever the dropdown opens.
    // Until the first check every provider counts as installed, so nothing flickers away at start.
    property var installed: ({})
    property bool detected: false
    readonly property var availableProviders: providers.filter((entry) => !detected || installed[entry.key] === true)
    readonly property bool hasProviders: availableProviders.length > 0
    function isInstalled(key) {
        return !detected || installed[key] === true;
    }

    property string savedKey: selection.value("provider", providers[0].key)
    // Falls back to an installed provider; with none installed the first one only keeps the bar icon drawable
    readonly property var provider: availableProviders.find((entry) => entry.key === savedKey) || availableProviders[0] || providers[0]
    readonly property string selectedKey: provider.key
    property var pendingProvider: null

    function saveSelection(key) {
        savedKey = key;
        selection.setValue("provider", key);
        selection.sync();
    }

    function select(key) {
        const next = providers.find((entry) => entry.key === key);
        if (!next)
            return;
        pendingProvider = null;
        if (key === selectedKey)
            return;
        const usage = next.usage();
        if (usage.ready === false) {
            pendingProvider = next;
            usage.refresh();
        } else {
            saveSelection(key);
        }
    }

    Connections {
        target: root.pendingProvider ? root.pendingProvider.usage() : null

        function onReadyChanged() {
            if (target.ready) {
                const key = root.pendingProvider.key;
                root.pendingProvider = null;
                root.saveSelection(key);
            }
        }
    }
    Component.onCompleted: detect()

    function detect() {
        if (!detectProc.running)
            detectProc.running = true;
    }

    // Check again when the dropdown opens: a CLI installed or removed meanwhile shows up right away
    Connections {
        target: DropdownState

        function onCurrentChanged() {
            if (DropdownState.current === "claude")
                root.detect();
        }
    }

    // Quickshell inherits Hyprland's PATH, not the shell's: also look in the usual user install places
    Process {
        id: detectProc

        command: ["sh", "-c", 'PATH="$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.bun/bin:$HOME/.claude/local:$HOME/.volta/bin"; '
            + 'for c in claude codex; do if command -v "$c" >/dev/null 2>&1; then echo "$c 1"; else echo "$c 0"; fi; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.trim().split("\n")) {
                    const parts = line.trim().split(" ");
                    if (parts.length === 2)
                        found[parts[0]] = parts[1] === "1";
                }
                const wasDetected = root.detected;
                root.installed = found;
                root.detected = true;
                if (!wasDetected && found.codex)
                    CodexUsage.refresh();
            }
        }
    }

    Settings {
        id: selection

        location: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/quickshell/ai-usage.ini"
    }
}
