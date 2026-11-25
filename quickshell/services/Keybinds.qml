pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Changeable keybindings for the settings window (Shortcuts page).
//
// Hyprland's config (hypr/modules/keys.lua) is the one place that describes them: it gives every
// binding a name and a default and writes what is bound now to
// $XDG_RUNTIME_DIR/shiori-shell-keybinds.json. This service reads that list and turns it into rows.
// A change goes to ~/.config/shiori-shell/settings.json ("keys": { "mod": ..., "binds": { name: keys } },
// only what differs from the default) and Hyprland reloads, which writes the list again.
//
// Keys are texts as hl.bind takes them: "SUPER + SHIFT + M". "" means: not bound.
//
// Capturing: captureId names the row waiting for a key press. settings/SettingsView sends all keys
// here meanwhile, settings/SettingsWindow asks Hyprland to hold its own shortcuts back.
Singleton {
    id: root

    readonly property string listFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shiori-shell-keybinds.json"
    // [{ id?, description: "Group: what it does", default, keys, fixed?, error? }] in the order of the config
    property var binds: []
    // false: Hyprland has not written the list (not reloaded since the update, or another compositor)
    property bool known: false
    // Every binding Hyprland has right now, also private ones from other files: [{ combo, title }]
    property var live: []
    // Row waiting for keys ("" = none), the modifiers held meanwhile, and what to say about a key that
    // was not taken
    property string captureId: ""
    property var held: []
    property string notice: ""
    // A captured shortcut another changeable binding already has: { id, keys, other: { id, title } }.
    // Waits for Replace or Cancel.
    property var pending: null
    readonly property var modOrder: ["SUPER", "CTRL", "ALT", "SHIFT"]
    readonly property var modNames: ({
        "SUPER": "Super",
        "CTRL": "Ctrl",
        "ALT": "Alt",
        "SHIFT": "Shift"
    })
    // Groups of the page in this order; "Display" joins "Media"
    readonly property var groupOrder: ["Quickshell", "Apps", "Windows", "Workspaces", "Media"]
    readonly property var groupTitles: ({
        "Quickshell": "Shell",
        "Apps": "Apps",
        "Windows": "Windows",
        "Workspaces": "Workspaces",
        "Media": "Media and display keys"
    })
    // Qt key -> name Hyprland knows. Keys with a fixed name on every layout.
    readonly property var namedKeys: {
        const m = {
        };
        m[Qt.Key_Space] = "SPACE";
        m[Qt.Key_Return] = "Return";
        m[Qt.Key_Enter] = "KP_Enter";
        m[Qt.Key_Tab] = "Tab";
        m[Qt.Key_Backtab] = "Tab";
        m[Qt.Key_Backspace] = "BackSpace";
        m[Qt.Key_Delete] = "Delete";
        m[Qt.Key_Insert] = "Insert";
        m[Qt.Key_Home] = "Home";
        m[Qt.Key_End] = "End";
        m[Qt.Key_PageUp] = "Prior";
        m[Qt.Key_PageDown] = "Next";
        m[Qt.Key_Left] = "left";
        m[Qt.Key_Right] = "right";
        m[Qt.Key_Up] = "up";
        m[Qt.Key_Down] = "down";
        m[Qt.Key_Print] = "Print";
        m[Qt.Key_Pause] = "Pause";
        m[Qt.Key_Menu] = "Menu";
        m[Qt.Key_Escape] = "Escape";
        return m;
    }
    // Signs: only trusted without Shift. With Shift, Qt reports the sign the layout puts on top
    // (Shift + comma is "<" on one keyboard and ";" on another), and Hyprland wants the key itself.
    readonly property var signKeys: {
        const m = {
        };
        m[Qt.Key_Comma] = "comma";
        m[Qt.Key_Period] = "period";
        m[Qt.Key_Minus] = "minus";
        m[Qt.Key_Plus] = "plus";
        m[Qt.Key_Slash] = "slash";
        m[Qt.Key_Backslash] = "backslash";
        m[Qt.Key_Semicolon] = "semicolon";
        m[Qt.Key_Apostrophe] = "apostrophe";
        m[Qt.Key_BracketLeft] = "bracketleft";
        m[Qt.Key_BracketRight] = "bracketright";
        m[Qt.Key_QuoteLeft] = "grave";
        m[Qt.Key_Equal] = "equal";
        m[Qt.Key_Less] = "less";
        m[Qt.Key_NumberSign] = "numbersign";
        m[Qt.Key_Adiaeresis] = "adiaeresis";
        m[Qt.Key_Odiaeresis] = "odiaeresis";
        m[Qt.Key_Udiaeresis] = "udiaeresis";
        m[Qt.Key_ssharp] = "ssharp";
        return m;
    }
    // Keys that may stand alone, without a modifier
    readonly property var bareKeys: ["print", "pause", "menu"]
    // The page as SettingsState wants it: groups of rows
    readonly property var groups: {
        const out = [{
            "title": "General",
            "rows": [{
                "key": "settings:keys.mod",
                "label": "Main modifier",
                "desc": "The key every default shortcut starts with. Shortcuts you have set yourself keep their keys.",
                "type": "choice",
                "options": [{
                    "value": "SUPER",
                    "label": "Super"
                }, {
                    "value": "ALT",
                    "label": "Alt"
                }]
            }],
            "footer": known ? "" : "The list of shortcuts comes from Hyprland's config and is not there yet. Reload Hyprland once (hyprctl reload)."
        }];
        for (const g of groupOrder) {
            const rows = binds.filter((b) => {
                return groupOf(b) === g;
            }).map((b) => {
                return {
                    "key": b.id ? "keys:" + b.id : "",
                    "label": titleOf(b),
                    "desc": "",
                    "type": "key",
                    "fixed": b.fixed === true,
                    "keys": b.keys
                };
            });
            if (rows.length === 0)
                continue;

            out.push({
                "title": groupTitles[g],
                "rows": rows,
                "footer": rows.some((r) => {
                    return r.fixed;
                }) ? "Shortcuts without a frame are groups or special keys. They follow the main modifier and are not changed one by one." : ""
            });
        }
        return out;
    }

    // ---- reading the list ----
    function groupOf(b) {
        const i = b.description.indexOf(": ");
        const g = i >= 0 ? b.description.slice(0, i) : "Apps";
        return g === "Display" ? "Media" : (groupOrder.indexOf(g) >= 0 ? g : "Apps");
    }

    function titleOf(b) {
        const i = b.description.indexOf(": ");
        return i >= 0 ? b.description.slice(i + 2) : b.description;
    }

    function entry(id) {
        return binds.find((b) => {
            return b.id === id;
        }) || null;
    }

    function keysOf(id) {
        const e = entry(id);
        return e ? e.keys : "";
    }

    function defaultOf(id) {
        const e = entry(id);
        return e ? e.default : undefined;
    }

    // Keys Hyprland refused for this binding (a typo made by hand in settings.json); "" if none
    function errorOf(id) {
        const e = entry(id);
        return e && e.error ? e.error : "";
    }

    // ---- keys as text ----
    // "SUPER + shift + m" -> { mods: ["SUPER", "SHIFT"], key: "m" }
    function parts(keys) {
        const mods = [];
        let key = "";
        for (const raw of String(keys).split("+")) {
            const t = raw.trim();
            if (t === "")
                continue;

            const up = t.toUpperCase();
            if (up === "SUPER" || up === "WIN" || up === "LOGO" || up === "META" || up === "MOD4")
                mods.push("SUPER");
            else if (up === "CTRL" || up === "CONTROL")
                mods.push("CTRL");
            else if (up === "ALT" || up === "MOD1")
                mods.push("ALT");
            else if (up === "SHIFT")
                mods.push("SHIFT");
            else
                key = t;
        }
        return {
            "mods": modOrder.filter((m) => {
                return mods.indexOf(m) >= 0;
            }),
            "key": key
        };
    }

    // The same shortcut always gives the same text, however it was written
    function norm(keys) {
        const p = parts(keys);
        return p.key === "" ? "" : p.mods.join("+") + "+" + p.key.toLowerCase();
    }

    function join(mods, key) {
        return mods.concat([key]).join(" + ");
    }

    // Labels for the key caps: ["Super", "Shift", "M"]
    function caps(keys) {
        const p = parts(keys);
        const out = p.mods.map((m) => {
            return modNames[m];
        });
        if (p.key !== "")
            out.push(p.key.toLowerCase().startsWith("code:") ? "Key " + p.key.slice(5) : ShortcutState.displayKey(p.key));

        return out;
    }

    // ---- who has a shortcut ----
    // The changeable binding (other than exceptId) or any other live binding on these keys; null if free.
    // { id, title } for a changeable one, { id: "", title } for one that cannot be changed here.
    function ownerOf(keys, exceptId) {
        const n = norm(keys);
        if (n === "")
            return null;

        const mine = binds.find((b) => {
            return b.id && b.id !== exceptId && norm(b.keys) === n;
        });
        if (mine)
            return {
                "id": mine.id,
                "title": titleOf(mine)
            };

        // The binding itself is in the live list too, under its current keys
        if (norm(keysOf(exceptId)) === n)
            return null;

        const other = live.find((b) => {
            return b.combo === n;
        });
        return other ? {
            "id": "",
            "title": other.title
        } : null;
    }

    // ---- changing ----
    // Called by SettingsState.write (store "keys"): remembers the change and lets Hyprland reload
    function set(id, keys) {
        const e = entry(id);
        if (!e)
            return ;

        Settings.set("keys.binds." + id, keys === e.default ? undefined : keys);
        // Shown at once; the list Hyprland writes after the reload then only confirms it
        binds = binds.map((b) => {
            return b.id === id ? Object.assign({
            }, b, {
                "keys": keys,
                "error": ""
            }) : b;
        });
        reload();
    }

    function reload() {
        reloadSoon.restart();
    }

    // ---- capturing ----
    function startCapture(id) {
        pending = null;
        notice = "";
        held = [];
        captureId = id;
        giveUp.restart();
    }

    function cancel() {
        captureId = "";
        pending = null;
        notice = "";
        held = [];
        giveUp.stop();
    }

    function modsOf(modifiers) {
        const out = [];
        if (modifiers & Qt.MetaModifier)
            out.push("SUPER");

        if (modifiers & Qt.ControlModifier)
            out.push("CTRL");

        if (modifiers & Qt.AltModifier)
            out.push("ALT");

        if (modifiers & Qt.ShiftModifier)
            out.push("SHIFT");

        return out;
    }

    function isModifier(key) {
        return key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_AltGr || key === Qt.Key_Shift || key === Qt.Key_CapsLock || key === Qt.Key_NumLock;
    }

    // Name of the pressed key for Hyprland. scan = keycode as xkb counts (the "1" key is 10).
    function keyName(key, shift, scan) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            return String.fromCharCode(key);

        if (key >= Qt.Key_F1 && key <= Qt.Key_F24)
            return "F" + (key - Qt.Key_F1 + 1);

        // Number row: with Shift, Qt reports the sign above the number
        if (scan >= 10 && scan <= 19)
            return String((scan - 9) % 10);

        if (namedKeys[key] !== undefined)
            return namedKeys[key];

        if (!shift && signKeys[key] !== undefined)
            return signKeys[key];

        // Anything else by its position on the keyboard, which holds on every layout
        return scan > 0 ? "code:" + scan : "";
    }

    // A key press while a row is capturing. Esc cancels, Backspace or Delete alone take the shortcut away.
    function captureKey(key, modifiers, scan) {
        if (captureId === "")
            return ;

        giveUp.restart();
        const mods = modsOf(modifiers);
        if (isModifier(key)) {
            held = mods;
            return ;
        }
        if (mods.length === 0 && key === Qt.Key_Escape) {
            cancel();
            return ;
        }
        if (mods.length === 0 && (key === Qt.Key_Backspace || key === Qt.Key_Delete)) {
            take(captureId, "");
            return ;
        }
        const name = keyName(key, mods.indexOf("SHIFT") >= 0, scan);
        if (name === "") {
            notice = "This key has no name Hyprland could bind.";
            return ;
        }
        held = mods;
        // A plain key, or one with only Shift, is typing
        const real = mods.filter((m) => {
            return m !== "SHIFT";
        });
        if (real.length === 0 && !/^F\d+$/.test(name) && bareKeys.indexOf(name.toLowerCase()) < 0) {
            notice = "Add Super, Ctrl or Alt: a key alone would no longer type.";
            return ;
        }
        take(captureId, join(mods, name));
    }

    function keyReleased(modifiers) {
        if (captureId !== "")
            held = modsOf(modifiers);

    }

    // Try to give keys to a binding: free -> done, taken by a changeable one -> ask, taken by another -> say so
    function take(id, keys) {
        if (keys === keysOf(id)) {
            cancel();
            return ;
        }
        const owner = keys === "" ? null : ownerOf(keys, id);
        if (owner === null) {
            commit(id, keys);
            return ;
        }
        if (owner.id === "") {
            notice = "Taken by \"" + owner.title + "\", which cannot be changed here.";
            return ;
        }
        captureId = "";
        held = [];
        notice = "";
        giveUp.stop();
        pending = {
            "id": id,
            "keys": keys,
            "other": owner
        };
    }

    function commit(id, keys) {
        const e = entry(id);
        cancel();
        SettingsState.apply("keys:" + id, keys, e ? titleOf(e) : id);
    }

    // Replace: the other binding loses its shortcut. One step for Undo.
    function replace() {
        const p = pending;
        if (!p)
            return ;

        pending = null;
        const e = entry(p.id);
        const changes = [{
            "key": "keys:" + p.other.id,
            "old": keysOf(p.other.id)
        }, {
            "key": "keys:" + p.id,
            "old": keysOf(p.id)
        }];
        set(p.other.id, "");
        set(p.id, p.keys);
        SettingsState.pushUndo(e ? titleOf(e) : p.id, changes);
    }

    // What the row has to say below its name: { text, tone: "dim" | "warn" }; null for nothing
    function noteOf(id) {
        if (id === "")
            return null;

        if (captureId === id)
            return {
                "text": notice !== "" ? notice : "Press the new shortcut. Esc cancels, Backspace removes it.",
                "tone": notice !== "" ? "warn" : "dim"
            };

        if (pending && pending.id === id)
            return {
                "text": "Taken by \"" + pending.other.title + "\". Replacing leaves that one without a shortcut.",
                "tone": "warn"
            };

        const err = errorOf(id);
        if (err !== "")
            return {
                "text": "Hyprland does not know \"" + err + "\" from settings.json. The default is used.",
                "tone": "warn"
            };

        return null;
    }

    function readList() {
        list.reload();
    }

    function parse(text) {
        try {
            const data = JSON.parse(text);
            const rows = Array.isArray(data.binds) ? data.binds.filter((b) => {
                return b && typeof b.description === "string" && typeof b.keys === "string";
            }) : [];
            if (JSON.stringify(rows) !== JSON.stringify(binds))
                binds = rows;

            known = rows.length > 0;
        } catch (e) {
            known = false;
        }
    }

    Component.onCompleted: liveReader.running = true

    FileView {
        id: list

        path: root.listFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.known = false
    }

    // Hyprland reloaded: its list is new (it replaces the file, so do not rely on the watcher alone)
    Connections {
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                root.readList();
                liveReader.running = true;
            }
        }

        target: Hyprland
    }

    // The settings window opens: the list may have changed while nothing listened
    Connections {
        function onOpenChanged() {
            if (SettingsState.open) {
                root.readList();
                liveReader.running = true;
            } else {
                root.cancel();
            }
        }

        function onSectionChanged() {
            root.cancel();
        }

        function onQueryChanged() {
            root.cancel();
        }

        target: SettingsState
    }

    // Several changes at once (Reset page, Undo) end in one reload; the pause also lets settings.json land
    Timer {
        id: reloadSoon

        interval: 300
        onTriggered: reloader.running = true
    }

    Process {
        id: reloader

        command: ["hyprctl", "reload"]
    }

    // Nobody pressed anything: stop capturing, so Hyprland's shortcuts are not held back for long
    Timer {
        id: giveUp

        interval: 15000
        onTriggered: root.cancel()
    }

    Process {
        id: liveReader

        command: ["hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.live = JSON.parse(text).filter((b) => {
                        return b && typeof b.modmask === "number";
                    }).map((b) => {
                        const mods = [];
                        if (b.modmask & 64)
                            mods.push("SUPER");

                        if (b.modmask & 4)
                            mods.push("CTRL");

                        if (b.modmask & 8)
                            mods.push("ALT");

                        if (b.modmask & 1)
                            mods.push("SHIFT");

                        const key = b.key ? String(b.key) : (b.keycode > 0 ? "code:" + b.keycode : "");
                        const d = String(b.description || "");
                        const i = d.indexOf(": ");
                        return {
                            "combo": key === "" ? "" : mods.join("+") + "+" + key.toLowerCase(),
                            "title": (i >= 0 ? d.slice(i + 2) : d) || "another shortcut"
                        };
                    });
                } catch (e) {
                }
            }
        }

    }

}
