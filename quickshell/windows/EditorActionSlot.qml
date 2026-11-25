import "../services"
import QtQuick

// Row of the optional editor action (services/Addons) in the image and video editors.
// Takes no space when no add-on provides one or the action is unavailable.
Loader {
    id: slot

    signal requested()

    width: parent ? parent.width : 0
    active: Addons.editorAction !== null
    sourceComponent: Addons.editorAction ? Addons.editorAction.button : null
    // Not item.visible: a child reports false while its parent is hidden, so the slot would never show
    visible: item !== null && Addons.editorAction !== null && Addons.editorAction.available
    onLoaded: item.divider = false

    Connections {
        function onRequested() {
            slot.requested();
        }

        target: slot.item
        ignoreUnknownSignals: true
    }

}
