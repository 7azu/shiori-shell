import QtQuick
import Quickshell

// Probe for monitor-order.sh: prints the monitor Qt sees first (the one whose refresh rate drives all
// Qt animations) and quits.
ShellRoot {
    Component.onCompleted: {
        console.log("FIRST_SCREEN " + (Qt.application.screens.length > 0 ? Qt.application.screens[0].name : ""));
        Qt.quit();
    }
}
