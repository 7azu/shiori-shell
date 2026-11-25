pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// State of the settings window (settings/SettingsWindow.qml): which page is open, the search, the undo
// list, and above all the description of every page as data (sections). A page that is only rows needs
// no code of its own: settings/SettingsPage.qml draws it from this list, the search runs over the same
// list and "Reset page" knows the defaults from it.
//
// A row names its value by a key "<store>:<name>":
//   settings:<path>   ~/.config/shiori-shell/settings.json (services/Settings, all machines)
//   machine:<name>    ~/.config/quickshell-local/screens.json (services/MachineConfig, this machine)
//   bar:<icon id>     bar icon on/off (services/BarIcons, this machine)
//   addon:<name>      read only, what services/Addons found
//   keys:<name>       a keybinding (services/Keybinds; the keys go to settings.json, Hyprland reloads)
// A page with local: true holds values of this machine only (they are not synced), the head says so.
// Every change is written at once (there is no Save button) and remembered for Undo.
Singleton {
    id: root

    property bool open: false
    property string section: "system"
    property string query: ""
    // Rows marked adv only show with this on
    property bool advanced: false
    // Row (type path) whose folder is being chosen in the folder browser; "" = browser closed
    property string browseKey: ""
    // Row to light up briefly after a jump from the search
    property string flashKey: ""
    // [{label, changes: [{key, old}]}], newest last; only for this session
    property var undoStack: []
    // Counts the saves (the footer lets its star light up on each)
    property int saves: 0
    // From scripts/settings_probe.py: {programs: {cmd: bool}, paths: {path: bool}, info: {host, shell ...}}
    property var probe: ({
        "programs": {
        },
        "paths": {
        },
        "info": {
        }
    })
    readonly property string probeScript: Qt.resolvedUrl("../scripts/settings_probe.py").toString().replace("file://", "")
    readonly property var groups: ["Overview", "Shell", "Content"]
    readonly property var folderKeys: ["wallpapers", "screenshots", "music", "languages", "books", "notes", "projects"]
    readonly property var sections: [{
        "id": "system",
        "group": 0,
        "name": "System",
        "seal": "概",
        "blurb": "This machine, the shell on it and what is installed.",
        "page": "system",
        "words": "version programs installed missing files host about"
    }, {
        "id": "appearance",
        "group": 1,
        "name": "Appearance",
        "seal": "観",
        "blurb": "Size and motion of the whole interface.",
        "file": "machine",
        "local": true,
        "groups": [{
            "title": "Interface",
            "rows": [{
                "key": "machine:uiScale",
                "label": "Interface scale",
                "desc": "Fine tuning on top of the monitor scale of Hyprland.",
                "type": "number",
                "min": 0.7,
                "max": 1.6,
                "step": 0.05,
                "decimals": 2
            }, {
                "key": "machine:simpleAnimations",
                "label": "Simple animations",
                "desc": "Crossfade instead of small movements. Calmer on 60 Hz displays.",
                "type": "toggle"
            }]
        }, {
            "title": "Bar",
            "rows": [{
                "key": "machine:barScreen",
                "label": "Bar monitor",
                "desc": "There is always exactly one bar. This is where it lives.",
                "type": "choice",
                "options": "screens"
            }]
        }]
    }, {
        "id": "desktop",
        "group": 1,
        "name": "Desktop",
        "seal": "卓",
        "blurb": "What moves on the desktop, and how calm it is.",
        "file": "settings",
        "groups": [{
            "title": "Visualizer",
            "rows": [{
                "key": "settings:desktop.visualizer",
                "label": "Audio visualizer",
                "desc": "The wave along the bottom of workspace 1. Off also stops listening to the audio output.",
                "type": "toggle",
                "needs": ["cava"]
            }]
        }, {
            "title": "Starry sky",
            "footer": "The galaxy in the Wi-Fi, Bluetooth and VPN pickers is part of those tools and stays as it is.",
            "rows": [{
                "key": "settings:desktop.stars",
                "label": "Stars",
                "desc": "The sky in the power menu, lock screen and workspace overview. Calm keeps the stars but stops twinkling and drift.",
                "type": "choice",
                "options": [{
                    "value": "off",
                    "label": "Off"
                }, {
                    "value": "calm",
                    "label": "Calm"
                }, {
                    "value": "animated",
                    "label": "Animated"
                }]
            }]
        }]
    }, {
        "id": "bar",
        "group": 1,
        "name": "Bar & Features",
        "seal": "帯",
        "blurb": "Every icon is a feature. Off removes the icon and stops what it polls in the background.",
        "file": "bar",
        "local": true,
        "groups": [{
            "title": "Drawer, left",
            "footer": "The order is changed in the bar itself: right-click the logo, then drag.",
            "rows": [feature("clipboard", "Clipboard history", "Copied text and images.", ["cliphist"]), feature("trash", "Trash", "Deleted files, to restore or empty.", []), feature("bluetooth", "Bluetooth", "Devices around you.", ["bluetoothctl"]), feature("wifi", "Wi-Fi", "Networks around you.", ["nmcli"]), feature("apps", "App launcher", "Start apps from the bar.", []), feature("media", "Media picker", "Add-on, only present with the media add-on.", ["mpv"]), feature("monitor", "Monitors", "Move the bar to another monitor.", []), feature("ja", "Language tool", "Listen, read and keep track in the languages you learn.", ["mpv", "yt-dlp"])]
        }, {
            "title": "Status, right",
            "rows": [feature("sync", "Sync", "Git folders, cloud drives and your own sync commands.", []), feature("claude", "AI usage", "Limits and tokens of Claude Code and Codex.", []), feature("vpn", "VPN", "Connection, location and throughput.", ["nmcli"]), feature("audio", "Audio", "What is playing, volume and outputs.", []), feature("stats", "System stats", "Processor, graphics, memory and disk.", []), feature("battery", "Battery", "Charge and power.", ["upower"])]
        }, {
            "title": "Fixed places",
            "rows": [feature("settings", "Settings", "The gear next to the logo that opens this window. Super + , works without it.", []), feature("power", "Power menu", "At the far right: shut down, restart, lock, log out.", [])]
        }]
    }, {
        // The rows come from Hyprland's config at run time: groupsOf() asks services/Keybinds
        "id": "shortcuts",
        "group": 1,
        "name": "Shortcuts",
        "seal": "鍵",
        "blurb": "Which keys do what. Click a shortcut and press the new keys.",
        "file": "settings",
        "rows": "keys",
        "words": "keys keybindings keybinds hotkeys shortcut modifier super bind"
    }, {
        "id": "folders",
        "group": 2,
        "name": "Folders",
        "seal": "庫",
        "blurb": "Where the shell looks for your things. ~, $PICTURES, $MUSIC and $DOCUMENTS work in every path.",
        "file": "settings",
        "groups": [{
            "title": "Pictures",
            "rows": [folderRow("wallpapers", "Wallpapers", "Shown in the wallpaper picker."), folderRow("screenshots", "Screenshots", "Where new screenshots are saved.")]
        }, {
            "title": "Media",
            "rows": [folderRow("music", "Music", "Library of the music picker. Set music_directory in mpd/mpd.conf to the same folder.")]
        }, {
            "title": "Language tool",
            "rows": [folderRow("languages", "Languages", "One subfolder per language with its videos."), folderRow("books", "Books", "Your books for the Read tab."), folderRow("notes", "Notes", "Notes that the Read tab offers as sentence cards. Empty = none.")]
        }, {
            "title": "Work",
            "rows": [Object.assign(folderRow("projects", "Projects", "Your code folder: Neovim project search and the tmux project layout. Empty = off."), {
                "adv": true
            })]
        }]
    }, {
        "id": "sync",
        "group": 2,
        "name": "Sync",
        "seal": "同",
        "blurb": "One row in the sync dropdown per entry. Without entries the sync icon is gone.",
        "page": "sync",
        "file": "settings",
        "words": "git rclone remote ssh key vault drive command"
    }, {
        "id": "languages",
        "group": 2,
        "name": "Languages",
        "seal": "語",
        "blurb": "How the language tool translates, and where languages live that are not in the languages folder.",
        "file": "settings",
        "groups": [{
            "title": "Translation",
            "footer": "Auto takes the first service that works. Off hides the translate buttons.",
            "rows": [{
                "key": "settings:translation.provider",
                "label": "Service",
                "desc": "Translates book chapters and subtitle lines into English.",
                "type": "choice",
                "options": ["auto", "claude", "codex", "ollama", "deepl", "argos", "off"].map((v) => {
                    return {
                        "value": v,
                        "label": v === "deepl" ? "DeepL" : v.charAt(0).toUpperCase() + v.slice(1)
                    };
                })
            }, {
                "key": "settings:translation.ollamaModel",
                "label": "Ollama model",
                "desc": "Only used with the service Ollama.",
                "type": "text",
                "adv": true
            }, {
                "key": "settings:translation.ollamaUrl",
                "label": "Ollama address",
                "desc": "Where the Ollama server answers.",
                "type": "text",
                "adv": true
            }]
        }, {
            "title": "Extra language folders",
            "footer": "For a language whose material is somewhere else than in the languages folder.",
            "rows": [{
                "key": "settings:languageFolders",
                "label": "Extra language folders",
                "desc": "",
                "type": "map",
                "keyLabel": "Language",
                "valueLabel": "Folder"
            }]
        }]
    }, {
        "id": "icons",
        "group": 2,
        "name": "App Icons",
        "seal": "印",
        "blurb": "Your own icons for apps and windows. The files live in ~/.config/shiori-shell/icons.",
        "file": "settings",
        "groups": [{
            "title": "Icons",
            "footer": "Name: a window class or part of an app name in lower case, title:<window title> or browser:<name>. File: a name from the icons folder or a full path.",
            "rows": [{
                "key": "settings:icons",
                "label": "App icons",
                "desc": "",
                "type": "map",
                "keyLabel": "Name",
                "valueLabel": "File",
                "previews": true
            }]
        }]
    }, {
        "id": "addons",
        "group": 2,
        "name": "Add-ons",
        "seal": "加",
        "blurb": "Private parts that are not in the repository. They live in ~/.config/shiori-shell/addons.",
        "groups": [{
            "title": "Found",
            "rows": [{
                "key": "addon:media",
                "label": "Media picker",
                "desc": "Films, series, anime, manga and novels.",
                "type": "info"
            }, {
                "key": "addon:editorAction",
                "label": "Editor action",
                "desc": "An extra button in the image and video editor, such as sending to DaVinci Resolve.",
                "type": "info"
            }]
        }]
    }]

    // A text field gives the keyboard back to the search field (Esc)
    signal focusSearch()

    function feature(id, label, desc, needs) {
        return {
            "key": "bar:" + id,
            "label": label,
            "desc": desc,
            "type": "toggle",
            "needs": needs
        };
    }

    function folderRow(key, label, desc) {
        return {
            "key": "settings:folders." + key,
            "label": label,
            "desc": desc,
            "type": "path"
        };
    }

    // ---- window ----
    function toggle() {
        if (open)
            close();
        else
            openAt("");
    }

    // "" = the page that was open last
    function openAt(id) {
        if (id && sectionById(id))
            section = id;

        query = "";
        open = true;
        refreshProbe();
    }

    function close() {
        browseKey = "";
        open = false;
    }

    function rowByKey(key) {
        for (const s of sections) {
            const r = rowsOf(s).find((row) => {
                return row.key === key;
            });
            if (r)
                return r;

        }
        return null;
    }

    // The folder browser reported a folder for the row that asked (browseKey)
    function folderChosen(path) {
        const row = rowByKey(browseKey);
        browseKey = "";
        if (row)
            apply(row.key, Settings.shortPath(path), row.label);

    }

    function sectionById(id) {
        return sections.find((s) => {
            return s.id === id;
        }) || null;
    }

    // Groups of a page: written down in sections, or made at run time (rows: "keys")
    function groupsOf(sec) {
        return sec.rows === "keys" ? Keybinds.groups : (sec.groups || []);
    }

    function rowsOf(sec) {
        return groupsOf(sec).reduce((all, g) => {
            return all.concat(g.rows);
        }, []);
    }

    function shownRow(row) {
        return !row.adv || advanced;
    }

    // Next/previous page in the rail
    function step(dir) {
        const i = sections.findIndex((s) => {
            return s.id === section;
        });
        section = sections[(i + dir + sections.length) % sections.length].id;
    }

    // ---- values ----
    function storeOf(key) {
        return key.slice(0, key.indexOf(":"));
    }

    function nameOf(key) {
        return key.slice(key.indexOf(":") + 1);
    }

    function read(key) {
        const name = nameOf(key);
        switch (storeOf(key)) {
        case "settings":
            return Settings.get(name);
        case "machine":
            return name === "barScreen" ? MachineConfig.barScreenName : MachineConfig[name];
        case "bar":
            return BarIcons.shown(name);
        case "addon":
            return (name === "media" ? Addons.media : Addons.editorAction !== null) ? "Installed" : "Not installed";
        case "keys":
            return Keybinds.keysOf(name);
        }
        return undefined;
    }

    function defaultOf(key) {
        const name = nameOf(key);
        switch (storeOf(key)) {
        case "settings":
            return Settings.defaultOf(name);
        case "machine":
            return ({
                "uiScale": 1,
                "simpleAnimations": false
            })[name];
        case "bar":
            return true;
        case "keys":
            return Keybinds.defaultOf(name);
        }
        return undefined;
    }

    function write(key, value) {
        const name = nameOf(key);
        switch (storeOf(key)) {
        case "settings":
            Settings.set(name, value);
            // The main modifier is read by Hyprland's config
            if (name === "keys.mod")
                Keybinds.reload();

            break;
        case "keys":
            Keybinds.set(name, value);
            break;
        case "machine":
            if (name === "barScreen") {
                MachineConfig.setBarScreen(value);
            } else {
                MachineConfig[name] = value;
                MachineConfig.save();
            }
            break;
        case "bar":
            if (BarIcons.shown(name) !== value)
                BarIcons.toggle(name);

            break;
        }
    }

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    // Change one value: written at once, the old value goes to the undo list
    function apply(key, value, label) {
        const old = read(key);
        if (same(old, value))
            return ;

        write(key, value);
        pushUndo(label, [{
            "key": key,
            "old": old
        }]);
        if (storeOf(key) === "settings" && nameOf(key).startsWith("folders."))
            refreshProbe();

    }

    function pushUndo(label, changes) {
        undoStack = undoStack.concat([{
            "label": label,
            "changes": changes
        }]).slice(-50);
        saves++;
    }

    function undo() {
        if (undoStack.length === 0)
            return ;

        const last = undoStack[undoStack.length - 1];
        for (const c of last.changes) write(c.key, c.old)
        undoStack = undoStack.slice(0, -1);
        saves++;
        refreshProbe();
    }

    // Rows of a page that differ from their default
    function changedRows(sec) {
        return rowsOf(sec).filter((r) => {
            const d = defaultOf(r.key);
            return d !== undefined && !same(read(r.key), d);
        });
    }

    function resetSection(sec) {
        const changes = changedRows(sec).map((r) => {
            return {
                "key": r.key,
                "old": read(r.key)
            };
        });
        if (changes.length === 0)
            return ;

        for (const c of changes) write(c.key, defaultOf(c.key))
        pushUndo("Reset " + sec.name, changes);
        refreshProbe();
    }

    // ---- search ----
    // Every word of the query starts a word of the text ("star" finds Stars, not "restart")
    function hit(words, text) {
        const have = text.toLowerCase().split(/[^a-z0-9]+/);
        return words.every((w) => {
            return have.some((h) => {
                return h.startsWith(w);
            });
        });
    }

    // The pages as one made-up page: a group per page with the rows that match. Pages with their own
    // layout (sync, system) appear as a row that leads there.
    function searchSection(text) {
        const words = text.toLowerCase().split(/\s+/).filter((w) => {
            return w !== "";
        });
        const groupsOut = [];
        let count = 0;
        for (const s of sections) {
            const pageHit = hit(words, s.name + " " + (s.words || ""));
            const rows = rowsOf(s).filter((r) => {
                return pageHit || hit(words, r.label + " " + (r.desc || "") + " " + s.name);
            });
            if (rows.length === 0 && pageHit)
                rows.push({
                "key": "",
                "label": s.name,
                "desc": s.blurb,
                "type": "link",
                "target": s.id
            });

            if (rows.length === 0)
                continue;

            count += rows.length;
            groupsOut.push({
                "title": s.name,
                "target": s.id,
                "rows": rows
            });
        }
        return {
            "id": "search",
            "group": -1,
            "name": "Search",
            "seal": "探",
            "blurb": count === 0 ? "Nothing found." : count + (count === 1 ? " setting" : " settings") + " found.",
            "groups": groupsOut,
            "searching": true
        };
    }

    // Leave the search for the page of a row and light the row up there
    function jump(id, key) {
        query = "";
        section = id;
        flashKey = key || "";
        flashOff.restart();
    }

    // ---- files ----
    function fileOf(sec) {
        if (sec.file === "settings")
            return Settings.userFile;

        if (sec.file === "machine")
            return MachineConfig.localFile;

        if (sec.file === "bar")
            return BarIcons.localFile;

        return "";
    }

    function openPath(path) {
        Quickshell.execDetached(["xdg-open", path]);
    }

    // ---- what is installed, which folders exist ----
    function refreshProbe() {
        if (probeProc.running)
            return ;

        probeProc.command = ["python3", probeScript].concat(folderKeys.map((k) => {
            return Settings.folder(k);
        }).filter((p) => {
            return p !== "";
        }));
        probeProc.running = true;
    }

    // Programs a row needs that are not installed
    function missing(row) {
        return (row.needs || []).filter((p) => {
            return probe.programs[p] === false;
        });
    }

    Process {
        id: probeProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.probe = JSON.parse(text);
                } catch (e) {
                }
            }
        }

    }

    Timer {
        id: flashOff

        interval: 1600
        onTriggered: root.flashKey = ""
    }

}
