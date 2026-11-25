pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Keep awake: while it is on, the screen does not lock or switch off by itself (bar icon bar/ScreenToggle,
// dropdown dropdowns/ScreenContent). Works like a playing video: the shell holds an idle inhibitor, which
// hypridle respects. Locking by hand and locking before sleep still work.
// On for a set time or until it is turned off. It survives a reload of the shell, but not a restart:
// a forgotten "always" should not keep the screen unlocked for days.
Singleton {
    id: root

    // The feature is its bar icon: hidden means off
    readonly property bool enabled: BarIcons.shown("screen")
    // What was chosen, in minutes: 0 = off, -1 = until it is turned off
    readonly property int minutes: persist.minutes
    // End as milliseconds since 1970, only for a set time
    readonly property double until: persist.until
    property double clock: Date.now()
    readonly property bool active: enabled && (minutes === -1 || (minutes > 0 && until > clock))
    // Line for the dropdown
    readonly property string statusText: {
        if (!active)
            return "Off";

        return minutes === -1 ? "Until you turn it off" : "Until " + Qt.formatTime(new Date(until), "HH:mm");
    }

    // minutes: 0 = off, -1 = until turned off, otherwise for that long from now
    function set(minutes) {
        clock = Date.now();
        persist.minutes = minutes;
        persist.until = minutes > 0 ? clock + minutes * 60000 : 0;
    }

    function toggle() {
        set(active ? 0 : -1);
    }

    PersistentProperties {
        id: persist

        property int minutes: 0
        property double until: 0

        reloadableId: "keepAwake"
    }

    // The set time is over
    Timer {
        interval: 10000
        running: root.minutes > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.clock = Date.now();
            if (root.until <= root.clock)
                root.set(0);

        }
    }

    // An inhibitor belongs to a window. This one is a transparent pixel in a corner that takes no input
    // and only exists while keep awake is on.
    IdleInhibitor {
        enabled: root.active

        window: PanelWindow {
            visible: root.active
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:keep-awake"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                right: true
                bottom: true
            }

            mask: Region {
            }

        }

    }

}
