import "../services"
import QtQuick

// Default glide of the pickers: fast start, long and soft ending
NumberAnimation {
    duration: 320
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.anim.curves.outQuint
}
