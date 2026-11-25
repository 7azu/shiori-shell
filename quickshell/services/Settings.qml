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
    property var xdgDirs: ({})

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
        const merged = parseJson(defaultsFile.text(), "defaults/settings.json");
        const own = parseJson(userSettings.text(), userFile);
        for (const key in own) {
            const v = own[key];
            if (v && typeof v === "object" && !Array.isArray(v) && merged[key] && typeof merged[key] === "object")
                merged[key] = Object.assign({}, merged[key], v);
            else
                merged[key] = v;
        }
        data = merged;    }

    Component.onCompleted: load()

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
