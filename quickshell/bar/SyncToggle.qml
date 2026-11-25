import "../services"
import QtQuick

// Bar icon for the sync entries from the settings (services/SyncState.qml):
// Hover opens the dropdown (dropdowns/SyncContent.qml), a click syncs.
// The symbol shows the state (spins during the sync, check mark after success, warning on error, key = an
// entry needs input such as a 2FA code, offline, lock = SSH key locked), next to it the number of changes not uploaded yet
// (like the percentage at the Claude icon).
// Performance (an earlier version stuttered on a laptop): the rotation jumps in 30° steps
// instead of making the bar redraw permanently at 60 fps.
BarIcon {
    id: root

    readonly property bool failed: SyncState.failedEntry !== null
    readonly property bool offline: SyncState.offlineEntry !== null
    readonly property bool syncing: SyncState.running
    readonly property bool locked: SyncState.locked
    // An entry waits for input (e.g. a 2FA code): the field is in the dropdown
    readonly property bool needsInput: SyncState.inputEntry !== null
    // Shortly after a successful sync
    property bool flash: false
    readonly property int pending: SyncState.pending
    readonly property bool showCount: pending > 0 && !syncing && !failed
    readonly property int iconSize: 18
    readonly property int labelGap: 5
    readonly property int switchDuration: 320
    readonly property color stateColor: {
        if (syncing)
            return WalColors.color4;

        if (failed)
            return Theme.bad;

        if (flash)
            return Theme.good;

        if (needsInput || offline)
            return Theme.warn;

        // Locked is not an error: lock in the normal bar color
        return WalColors.color2;
    }
    // Nerd Font Material: sync, check, alert, key, wifi-off, lock (during the sync always the sync icon)
    readonly property string glyph: String.fromCodePoint(syncing ? 0xf04e6 : (failed ? 0xf0026 : (flash ? 0xf012c : (needsInput ? 0xf030b : (offline ? 0xf05aa : (locked ? 0xf033e : 0xf04e6))))))

    // With a number like the Claude icon (tighter, pill a bit wider), without like the other icons
    padding: showCount ? 8 : 16
    pillExtra: showCount ? 10 : 0
    contentWidth: content.width
    onClicked: SyncState.sync()

    TextMetrics {
        id: countMetrics

        font.family: Theme.font
        font.pixelSize: 12
        font.bold: true
        text: root.pending > 99 ? "99+" : String(root.pending)
    }

    Item {
        id: content

        anchors.centerIn: parent
        width: root.iconSize + (root.showCount ? root.labelGap + Math.ceil(countMetrics.advanceWidth) : 0)
        height: root.iconSize

        BarGlyph {
            id: glyphText

            width: root.iconSize
            height: root.iconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.glyph
            color: root.stateColor
            // Hover like all bar icons, success: a short pulse
            hot: root.hovered || root.flash

            // Spins while the sync runs; afterwards back to the next whole turn.
            Timer {
                id: spin

                running: root.syncing
                interval: 75
                repeat: true
                onTriggered: glyphText.rotation = (glyphText.rotation + 30) % 360
                onRunningChanged: {
                    if (!running)
                        settle.restart();

                }
            }

            RotationAnimator {
                id: settle

                target: glyphText
                to: 360
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
                onFinished: glyphText.rotation = 0
            }

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }

            }

        }

        Text {
            x: root.iconSize + root.labelGap
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.showCount ? 1 : 0
            visible: opacity > 0
            text: countMetrics.text
            color: WalColors.color2
            font: countMetrics.font

            Behavior on opacity {
                NumberAnimation {
                    duration: root.switchDuration
                    easing.type: Easing.InOutCubic
                }

            }

        }

        Behavior on width {
            NumberAnimation {
                duration: root.switchDuration
                easing.type: Easing.InOutCubic
            }

        }

    }

    Behavior on padding {
        NumberAnimation {
            duration: root.switchDuration
            easing.type: Easing.InOutCubic
        }

    }

    // Let success light up green briefly
    Connections {
        function onFinished(id) {
            root.flash = true;
            flashTimer.restart();
        }

        target: SyncState
    }

    Timer {
        id: flashTimer

        interval: 1400
        onTriggered: root.flash = false
    }

}
