import "../../services"
import QtQuick

// Row that expands and collapses softly (rōmaji / German below a sentence)
Item {
    id: rev

    required property var picker

    property bool shown: false
    property alias text: revText.text
    property alias pixelSize: revText.font.pixelSize
    property alias color: revText.color
    property alias family: revText.font.family
    property real k: shown ? 1 : 0

    width: parent ? parent.width : 0
    // Not rounded: rounded heights of many paragraphs added up to uneven jumps of the
    // text below. At the end (k = 0/1) the height is an integer anyway.
    // Never exactly 0 and never invisible: columns (Column) leave out elements with height 0 together with the spacing
    // before them - the text below then jumped by this spacing at the end of collapsing (and at the start of expanding)
    // (e.g. 4 px below the chapter title). 0.01 px draws nothing.
    height: Math.max(0.01, (revText.implicitHeight + 4) * k)
    clip: true

    Text {
        id: revText

        y: 2
        width: parent.width
        wrapMode: Text.Wrap
        font.family: picker.mono
        opacity: rev.k
    }

    // Soft start and end: the text below shifts, the eye should be able to follow that.
    // (Smooth/outQuint put almost the whole movement into the first two frames -> felt like a jump)
    Behavior on k {
        NumberAnimation {
            duration: 340
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.anim.curves.inOutSoft
        }

    }

}
