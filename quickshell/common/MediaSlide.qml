import "../services"
import QtQuick

// On a switch, pushes the old image out and the new one in. Of the old content only the
// snapshot is left then, because the real content switches to the new file right away. The new one only comes when
// the owner calls reveal(): this way no empty surface ever stays, even with slowly loading files.
Item {
    id: root

    // The real content; must lie centered in this area
    required property Item source
    // For the content: offset and opacity of the incoming image
    readonly property bool active: phase !== "idle"
    readonly property bool incoming: phase === "waiting" || phase === "sliding"
    readonly property real contentOffset: incoming ? direction * distance * (1 - t) : 0
    readonly property real contentOpacity: incoming ? t : 1
    // Safety net in case the new file never reports: the window must not freeze
    property int revealTimeout: 1000
    property string phase: "idle" // idle -> capturing -> waiting -> sliding -> idle
    property int direction: 1
    property real t: 0
    property var pending: []
    readonly property real distance: width

    // Start the switch: action swaps the file and only runs when the snapshot stands
    function begin(dir, action) {
        direction = dir;
        if (phase === "capturing") {
            pending = pending.concat([action]);
            return ;
        }
        // The image is not there yet: the snapshot keeps showing the last visible one
        if (phase === "waiting") {
            revealGuard.restart();
            action();
            return ;
        }
        // During a running slide: end the previous one and continue from the new state
        run.stop();
        t = 0;
        pending = [action];
        phase = "capturing";
        snapshot.width = source.width;
        snapshot.height = source.height;
        snapshot.sourceItem = source;
        snapshot.scheduleUpdate();
        captureGuard.restart();
    }

    function captured() {
        if (phase !== "capturing")
            return ;

        captureGuard.stop();
        // Before the actions: an image from the cache may already be done meanwhile
        phase = "waiting";
        revealGuard.restart();
        const actions = pending;
        pending = [];
        for (const action of actions)
            action();
    }

    function reveal() {
        if (phase !== "waiting")
            return ;

        revealGuard.stop();
        phase = "sliding";
        run.restart();
    }

    // Cancel the switch, for example because the window closes or the deletion fails
    function cancel() {
        run.stop();
        captureGuard.stop();
        revealGuard.stop();
        pending = [];
        finish();
    }

    function finish() {
        phase = "idle";
        t = 0;
        // Otherwise the source holds a window-sized texture that nobody sees anymore
        snapshot.sourceItem = null;
    }

    ShaderEffectSource {
        id: snapshot

        x: (root.width - width) / 2 - root.direction * root.distance * root.t
        y: (root.height - height) / 2
        visible: root.active
        opacity: 1 - root.t
        live: false
        smooth: true
        onScheduledUpdateCompleted: root.captured()
    }

    Anim {
        id: run

        target: root
        property: "t"
        from: 0
        to: 1
        onFinished: root.finish()
    }

    Timer {
        id: captureGuard

        interval: 100
        onTriggered: root.captured()
    }

    Timer {
        id: revealGuard

        interval: root.revealTimeout
        onTriggered: root.reveal()
    }

}
