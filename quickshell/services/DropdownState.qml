import QtQuick
import Quickshell
pragma Singleton

Singleton {
    id: root

    property string current: "" // "", "audio", "stats", "vpn", "claude", "battery", "screen", "sync"
    property real anchorX: 0 // icon center in screen coordinates
    property string hoveredIcon: ""
    property bool dropdownHovered: false
    property int closeDelay: 200
    // Pinned (pin in the header): the open dropdown stays even when the mouse leaves,
    // e.g. to keep an eye on usage or throughput. Other icons open nothing meanwhile.
    // Release: click the pin again; if the dropdown closes another way (dismiss, bar gone), it is released too.
    property bool pinned: false

    function enter(id, centerX) {
        hoveredIcon = id;
        if (pinned && id !== current)
            return ;

        closeTimer.stop();
        // When hovering back, the already open menu stays at its position.
        if (id === current)
            return;

        current = id; // page first, then X -> one single clean morph
        anchorX = centerX;
    }

    function leave(id) {
        if (hoveredIcon === id)
            hoveredIcon = "";

        updateCloseTimer();
    }

    function togglePin() {
        if (current === "")
            return ;

        pinned = !pinned;
        updateCloseTimer();
    }

    // Close right away although the mouse is still on the icon (e.g. a click opens something else).
    // It only opens again when the mouse leaves the icon and enters it again.
    function dismiss() {
        closeTimer.stop();
        current = "";
    }

    function updateCloseTimer() {
        if (pinned || hoveredIcon !== "" || dropdownHovered)
            closeTimer.stop();
        else
            closeTimer.restart();
    }

    onCurrentChanged: {
        if (current === "")
            pinned = false;

    }

    // Bar hidden: a pinned dropdown should not hang alone in the air
    Connections {
        function onBarVisibleChanged() {
            if (!BarState.barVisible)
                root.dismiss();

        }

        target: BarState
    }

    Timer {
        id: closeTimer

        interval: root.closeDelay
        onTriggered: {
            if (!root.pinned && root.hoveredIcon === "" && !root.dropdownHovered)
                root.current = "";

        }
    }

}
