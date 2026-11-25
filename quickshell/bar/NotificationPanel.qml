import "../common"
import "../services"
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets

// Content of the notification center that the whole bar morphs into (like calendar/monitors).
// On top: profile + session, below it the day line, then the notifications.
// Profile picture: ~/.face, otherwise common/DefaultAvatar in the pywal colors (see NotificationState.avatar)
Item {
    id: panel

    // true as soon as the content becomes visible -> sections fade in one after another
    property bool shown: false
    property real maxListH: 460
    // For choosing the profile picture: yazi is placed centered below the center
    property string screenName: ""
    property real bottomY: 0
    property int introRun: 0
    // Clear all: cards fly out staggered, afterwards they are really deleted
    property bool clearing: false

    function clearAll() {
        if (clearing || NotificationState.count === 0)
            return ;

        clearing = true;
        clearTimer.interval = Math.min(NotificationState.count, 8) * 45 + 260;
        clearTimer.restart();
    }

    // Deliberately without its own animation: the sections animate their height themselves, the edge sticks
    // to them and morphs along as a unit. A second Behavior here would restart on every frame
    // and first stand still and then fall behind.
    implicitHeight: col.implicitHeight
    // Height with a full list (maxListH): the MainBar sizes its surface once by it instead of
    // growing it anew with every new/swiped notification (every resize made the morph stutter).
    // The rest of the column is fixed, so the value stays the same while the list animates.
    readonly property real maxHeight: implicitHeight - listBox.height + Math.max(maxListH, emptyState.height)
    onShownChanged: {
        if (shown)
            introRun++;

    }

    Timer {
        id: clearTimer

        onTriggered: {
            NotificationState.clearAll();
            panel.clearing = false;
        }
    }

    Column {
        id: col

        width: parent.width
        spacing: 14

        // ---------- Profile + session ----------
        Reveal {
            delay: 0

            Item {
                width: parent.width
                height: 60

                Item {
                    id: avatar

                    width: 60
                    height: 60

                    // Quiet ring + circling arc
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 1.5
                        border.color: WalColors.withAlpha(WalColors.color7, 0.08)
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: WalColors.color4
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: 30
                                centerY: 30
                                radiusX: 29
                                radiusY: 29
                                startAngle: 0
                                sweepAngle: 80
                            }

                        }

                        NumberAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 7000
                            loops: Animation.Infinite
                            running: panel.shown
                        }

                    }

                    ClippingRectangle {
                        anchors.centerIn: parent
                        width: 50
                        height: 50
                        radius: height / 2
                        color: WalColors.withAlpha(WalColors.color4, 0.18)

                        Image {
                            id: faceImg

                            anchors.fill: parent
                            source: NotificationState.avatar
                            sourceSize.width: 100
                            sourceSize.height: 100
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        // No ~/.face (or not loaded yet): silhouette in the pywal colors
                        DefaultAvatar {
                            anchors.fill: parent
                            visible: faceImg.status !== Image.Ready
                        }

                        // Hover: darkened with a pen -> a click chooses a new profile picture (yazi)
                        Rectangle {
                            anchors.fill: parent
                            color: WalColors.withAlpha(WalColors.color0, 0.55)
                            opacity: faceMouse.containsMouse ? 1 : 0

                            Text {
                                anchors.centerIn: parent
                                text: "󰏫"
                                color: WalColors.color7
                                font.family: Theme.font
                                font.pixelSize: 20
                                scale: faceMouse.pressed ? 0.85 : 1

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 120
                                        easing.type: Easing.OutCubic
                                    }

                                }

                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.anim.durations.fast
                                }

                            }

                        }

                        MouseArea {
                            id: faceMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationState.changeAvatar(panel.screenName, panel.bottomY + 20)
                        }

                    }

                    // Online dot with a pulse
                    Item {
                        x: 44
                        y: 44
                        width: 12
                        height: 12

                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: height / 2
                            color: WalColors.color2

                            SequentialAnimation on scale {
                                running: panel.shown
                                loops: Animation.Infinite

                                NumberAnimation {
                                    from: 1
                                    to: 2.4
                                    duration: 1600
                                    easing.type: Easing.OutCubic
                                }

                                PauseAnimation {
                                    duration: 400
                                }

                            }

                            SequentialAnimation on opacity {
                                running: panel.shown
                                loops: Animation.Infinite

                                NumberAnimation {
                                    from: 0.5
                                    to: 0
                                    duration: 1600
                                    easing.type: Easing.OutCubic
                                }

                                PauseAnimation {
                                    duration: 400
                                }

                            }

                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: height / 2
                            color: WalColors.color2
                            border.width: 2
                            border.color: WalColors.color0
                        }

                    }

                }

                Column {
                    anchors.left: avatar.right
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: NotificationState.user
                        color: WalColors.color7
                        font.family: Theme.fontUi
                        font.pixelSize: 18
                        font.bold: true
                    }

                    Text {
                        text: "@" + NotificationState.host
                        color: WalColors.withAlpha(WalColors.color7, 0.45)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                    }

                }

                // Session duration big on the right
                Column {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        anchors.right: parent.right
                        text: NotificationState.sessionStartMs > 0 ? NotificationState.duration(NotificationState.nowMs - NotificationState.sessionStartMs) : "–"
                        color: WalColors.color4
                        font.family: Theme.fontUi
                        font.pixelSize: 20
                        font.features: Theme.tabular
                        font.bold: true
                    }

                    Text {
                        anchors.right: parent.right
                        text: "SESSION"
                        color: WalColors.withAlpha(WalColors.color7, 0.4)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                }

            }

        }

        // ---------- Day line: 0-24 h, marks the session, dot = now ----------
        Reveal {
            id: dayReveal

            delay: 70

            Item {
                id: day

                readonly property real dayStart: {
                    const d = new Date(NotificationState.nowMs);
                    d.setHours(0, 0, 0, 0);
                    return d.getTime();
                }
                readonly property real fracNow: Math.max(0, Math.min(1, (NotificationState.nowMs - dayStart) / 86400000))
                readonly property real fracStart: NotificationState.sessionStartMs > 0 ? Math.max(0, Math.min(fracNow, (NotificationState.sessionStartMs - dayStart) / 86400000)) : fracNow

                width: parent.width
                height: 26

                Rectangle {
                    y: 5
                    width: parent.width
                    height: 3
                    radius: 1.5
                    color: WalColors.withAlpha(WalColors.color7, 0.08)
                }

                Rectangle {
                    y: 5
                    x: day.fracStart * day.width
                    width: Math.max(0, (day.fracNow - day.fracStart) * day.width * dayReveal.t)
                    height: 3
                    radius: 1.5
                    color: WalColors.withAlpha(WalColors.color4, 0.6)
                }

                Item {
                    x: (day.fracStart + (day.fracNow - day.fracStart) * dayReveal.t) * day.width - 6.5
                    y: 0
                    width: 13
                    height: 13

                    Rectangle {
                        anchors.centerIn: parent
                        width: 13
                        height: 13
                        radius: height / 2
                        color: WalColors.color4

                        SequentialAnimation on opacity {
                            running: panel.shown
                            loops: Animation.Infinite

                            NumberAnimation {
                                from: 0.35
                                to: 0
                                duration: 1400
                                easing.type: Easing.OutCubic
                            }

                            PauseAnimation {
                                duration: 600
                            }

                        }

                        SequentialAnimation on scale {
                            running: panel.shown
                            loops: Animation.Infinite

                            NumberAnimation {
                                from: 0.6
                                to: 1.6
                                duration: 1400
                                easing.type: Easing.OutCubic
                            }

                            PauseAnimation {
                                duration: 600
                            }

                        }

                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 7
                        height: 7
                        radius: height / 2
                        color: WalColors.color4
                        border.width: 2
                        border.color: WalColors.color0
                    }

                }

                Text {
                    anchors.bottom: parent.bottom
                    text: NotificationState.sessionStartMs > 0 ? "since " + Qt.formatTime(new Date(NotificationState.sessionStartMs), "hh:mm") : ""
                    color: WalColors.withAlpha(WalColors.color7, 0.4)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.features: Theme.tabular
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    text: Math.round(day.fracNow * 100) + "% of today"
                    color: WalColors.withAlpha(WalColors.color7, 0.4)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.features: Theme.tabular
                }

            }

        }

        // ---------- Title row: count, do not disturb, clear all ----------
        Reveal {
            delay: 130

            Item {
                width: parent.width
                height: 26

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notifications"
                        color: WalColors.withAlpha(WalColors.color7, 0.85)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                        font.bold: true
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: NotificationState.count > 0
                        width: countText.implicitWidth + 10
                        height: 16
                        radius: height / 2
                        color: WalColors.withAlpha(WalColors.color4, 0.18)

                        Text {
                            id: countText

                            anchors.centerIn: parent
                            text: NotificationState.count
                            color: WalColors.color4
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeMicro
                            font.features: Theme.tabular
                            font.bold: true
                        }

                    }

                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: NotificationState.count > 0
                        text: "Clear all"
                        color: clearMouse.containsMouse ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.45)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall

                        MouseArea {
                            id: clearMouse

                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.clearAll()
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                    }

                    DndSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                    }

                }

            }

        }

        Item {
            id: listBox

            width: parent.width
            // childrenRect in addition to contentHeight: that one gets stuck when a card grows
            // afterwards. But only at rest: during transitions it fidgets along with the sliding and
            // fading cards, the height would then get a new target every frame.
            readonly property bool listSettled: !historyRemove.running && !historyDisplaced.running

            height: NotificationState.count > 0 ? Math.min(panel.maxListH, listSettled ? Math.max(historyList.contentHeight, historyList.contentItem.childrenRect.height) : historyList.contentHeight) : emptyState.height

            Behavior on height {
                enabled: panel.shown

                HeightAnim {
                }

            }

            ListView {
                id: historyList

                anchors.fill: parent
                clip: true
                spacing: 8
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                visible: NotificationState.count > 0

                model: ScriptModel {
                    values: [...NotificationState.list].reverse()
                }

                delegate: NotificationCard {
                    width: historyList.width
                    introRun: panel.introRun
                    clearing: panel.clearing
                }

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Appearance.anim.durations.normal
                        }

                        NumberAnimation {
                            property: "scale"
                            from: 0.94
                            to: 1
                            duration: 380
                            easing.type: Easing.OutBack
                        }

                    }

                }

                remove: Transition {
                    id: historyRemove

                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: 160
                    }

                }

                // Always finish an interrupted fade-in (two almost at the same time)
                displaced: Transition {
                    id: historyDisplaced

                    NumberAnimation {
                        property: "y"
                        duration: 360
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        properties: "opacity,scale"
                        to: 1
                        duration: 200
                    }

                }

            }

            // Empty: the bell swings softly / in do-not-disturb mode small z's rise.
            // The change between both is soft (dndK 0..1): the bell tips away and fades out,
            // the crossed-out one springs in, the z's and the text crossfade. When turning off
            // the bell rings once briefly ("reachable again")
            Item {
                id: emptyState

                property real dndK: NotificationState.dnd ? 1 : 0

                width: parent.width
                height: 100
                visible: NotificationState.count === 0

                Connections {
                    function onDndChanged() {
                        if (!NotificationState.dnd && panel.shown && emptyState.visible)
                            ringAnim.restart();

                    }

                    target: NotificationState
                }

                Item {
                    id: emptyIcon

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    width: 40
                    height: 40

                    // Normal bell: swings at rest, tips away when DND is turned on
                    Item {
                        anchors.fill: parent
                        opacity: Math.max(0, 1 - 1.6 * emptyState.dndK)
                        visible: opacity > 0.01
                        scale: 1 - 0.3 * emptyState.dndK
                        rotation: -28 * emptyState.dndK

                        Text {
                            id: bell

                            anchors.centerIn: parent
                            transformOrigin: Item.Top
                            text: "󰂜"
                            color: WalColors.withAlpha(WalColors.color7, 0.3)
                            font.family: Theme.font
                            font.pixelSize: 30

                            SequentialAnimation on rotation {
                                running: panel.shown && emptyState.visible && !NotificationState.dnd && !ringAnim.running
                                loops: Animation.Infinite

                                NumberAnimation {
                                    from: 0
                                    to: 9
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }

                                NumberAnimation {
                                    from: 9
                                    to: -9
                                    duration: 1800
                                    easing.type: Easing.InOutSine
                                }

                                NumberAnimation {
                                    from: -9
                                    to: 0
                                    duration: 900
                                    easing.type: Easing.InOutSine
                                }

                            }

                        }

                    }

                    // Crossed-out bell: springs in
                    Text {
                        anchors.centerIn: parent
                        text: "󰂛"
                        color: WalColors.withAlpha(WalColors.color7, 0.3)
                        font.family: Theme.font
                        font.pixelSize: 30
                        opacity: Math.max(0, (emptyState.dndK - 0.25) / 0.75)
                        visible: opacity > 0.01
                        scale: 0.6 + 0.4 * emptyState.dndK
                        rotation: 18 * (1 - emptyState.dndK)
                    }

                    Repeater {
                        model: 3

                        delegate: Text {
                            id: zz

                            required property int index
                            property real t: 0

                            x: 30 + index * 7
                            y: 6 - t * 22
                            opacity: Math.sin(t * Math.PI) * 0.6 * emptyState.dndK
                            visible: emptyState.dndK > 0.01
                            text: "z"
                            color: WalColors.color4
                            font.family: Theme.font
                            font.pixelSize: 9 + index * 2
                            font.bold: true

                            SequentialAnimation on t {
                                running: panel.shown && emptyState.dndK > 0.01
                                loops: Animation.Infinite

                                PauseAnimation {
                                    duration: zz.index * 450
                                }

                                NumberAnimation {
                                    from: 0
                                    to: 1
                                    duration: 1800
                                    easing.type: Easing.OutSine
                                }

                                PauseAnimation {
                                    duration: (2 - zz.index) * 450
                                }

                            }

                        }

                    }

                }

                // Status text: the old one glides down and away, then the new one comes in from the top
                // (one after another, so the two do not overlap)
                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: emptyIcon.bottom
                    anchors.topMargin: 8
                    height: 16

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8 * emptyState.dndK
                        opacity: Math.max(0, 1 - 2 * emptyState.dndK)
                        text: "All caught up"
                        color: WalColors.withAlpha(WalColors.color7, 0.45)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -8 * (1 - emptyState.dndK)
                        opacity: Math.max(0, 2 * emptyState.dndK - 1)
                        text: "Do not disturb is on"
                        color: WalColors.withAlpha(WalColors.color7, 0.45)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                    }

                }

                // Short ringing when turning off (runs instead of the calm swinging)
                SequentialAnimation {
                    id: ringAnim

                    PauseAnimation {
                        duration: 140
                    }

                    NumberAnimation {
                        target: bell
                        property: "rotation"
                        to: 22
                        duration: 90
                        easing.type: Easing.OutQuad
                    }

                    NumberAnimation {
                        target: bell
                        property: "rotation"
                        to: -18
                        duration: 140
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        target: bell
                        property: "rotation"
                        to: 12
                        duration: 130
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        target: bell
                        property: "rotation"
                        to: -6
                        duration: 120
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        target: bell
                        property: "rotation"
                        to: 0
                        duration: 160
                        easing.type: Easing.OutQuad
                    }

                }

                Behavior on dndK {
                    NumberAnimation {
                        duration: 420
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

    }

    // Same curve and duration as the moving up of the cards (displaced), so edge and content
    // run together. Falls without a run-up, so fast clicking away does not stall.
    component HeightAnim: NumberAnimation {
        duration: 360
        easing.type: Easing.OutCubic
    }

    // Section that fades in delayed when opening and slides in slightly from the top
    component Reveal: Item {
        id: rv

        property int delay: 0
        property real t: 1
        default property alias content: holder.data

        width: parent ? parent.width : 0
        implicitHeight: holder.childrenRect.height
        height: implicitHeight

        Item {
            id: holder

            width: parent.width
            height: childrenRect.height
            opacity: rv.t
            y: (1 - rv.t) * -10
        }

        Connections {
            function onIntroRunChanged() {
                rvAnim.restart();
            }

            target: panel
        }

        SequentialAnimation {
            id: rvAnim

            PropertyAction {
                target: rv
                property: "t"
                value: 0
            }

            PauseAnimation {
                duration: rv.delay
            }

            NumberAnimation {
                target: rv
                property: "t"
                to: 1
                duration: 380
                easing.type: Easing.OutCubic
            }

        }

    }

    // Do not disturb: small switch, knob with a moon
    component DndSwitch: Item {
        width: 42
        height: 22

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: NotificationState.dnd ? WalColors.color4 : WalColors.withAlpha(WalColors.color7, 0.12)

            Rectangle {
                y: 2
                x: NotificationState.dnd ? parent.width - width - 2 : 2
                width: 18
                height: 18
                radius: height / 2
                color: NotificationState.dnd ? WalColors.color0 : WalColors.withAlpha(WalColors.color7, 0.6)

                Text {
                    anchors.centerIn: parent
                    text: "󰖔"
                    color: NotificationState.dnd ? WalColors.color4 : WalColors.color0
                    font.family: Theme.font
                    font.pixelSize: 10
                    rotation: NotificationState.dnd ? 0 : -90

                    Behavior on rotation {
                        NumberAnimation {
                            duration: 380
                            easing.type: Easing.OutBack
                        }

                    }

                }

                Behavior on x {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.6
                    }

                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }

                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }

            }

        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: NotificationState.setDnd(!NotificationState.dnd)
        }

    }

}
