import "../common"
import "../services"
import QtQuick
import Quickshell

// Clock in the bar. A left click sends `clicked()`; MainBar then turns into the calendar.
Item {
    id: clockRoot

    signal clicked()

    // 0 = rest, 1 = hover. One single animated value drives all hover effects, so they run in sync
    property real hot: clockHover.hovered ? 1 : 0
    readonly property int sec: clock.seconds

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
    }

    // Fixed width = widest state: the bar must not shift on hover
    implicitWidth: Math.max(timeRow.implicitWidth + 4, dateText.implicitWidth, weekText.implicitWidth)
    implicitHeight: parent ? parent.height : 40

    // System clock instead of a 1 s timer: switches exactly at the minute change. Only the
    // pulsing colon on hover needs seconds, otherwise the clock ticks every minute.
    SystemClock {
        id: clock

        precision: clockHover.hovered ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Hover: the date rolls up and away like a departure board and weekday + week roll in,
    // the time grows slightly. A click squeezes everything briefly.
    Column {
        id: clockColumn

        anchors.centerIn: parent
        spacing: 0
        scale: clockTap.pressed ? 0.95 : 1

        // Everything in the grotesque: the serif looks too playful at bar size. Time SemiBold (bold was too heavy), AM/PM
        // small next to it. tnum, so the width does not jump at the minute change.
        // Hover: the time grows slightly upward, gets brighter, and the colon pulses every second
        // as in the calendar clock. Scaled as a layer texture (at double resolution, so it stays
        // sharp); at rest the layer is off, then the text renders normally pixel-exact.
        Row {
            id: timeRow

            readonly property color timeColor: Qt.tint(WalColors.color2, Qt.rgba(1, 1, 1, 0.3 * clockRoot.hot))

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3
            transformOrigin: Item.Bottom
            scale: 1 + 0.07 * clockRoot.hot
            layer.enabled: clockRoot.hot > 0.001
            layer.smooth: true
            layer.textureSize: Qt.size(width * 2, height * 2)

            Row {
                id: hhmmRow

                // So AM/PM sits on the time's baseline via anchors.baseline (Row has none otherwise)
                baselineOffset: hourText.baselineOffset

                Text {
                    id: hourText

                    text: Qt.formatDateTime(clock.date, "hh")
                    color: timeRow.timeColor
                    font: timeFont.font
                }

                Text {
                    anchors.baseline: hourText.baseline
                    text: ":"
                    color: timeRow.timeColor
                    // Only pulses on hover; at rest the colon stands still, so the bar stays calm
                    opacity: clockHover.hovered && clockRoot.sec % 2 === 1 ? 0.3 : 1
                    font: timeFont.font

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.InOutSine
                        }

                    }

                }

                Text {
                    id: minuteText

                    text: Qt.formatDateTime(clock.date, "mm")
                    anchors.baseline: hourText.baseline
                    color: timeRow.timeColor
                    font: timeFont.font
                }

            }

            Text {
                id: ampmText

                text: Qt.formatDateTime(clock.date, "AP")
                anchors.baseline: hhmmRow.baseline
                color: timeRow.timeColor
                opacity: 0.7 + 0.3 * clockRoot.hot
                font.family: Theme.fontUi
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1
            }

        }

        // Two lines on top of each other in a window one line high; on hover both slide up.
        // Moved by a translate on a layer texture: normal text snaps to whole pixels and
        // visibly stutters in 1 px steps on the short distance (~12 px), the texture glides with subpixel precision.
        Item {
            id: dateSlot

            anchors.horizontalCenter: parent.horizontalCenter
            width: clockRoot.implicitWidth
            height: dateText.implicitHeight
            clip: true

            Text {
                id: dateText

                text: Qt.formatDateTime(clock.date, "MMMM d, yyyy")
                anchors.horizontalCenter: parent.horizontalCenter
                color: WalColors.color2
                opacity: 0.7 * (1 - clockRoot.hot)
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                font.weight: Font.Medium
                font.letterSpacing: 0.3
                layer.enabled: true
                layer.smooth: true

                transform: Translate {
                    y: -dateSlot.height * clockRoot.hot
                }

            }

            Text {
                id: weekText

                text: Qt.formatDateTime(clock.date, "dddd") + "  \u00b7  W" + clockRoot.isoWeek(clock.date)
                anchors.horizontalCenter: parent.horizontalCenter
                color: WalColors.color2
                opacity: 0.9 * clockRoot.hot
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                font.weight: Font.Bold
                font.letterSpacing: 0.6
                layer.enabled: true
                layer.smooth: true

                transform: Translate {
                    y: dateSlot.height * (1 - clockRoot.hot)
                }

            }

        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.fast
            }

        }

    }

    // Shared font of the three time parts (hour, colon, minute)
    // wght explicitly, because the variable grotesque does not always pick up font.weight alone
    Text {
        id: timeFont

        visible: false
        font.family: Theme.fontUi
        font.pixelSize: 16
        font.weight: Font.DemiBold
        font.variableAxes: {
            "wght": 600
        }
        font.letterSpacing: -0.3
        font.features: {
            "tnum": 1
        }
    }

    HoverHandler {
        id: clockHover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: clockTap

        acceptedButtons: Qt.LeftButton
        onTapped: clockRoot.clicked()
    }

    // MD3 curves: in fast start and soft end, out calm. No overshoot,
    // on the short distance that felt more like a stutter than snapping in.
    Behavior on hot {
        Anim {
            duration: clockHover.hovered ? 420 : Appearance.anim.durations.normal
            easing.bezierCurve: clockHover.hovered ? Appearance.anim.curves.emphasizedDecelerate : Appearance.anim.curves.standard
        }

    }

}
