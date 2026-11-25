import QtQuick
import Quickshell
pragma Singleton

Singleton {
    id: root

    // Survives reloads (otherwise the bar slides in on every config change)
    property alias barVisible: persist.barVisible
    // Density of the bar icons (spacing/padding), depends on the monitor width:
    // 1 at 2560px, narrower = tighter (set by MainBar)
    property real density: 1

    // Calendar open/close by shortcut (SUPER+K); the calendar itself belongs to the MainBar
    signal calendarToggleRequested()

    PersistentProperties {
        id: persist

        // Open at start (boot/restart of qs); across reloads the last state stays
        property bool barVisible: true

        reloadableId: "barState"
    }

}
