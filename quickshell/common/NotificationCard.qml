import "../services"
import QtQuick
import QtQuick.Effects
import Quickshell.Services.Notifications
import Quickshell.Widgets

// One notification, as a delegate of a ListView.
//   toast: true  -> compact card at the top right (remaining time line, a click opens the center)
//   toast: false -> full card in the notification center (actions, click = default action)
// Swiping left/right or x = dismiss.
Item {
    id: card

    required property var modelData
    required property int index
    readonly property var n: modelData
    property bool toast: false
    property bool paused: false
    // From the center: counted up when opening (cards fall in one after another) or "Clear all"
    property int introRun: 0
    property bool clearing: false
    readonly property bool hovered: cardHover.hovered
    // Freeze values: while flying away the notification object is already deleted
    property string summary: ""
    property string body: ""
    property string appName: ""
    property string icon: ""
    property bool isImage: false
    property bool critical: false
    // Success (hint x-qs-success, set by NotificationState.send({success}) and our own scripts).
    // The star birth at the icon no longer depends on it (fires on every toast, see successMark)
    property bool success: false
    property real arrivedMs: 0
    property var actions: []
    readonly property int duration: toast && n ? NotificationState.popupDuration(n) : 0
    property real progress: 1
    property bool leaving: false

    function fling(dir) {
        if (leaving)
            return ;

        leaving = true;
        flingAnim.to = dir * (width + 40);
        flingSeq.restart();
    }

    height: face.height
    // Only start the remaining time here, so the duration is already set (a declarative running
    // could start with duration 0 and end the toast right away)
    Component.onCompleted: {
        if (toast && duration > 0) {
            lifeAnim.duration = duration;
            lifeAnim.start();
        }
    }
    onIntroRunChanged: {
        if (!toast && index < 8)
            introAnim.restart();

    }

    // Remaining time of the toast; hover pauses
    NumberAnimation {
        id: lifeAnim

        target: card
        property: "progress"
        from: 1
        to: 0
        paused: running && (card.paused || card.leaving)
        onFinished: {
            if (card.n)
                NotificationState.hidePopup(card.n);

        }
    }

    SequentialAnimation {
        id: flingSeq

        ParallelAnimation {
            NumberAnimation {
                id: flingAnim

                target: face
                property: "x"
                duration: 220
                easing.type: Easing.InCubic
            }

            NumberAnimation {
                target: face
                property: "opacity"
                to: 0
                duration: 220
            }

        }

        ScriptAction {
            script: {
                if (card.n)
                    NotificationState.dismiss(card.n);

            }
        }

    }

    // Clear all: staggered out to the right
    SequentialAnimation {
        running: card.clearing && !card.toast
        onStarted: card.leaving = true

        PauseAnimation {
            duration: Math.max(0, Math.min(card.index, 8)) * 45
        }

        ParallelAnimation {
            NumberAnimation {
                target: face
                property: "x"
                to: card.width + 40
                duration: 240
                easing.type: Easing.InCubic
            }

            NumberAnimation {
                target: face
                property: "opacity"
                to: 0
                duration: 240
            }

        }

    }

    SequentialAnimation {
        id: introAnim

        PropertyAction {
            target: face
            property: "opacity"
            value: 0
        }

        PropertyAction {
            target: face
            property: "y"
            value: -8
        }

        PauseAnimation {
            duration: 140 + Math.max(0, card.index) * 40
        }

        ParallelAnimation {
            NumberAnimation {
                target: face
                property: "opacity"
                to: 1
                duration: 320
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: face
                property: "y"
                to: 0
                duration: 380
                easing.type: Easing.OutCubic
            }

        }

    }

    Rectangle {
        id: face

        width: parent.width
        height: card.toast ? Math.max(74, row.height + 26) : row.height + 24
        radius: card.toast ? 18 : 14
        color: card.toast ? WalColors.withAlpha(WalColors.color0, 1) : WalColors.withAlpha(WalColors.color7, card.hovered ? 0.08 : 0.045)
        border.width: card.toast ? 1 : 0
        border.color: WalColors.withAlpha(WalColors.color7, card.hovered ? 0.16 : 0.08)
        clip: true
        // Toasts float freely -> own soft shadow
        layer.enabled: card.toast

        // Urgent: colored stripe on the left
        Rectangle {
            visible: card.critical
            width: 3
            height: parent.height - (card.toast ? 20 : 24)
            anchors.verticalCenter: parent.verticalCenter
            x: 4
            radius: 1.5
            color: WalColors.color1
        }

        // ---- Star birth above the icon (every toast) ----
        // Like the confirmations in the clipboard: the icon is briefly tinted dark, on it a sparkle fires
        // (StarBurst), then everything fades out softly and the icon stands free again. Nothing in the center (review).
        Item {
            id: successMark

            property real veil: 0
            property real k: 0
            readonly property real iconW: card.toast ? 44 : 36

            // Above the card instead of IN it: face is drawn as a layer with a blurred shadow
            // (layer + MultiEffect). If the star were inside, the whole card including the shadow would have to be
            // recomputed every frame while it animates - the toast's glide-in stuttered then
            parent: card
            x: face.x + row.x
            y: face.y + row.y + (card.toast ? (row.height - iconW) / 2 : 0)
            width: iconW
            height: iconW
            z: 3
            opacity: k * row.opacity
            visible: opacity > 0.01
            // On EVERY toast, not only on success (x-qs-success)
            Component.onCompleted: {
                if (card.toast)
                    successBurst.start();

            }

            Rectangle {
                anchors.fill: parent
                radius: card.toast ? 13 : 11
                color: Qt.tint(WalColors.withAlpha(WalColors.color0, 0.6), WalColors.withAlpha(WalColors.vividAccent, 0.18))
                opacity: successMark.veil
            }

            StarBurst {
                anchors.centerIn: parent
                size: 8
                color: Qt.lighter(WalColors.color7, 1.1)
                glowColor: WalColors.vividAccent
                active: successMark.k > 0
            }

            SequentialAnimation {
                id: successBurst

                // Only fire when the toast has almost arrived: it glides in for 460 ms (NotificationToasts, add
                // transition), right away the star birth was hardly visible in flight; 420 ms was already a bit too late
                PauseAnimation {
                    duration: 280
                }

                PropertyAction {
                    target: successMark
                    property: "k"
                    value: 1
                }

                NumberAnimation {
                    target: successMark
                    property: "veil"
                    from: 0
                    to: 1
                    duration: 160
                    easing.type: Easing.OutCubic
                }

                PauseAnimation {
                    duration: 1000
                }

                NumberAnimation {
                    target: successMark
                    property: "k"
                    to: 0
                    duration: 750
                    easing.type: Easing.InOutSine
                }

            }

        }

        Row {
            id: row

            x: card.toast ? 14 : 12
            y: card.toast ? (face.height - height) / 2 : 12
            width: parent.width - (card.toast ? 28 : 24)
            spacing: 12
            // Fade out slowly while swiping
            opacity: Math.max(0.25, 1 - Math.abs(face.x) / (card.width * 0.9))

            ClippingRectangle {
                anchors.verticalCenter: card.toast ? parent.verticalCenter : undefined
                width: card.toast ? 44 : 36
                height: width
                radius: card.toast ? 13 : 11
                color: WalColors.withAlpha(WalColors.color4, 0.15)

                Image {
                    id: iconImg

                    anchors.centerIn: parent
                    width: card.isImage ? parent.width : parent.width * 0.66
                    height: width
                    source: card.icon
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Text {
                    readonly property string glyph: NotificationState.glyphOf(card.appName)

                    anchors.centerIn: parent
                    visible: iconImg.status !== Image.Ready
                    text: glyph || card.appName.charAt(0).toUpperCase()
                    color: WalColors.color4
                    font.family: Theme.font
                    font.pixelSize: glyph ? (card.toast ? 21 : 18) : (card.toast ? 17 : 15)
                    font.bold: true
                }

            }

            // ---- Toast: two lines, only the essentials ----
            Column {
                visible: card.toast
                anchors.verticalCenter: parent.verticalCenter
                width: row.width - 56
                spacing: 3

                Item {
                    width: parent.width
                    height: toastTitle.implicitHeight

                    Text {
                        id: toastTitle

                        width: parent.width - toastAgo.width - 8
                        text: card.summary || card.appName
                        color: WalColors.color7
                        elide: Text.ElideRight
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeLead
                        font.bold: true
                    }

                    Text {
                        id: toastAgo

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.hovered ? "󰅖" : card.appName
                        color: card.hovered ? WalColors.withAlpha(WalColors.color7, 0.6) : WalColors.withAlpha(WalColors.color4, 0.8)
                        font.family: Theme.font
                        font.pixelSize: card.hovered ? 14 : 10
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: card.hovered
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.fling(1)
                        }

                    }

                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: card.body
                    textFormat: Text.StyledText
                    color: WalColors.withAlpha(WalColors.color7, 0.7)
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                }

            }

            // ---- Center: full card ----
            Column {
                visible: !card.toast
                width: row.width - 48
                spacing: 3

                Item {
                    width: parent.width
                    height: appText.implicitHeight

                    Text {
                        id: appText

                        width: parent.width - 30
                        text: card.appName + (card.arrivedMs ? "  ·  " + NotificationState.ago(card.arrivedMs) : "")
                        color: WalColors.withAlpha(WalColors.color4, 0.9)
                        elide: Text.ElideRight
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                        font.features: Theme.tabular
                        font.bold: true
                    }

                    // x to dismiss, appears on hover
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅖"
                        color: closeMouse.containsMouse ? WalColors.color1 : WalColors.withAlpha(WalColors.color7, 0.5)
                        font.family: Theme.font
                        font.pixelSize: 12
                        opacity: card.hovered ? 1 : 0
                        scale: closeMouse.containsMouse ? 1.2 : 1

                        MouseArea {
                            id: closeMouse

                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.fling(1)
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.anim.durations.fast
                            }

                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 120
                            }

                        }

                    }

                }

                Text {
                    width: parent.width
                    text: card.summary
                    color: WalColors.color7
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLabel
                    font.bold: true
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: card.body
                    textFormat: Text.StyledText
                    color: WalColors.withAlpha(WalColors.color7, 0.65)
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeSmall
                    lineHeight: 1.1
                }

                // Actions of the app (without the default action, that one is on the click)
                Flow {
                    width: parent.width
                    visible: card.actions.length > 0
                    spacing: 6
                    topPadding: 4

                    Repeater {
                        model: card.actions

                        delegate: Rectangle {
                            id: actBtn

                            required property var modelData

                            width: actText.implicitWidth + 18
                            height: 22
                            radius: height / 2
                            color: actMouse.containsMouse ? WalColors.withAlpha(WalColors.color4, 0.3) : WalColors.withAlpha(WalColors.color4, 0.14)

                            Text {
                                id: actText

                                anchors.centerIn: parent
                                text: actBtn.modelData ? actBtn.modelData.text : ""
                                color: WalColors.color4
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.sizeMicro
                                font.bold: true
                            }

                            MouseArea {
                                id: actMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (actBtn.modelData)
                                        actBtn.modelData.invoke();

                                    if (card.n && !card.n.resident)
                                        NotificationState.dismiss(card.n);

                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }

                            }

                        }

                    }

                }

            }

        }

        // Remaining time line at the bottom of the toast
        Rectangle {
            visible: card.toast && card.duration > 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            anchors.left: parent.left
            anchors.leftMargin: 18
            width: (parent.width - 36) * card.progress
            height: 2.5
            radius: 1
            color: WalColors.withAlpha(WalColors.color4, 0.7)
        }

        HoverHandler {
            id: cardHover

            cursorShape: Qt.PointingHandCursor
        }

        // Toast: a click opens the center. Center: run the app's default action.
        TapHandler {
            onTapped: {
                if (!card.n || card.leaving)
                    return ;

                if (card.toast) {
                    NotificationState.open();
                } else if (NotificationState.activate(card.n)) {
                    NotificationState.dismiss(card.n);
                    NotificationState.close();
                }
            }
        }

        // Swipe to dismiss
        DragHandler {
            target: face
            yAxis.enabled: false
            xAxis.minimum: -card.width
            xAxis.maximum: card.width
            onActiveChanged: {
                if (active)
                    return ;

                if (Math.abs(face.x) > card.width * 0.3)
                    card.fling(face.x > 0 ? 1 : -1);
                else
                    snapBack.restart();
            }
        }

        NumberAnimation {
            id: snapBack

            target: face
            property: "x"
            to: 0
            duration: Appearance.anim.durations.normal
            easing.type: Easing.OutBack
        }

        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.7
            blurMax: 20
            shadowVerticalOffset: 3
            autoPaddingEnabled: true
        }

    }

    Binding on summary {
        when: card.n !== null
        value: card.n ? card.n.summary : ""
        restoreMode: Binding.RestoreNone
    }

    Binding on body {
        when: card.n !== null
        value: card.n ? card.n.body : ""
        restoreMode: Binding.RestoreNone
    }

    Binding on appName {
        when: card.n !== null
        value: card.n ? (card.n.appName || "Notification") : ""
        restoreMode: Binding.RestoreNone
    }

    Binding on icon {
        when: card.n !== null
        value: card.n ? NotificationState.iconOf(card.n) : ""
        restoreMode: Binding.RestoreNone
    }

    Binding on isImage {
        when: card.n !== null
        value: card.n ? card.n.image !== "" : false
        restoreMode: Binding.RestoreNone
    }

    Binding on critical {
        when: card.n !== null
        value: card.n ? card.n.urgency === NotificationUrgency.Critical : false
        restoreMode: Binding.RestoreNone
    }

    Binding on success {
        when: card.n !== null
        value: card.n ? !!(card.n.hints && card.n.hints["x-qs-success"]) : false
        restoreMode: Binding.RestoreNone
    }

    Binding on arrivedMs {
        when: card.n !== null
        value: card.n ? NotificationState.timeOf(card.n) : 0
        restoreMode: Binding.RestoreNone
    }

    Binding on actions {
        when: card.n !== null
        value: card.n ? Array.from(card.n.actions).filter((a) => {
            return a.identifier !== "default" && a.text !== "";
        }) : []
        restoreMode: Binding.RestoreNone
    }

}
