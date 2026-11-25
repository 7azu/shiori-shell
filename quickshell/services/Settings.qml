pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings of shiori-shell (scripts use scripts/shiori_settings.py, same rules).
// Defaults: defaults/settings.json. Your own values: ~/.config/shiori-shell/settings.json, merged over
// the defaults key by key and reloaded when the file changes. In paths, ~, $HOME and the XDG user
// folders ($PICTURES, $MUSIC, $DOCUMENTS, $DOWNLOAD, $VIDEOS, $DESKTOP) are expanded.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string userFile: configHome + "/shiori-shell/settings.json"
    property var data: ({})
    // The two sources of data: the shipped defaults and what the user's file holds
    property var defaults: ({})
    property var own: ({})
    property var xdgDirs: ({})

    function dig(obj, path) {
        let v = obj;
        for (const k of path.split(".")) {
            if (v === null || typeof v !== "object")
                return undefined;

            v = v[k];
        }
        return v;
    }

    // Value by path ("desktop.stars"); undefined if unset
    function get(path) {
        return dig(data, path);
    }

    function defaultOf(path) {
        return dig(defaults, path);
    }

    // Writes one value to the user's file (the settings window, services/SettingsState). The file only
    // holds what differs: a value equal to the default (or undefined) is removed there. Takes effect at
    // once, the file watcher then only confirms it.
    function set(path, value) {
        const next = JSON.parse(JSON.stringify(own));
        const keys = path.split(".");
        const chain = [next];
        let node = next;
        for (let i = 0; i < keys.length - 1; i++) {
            const k = keys[i];
            if (!node[k] || typeof node[k] !== "object" || Array.isArray(node[k]))
                node[k] = {
            };

            node = node[k];
            chain.push(node);
        }
        const last = keys[keys.length - 1];
        if (value === undefined || JSON.stringify(value) === JSON.stringify(defaultOf(path)))
            delete node[last];
        else
            node[last] = value;
        // Objects that became empty go too
        for (let i = keys.length - 2; i >= 0; i--) {
            if (Object.keys(chain[i + 1]).length > 0)
                break;

            delete chain[i][keys[i]];
        }
        own = next;
        data = merged(defaults, next);
        userSettings.setText(JSON.stringify(next, null, 2) + "\n");
    }

    // The user's values over the defaults, key by key (one level deep)
    function merged(base, over) {
        const out = Object.assign({
        }, base);
        for (const key in over) {
            const v = over[key];
            if (v && typeof v === "object" && !Array.isArray(v) && out[key] && typeof out[key] === "object")
                out[key] = Object.assign({
            }, out[key], v);
            else
                out[key] = v;
        }
        return out;
    }

    // Folder by key ("wallpapers", "screenshots", "music", "languages", "books", "notes"), without
    // trailing slash; "" if unset
    function folder(key) {
        const f = data.folders || {};
        return expand(f[key] || "");
    }

    // Extra language folders outside the languages folder: { "Japanese": "/home/me/..." }
    function languageFolders() {
        const src = data.languageFolders || {};
        const out = {};
        for (const name in src) out[name] = expand(src[name])
        return out;
    }

    // Own icons (settings "icons": key -> file in ~/.config/shiori-shell/icons or absolute path) as URL,
    // "" if none. Keys: "title:<window title>", window class or app name in lower case, "browser:<name>".
    function icon(key) {
        const f = (data.icons || {})[key];
        if (!f)
            return "";

        const p = expand(f);
        return "file://" + (p.startsWith("/") ? p : configHome + "/shiori-shell/icons/" + p);
    }

    // Keys of the own icons without a prefix (matched as part of app names, e.g. "youtube")
    function iconKeys() {
        return Object.keys(data.icons || {}).filter((k) => {
            return k.indexOf(":") === -1;
        });
    }

    // For showing a path: the home folder as ~
    function shortPath(path) {
        return path === home || path.startsWith(home + "/") ? "~" + path.substring(home.length) : path;
    }

    function expand(path) {
        if (!path)
            return "";

        let p = path;
        if (p === "~" || p.startsWith("~/"))
            p = home + p.substring(1);

        p = p.replace(/\$([A-Z]+)/g, (m, name) => {
            if (name === "HOME")
                return home;

            return xdgDirs[name] || m;
        });
        while (p.length > 1 && p.endsWith("/"))p = p.slice(0, -1)
        return p;
    }

    function parseJson(text, what) {
        if (!text)
            return {};

        try {
            return JSON.parse(text);
        } catch (e) {
            console.warn("Settings:", what, "is not valid JSON:", e);
            return {};
        }
    }

    function load() {
        const dirs = {
            "PICTURES": home + "/Pictures",
            "MUSIC": home + "/Music",
            "DOCUMENTS": home + "/Documents",
            "DOWNLOAD": home + "/Downloads",
            "VIDEOS": home + "/Videos",
            "DESKTOP": home + "/Desktop"
        };
        for (const line of userDirsFile.text().split("\n")) {
            const m = line.match(/^\s*XDG_([A-Z]+)_DIR="(.*)"/);
            if (m)
                dirs[m[1]] = m[2].replace("$HOME", home);

        }
        xdgDirs = dirs;
        defaults = parseJson(defaultsFile.text(), "defaults/settings.json");
        own = parseJson(userSettings.text(), userFile);
        data = merged(defaults, own);
    }

    Component.onCompleted: load()

    // Create the folder, so the first save works
    Process {
        command: ["mkdir", "-p", root.configHome + "/shiori-shell"]
        running: true
    }

    FileView {
        id: defaultsFile

        path: Quickshell.shellPath("defaults/settings.json")
        blockLoading: true
    }

    FileView {
        id: userSettings

        path: root.userFile
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load()
    }

    FileView {
        id: userDirsFile

        path: root.configHome + "/user-dirs.dirs"
        blockLoading: true
        printErrors: false
    }

}
