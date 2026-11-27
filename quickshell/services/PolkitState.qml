pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit

// Password prompt of the shell (polkit agent): when an app asks for administrator rights (pkexec,
// GParted, mounting a disk ...), windows/PolkitDialog shows the question in the look of the shell
// instead of hyprpolkitagent's own window.
//
// Only one agent can answer in a session, so the shell first hands hyprpolkitagent over to a small
// watcher (scripts/polkit_agent.sh takeover) and registers afterwards. When the shell ends, the
// watcher starts hyprpolkitagent again. Setting "polkit.ownDialog" false = hyprpolkitagent answers.
//
// The flow of one request (AuthFlow of Quickshell.Services.Polkit): message, inputPrompt,
// responseVisible (echo the input or not), supplementaryMessage, submit(), cancelAuthenticationRequest(),
// signals authenticationSucceeded / authenticationFailed.
Singleton {
    id: root

    readonly property bool enabled: Settings.get("polkit.ownDialog") !== false
    // The handover is done and the agent may register
    property bool handedOver: false
    readonly property var agent: agentLoader.item
    readonly property bool registered: !!agent && agent.isRegistered
    readonly property var flow: agent ? agent.flow : null
    // A request is being shown; stays true a moment after success, for the confirmation
    readonly property bool showing: (flow !== null && !flow.isCompleted) || holdTimer.running
    // Waiting for polkit's answer after the password was sent
    property bool checking: false
    // Wrong password: counts up, so the dialog can shake on every failure
    property int failures: 0
    property bool succeeded: false
    property int registerTries: 0

    function submit(text) {
        if (!flow || checking || !flow.isResponseRequired)
            return ;

        checking = true;
        flow.submit(text);
    }

    function cancel() {
        if (flow && !flow.isCompleted)
            flow.cancelAuthenticationRequest();

    }

    onEnabledChanged: {
        if (enabled) {
            takeover.running = true;
        } else {
            handedOver = false;
            release.running = true;
        }
    }
    Component.onCompleted: {
        if (enabled)
            takeover.running = true;

    }

    // A new request starts fresh
    onFlowChanged: {
        checking = false;
        if (flow) {
            succeeded = false;
            failures = 0;
        }
    }

    Process {
        id: takeover

        command: [Qt.resolvedUrl("../scripts/polkit_agent.sh").toString().replace("file://", ""), "takeover"]
        onExited: {
            root.registerTries = 0;
            root.handedOver = true;
        }
    }

    Process {
        id: release

        command: [Qt.resolvedUrl("../scripts/polkit_agent.sh").toString().replace("file://", ""), "release"]
    }

    LazyLoader {
        id: agentLoader

        active: root.enabled && root.handedOver

        PolkitAgent {
        }

    }

    // The old agent may need a moment to let go: if registering fails, try again a few times
    Timer {
        interval: 1500
        running: root.enabled && root.handedOver && !!root.agent && !root.agent.isRegistered && root.registerTries < 5
        onTriggered: {
            root.registerTries++;
            agentLoader.active = false;
            agentLoader.active = Qt.binding(() => {
                return root.enabled && root.handedOver;
            });
        }
    }

    Connections {
        function onAuthenticationFailed() {
            root.checking = false;
            root.failures++;
        }

        function onAuthenticationSucceeded() {
            root.checking = false;
            root.succeeded = true;
            holdTimer.restart();
        }

        function onIsResponseRequiredChanged() {
            // A new question (after a wrong password polkit asks again)
            if (root.flow && root.flow.isResponseRequired)
                root.checking = false;

        }

        target: root.flow
        ignoreUnknownSignals: true
    }

    // Keeps the dialog on screen for the confirmation after a correct password
    Timer {
        id: holdTimer

        interval: 1100
    }

    IpcHandler {
        // qs ipc call polkit state -> registered / waiting / off
        function state(): string {
            if (!root.enabled)
                return "off";

            return root.registered ? "registered" : "waiting";
        }

        target: "polkit"
    }

}
