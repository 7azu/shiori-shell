import "../services"
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets

// Small glass card with the playing song (cover, title, progress, controls).
// Invisible when no player has a title.
Item {
    id: root

    // All players with a title you can switch between with the arrows
    // (playerctld only mirrors another player)
    readonly property var players: Mpris.players.values.filter((p) => {
        return !(p.dbusName || "").includes("playerctld") && p.trackTitle && p.trackTitle !== "";
    })
    // By itself: the playing player first, otherwise mpd (main player), otherwise any one with a title
    readonly property var autoPlayer: players.find((p) => {
        return p.isPlaying;
    }) || players.find((p) => {
        return p.identity && p.identity.toLowerCase().indexOf("mpd") >= 0;
    }) || players[0] || null
    // Chosen by arrow: holds until another player starts playing (as in the audio dropdown)
    property var chosenPlayer: null
    readonly property var player: chosenPlayer && players.indexOf(chosenPlayer) !== -1 ? chosenPlayer : autoPlayer
    readonly property bool hasTrack: player !== null
    readonly property bool canSwitch: players.length > 1
    // Switch: cover + title glide out to the side and back in from the other edge
    readonly property real slideDist: Theme.px(28)
    property real slideX: 0
    property real slideFade: 1
    property int slideDir: 1
    property bool switching: false
    readonly property double createdAt: Date.now()

    function cyclePlayer(dir) {
        const list = players;
        if (list.length < 2)
            return ;

        const i = list.indexOf(player);
        chosenPlayer = list[((i < 0 ? 0 : i + dir) % list.length + list.length) % list.length];
    }

    // Arrow clicked: out -> switch the player -> in
    function switchPlayer(dir) {
        if (!canSwitch)
            return ;

        slideDir = dir;
        switching = true;
        slideInAnim.stop();
        slideAnim.restart();
    }
    readonly property real progress: player && player.length > 0 ? Math.min(player.position / player.length, 1) : 0

    function fmt(sec) {
        if (!(sec > 0))
            return "0:00";

        const s = Math.floor(sec);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    implicitWidth: Theme.px(440)
    implicitHeight: Theme.px(92)
    opacity: hasTrack ? 1 : 0
    visible: opacity > 0.01

    // Mpris does not report the position by itself -> ask regularly
    Timer {
        interval: 1000
        repeat: true
        running: root.hasTrack && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusL
        color: WalColors.withAlpha(WalColors.color0, 0.5)
        border.width: 1
        border.color: Theme.stroke
    }

    Row {
        anchors.fill: parent
        anchors.margins: Theme.px(12)
        spacing: Theme.px(14)

        ClippingRectangle {
            opacity: root.slideFade
            transform: Translate {
                x: root.slideX
            }
            width: parent.height
            height: width
            radius: Theme.radiusM
            color: Theme.card

            Text {
                anchors.centerIn: parent
                text: ""
                font.family: Theme.font
                font.pixelSize: Theme.px(22)
                color: Theme.textFaint
            }

            Image {
                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                asynchronous: true
                cache: false
            }

        }

        Column {
            opacity: root.slideFade
            transform: Translate {
                x: root.slideX
            }
            width: parent.width - parent.height - controls.width - 2 * parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(3)

            Text {
                width: parent.width
                text: root.player ? root.player.trackTitle : ""
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLead
                font.weight: Font.Medium
                color: Theme.text
            }

            Text {
                width: parent.width
                text: root.player ? (root.player.trackArtist || root.player.identity) : ""
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                color: Theme.textDim
            }

            Item {
                width: 1
                height: Theme.px(6)
            }

            Rectangle {
                width: parent.width
                height: Theme.px(3)
                visible: root.player && root.player.length >= 2
                radius: height / 2
                color: Theme.track

                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: height / 2
                    color: WalColors.color4

                    Behavior on width {
                        NumberAnimation {
                            duration: 900
                        }

                    }

                }

            }

            // Streams in the browser often report no length -> then no times
            Row {
                width: parent.width
                visible: root.player && root.player.length >= 2

                Text {
                    width: parent.width / 2
                    text: root.player ? root.fmt(root.player.position) : ""
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.features: Theme.tabular
                    color: Theme.textFaint
                }

                Text {
                    width: parent.width / 2
                    horizontalAlignment: Text.AlignRight
                    text: root.player ? root.fmt(root.player.length) : ""
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.features: Theme.tabular
                    color: Theme.textFaint
                }

            }

        }

        Row {
            id: controls

            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(2)

            Repeater {
                model: [{
                    "glyph": "",
                    "act": "prev",
                    "big": false
                }, {
                    "glyph": root.player && root.player.isPlaying ? "" : "",
                    "act": "toggle",
                    "big": true
                }, {
                    "glyph": "",
                    "act": "next",
                    "big": false
                }]

                delegate: Rectangle {
                    required property var modelData

                    width: modelData.big ? Theme.px(40) : Theme.px(32)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.big ? WalColors.color4 : (mouse.containsMouse ? Theme.cardHover : "transparent")
                    scale: mouse.pressed ? 0.9 : 1

                    Text {
                        anchors.centerIn: parent
                        // Play triangle optically centered
                        anchors.horizontalCenterOffset: parent.modelData.glyph === "" ? 1 : 0
                        text: parent.modelData.glyph
                        font.family: Theme.font
                        font.pixelSize: parent.modelData.big ? Theme.px(14) : Theme.px(12)
                        color: parent.modelData.big ? Theme.onAccent : Theme.textDim
                    }

                    MouseArea {
                        id: mouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const p = root.player;
                            if (!p)
                                return ;

                            if (parent.modelData.act === "prev" && p.canGoPrevious)
                                p.previous();
                            else if (parent.modelData.act === "next" && p.canGoNext)
                                p.next();
                            else if (parent.modelData.act === "toggle" && p.canTogglePlaying)
                                p.togglePlaying();
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                        }

                    }

                }

            }

        }

    }

    // If another player starts playing, the arrow choice no longer holds
    Instantiator {
        model: Mpris.players

        delegate: Connections {
            required property MprisPlayer modelData

            function onIsPlayingChanged() {
                if (modelData.isPlaying && root.chosenPlayer && modelData !== root.chosenPlayer)
                    root.chosenPlayer = null;

            }

            target: modelData
        }

    }

    // Arrows left/right of the card, only when several players have a title
    SwitchArrow {
        dir: -1
        anchors.right: parent.left
        anchors.rightMargin: Theme.px(8)
        anchors.verticalCenter: parent.verticalCenter
    }

    SwitchArrow {
        dir: 1
        anchors.left: parent.right
        anchors.leftMargin: Theme.px(8)
        anchors.verticalCenter: parent.verticalCenter
    }

    SequentialAnimation {
        id: slideAnim

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "slideX"
                to: -root.slideDir * root.slideDist
                duration: 140
                easing.type: Easing.InCubic
            }

            NumberAnimation {
                target: root
                property: "slideFade"
                to: 0
                duration: 140
                easing.type: Easing.InCubic
            }

        }

        ScriptAction {
            script: root.cyclePlayer(root.slideDir)
        }

        PropertyAction {
            target: root
            property: "slideX"
            value: root.slideDir * root.slideDist
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "slideX"
                to: 0
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: root
                property: "slideFade"
                to: 1
                duration: 240
                easing.type: Easing.OutCubic
            }

        }

        ScriptAction {
            script: root.switching = false
        }

    }

    // The player changed by itself (another one starts playing): only glide in.
    // Not right after the start (there the player reports itself once as "changed" while building)
    onPlayerChanged: {
        if (!switching && hasTrack && !slideAnim.running && Date.now() - createdAt > 600)
            slideInAnim.restart();

    }

    SequentialAnimation {
        id: slideInAnim

        PropertyAction {
            target: root
            property: "slideX"
            value: root.slideDist
        }

        PropertyAction {
            target: root
            property: "slideFade"
            value: 0
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "slideX"
                to: 0
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: root
                property: "slideFade"
                to: 1
                duration: 240
                easing.type: Easing.OutCubic
            }

        }

    }

    // Small glass pill; the generous click area stays invisible.
    component SwitchArrow: Item {
        id: sa

        property int dir: 1

        width: Theme.px(30)
        height: Theme.px(52)
        visible: root.canSwitch

        Rectangle {
            anchors.centerIn: parent
            width: Theme.px(26)
            height: Theme.px(40)
            radius: width / 2
            scale: saMouse.pressed ? 0.94 : 1
            color: WalColors.withAlpha(WalColors.color0, saMouse.containsMouse ? 0.22 : 0.12)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, saMouse.containsMouse ? 0.22 : 0.10)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, saMouse.containsMouse ? 0.14 : 0.08) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.02) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.04) }
                }
            }

            // Two fine lines instead of a heavy font glyph.
            Item {
                anchors.centerIn: parent
                width: Theme.px(6)
                height: Theme.px(10)
                rotation: sa.dir > 0 ? 0 : 180
                opacity: saMouse.containsMouse ? 0.85 : 0.48

                Repeater {
                    model: [-1, 1]
                    delegate: Rectangle {
                        required property int modelData
                        x: 0
                        y: parent.height / 2 - height / 2
                        width: Theme.px(7)
                        height: Theme.px(1.4)
                        radius: height / 2
                        color: "white"
                        transformOrigin: Item.Right
                        rotation: modelData * 45
                        antialiasing: true
                    }
                }

                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on border.color { ColorAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: saMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            propagateComposedEvents: false
            onPressed: (mouse) => { mouse.accepted = true; }
            onClicked: (mouse) => {
                mouse.accepted = true;
                root.switchPlayer(sa.dir);
            }
        }

    }

    // No Behavior on opacity: LockSurface controls the opacity (intro/unlock), a sluggish
    // fade made the card stay when unlocking while everything else was already gone.
}
