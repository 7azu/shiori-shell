import "../../common"
import "../../services"
import "../parts"
import QtQuick

// Header of a language: back + its name (own name big, English name small next to it), on the right today's
// listening time as a small ring (click = stats); below it the search field and the tabs Listen/Read/Stats.
// The keys of the search field are handled by the core (picker.handleKey).
// Part of LanguagePicker.qml (picker = core).
Item {
    id: header

    required property var picker
    property alias searchInput: searchInput

    width: parent.width
    height: header.picker.choosing ? 0 : header.picker.headH
    opacity: header.picker.choosing ? 0 : 1
    visible: height > 0.5
    clip: true

    Behavior on height {
        Smooth {
            duration: 420
        }

    }

    // Title row: back + name of the language (native name big, English name small next to it),
    // on the right today's listening time as a small ring (click = stats)
    Item {
        id: titleRow

        width: parent.width
        height: header.picker.titleH

        Rectangle {
            id: backBtn

            // Flush with the search field: the header clips (for its height animation), at x: -4 the
            // left edge of the round hover pill was cut off
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: height / 2
            color: backMouse.containsMouse ? Theme.glassHover : WalColors.withAlpha(WalColors.color7, 0)
            scale: backMouse.pressed ? 0.9 : 1

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                text: String.fromCodePoint(0xF053)
                color: backMouse.containsMouse ? Theme.text : Theme.textDim
                font.family: Theme.font
                font.pixelSize: 12
            }

            MouseArea {
                id: backMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: header.picker.backToChooser()
            }

            Behavior on color {
                ColorAnimation {
                    duration: 140
                }

            }

            Behavior on scale {
                Springy {
                }

            }

        }

        Text {
            id: langTitle

            readonly property string nativeName: LanguageAudioState.nativeOf(LanguageAudioState.language)

            anchors.left: backBtn.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: nativeName !== "" ? nativeName : LanguageAudioState.language
            color: Theme.text
            // Latin names in the serif (like the shell's big titles), otherwise a font with the characters
            font.family: /^[\u0000-\u024F\s]+$/.test(text) ? Theme.fontDisplay : header.picker.jp
            font.pixelSize: 24
            font.weight: /^[\u0000-\u024F\s]+$/.test(text) ? Font.Normal : Font.Medium
        }

        Text {
            anchors.left: langTitle.right
            anchors.leftMargin: 12
            anchors.baseline: langTitle.baseline
            visible: langTitle.nativeName !== ""
            text: LanguageAudioState.language.toUpperCase()
            color: Theme.textFaint
            font.family: Theme.fontUi
            font.pixelSize: Theme.sizeMicro
            font.weight: Font.DemiBold
            font.letterSpacing: Theme.microSpacing
        }

        Row {
            id: today

            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            opacity: todayMouse.containsMouse ? 1 : 0.85

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    anchors.right: parent.right
                    text: Math.floor(header.picker.listenStats.todayMinutes) + " / " + Math.round(header.picker.listenStats.dailyGoal) + " min"
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeBody
                    font.weight: Font.Medium
                    font.features: Theme.tabular
                }

                Text {
                    anchors.right: parent.right
                    text: header.picker.listenStats.streak > 1 ? header.picker.listenStats.streak + "-DAY STREAK" : "TODAY"
                    color: Theme.textFaint
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.sizeMicro
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.microSpacing
                }

            }

            ProgressRing {
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                thickness: 3
                color: Theme.accent
                trackColor: Theme.track
                value: Math.min(1, header.picker.listenStats.todayMinutes / header.picker.listenStats.dailyGoal)
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }

            }

        }

        MouseArea {
            id: todayMouse

            anchors.fill: today
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: header.picker.filter = "stats"
        }

    }

    SearchField {
        id: searchInput

        anchors.left: parent.left
        anchors.right: segmented.left
        anchors.rightMargin: 10
        y: header.picker.titleH + header.picker.headGap
        height: header.picker.fieldH
        placeholder: header.picker.filter === "read" ? (LanguageAudioState.isJapanese ? "Filter books · Enter: ISBN / Aozora" : "Filter books") : header.picker.filter === "stats" ? "Search files · Enter: YouTube" : "Search · Enter: YouTube · paste link"
        placeholderElide: true
        focusOnStart: false
        text: header.picker.searchQuery
        onTextChanged: {
            header.picker.searchQuery = text;
            // Typing changes the list -> reset the keyboard selection
            header.picker.kbIndex = -1;
            // Keep typing after a YouTube search -> back to the file search
            if (LanguageDownloadState.lastQuery !== "" && text !== LanguageDownloadState.lastQuery)
                LanguageDownloadState.clearSearch();

            if (text !== "" && header.picker.filter !== "read")
                header.picker.filter = "library";

            if (text === "" && header.picker.filter === "read")
                LanguageReadingState.clearResults();

        }
        onAccepted: {
            if (text === "")
                return ;

            if (header.picker.filter === "read")
                LanguageReadingState.search(text);
            else
                LanguageDownloadState.downloadFromInput(text);
        }
        onKeyPressed: (event) => {
            return header.picker.handleKey(event);
        }
    }

    PillSegmented {
        id: segmented

        anchors.right: parent.right
        y: header.picker.titleH + header.picker.headGap
        height: header.picker.fieldH
        segW: 76
        current: header.picker.filter
        options: header.picker.tabKeys.map((k) => {
            return {
                "label": k === "library" ? "Listen" : k === "read" ? "Read" : "Stats",
                "key": k
            };
        })
        onPicked: (key) => {
            header.picker.filter = key;
        }
    }

}
