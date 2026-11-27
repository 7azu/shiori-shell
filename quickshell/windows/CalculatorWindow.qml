import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../services"
import "../common"

PanelWindow {
    id: win
    readonly property var st: CalculatorState
    property bool showHistory: false
    property real reveal: 0
    screen: anchor.screen
    // Card on its own surface ("-card", no Hyprland animation); dimming + blur in the backdrop below,
    // so on closing both leave together (common/ModalBackdrop, common/Evaporate)
    visible: ev.held && anchor.here
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    WlrLayershell.namespace: "quickshell:calculator-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible && anchor.focused && !ev.closing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: surface }
    WindowAnchor {
        id: anchor
        open: st.isOpen
        onClosedWhileAway: st.isOpen = true
    }
    onVisibleChanged: {
        opening.stop();
        if (visible) {
            // Do not pop up again on a workspace change; only on a real opening.
            if (anchor.isReturn()) reveal = 1;
            else opening.restart();
            Qt.callLater(() => surface.forceActiveFocus());
        } else {
            reveal = 0;
        }
    }

    Evaporate {
        id: ev
        window: win
        open: st.isOpen
        onReopened: {
            opening.restart();
            surface.forceActiveFocus();
        }
    }

    NumberAnimation {
        id: opening
        target: win
        property: "reveal"
        from: 0
        to: 1
        duration: Appearance.anim.durations.slow
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.anim.curves.outQuint
    }

    ModalBackdrop {
        screen: anchor.screen
        name: "quickshell:calculator"
        shown: st.isOpen && anchor.here
        onClicked: st.close()
    }

    Rectangle {
        id: surface
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Theme.px(24) * (1 - win.reveal)
        scale: (0.92 + 0.08 * win.reveal) * ev.scale
        opacity: win.reveal * ev.opacity
        enabled: !ev.closing
        layer.enabled: ev.closing
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: true
            blur: ev.blur
            blurMax: 64
            blurMultiplier: 0.6
        }
        width: Math.min(Theme.px(360), parent.width - Theme.px(32))
        height: Math.min(Theme.px(580), parent.height - Theme.px(32))
        radius: Theme.radiusXL
        color: WalColors.withAlpha(WalColors.color0, 0.72)
        border.width: 1
        border.color: Theme.glass
        focus: true
        MouseArea { anchors.fill: parent }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (win.showHistory) win.showHistory = false;
                else st.close();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "=") st.calculate();
            else if (event.key === Qt.Key_Backspace) st.input("⌫");
            else if (event.key === Qt.Key_Delete) st.clear();
            else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_C) Quickshell.clipboardText = st.completed ? st.result : st.preview;
            else if (/^[0-9.,+*/%()−×÷-]$/.test(event.text)) st.input(event.text);
            else { event.accepted = false; return; }
            event.accepted = true;
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(20)
            spacing: Theme.gapSmall
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Calculator"
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeHeading
                    Layout.fillWidth: true
                }
                Rectangle {
                    Layout.preferredWidth: Theme.px(34); Layout.preferredHeight: Theme.px(34); radius: width / 2
                    color: historyMouse.containsMouse || win.showHistory ? Theme.glassHover : Theme.glass
                    Text { anchors.centerIn: parent; text: "◷"; color: Theme.text; font.pixelSize: Theme.px(22) }
                    MouseArea { id: historyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.showHistory = !win.showHistory }
                }
                Rectangle {
                    Layout.preferredWidth: Theme.px(34); Layout.preferredHeight: Theme.px(34); radius: width / 2
                    color: closeMouse.containsMouse ? Theme.glassHover : Theme.glass
                    Text { anchors.centerIn: parent; text: "×"; color: Theme.text; font.pixelSize: Theme.px(22) }
                    MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: st.close() }
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(146)
                visible: !win.showHistory
                Column {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: Theme.gap }
                    spacing: Theme.gapSmall
                    Text {
                        width: parent.width
                        text: st.expression || "Ready when you are"
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeLarge
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }
                    Text {
                        width: parent.width
                        text: st.error ? "Error" : (st.completed ? st.result : st.preview || "…")
                        color: st.error ? Theme.bad : Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.px(52)
                        font.features: Theme.tabular
                        horizontalAlignment: Text.AlignRight
                        fontSizeMode: Text.Fit
                        minimumPixelSize: Theme.sizeTitleLarge
                        height: Theme.px(66)
                    }
                    Text {
                        width: parent.width
                        text: st.error || ""
                        color: Theme.bad
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeBody
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        visible: !!st.error
                    }
                }
            }
            GridLayout {
                visible: !win.showHistory
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 4
                rowSpacing: Theme.gapSmall
                columnSpacing: Theme.gapSmall
                Repeater {
                    model: ["AC", "±", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "⌫", "0", ".", "="]
                    delegate: Rectangle {
                        id: button
                        required property string modelData
                        required property int index
                        readonly property bool op: index % 4 === 3
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: Theme.px(70)
                        Layout.preferredHeight: Theme.px(64)
                        radius: Math.min(width, height) / 2
                        color: modelData === "=" ? Theme.accent : (tap.pressed ? Theme.glassHover : tap.containsMouse ? Theme.glass : op ? Theme.accentSoft : index < 3 ? Theme.groupPressed : Theme.groupFill)
                        border.width: op ? 1 : 0
                        border.color: Theme.tint(Theme.accent, 0.18)
                        scale: tap.pressed ? 0.93 : 1
                        Behavior on scale { NumberAnimation { duration: Appearance.anim.durations.fast } }
                        Behavior on color { ColorAnimation { duration: Appearance.anim.durations.fast } }
                        Text {
                            anchors.centerIn: parent
                            text: button.modelData
                            color: button.modelData === "=" ? Theme.onAccent : button.op ? Theme.accent : Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.px(button.modelData === "AC" ? 20 : 28)
                        }
                        MouseArea {
                            id: tap
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { st.input(button.modelData); surface.forceActiveFocus(); }
                        }
                    }
                }
            }
            ListView {
                visible: win.showHistory
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.gapSmall
                model: st.history
                Text {
                    anchors.centerIn: parent
                    visible: st.history.length === 0
                    text: "Your calculations will appear here"
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                }
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: Theme.px(76)
                    radius: Theme.radiusM
                    color: entryMouse.containsMouse ? Theme.cardHover : Theme.groupFill
                    Column {
                        anchors { fill: parent; margins: Theme.padX }
                        spacing: Theme.gapSmall
                        Text { width: parent.width; text: modelData.expression; elide: Text.ElideLeft; color: Theme.textDim; font.family: Theme.fontUi; font.pixelSize: Theme.sizeBody }
                        Text { width: parent.width; text: "= " + modelData.result; elide: Text.ElideRight; color: Theme.text; font.family: Theme.fontUi; font.pixelSize: Theme.sizeTitleLarge }
                    }
                    MouseArea { id: entryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { st.recall(modelData); win.showHistory = false; } }
                }
            }
            Text {
                Layout.fillWidth: true
                text: win.showHistory ? "Select a result to use it again" : "Enter to calculate · Ctrl+C to copy"
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
                Layout.topMargin: Theme.gapSmall
            }
        }
    }
}
