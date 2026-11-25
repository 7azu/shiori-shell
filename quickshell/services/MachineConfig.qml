// Machine-specific state, deliberately separate from the repo.
// File (created on the first switch): ~/.config/quickshell-local/screens.json
//   { "barScreen": "DP-2", "uiScale": 1.0, "simpleAnimations": false }

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton

// - There is ALWAYS exactly ONE bar (barTargets gives max. 1 screen).
// - barScreenName is the wanted monitor. If it is not connected
//   (or empty), the leftmost available monitor is taken. The choice
//   is NOT overwritten then.
// - The state lives in memory (reactive right away); the file is only
//   read at start and written on a switch (no reload race).
Singleton {
    id: root

    property string barScreenName: ""
    property real uiScale: 1
    // Only crossfade instead of small movements (slide/rotate): on 60 Hz displays movements of
    // a few pixels look steppy, although every frame comes on time (laptop).
    property bool simpleAnimations: false
    property bool loaded: false
    readonly property string dir: {
        var base = Quickshell.env("XDG_CONFIG_HOME");
        if (!base)
            base = Quickshell.env("HOME") + "/.config";

        return base + "/quickshell-local";
    }
    readonly property string localFile: dir + "/screens.json"

    // Logical pixels (Hyprland already scales) with an optional fine-tuning factor.
    function px(v) {
        return Math.round(v * uiScale);
    }

    // Screens from left to right (then top to bottom)
    function sortedScreens(all) {
        var list = [];
        for (var i = 0; i < all.length; ++i) list.push(all[i])
        list.sort(function(a, b) {
            return (a.x - b.x) || (a.y - b.y);
        });
        return list;
    }

    // The one screen the bar sits on right now
    function activeBarScreen(all) {
        var list = sortedScreens(all);
        if (list.length === 0)
            return null;

        for (var i = 0; i < list.length; ++i) {
            if (list[i].name === barScreenName)
                return list[i];

        }
        return list[0];
    }

    // For Variants.model: always at most one entry
    // (empty until the file has been read -> no flicker on the wrong monitor)
    function barTargets(all) {
        if (!loaded)
            return [];

        var s = activeBarScreen(all);
        return s ? [s] : [];
    }

    // Move the bar to the next (+1) or previous (-1) monitor
    function moveBar(all, step) {
        var list = sortedScreens(all);
        if (list.length < 2)
            return ;

        var cur = activeBarScreen(all);
        var idx = 0;
        for (var i = 0; i < list.length; ++i) {
            if (cur && list[i].name === cur.name)
                idx = i;

        }
        var next = list[(idx + step + list.length) % list.length];
        setBarScreen(next.name);
    }

    // Put the bar on a specific monitor (e.g. from the monitor panel)
    function setBarScreen(name) {
        if (!name || name === barScreenName)
            return ;

        console.log("MachineConfig: bar", barScreenName || "?", "->", name);
        barScreenName = name;
        save();
    }

    // Screen of the currently focused Hyprland monitor (for pickers/overlays).
    function focusedScreen() {
        var all = Quickshell.screens;
        var m = Hyprland.focusedMonitor;
        if (m) {
            for (var i = 0; i < all.length; ++i) {
                if (all[i].name === m.name)
                    return all[i];

            }
        }
        return all.length > 0 ? all[0] : null;
    }

    function applyRaw(raw) {
        var cfg = {
        };
        try {
            cfg = JSON.parse(raw && raw.length > 0 ? raw : "{}");
        } catch (e) {
            console.warn("MachineConfig: screens.json invalid:", e);
        }
        barScreenName = (typeof cfg.barScreen === "string") ? cfg.barScreen : "";
        var s = Number(cfg.uiScale);
        uiScale = (s > 0.25 && s < 4) ? s : 1;
        simpleAnimations = cfg.simpleAnimations === true;
        loaded = true;
        chooseFirstScreen();
    }

    // First start (no screens.json yet): the bar goes to the monitor in use (focused), not just the
    // leftmost one, and stays there. Later the monitor panel moves it.
    function chooseFirstScreen() {
        if (!loaded || barScreenName !== "" || !Hyprland.focusedMonitor)
            return ;

        console.log("MachineConfig: first start, bar on", Hyprland.focusedMonitor.name);
        barScreenName = Hyprland.focusedMonitor.name;
        save();
    }

    // At startup Hyprland may not know the focused monitor yet
    property Connections firstScreenWatch: Connections {
        function onFocusedMonitorChanged() {
            root.chooseFirstScreen();
        }

        target: Hyprland
    }

    function save() {
        cfgFile.setText(JSON.stringify({
            "barScreen": barScreenName,
            "uiScale": uiScale,
            "simpleAnimations": simpleAnimations
        }, null, 2) + "\n");
    }

    // Create the folder, so saving works
    Process {
        command: ["mkdir", "-p", root.dir]
        running: true
    }

    FileView {
        id: cfgFile

        path: root.localFile
        printErrors: false
        onLoaded: root.applyRaw(text())
        onLoadFailed: root.applyRaw("")
    }

}
