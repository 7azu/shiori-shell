import QtQuick
import Quickshell
import Quickshell.Io

pragma Singleton

QtObject {
    id: root

    signal colorsUpdated()

    // Until pywal has run (fresh install): the default palette wal/colorschemes/dark/shiori.json
    property string color0: "#16161e"
    property string color1: "#f7768e"
    property string color2: "#9ece6a"
    property string color3: "#e0af68"
    property string color4: "#7aa2f7"
    property string color5: "#bb9af7"
    property string color6: "#7dcfff"
    property string color7: "#c0caf5"
    property string color8: "#414868"
    property string color9: "#f7768e"
    property string color10: "#9ece6a"
    property string color11: "#e0af68"
    property string color12: "#7aa2f7"
    property string color13: "#bb9af7"
    property string color14: "#7dcfff"
    property string color15: "#c0caf5"

    // Strong accent color for small colored details (tray icon, Claude logo; same rule in the
    // cursor script ~/.config/wal/cursor/gen-cursor.sh): the strongest color from color1..6 whose
    // lightness is close to 0.6. Fixed roles (Theme.accent = color4) are gray with desaturated
    // palettes, colors that are too dark or too light get lost on the bar.
    // During a color change (fadeTo): do NOT choose again from the mixed colors - the "strongest" jumped
    // back and forth between the slots (the Claude logo in the bar changed color abruptly). Instead
    // determine the strongest of the old and the target palette and mix softly in the same steps
    // (for an opaque icon the same as an opacity crossfade of two copies).
    readonly property string vividAccent: fadeAnim.running && fadeStep >= 0 && fadeFrom.color1 && fadeTarget.color1 ? mixHex(vividOf(slotsOf(fadeFrom)), vividOf(slotsOf(fadeTarget)), fadeStep / fadeSteps) : vividOf([color1, color2, color3, color4, color5, color6])

    function slotsOf(p) {
        return [p.color1, p.color2, p.color3, p.color4, p.color5, p.color6];
    }

    // The same rule for any list (color1..6 of a palette), e.g. for the target palette
    // of a wallpaper change (DesktopVisualizer fades over old and new palette)
    function vividOf(cs) {
        let best = cs[0], bestScore = -1;
        for (const c of cs) {
            const q = Qt.color(c);
            const score = q.hslSaturation * (1 - Math.abs(q.hslLightness - 0.6));
            if (score > bestScore) {
                bestScore = score;
                best = c;
            }
        }
        return best;
    }

    property FileView fileView: FileView {
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        // Missing before the first wallpaper: the default palette above stays
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: jsonAdapter
            property var colors: ({})

            onColorsChanged: {
                // The first pass at start arrives without colors. Before, this immediately became the
                // fallback palette below (blue) and only the second pass faded to the real palette in 0.6 s.
                // In the lock screen this fade only started on a redraw (mouse moved)
                // -> blue flash. So ignore an empty palette: the real one applies right away on the first load.
                if (!colors || !colors.color0)
                    return;

                const d = {"color0": "#1a1b26", "color1": "#7aa2f7", "color2": "#9ece6a", "color3": "#e0af68",
                    "color4": "#7aa2f7", "color5": "#bb9af7", "color6": "#7dcfff"};
                const next = {};
                for (const k of root.keys)
                    next[k] = colors?.[k] ?? d[k] ?? "#c0caf5";
                // If the wallpaper transition already faded in the palette in advance, this is
                // the same -> do nothing. Otherwise fade softly: during the transition in sync with the wave,
                // without it (e.g. theme setup) in 0.6 s. Only the very first load at start is instant.
                const ms = WallpaperTransition.active ? WallpaperTransition.colorFadeMs() : 600;
                root.fadeTo(next, root.loadedOnce ? ms : 0);
                root.loadedOnce = true;
            }
        }
    }

    // ==== Soft crossfade to a new palette (wallpaper transition) ====
    // The colors stay strings (well over 1000 places use them that way); while fading they are set
    // again in steps (~22/s), not per frame: every change re-evaluates all dependent bindings.
    readonly property var keys: ["color0", "color1", "color2", "color3", "color4", "color5", "color6", "color7",
        "color8", "color9", "color10", "color11", "color12", "color13", "color14", "color15"]
    property bool loadedOnce: false
    property var fadeFrom: ({})
    property var fadeTarget: ({})
    property real fadeT: 1
    property int fadeSteps: 1
    property int fadeStep: -1

    property NumberAnimation fadeAnim: NumberAnimation {
        target: root
        property: "fadeT"
        from: 0
        to: 1
        easing.type: Easing.InOutQuad
        onFinished: root.colorsUpdated()
    }

    onFadeTChanged: {
        const step = Math.round(fadeT * fadeSteps);
        if (step === fadeStep)
            return;
        fadeStep = step;
        const t = step / fadeSteps;
        for (const k of keys)
            root[k] = mixHex(fadeFrom[k] || root[k], fadeTarget[k] || root[k], t);
    }

    // Fade to the palette `colors` ({"color0": "#...", ...}); ms <= 0 = instantly
    function fadeTo(colors, ms) {
        // Already on the way there or there: do nothing (otherwise the fade would start over)
        if (keys.every((k) => (fadeTarget[k] || root[k]).toLowerCase() === String(colors[k]).toLowerCase()))
            return;
        const from = {};
        for (const k of keys)
            from[k] = root[k];
        fadeFrom = from;
        fadeTarget = colors;
        fadeAnim.stop();
        if (!(ms > 0)) {
            for (const k of keys)
                root[k] = colors[k];
            fadeT = 1;
            colorsUpdated();
            return;
        }
        fadeSteps = Math.max(6, Math.round(ms / 45));
        fadeStep = -1;
        fadeAnim.duration = ms;
        fadeAnim.start();
    }

    function mixHex(a, b, t) {
        const pa = parseInt(String(a).replace("#", "").slice(-6), 16);
        const pb = parseInt(String(b).replace("#", "").slice(-6), 16);
        if (isNaN(pa) || isNaN(pb))
            return t < 0.5 ? a : b;
        let out = "#";
        for (const shift of [16, 8, 0]) {
            const ca = (pa >> shift) & 255, cb = (pb >> shift) & 255;
            out += Math.round(ca + (cb - ca) * t).toString(16).padStart(2, "0");
        }
        return out;
    }

    function withAlpha(hex, alpha) {
        if (hex === undefined || hex === null) return "#000000"
        var s = (typeof hex === "string") ? hex : hex.toString()
        if (s.charAt(0) === "#") s = s.slice(1)
        if (s.length === 8) s = s.slice(2)   // #aarrggbb → rrggbb
        if (s.length !== 6) return "#000000"
        var a = Math.round(alpha * 255).toString(16).padStart(2, '0')
        return "#" + a + s
    }
}
