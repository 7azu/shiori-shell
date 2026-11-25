import "../services"
import QtQuick

// Text field of the settings window. Nothing is written while typing: Enter or leaving the field
// commits (committed), Esc takes the stored text back and returns the keyboard to the search.
Rectangle {
    id: field

    // The stored value; the field follows it while it is not being edited (undo, reset)
    property string text: ""
    property string placeholder: ""
    // Something is wrong with the value (e.g. the folder does not exist)
    property bool warn: false
    readonly property alias input: input

    signal committed(string text)

    function commit() {
        const t = input.text.trim();
        if (t !== field.text)
            field.committed(t);

    }

    height: Theme.px(30)
    radius: Theme.px(8)
    color: Theme.tint(Theme.text, input.activeFocus ? 0.1 : 0.06)
    border.width: 1
    border.color: input.activeFocus ? Theme.tint(Theme.accent, 0.6) : (warn ? Theme.tint(Theme.warn, 0.55) : "transparent")
    onTextChanged: {
        if (input.text !== text)
            input.text = text;

    }
    Component.onCompleted: input.text = text

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: Theme.px(10)
        anchors.rightMargin: Theme.px(10)
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        selectByMouse: true
        color: Theme.text
        selectionColor: Theme.tint(Theme.accent, 0.45)
        selectedTextColor: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.sizeBody
        onAccepted: field.commit()
        onActiveFocusChanged: {
            if (!activeFocus)
                field.commit();

        }
        Keys.onEscapePressed: {
            text = field.text;
            SettingsState.focusSearch();
        }
    }

    Text {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        visible: input.text === "" && !input.activeFocus
        text: field.placeholder
        elide: Text.ElideRight
        color: Theme.textFaint
        font: input.font
    }

    Behavior on color {
        ColorAnimation {
            duration: Appearance.anim.durations.fast
        }

    }

}
