import QtQuick
pragma Singleton

QtObject {
    readonly property QtObject
    anim: QtObject {
        readonly property QtObject
        durations: QtObject {
            readonly property int fast: 150
            readonly property int normal: 300
            readonly property int slow: 500
            // MD3 Expressive (values as in the Caelestia shell)
            readonly property int expressiveFastSpatial: 350
            readonly property int expressiveDefaultSpatial: 500
            readonly property int expressiveSlowSpatial: 650
            readonly property int expressiveDefaultEffects: 200
            // Length of curves.spring (the curve is normalized to this duration)
            readonly property int spring: 700
            readonly property int springSoft: 520
        }
        // Material Design 3 motion curves (official values)

        readonly property QtObject
        curves: QtObject {
            readonly property var standard: [0.2, 0, 0, 1, 1, 1]
            readonly property var standardDecelerate: [0, 0, 0, 1, 1, 1]
            readonly property var standardAccelerate: [0.3, 0, 1, 1, 1, 1]
            readonly property var emphasized: [0.3, 0, 0.8, 0.15, 0.2, 1, 0.4, 0.99, 1, 1]
            readonly property var emphasizedDecelerate: [0.05, 0.7, 0.1, 1, 1, 1]
            // House curves of the pickers: outQuint = fast start, long and soft ending (fade in, glide),
            // inOutSoft = soft start and end (spacing in the bar), accelerate = fade out
            readonly property var outQuint: [0.22, 1, 0.36, 1, 1, 1]
            readonly property var inOutSoft: [0.385, 0, 0.415, 1, 1, 1]
            readonly property var accelerate: [0.4, 0, 1, 1, 1, 1]
            // MD3 Expressive "Spatial": second control point > 1 -> slight overshoot (bounce)
            // for movement/size. "Effects" without overshoot for opacity/color.
            readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
            readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
            readonly property var expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
            readonly property var expressiveDefaultEffects: [0.34, 0.8, 0.34, 1, 1, 1]
            // iOS-like opening spring: a real damped spring (damping ratio 0.62) sampled into Hermite
            // segments. Peaks at ~10 % overshoot at 35 %, then settles calmly without a second visible wobble.
            // Meant for a scale multiplier from ~0.88 (window pop), use with durations.spring.
            // Softer spring (damping ratio 0.72, ~3.8 % overshoot) for small popups that grow from far
            // (e.g. scale 0.2 -> 1: one gentle ~3 % swell). Use with durations.springSoft.
            readonly property var springSoft: [0.0267, 0, 0.0533, 0.101, 0.08, 0.2149, 0.1133, 0.3572, 0.1467, 0.5195, 0.18, 0.6442, 0.22, 0.7938, 0.26, 0.8941, 0.3, 0.9521, 0.35, 1.0245, 0.4, 1.0379, 0.45, 1.0384, 0.5067, 1.039, 0.5633, 1.0242, 0.62, 1.0155, 0.68, 1.0064, 0.74, 1.0017, 0.8, 0.9998, 0.8667, 0.9978, 0.9333, 1, 1, 1]
            readonly property var spring: [0.0267, 0, 0.0533, 0.1458, 0.08, 0.2997, 0.1133, 0.492, 0.1467, 0.6943, 0.18, 0.8269, 0.22, 0.986, 0.26, 1.0551, 0.3, 1.0755, 0.35, 1.1011, 0.4, 1.0647, 0.45, 1.0408, 0.5067, 1.0137, 0.5633, 0.9981, 0.62, 0.9944, 0.68, 0.9905, 0.74, 0.995, 0.8, 0.9972, 0.8667, 0.9997, 0.9333, 1, 1, 1]
        }

    }

}
