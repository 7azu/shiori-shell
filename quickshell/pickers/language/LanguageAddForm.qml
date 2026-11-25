import "../../common"
import "../../services"
import QtQuick
import Quickshell.Widgets

// Add a new language (plus tile of the language choice). Replaces the tile row at the same height:
// on the left a live preview of the future tile (the same ChooserTile), on the right the form:
//   Name    -> folder <languages folder>/<Name>
//   Symbol  -> character in the circle (empty = suggestion: known character or the first two letters)
//   Image   -> optional, copied into the language folder as cover.<ext> (then it replaces the character,
//              like the Japan image). Chosen in the picker instead of an external dialog: the newest images from
//              Downloads/Pictures/Desktop (LanguageAudioState.pickImages), or "Browse": the panel morphs
//              into the folder browser of the editors (LanguagePicker.openImageBrowser), the image comes via setImage
// Keys: Tab/Shift+Tab switch fields, in the image strip <-/-> or h/l, B (strip) or Ctrl+B = browse,
// Enter creates, Esc goes back.
// The fields are NOT in the tile: its MouseArea lies above all content and swallowed the clicks.
Item {
    id: form

    required property var host
    readonly property real tileW: host.tileW
    readonly property real gap: host.gap
    // -1 = no image
    property int imageIndex: -1
    property string error: ""
    // Last focused field (for refocus)
    property Item lastField: null
    // Images chosen in the browser are in front in the strip (even if they are not among the newest)
    property var extraImages: []
    readonly property var images: {
        const seen = {};
        const out = [];
        for (const e of extraImages.concat(LanguageAudioState.pickImages)) {
            if (seen[e.path])
                continue;

            seen[e.path] = true;
            out.push(e);
        }
        return out;
    }
    readonly property string cleanName: LanguageAudioState.cleanLanguageName(nameInput.text)
    readonly property string typedName: nameInput.text.trim()
    readonly property string autoMark: typedName === "" ? "" : LanguageAudioState.defaultMarkOf(typedName.charAt(0).toUpperCase() + typedName.slice(1))
    readonly property string mark: symbolInput.text.trim() !== "" ? symbolInput.text.trim() : autoMark
    readonly property string image: imageIndex >= 0 && imageIndex < images.length ? images[imageIndex].path : ""
    readonly property bool latin: /^[A-Za-z]/.test(mark)

    function open() {
        nameInput.text = "";
        symbolInput.text = "";
        imageIndex = -1;
        extraImages = [];
        error = "";
        lastField = nameInput;
        strip.positionViewAtBeginning();
        LanguageAudioState.loadPickImages();
        nameInput.forceActiveFocus();
    }

    // Focus back into the form, into the field you were in last
    function refocus() {
        (lastField || nameInput).forceActiveFocus();
    }

    // Folder browser: starts at the chosen image, otherwise at the newest, otherwise in ~/Pictures
    function browse() {
        const start = image !== "" ? image : images.length > 0 ? images[0].path : Settings.expand("$PICTURES") + "/";
        host.picker.openImageBrowser(start);
    }

    function setImage(path) {
        extraImages = [{
            "path": path,
            "name": path.substring(path.lastIndexOf("/") + 1)
        }].concat(extraImages.filter((e) => {
            return e.path !== path;
        }));
        imageIndex = 0;
        lastField = strip;
        strip.positionViewAtBeginning();
    }

    function submit() {
        if (cleanName === "") {
            error = typedName === "" ? "Type a name" : "Already exists";
            shake.restart();
            nameInput.forceActiveFocus();
            return ;
        }
        // Create folder + character + image; as soon as it is read, the picker goes into it (languageAdded)
        LanguageAudioState.addLanguage(nameInput.text, symbolInput.text, image);
        host.finishAdding();
    }

    function cancel() {
        host.cancelAdding();
    }

    // Tab order name -> symbol -> images -> name
    function focusNext(from, back) {
        const order = [nameInput, symbolInput, strip];
        const i = order.indexOf(from);
        order[(i + (back ? order.length - 1 : 1)) % order.length].forceActiveFocus();
    }

    function selectImage(i) {
        imageIndex = Math.max(-1, Math.min(images.length - 1, i));
        // -1 = tile "no image" (index 0 of the strip)
        strip.positionViewAtIndex(imageIndex + 1, ListView.Contain);
    }

    // Shared keys of all fields
    function handleKey(event, item) {
        const key = event.key;
        if (key === Qt.Key_B && (event.modifiers & Qt.ControlModifier))
            browse();
        else if (key === Qt.Key_Tab || key === Qt.Key_Backtab)
            focusNext(item, key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier));
        else if (key === Qt.Key_Escape)
            cancel();
        else if (key === Qt.Key_Return || key === Qt.Key_Enter)
            submit();
        else
            return false;
        event.accepted = true;
        return true;
    }

    // ── Preview ──
    ChooserTile {
        id: preview

        width: form.tileW
        height: parent.height
        selected: true
        glyph: form.mark !== "" ? form.mark : String.fromCodePoint(0xF067)
        glyphFont: form.mark === "" ? Theme.font : form.latin ? Theme.fontUi : form.host.picker.jp
        glyphSize: form.mark === "" ? 36 : form.latin ? 34 : 40
        label: form.cleanName !== "" ? form.cleanName : (form.typedName !== "" ? form.typedName : "New Language")
        cover: LanguageAudioState.fileUrl(form.image)
        showGlyph: form.image === ""
    }

    // ── Form ──
    Rectangle {
        id: card

        // Shake on an invalid name
        property real shakeX: 0

        x: form.tileW + form.gap + shakeX
        width: form.width - form.tileW - form.gap
        height: parent.height
        radius: 24
        color: WalColors.withAlpha(WalColors.color7, 0.045)
        border.width: 1
        border.color: WalColors.withAlpha(WalColors.color7, 0.08)

        SequentialAnimation {
            id: shake

            NumberAnimation {
                target: card
                property: "shakeX"
                to: -7
                duration: 50
            }

            NumberAnimation {
                target: card
                property: "shakeX"
                to: 7
                duration: 70
            }

            NumberAnimation {
                target: card
                property: "shakeX"
                to: -3
                duration: 60
            }

            NumberAnimation {
                target: card
                property: "shakeX"
                to: 0
                duration: 50
            }

        }

        Item {
            id: inner

            anchors.fill: parent
            anchors.margins: 22

            Text {
                id: title

                text: "New Language"
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeLead + 3
                font.weight: Font.DemiBold
            }

            // ── Name ──
            Text {
                id: nameLabel

                y: 36
                text: "NAME"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeMicro
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }

            Rectangle {
                id: nameBox

                y: nameLabel.y + 18
                width: parent.width
                height: 40
                radius: 12
                color: Theme.tint(Theme.text, nameInput.activeFocus ? 0.09 : 0.06)
                border.width: 1
                border.color: form.error !== "" ? WalColors.withAlpha(WalColors.color1, 0.8) : nameInput.activeFocus ? WalColors.withAlpha(WalColors.color4, 0.6) : "transparent"

                // A click anywhere in the field (not only on the text) sets the focus
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onPressed: nameInput.forceActiveFocus()
                }

                TextInput {
                    id: nameInput

                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.text
                    selectionColor: WalColors.withAlpha(WalColors.color4, 0.4)
                    selectByMouse: true
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeLead
                    maximumLength: 40
                    clip: true
                    onTextChanged: form.error = ""
                    onActiveFocusChanged: {
                        if (activeFocus)
                            form.lastField = nameInput;

                    }
                    Keys.onPressed: (event) => {
                        return form.handleKey(event, nameInput);
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: nameInput.text === ""
                        text: "e.g. Korean"
                        color: Theme.textFaint
                        font: nameInput.font
                    }

                }

            }

            // ── Symbol + image ──
            Text {
                id: iconLabel

                y: nameBox.y + nameBox.height + 18
                text: "SYMBOL"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeMicro
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }

            // Open the folder browser (the panel morphs into the editors' file browser)
            Rectangle {
                id: browseBtn

                anchors.right: parent.right
                anchors.verticalCenter: iconLabel.verticalCenter
                width: browseRow.implicitWidth + 20
                height: 24
                radius: height / 2
                color: Theme.tint(Theme.text, browseArea.containsMouse ? 0.12 : 0.07)

                Row {
                    id: browseRow

                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF07C)
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: WalColors.color4
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Browse"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "B"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.sizeMicro
                        color: Theme.textFaint
                    }

                }

                MouseArea {
                    id: browseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: form.browse()
                }

            }

            Text {
                x: strip.x
                y: iconLabel.y
                text: "OR IMAGE"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeMicro
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }

            Rectangle {
                id: symbolBox

                y: iconLabel.y + 18
                width: 56
                height: 56
                radius: 16
                color: Theme.tint(Theme.text, symbolInput.activeFocus ? 0.09 : 0.06)
                border.width: 1
                border.color: symbolInput.activeFocus ? WalColors.withAlpha(WalColors.color4, 0.6) : "transparent"
                // With an image the character on the tile is off: show that it does not count right now
                opacity: form.image !== "" ? 0.45 : 1

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onPressed: symbolInput.forceActiveFocus()
                }

                TextInput {
                    id: symbolInput

                    anchors.fill: parent
                    anchors.margins: 6
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.text
                    selectionColor: WalColors.withAlpha(WalColors.color4, 0.4)
                    font.family: form.latin ? Theme.fontUi : form.host.picker.jp
                    font.pixelSize: text.length > 2 ? 16 : 22
                    maximumLength: 4
                    clip: true
                    onActiveFocusChanged: {
                        if (activeFocus)
                            form.lastField = symbolInput;

                    }
                    Keys.onPressed: (event) => {
                        return form.handleKey(event, symbolInput);
                    }

                    // Empty = suggestion (known character or the first two letters)
                    Text {
                        anchors.centerIn: parent
                        visible: symbolInput.text === ""
                        text: form.autoMark !== "" ? form.autoMark : "あ"
                        color: Theme.textFaint
                        font: symbolInput.font
                    }

                }

            }

            // Image strip: first tile = no image, then the newest images
            ListView {
                id: strip

                x: symbolBox.width + 14
                y: symbolBox.y - 4
                width: parent.width - x
                height: symbolBox.height + 8
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                // Room for the ring + enlargement of the chosen tile
                leftMargin: 4
                rightMargin: 4
                boundsBehavior: Flickable.StopAtBounds
                model: form.images.length + 1
                onActiveFocusChanged: {
                    if (activeFocus)
                        form.lastField = strip;

                }
                Keys.onPressed: (event) => {
                    const key = PickerManager.navKey(event);
                    if (key === Qt.Key_Left || key === Qt.Key_H) {
                        form.selectImage(form.imageIndex - 1);
                        event.accepted = true;
                    } else if (key === Qt.Key_Right || key === Qt.Key_L) {
                        form.selectImage(form.imageIndex + 1);
                        event.accepted = true;
                    } else if (key === Qt.Key_B && !(event.modifiers & Qt.ControlModifier)) {
                        // B as in the editors: folder browser
                        form.browse();
                        event.accepted = true;
                    } else {
                        form.handleKey(event, strip);
                    }
                }

                // The strip has the focus: subtle frame, so it is clear where the arrows go
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    radius: 18
                    color: "transparent"
                    border.width: 1
                    border.color: WalColors.withAlpha(WalColors.color4, 0.35)
                    visible: strip.activeFocus
                }

                // The mouse wheel scrolls horizontally
                WheelHandler {
                    onWheel: (event) => {
                        strip.contentX = Math.max(strip.originX - strip.leftMargin, Math.min(strip.originX + strip.contentWidth - strip.width + strip.rightMargin, strip.contentX - event.angleDelta.y));
                    }
                }

                delegate: Item {
                    id: thumb

                    required property int index
                    readonly property int imgIndex: index - 1
                    readonly property bool chosen: form.imageIndex === imgIndex

                    width: 56
                    height: 56
                    y: 4
                    scale: chosen ? 1.05 : 1

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 14
                        color: Theme.tint(Theme.text, 0.06)

                        Image {
                            anchors.fill: parent
                            visible: thumb.imgIndex >= 0
                            source: thumb.imgIndex >= 0 ? LanguageAudioState.fileUrl(form.images[thumb.imgIndex].path) : ""
                            asynchronous: true
                            cache: false
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 112
                            sourceSize.height: 112
                        }

                        // "No image": crossed-out circle
                        Text {
                            anchors.centerIn: parent
                            visible: thumb.imgIndex < 0
                            text: String.fromCodePoint(0xF05E)
                            font.family: Theme.font
                            font.pixelSize: 20
                            color: Theme.textFaint
                        }

                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: "transparent"
                        border.width: 2
                        border.color: WalColors.color4
                        visible: thumb.chosen
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: form.imageIndex = thumb.imgIndex
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

            Text {
                anchors.left: strip.left
                anchors.leftMargin: 64 + 12
                anchors.verticalCenter: strip.verticalCenter
                visible: form.images.length === 0
                text: "No recent images, use Browse"
                color: Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
            }

            // ── Hint + buttons ──
            Text {
                anchors.left: parent.left
                anchors.right: buttons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: buttons.verticalCenter
                elide: Text.ElideMiddle
                text: form.error !== "" ? form.error : form.image !== "" ? "Image: " + form.images[form.imageIndex].name : Settings.shortPath(LanguageAudioState.languagesRoot) + "/" + (form.cleanName !== "" ? form.cleanName : "…")
                color: form.error !== "" ? WalColors.color1 : Theme.textFaint
                font.family: Theme.fontUi
                font.pixelSize: Theme.sizeSmall
            }

            Row {
                id: buttons

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 8

                Repeater {
                    model: [{
                        "label": "Cancel",
                        "primary": false
                    }, {
                        "label": "Create",
                        "primary": true
                    }]

                    delegate: Rectangle {
                        id: btn

                        required property var modelData

                        width: btnText.implicitWidth + 32
                        height: 36
                        radius: height / 2
                        color: modelData.primary ? WalColors.withAlpha(WalColors.color4, btnArea.containsMouse ? 0.95 : 0.8) : Theme.tint(Theme.text, btnArea.containsMouse ? 0.1 : 0.06)
                        opacity: modelData.primary && form.cleanName === "" ? 0.5 : 1

                        Text {
                            id: btnText

                            anchors.centerIn: parent
                            text: btn.modelData.label
                            color: btn.modelData.primary ? WalColors.color0 : Theme.text
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.sizeBody
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: btnArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: btn.modelData.primary ? form.submit() : form.cancel()
                        }

                    }

                }

            }

        }

    }

}
