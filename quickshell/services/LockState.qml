import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
pragma Singleton

// Logic of the lock screen (lock.qml, its own qs instance). All monitors share this state:
// typing only happens on the focused one, but dots, errors and unlocking are seen everywhere.
// Phases: "ambient" (only the clock, calm) -> "awake" (input visible) -> "checking" -> "unlocking".
Singleton {
    id: root

    // The password only lives in memory and is cleared after every attempt
    property string buffer: ""
    property string phase: "ambient"
    property bool capsLock: false
    property int failures: 0
    // Counts up on every failed attempt -> the surfaces play their shake on it
    property int failTick: 0
    // Last message from PAM (e.g. faillock: "account locked"), otherwise our own hint
    property string message: ""
    property bool messageIsError: false
    readonly property bool checking: phase === "checking"
    readonly property bool unlocking: phase === "unlocking"
    readonly property bool awake: phase !== "ambient"
    // Unlock animation (LockSurface): the foreground fades out in fadeMs, the background thaws to the
    // desktop after thawDelay in thawMs. lock.qml releases the session only after thawTotal.
    readonly property int fadeMs: 380
    readonly property int thawDelay: 60
    readonly property int thawMs: 900
    readonly property int thawTotal: thawDelay + thawMs + 50
    // Becomes true as soon as unlocking is done -> lock.qml releases the session
    signal unlocked()

    // Key pressed: wake up and restart the idle timer
    function poke() {
        if (unlocking)
            return ;

        if (phase === "ambient")
            phase = "awake";

        idleTimer.restart();
        capsProbe.running = true;
    }

    function type(text) {
        if (checking || unlocking)
            return ;

        // In the idle state the first key only wakes up (opens the input), it does not count toward the
        // password -> only the next input lands in the field
        if (phase === "ambient") {
            poke();
            return ;
        }
        poke();
        if (message !== "" && !messageIsError)
            message = "";

        buffer += text;
    }

    function backspace() {
        if (checking || unlocking)
            return ;

        poke();
        buffer = buffer.slice(0, -1);
    }

    function clear() {
        if (checking || unlocking)
            return ;

        if (buffer === "" && phase === "awake") {
            // Second Esc with an empty field: back to the idle state (like Esc in the pickers)
            phase = "ambient";
            return ;
        }
        poke();
        buffer = "";
    }

    function submit() {
        if (checking || unlocking)
            return ;

        poke();
        if (buffer === "")
            return ;

        phase = "checking";
        message = "";
        messageIsError = false;
        if (!pam.start()) {
            fail("Could not start authentication");
        }
    }

    function fail(msg) {
        failures += 1;
        failTick += 1;
        buffer = "";
        phase = "awake";
        message = msg;
        messageIsError = true;
        idleTimer.restart();
    }

    PamContext {
        id: pam

        // Own PAM file /etc/pam.d/quickshell-lock (auth include login) -> faillock applies as at
        // login. Created by install.sh (it belongs to no package).
        config: "quickshell-lock"
        onPamMessage: {
            if (responseRequired) {
                respond(root.buffer);
                return ;
            }
            // Pass on info/error texts from PAM (e.g. lockout after too many attempts)
            if (message !== "") {
                root.message = message;
                root.messageIsError = messageIsError;
            }
        }
        onCompleted: (result) => {
            if (result === PamResult.Success) {
                root.buffer = "";
                root.failures = 0;
                root.message = "";
                root.phase = "unlocking";
                root.unlocked();
                return ;
            }
            // Our own PAM error message (faillock) takes precedence over the general text
            const pamMsg = root.messageIsError && root.message !== "" ? root.message : "";
            root.fail(pamMsg !== "" ? pamMsg : (result === PamResult.MaxTries ? "Too many attempts" : "Wrong password"));
        }
        onError: (error) => {
            root.fail("Authentication error: " + PamError.toString(error));
        }
    }

    // 12 s nothing typed and the field empty -> back to the calm clock
    Timer {
        id: idleTimer

        interval: 12000
        onTriggered: {
            if (root.phase === "awake" && root.buffer === "") {
                root.phase = "ambient";
                root.message = "";
            } else if (root.phase === "awake") {
                restart();
            }
        }
    }

    // Caps Lock: Qt does not know the state, Hyprland does (any keyboard with capsLock)
    Process {
        id: capsProbe

        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.capsLock = (d.keyboards || []).some((k) => {
                        return k.capsLock;
                    });
                } catch (e) {
                }
            }
        }

    }

}
