import "../services"
import QtQuick
import Quickshell

// Foreground of the lock screen without the login: clock, vertical date, corners, media card,
// power buttons. Its own component, because TWO places show it: LockSurface (lock.qml) and the
// power menu (main shell). When locking from the menu the elements already fall in from the top in the menu
// while its tiles sink away; afterwards the lock screen takes over with the same image.
// So it must NOT access LockState (otherwise a PAM context would be created in the main shell).
Item {
    id: fg

    // Fade in (0 -> 1), fade out when unlocking (1 -> 0), awake = clock on top
    property real enter: 1
    property real fade: 1
    property real wake: 0
    // The main monitor (bar monitor, MachineConfig) shows everything; the others only the clock
    property bool primary: true
    property date now: new Date()
    readonly property real s: Math.min(width / 2560, height / 1440) * 0.5 + 0.5

    // Falling in from the top, staggered (clock first, then date, corners, media card): continues the movement
    // of the power menu tiles that sink away downward. d = delay as a share of enter.
    function drop(d) {
        return Math.max(0, Math.min(1, (enter - d) / (1 - d)));
    }

    // Date as kanji (11 -> 十一, 23 -> 二十三), for the vertical line at the edge
    function kanjiNumber(n) {
        const d = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"];
        if (n < 10)
            return d[n];

        const tens = Math.floor(n / 10), ones = n % 10;
        return (tens > 1 ? d[tens] : "") + "十" + d[ones];
    }

    function greeting(h) {
        if (h < 5)
            return "Still up";

        if (h < 12)
            return "Good morning";

        if (h < 18)
            return "Good afternoon";

        return "Good evening";
    }

    // Align the second tick to the real second boundary: menu and lock screen (two processes)
    // this way show the second line and the blinking colon the same at the same moment -> no jump
    // at the handover
    signal secondTick()

    Timer {
        id: tick

        interval: 1000 - (Date.now() % 1000)
        running: true
        onTriggered: {
            fg.now = new Date();
            interval = 1000 - (Date.now() % 1000);
            restart();
            fg.secondTick();
        }
    }

    // ---------- Vertical date (Japanese) at the right edge ----------
    Row {
        // Secondary monitors only show the clock (everything else only where the bar is: MachineConfig)
        visible: fg.primary
        anchors.right: parent.right
        anchors.rightMargin: 90 * fg.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 26 * fg.s
        opacity: fg.fade * fg.drop(0.08) * (1 - 0.4 * fg.wake)
        layoutDirection: Qt.RightToLeft

        transform: Translate {
            y: -(1 - fg.drop(0.08)) * 70 * fg.s
        }

        // Big line: month + day, like a stamp in the background
        Column {
            spacing: -6 * fg.s

            Repeater {
                model: (fg.kanjiNumber(fg.now.getMonth() + 1) + "月" + fg.kanjiNumber(fg.now.getDate()) + "日").split("")

                delegate: Text {
                    required property string modelData

                    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                    text: modelData
                    font.family: "Noto Serif CJK JP"
                    font.pixelSize: 84 * fg.s
                    font.weight: Font.Light
                    color: WalColors.withAlpha(WalColors.color7, 0.2)
                }

            }

        }

        // Small line: weekday in the accent color, flush at the top
        Column {
            spacing: 2 * fg.s

            Repeater {
                model: (["日", "月", "火", "水", "木", "金", "土"][fg.now.getDay()] + "曜日").split("")

                delegate: Text {
                    required property string modelData

                    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                    text: modelData
                    font.family: "Noto Serif CJK JP"
                    font.pixelSize: 26 * fg.s
                    color: WalColors.withAlpha(WalColors.color4, 0.75)
                }

            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 1
                height: 120 * fg.s
                color: WalColors.withAlpha(WalColors.color4, 0.35)
            }

        }

    }

    // ---------- Uhr ----------
    Column {
        id: clock

        readonly property var serifAxes: ({
            "opsz": 144,
            "WONK": 0,
            "SOFT": 60,
            "wght": 260
        })

        anchors.horizontalCenter: parent.horizontalCenter
        // Rest: optically centered; awake: up, smaller, so the orb has room
        y: (fg.height - height) / 2 - 30 * fg.s - fg.wake * (fg.height * 0.26) - (1 - fg.drop(0)) * 90 * fg.s - (1 - fg.fade) * 24 * fg.s
        scale: 1 - 0.32 * fg.wake
        transformOrigin: Item.Top
        opacity: fg.fade * fg.drop(0)
        spacing: 4 * fg.s

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // Greeting only on the main monitor, the others only show time and date
            visible: fg.primary
            text: fg.greeting(fg.now.getHours()) + ", " + (Quickshell.env("USER") || "")
            font.family: Theme.fontUi
            font.pixelSize: 20 * fg.s
            font.weight: Font.Medium
            font.letterSpacing: 0.6
            color: WalColors.color2
            opacity: 1 - fg.wake
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4 * fg.s

            Text {
                id: hours

                text: Qt.formatTime(fg.now, "HH")
                font.family: Theme.fontDisplay
                font.pixelSize: 230 * fg.s
                font.variableAxes: clock.serifAxes
                font.features: {
                    "tnum": 1,
                    "lnum": 1
                }
                color: WalColors.color7
            }

            // The colon breathes every second (as in the power menu)
            Text {
                id: colon

                anchors.baseline: hours.baseline
                text: ":"
                font.family: Theme.fontDisplay
                font.pixelSize: 230 * fg.s
                font.variableAxes: clock.serifAxes
                color: WalColors.color4

                // One breath per second, restarted at the second boundary (see tick): in the menu and
                // lock screen exactly in sync
                SequentialAnimation {
                    id: colonBlink

                    PauseAnimation {
                        duration: 450
                    }

                    NumberAnimation {
                        target: colon
                        property: "opacity"
                        to: 0.25
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }

                    PauseAnimation {
                        duration: 150
                    }

                    NumberAnimation {
                        target: colon
                        property: "opacity"
                        to: 1
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }

                }

                Connections {
                    function onSecondTick() {
                        colon.opacity = 1;
                        colonBlink.restart();
                    }

                    target: fg
                }

            }

            Text {
                anchors.baseline: hours.baseline
                text: Qt.formatTime(fg.now, "mm")
                font.family: Theme.fontDisplay
                font.pixelSize: 230 * fg.s
                font.variableAxes: clock.serifAxes
                font.features: {
                    "tnum": 1,
                    "lnum": 1
                }
                color: WalColors.color7
            }

        }

        // Seconds as a fine line below the clock
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * fg.s
            height: 2

            Rectangle {
                anchors.fill: parent
                radius: 1
                color: WalColors.withAlpha(WalColors.color7, 0.1)
            }

            Rectangle {
                width: parent.width * fg.now.getSeconds() / 59
                height: parent.height
                radius: 1
                color: WalColors.color4

                Behavior on width {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

        Item {
            width: 1
            height: 14 * fg.s
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(fg.now, "dddd, MMMM d").toUpperCase()
            font.family: Theme.fontUi
            font.pixelSize: 15 * fg.s
            font.weight: Font.Bold
            font.letterSpacing: 3.2
            color: WalColors.withAlpha(WalColors.color7, 0.55)
        }

    }

    // ---------- Corners ----------
    Row {
        // Secondary monitors only show the clock (everything else only where the bar is: MachineConfig)
        visible: fg.primary
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 40 * fg.s
        spacing: 10
        opacity: fg.fade * fg.drop(0.12) * 0.9

        transform: Translate {
            y: -(1 - fg.drop(0.12)) * 40 * fg.s
        }

        Rectangle {
            width: lockLabel.implicitWidth + 34
            height: Theme.px(28)
            radius: height / 2
            color: WalColors.withAlpha(WalColors.color0, 0.45)
            border.width: 1
            border.color: Theme.stroke

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11)
                    color: WalColors.color4
                }

                Text {
                    id: lockLabel

                    anchors.verticalCenter: parent.verticalCenter
                    text: "LOCKED"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.weight: Font.Bold
                    font.letterSpacing: Theme.microSpacing * 1.6
                    color: Theme.textDim
                }

            }

        }

    }

    LockMedia {
        visible: fg.primary && hasTrack
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Falls onto its place from a bit further up
        anchors.bottomMargin: 56 * fg.s + (1 - fg.drop(0.16)) * 70 * fg.s
        opacity: (hasTrack ? 1 : 0) * fg.fade * fg.drop(0.16)
        width: implicitWidth
        height: implicitHeight
    }

    LockPower {
        visible: fg.primary
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 40 * fg.s
        opacity: fg.fade * fg.drop(0.2) * (0.55 + 0.45 * fg.wake)

        transform: Translate {
            y: -(1 - fg.drop(0.2)) * 40 * fg.s
        }
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 46 * fg.s
        visible: fg.primary
        text: "ENTER  unlock     ESC  clear"
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeMicro
        font.weight: Font.Bold
        font.letterSpacing: Theme.microSpacing * 1.4
        color: Theme.textFaint
        opacity: fg.enter * fg.fade * fg.wake
    }

}
