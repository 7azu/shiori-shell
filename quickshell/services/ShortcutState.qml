pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    property string status: "loading"
    property bool refreshPending: false
    readonly property var categories: ["Quickshell", "Apps", "Windows", "Workspaces", "Media"]
    readonly property var modifiers: [
        [64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"],
        [2, "Caps Lock"], [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]
    ]
    readonly property var keyNames: ({
        "space": "Space",
        "return": "Enter",
        "escape": "Esc",
        "prior": "Page Up",
        "next": "Page Down",
        "mouse:272": "Left Click",
        "mouse:273": "Right Click",
        "mouse:274": "Middle Click",
        "mouse_up": "Scroll Up",
        "mouse_down": "Scroll Down",
        "xf86audionext": "Media Next",
        "xf86audioprev": "Media Previous",
        "xf86audioplay": "Media Play",
        "xf86audiopause": "Media Pause",
        "xf86audiomute": "Mute",
        "xf86audioraisevolume": "Volume Up",
        "xf86audiolowervolume": "Volume Down",
        "slash": "/",
        "minus": "−",
        "equal": "=",
        "comma": ",",
        "period": ".",
        "plus": "+",
        "semicolon": ";",
        "apostrophe": "'",
        "backslash": "\\",
        "bracketleft": "[",
        "bracketright": "]",
        "grave": "`",
        "less": "<",
        "numbersign": "#",
        "adiaeresis": "Ä",
        "odiaeresis": "Ö",
        "udiaeresis": "Ü",
        "ssharp": "ß",
        "backspace": "Backspace",
        "kp_enter": "Enter",
        "left": "←",
        "right": "→",
        "up": "↑",
        "down": "↓"
    })

    function refresh() {
        if (reader.running) {
            refreshPending = true;
            return;
        }

        status = "loading";
        reader.running = true;
        loadTimeout.restart();
    }

    function normalizeKey(key) {
        const token = key.toLowerCase();
        if (token === "control")
            return "ctrl";
        if (token === "meta" || token === "win")
            return "super";

        return token;
    }

    function displayKey(raw) {
        const name = keyNames[raw.toLowerCase()];
        if (typeof name === "string")
            return name;

        return raw.charAt(0).toUpperCase() + raw.slice(1);
    }

    // Natural order: numbers as numbers ("workspace 2" before "workspace 10"), otherwise case-insensitive
    function naturalCompare(a, b) {
        const left = String(a).toLowerCase().split(/(\d+)/);
        const right = String(b).toLowerCase().split(/(\d+)/);
        for (let i = 0; i < Math.min(left.length, right.length); ++i) {
            if (left[i] === right[i])
                continue;
            // Odd parts are the numbers (split with a group keeps the separators)
            if (i % 2 === 1)
                return parseInt(left[i], 10) - parseInt(right[i], 10);

            return left[i] < right[i] ? -1 : 1;
        }
        return left.length - right.length;
    }

    function categoryRank(category) {
        const index = categories.indexOf(category);
        return index < 0 ? categories.length : index;
    }

    function formatBindings(bindings) {
        if (!Array.isArray(bindings))
            throw new Error("Expected a list of Hyprland bindings");

        const rows = [];
        for (const bind of bindings) {
            if (!bind || typeof bind.modmask !== "number")
                continue;

            const raw = String(bind.key || "");
            const keys = modifiers.filter(modifier => bind.modmask & modifier[0]).map(modifier => modifier[1]);
            const key = raw ? displayKey(raw) : bind.keycode > 0 ? "Code " + bind.keycode : bind.catch_all ? "Any key" : "";
            if (key)
                keys.push(key);
            if (keys.length === 0)
                continue;

            const description = String(bind.description || "").trim();
            const split = description.indexOf(": ");
            const category = split >= 0 ? description.slice(0, split) : "Other";
            const dispatcher = String(bind.dispatcher || "");
            const fallback = dispatcher && dispatcher !== "__lua"
                ? displayKey(dispatcher.replace(/_/g, " ")) : "Unnamed shortcut";
            const title = (split >= 0 ? description.slice(split + 2) : description) || fallback;
            const submap = String(bind.submap || "");
            const context = submap && submap !== "default" && submap !== "reset" ? category + " · " + submap : category;
            const combo = keys.join(" + ");
            const keyTokens = keys.concat(raw).map(root.normalizeKey);

            rows.push({
                "title": title,
                "context": context,
                "category": category,
                "keys": keys,
                "keyTokens": keyTokens,
                "combo": combo,
                "search": [title, context, combo, raw].join(" ").toLowerCase()
            });
        }

        // Section (fixed order), within it by title; same title (e.g. Focus left with H and with the arrow):
        // the shorter shortcut first
        return rows.sort((a, b) => root.categoryRank(a.category) - root.categoryRank(b.category)
            || root.naturalCompare(a.category, b.category)
            || root.naturalCompare(a.context, b.context)
            || root.naturalCompare(a.title, b.title)
            || a.keys.length - b.keys.length
            || root.naturalCompare(a.combo, b.combo));
    }

    function search(query) {
        const terms = query.trim().toLowerCase().replace(/\s*\+\s*/g, "+").split(/\s+/).filter(Boolean);
        return entries.filter(entry => terms.every(term => {
            if (!term.includes("+"))
                return entry.search.includes(term) || entry.keyTokens.includes(root.normalizeKey(term));

            const keys = term.split("+").filter(Boolean).map(root.normalizeKey);
            return keys.length > 0 && keys.every(key => entry.keyTokens.includes(key));
        }));
    }

    Process {
        id: reader

        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { id: output }

        onExited: (code) => {
            loadTimeout.stop();
            try {
                if (code !== 0)
                    throw new Error("hyprctl failed");

                root.entries = root.formatBindings(JSON.parse(output.text));
                root.status = "ready";
            } catch (_) {
                root.entries = [];
                root.status = "error";
            }

            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Timer {
        id: loadTimeout

        interval: 5000
        onTriggered: reader.running = false
    }

    Connections {
        target: Hyprland
        enabled: PickerManager.isOpen("shortcuts")
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.refresh();
        }
    }
}
