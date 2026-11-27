import "../services"
import QtQuick

// A text that changes softly: the old one drifts up a little and fades while the new one rises into
// place, both at the same time. For values that change in place (a number, a word, a label), where
// counting or cutting would look restless. The font is set through `font` like on a Text.
// A change while one is still running carries on from what is on screen: the text that was coming in
// leaves from where it is and as bright as it is. Starting the old text again at full brightness made
// quick changes (moving the pointer over several days) flicker.
Item {
    id: cross

    property string text: ""
    property color color: Theme.text
    property alias font: now.font
    property int horizontalAlignment: Text.AlignLeft
    // How far the two travel, as a share of the text height
    property real travel: 0.28
    property int duration: 420
    property string current: ""
    property string previous: ""
    property real t: 1
    // Where the leaving text starts: its brightness and its offset (share of the height)
    property real prevFrom: 1
    property real prevShift: 0
    // The first text is simply there, only later ones change softly
    property bool ready: false

    implicitWidth: now.implicitWidth
    implicitHeight: now.implicitHeight
    Component.onCompleted: {
        current = text;
        ready = true;
    }
    onTextChanged: {
        if (!ready || text === current)
            return ;

        // The text on screen leaves from where it is now
        prevFrom = anim.running ? Math.min(1, t * 1.15) : 1;
        prevShift = anim.running ? travel * (1 - t) : 0;
        anim.stop();
        previous = current;
        current = text;
        anim.start();
    }

    Text {
        width: parent.width
        y: cross.height * (cross.prevShift - cross.travel * 0.6 * cross.t)
        text: cross.previous
        color: cross.color
        // Gone a little before the new one is fully there, so the two never read as one blur
        opacity: cross.prevFrom * Math.max(0, 1 - cross.t * 1.5)
        visible: opacity > 0.01
        elide: Text.ElideRight
        horizontalAlignment: cross.horizontalAlignment
        font: now.font
    }

    Text {
        id: now

        width: parent.width
        y: cross.height * cross.travel * (1 - cross.t)
        text: cross.current
        color: cross.color
        opacity: Math.min(1, cross.t * 1.15)
        elide: Text.ElideRight
        horizontalAlignment: cross.horizontalAlignment
        font.family: Theme.fontUi
    }

    // A calm curve: no hurried start, a long soft landing
    NumberAnimation {
        id: anim

        target: cross
        property: "t"
        from: 0
        to: 1
        duration: cross.duration
        easing.type: Easing.OutQuart
    }

}
