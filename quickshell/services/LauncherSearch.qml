pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What the app launcher (pickers/AppLauncher.qml) finds for a search text. The first character picks the mode:
//
//   (none)  apps and shell actions, the best match first; what you start often comes before the rest
//   =       calculator (in AppLauncher itself)
//   :       emoji          (resources/emoji/emoji.json, built by scripts/make-emoji.py)
//   ?       web search     (settings.json "launcher.searchUrl", %s = what you typed)
//   >       run a command  (in the terminal; Ctrl+Enter without one)
//   /       files          (fd below your home folder)
//
// Every result is a plain object with kind ("app", "action", "emoji", "file"), key (unique), name and what
// its kind needs. AppLauncher draws them all in the same grid and calls activate() for Enter or a click.
//
// Usage lives in <stateDir>/launcher-usage.json as { "<key>": { "n": count, "t": last time } }.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // Site chip in the "?" search: after "amazon.de " the address becomes an icon in front of the field
    // and the field only holds what to search for there. "raw" puts the pieces back together.
    property string siteHost: ""
    readonly property string raw: siteHost !== "" ? "? " + siteHost + " " + PickerManager.searchText : PickerManager.searchText
    readonly property string lead: raw.replace(/^\s+/, "")
    readonly property var prefixes: ({
        "=": "calc",
        ":": "emoji",
        "?": "web",
        ">": "run",
        "/": "files"
    })
    readonly property string mode: prefixes[lead.charAt(0)] || "apps"
    // The search text without the mode character
    readonly property string term: (mode === "apps" ? lead : lead.slice(1)).trim()
    // ---- usage ----
    property var usage: ({
    })
    readonly property string usageFile: Quickshell.stateDir + "/launcher-usage.json"
    // ---- emoji ----
    // Entries { kind, key, char, name, words, hay } in keyboard order; read on the first emoji search
    property var emojiAll: []
    property bool emojiWanted: false
    readonly property var emojiResults: mode === "emoji" ? searchEmoji(term) : []
    // ---- files ----
    property var fileResults: []
    property bool fileBusy: false
    // The term the shown file results belong to
    property string fileTerm: ""
    readonly property int fileMinLength: 2
    // ---- shell actions: found by name and words, only while searching ----
    // needs: bar icon that has to be on (a hidden icon turns its feature off)
    readonly property var actions: [{
        "id": "night",
        "name": "Night light",
        "words": "blue filter warm color temperature sunset",
        "glyph": "\u{F0594}",
        "needs": "screen"
    }, {
        "id": "awake",
        "name": "Keep awake",
        "words": "caffeine idle lock screen stay on inhibit",
        "glyph": "\u{F0176}",
        "needs": "screen"
    }, {
        "id": "lock",
        "name": "Lock screen",
        "words": "lock away",
        "glyph": "\u{F033E}"
    }, {
        "id": "power",
        "name": "Power menu",
        "words": "shut down shutdown restart reboot log out logout suspend sleep",
        "glyph": "\u{F0425}"
    }, {
        "id": "dnd",
        "name": "Do not disturb",
        "words": "dnd notifications silent quiet mute",
        "glyph": "\u{F009B}"
    }, {
        "id": "clipboard",
        "name": "Clipboard history",
        "words": "copy paste clip",
        "glyph": "\u{F0147}",
        "needs": "clipboard"
    }, {
        "id": "trash",
        "name": "Trash",
        "words": "deleted files bin restore",
        "glyph": "\u{F0A7A}",
        "needs": "trash"
    }, {
        "id": "wallpaper",
        "name": "Wallpapers",
        "words": "background picture colors",
        "glyph": "\u{F0E09}"
    }, {
        "id": "music",
        "name": "Music",
        "words": "songs library player mpd",
        "glyph": "\u{F075A}"
    }, {
        "id": "vpn",
        "name": "VPN",
        "words": "wireguard connection server",
        "glyph": "\u{F0483}",
        "needs": "vpn"
    }, {
        "id": "wifi",
        "name": "Wi-Fi",
        "words": "wifi wlan network internet",
        "glyph": "\u{F05A9}",
        "needs": "wifi"
    }, {
        "id": "bluetooth",
        "name": "Bluetooth",
        "words": "devices headphones pair",
        "glyph": "\u{F00AF}",
        "needs": "bluetooth"
    }, {
        "id": "tray",
        "name": "Tray",
        "words": "background programs steam systray status",
        "glyph": "\u{F0CA0}",
        "needs": "tray"
    }, {
        "id": "tasks",
        "name": "Task manager",
        "words": "windows processes running kill cpu ram",
        "glyph": "\u{F0C7F}"
    }, {
        "id": "language",
        "name": "Language tool",
        "words": "learn listen read japanese subtitles",
        "glyph": "\u{F05CA}",
        "needs": "ja"
    }, {
        "id": "calendar",
        "name": "Calendar",
        "words": "date month day",
        "glyph": "\u{F00ED}"
    }, {
        "id": "notifications",
        "name": "Notifications",
        "words": "notification center messages",
        "glyph": "\u{F009A}"
    }, {
        "id": "calculator",
        "name": "Calculator",
        "words": "calc math",
        "glyph": "\u{F00EC}"
    }, {
        "id": "screenshot",
        "name": "Screenshot",
        "words": "capture screen area edit",
        "glyph": "\u{F0E51}"
    }, {
        "id": "shortcuts",
        "name": "Shortcuts",
        "words": "keys keybindings hotkeys cheat sheet",
        "glyph": "\u{F030C}"
    }, {
        "id": "overview",
        "name": "Workspace overview",
        "words": "workspaces windows expose",
        "glyph": "\u{F0570}"
    }]

    // ==== Matching ====
    // How well the lowercase text fits the lowercase query, 0 (not at all) to 100 (the same)
    function score(query, text) {
        if (query === "")
            return 1;

        if (text === "")
            return 0;

        if (text === query)
            return 100;

        if (text.startsWith(query))
            return 90;

        const at = text.indexOf(query);
        if (at > 0)
            return /[\s\-_.:\/(]/.test(text.charAt(at - 1)) ? 80 : 60;

        // First letters of the words: "vsc" finds "Visual Studio Code"
        const words = text.split(/[\s\-_.]+/);
        let initials = "";
        for (const w of words) initials += w.charAt(0)
        if (query.length >= 2 && initials.startsWith(query))
            return 70;

        // The letters in this order with gaps: "fx" finds "Firefox". The first one has to start the text.
        if (query.length < 2 || text.charAt(0) !== query.charAt(0))
            return 0;

        let pos = 0;
        let gaps = 0;
        for (let i = 0; i < query.length; i++) {
            const next = text.indexOf(query.charAt(i), pos);
            if (next === -1)
                return 0;

            gaps += next - pos;
            pos = next + 1;
        }
        return Math.max(12, 45 - 3 * gaps);
    }

    // Several words have to fit all (each one anywhere in hay): for emoji and file names
    function scoreWords(query, hay) {
        let total = 0;
        for (const word of query.split(/\s+/)) {
            if (word === "")
                continue;

            const s = score(word, hay) || (hay.includes(" " + word) ? 75 : (hay.includes(word) ? 55 : 0));
            if (s === 0)
                return 0;

            total += s;
        }
        return total;
    }

    // ==== Usage ====
    // 0 (never) to 1 (often and lately): the count on a soft scale, halved every 30 days without use
    function heat(key) {
        const u = usage[key];
        if (!u || !u.n)
            return 0;

        const days = Math.max(0, (Date.now() - (u.t || 0)) / 8.64e+07);
        return Math.min(1, Math.log2(1 + u.n) / 5) * Math.pow(0.5, days / 30);
    }

    function used(key) {
        const next = Object.assign({
        }, usage);
        const u = next[key] || {
            "n": 0
        };
        next[key] = {
            "n": u.n + 1,
            "t": Date.now()
        };
        usage = next;
        usageView.setText(JSON.stringify(next) + "\n");
    }

    // ==== Apps and actions ====
    function appKey(app) {
        return "app:" + (app.file || app.name);
    }

    // apps: AppLauncherState.allApps (by name), hidden: { exec: true }
    function rank(apps, hidden, showHidden) {
        const q = term.toLowerCase();
        const out = [];
        for (const app of apps) {
            if (hidden[app.exec] === true && !showHidden)
                continue;

            const key = appKey(app);
            let s = score(q, app.name.toLowerCase());
            if (q !== "") {
                // What it is ("Web Browser") and its keywords count less than its name
                s = Math.max(s, 0.6 * score(q, (app.generic || "").toLowerCase()));
                for (const w of app.keywords || []) {
                    if (w.startsWith(q))
                        s = Math.max(s, 40);

                }
            }
            if (s <= 0)
                continue;

            out.push({
                "kind": "app",
                "key": key,
                "name": app.name,
                "exec": app.exec,
                "icon": app.icon,
                "terminal": app.terminal,
                "rank": (q === "" ? 0 : s) + 20 * heat(key)
            });
        }
        if (q !== "") {
            for (const a of actions) {
                if (a.needs && !BarIcons.shown(a.needs))
                    continue;

                let s = score(q, a.name.toLowerCase());
                // A search word only counts from its beginning ("set" is not "sunset")
                for (const w of a.words.split(" ")) {
                    if (w.startsWith(q))
                        s = Math.max(s, 40);

                }
                // Letters with gaps would make actions show up for almost anything
                if (s < 40)
                    continue;

                out.push({
                    "kind": "action",
                    "key": "action:" + a.id,
                    "id": a.id,
                    "name": a.name,
                    "glyph": a.glyph,
                    "rank": s - 5 + 20 * heat("action:" + a.id)
                });
            }
        }
        // Stable: equal rank keeps the order by name the list came in
        out.sort((a, b) => {
            return b.rank - a.rank || a.name.localeCompare(b.name);
        });
        return out;
    }

    // Whether an action is on right now (for the tile); undefined = not something that is on or off
    function actionOn(id) {
        switch (id) {
        case "night":
            return NightLight.mode !== "off";
        case "awake":
            return KeepAwake.active;
        case "dnd":
            return NotificationState.dnd;
        }
        return undefined;
    }

    // ==== Emoji ====
    function searchEmoji(text) {
        const q = text.toLowerCase();
        if (q === "") {
            // What you used first, then all of them in keyboard order
            const recent = emojiAll.filter((e) => {
                return heat(e.key) > 0;
            }).sort((a, b) => {
                return heat(b.key) - heat(a.key);
            }).slice(0, 18);
            const keys = {
            };
            for (const e of recent) keys[e.key] = true
            return recent.concat(emojiAll.filter((e) => {
                return !keys[e.key];
            }));
        }
        const out = [];
        const words = q.split(/\s+/).filter((w) => {
            return w !== "";
        });
        for (const e of emojiAll) {
            // Per word: the whole word in the name (90), a word of the name beginning with it (80), inside the
            // name (55), then the same in the further search words for less. Every word has to be found.
            let s = 0;
            for (const w of words) {
                const name = " " + e.name + " ";
                let one = 0;
                if (name.includes(" " + w + " "))
                    one = 90;
                else if (name.includes(" " + w))
                    one = 80;
                else if (name.includes(w))
                    one = 55;
                else if (e.hay.includes(" " + w + " "))
                    one = 50;
                else if (e.hay.includes(" " + w))
                    one = 40;
                if (one === 0) {
                    s = 0;
                    break;
                }
                s += one;
            }
            // "red heart" before "smiling face with heart-eyes"
            if (s > 0)
                out.push({
                "e": e,
                "s": s - 0.4 * e.name.length + 10 * heat(e.key)
            });

        }
        out.sort((a, b) => {
            return b.s - a.s;
        });
        return out.slice(0, 240).map((x) => {
            return x.e;
        });
    }

    function loadEmoji(text) {
        let data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
            console.warn("LauncherSearch: emoji.json is not valid:", e);
            return ;
        }
        emojiAll = (data.emoji || []).map((row) => {
            return {
                "kind": "emoji",
                "key": "emoji:" + row[0],
                "char": row[0],
                "name": row[1],
                "hay": " " + row[1] + " " + row[2] + " "
            };
        });
    }

    // ==== Files ====
    function glyphOf(path, isDir) {
        if (isDir)
            return "\u{F024B}";

        const ext = (/\.([a-z0-9]+)$/i.exec(path) || ["", ""])[1].toLowerCase();
        if (/^(png|jpe?g|webp|gif|svg|bmp|avif|heic)$/.test(ext))
            return "\u{F021F}";

        if (/^(mp4|mkv|webm|mov|avi)$/.test(ext))
            return "\u{F022B}";

        if (/^(mp3|flac|ogg|opus|wav|m4a)$/.test(ext))
            return "\u{F0223}";

        if (/^(pdf|epub)$/.test(ext))
            return "\u{F0226}";

        if (/^(zip|tar|gz|xz|zst|7z|rar)$/.test(ext))
            return "\u{F05C4}";

        if (/^(qml|py|js|ts|lua|rs|c|h|cpp|sh|json|toml|ya?ml|html|css|java|go)$/.test(ext))
            return "\u{F022E}";

        return "\u{F0214}";
    }

    function shortPath(path) {
        return path.startsWith(home) ? "~" + path.slice(home.length) : path;
    }

    function takeFiles(text, forTerm) {
        const q = forTerm.toLowerCase();
        const out = [];
        for (const line of text.split("\n")) {
            if (line === "")
                continue;

            const isDir = line.endsWith("/");
            const path = isDir ? line.slice(0, -1) : line;
            const cut = path.lastIndexOf("/");
            const name = path.slice(cut + 1);
            out.push({
                "kind": "file",
                "key": "file:" + path,
                "name": name,
                "sub": shortPath(path.slice(0, cut)) || "/",
                "path": path,
                "dir": isDir,
                "glyph": glyphOf(path, isDir),
                // The name counts, a shallow place breaks ties
                "rank": scoreWords(q, name.toLowerCase()) - path.split("/").length * 0.5
            });
        }
        out.sort((a, b) => {
            return b.rank - a.rank || a.path.localeCompare(b.path);
        });
        fileResults = out.slice(0, 60);
        fileTerm = forTerm;
    }

    // ==== Doing it ====
    function runAction(id) {
        switch (id) {
        case "night":
            NightLight.toggle();
            break;
        case "awake":
            KeepAwake.toggle();
            break;
        case "dnd":
            NotificationState.setDnd(!NotificationState.dnd);
            break;
        case "lock":
            Quickshell.execDetached([home + "/.config/hypr/scripts/lock.sh"]);
            break;
        case "power":
            Quickshell.execDetached(["qs", "ipc", "call", "powermenu", "toggle"]);
            break;
        case "overview":
            Quickshell.execDetached(["qs", "ipc", "call", "workspaceoverview", "toggle"]);
            break;
        case "clipboard":
            ClipboardState.toggle();
            break;
        case "trash":
            TrashState.toggle();
            break;
        case "wallpaper":
            WallpaperPickerState.toggle();
            break;
        case "music":
            MusicPickerState.toggle();
            break;
        case "vpn":
            VpnPickerState.toggle();
            break;
        case "wifi":
            WifiState.toggle();
            break;
        case "bluetooth":
            BluetoothState.toggle();
            break;
        case "tasks":
            PickerManager.toggle("apps");
            break;
        case "tray":
            TrayState.toggle();
            break;
        case "language":
            LanguageAudioState.toggle();
            break;
        case "shortcuts":
            PickerManager.toggle("shortcuts");
            break;
        case "calendar":
            BarState.calendarToggleRequested();
            break;
        case "notifications":
            NotificationState.toggle();
            break;
        case "calculator":
            CalculatorState.toggle();
            break;
        case "screenshot":
            ScreenshotEditorState.startCapture();
            break;
        }
    }

    // Actions that open another picker replace the launcher themselves; for all others it has to close first
    function opensPicker(id) {
        return ["clipboard", "trash", "wallpaper", "music", "vpn", "wifi", "bluetooth", "tasks", "language", "shortcuts"].indexOf(id) !== -1;
    }

    // "duckduckgo.com" or "https://…" is an address, anything else something to search for
    function isAddress(text) {
        const t = text.trim();
        return /^[a-z][a-z0-9+.-]*:\/\//i.test(t) || /^[^\s\/]+\.[a-z]{2,}(\/\S*)?$/i.test(t);
    }

    // Search URLs of well-known sites, matched on the host without "www." (first match wins); %s = the query.
    // Any other site: its own search, found on the start page by scripts/site-search.py (siteTemplates, cached in
    // <stateDir>/site-search.json); without one "site:host query" on the default search engine.
    readonly property var siteSearches: [
        [/^amazon\.[a-z.]+$/, "https://%h/s?k=%s"],
        [/^ebay\.[a-z.]+$/, "https://%h/sch/i.html?_nkw=%s"],
        [/^youtube\.com$/, "https://www.youtube.com/results?search_query=%s"],
        [/^github\.com$/, "https://github.com/search?q=%s"],
        [/^wikipedia\.org$|^[a-z]{2}\.wikipedia\.org$/, "https://%h/w/index.php?search=%s"],
        [/^reddit\.com$/, "https://www.reddit.com/search/?q=%s"],
        [/^google\.[a-z.]+$/, "https://www.%h/search?q=%s"],
        [/^idealo\.[a-z.]+$/, "https://www.%h/preisvergleich/MainSearchProductCategory.html?q=%s"],
        [/^otto\.de$/, "https://www.otto.de/suche/%s/"],
        [/^mydealz\.de$/, "https://www.mydealz.com/search?q=%s"],
        [/^galaxus\.[a-z]+$/, "https://www.galaxus.ch/search?q=%s"],
        [/^mediamarkt\.[a-z]+$/, "https://www.%h/de/search.html?query=%s"],
        [/^saturn\.de$/, "https://www.saturn.de/de/search.html?query=%s"],
        [/^notebooksbilliger\.de$/, "https://www.notebooksbilliger.de/produkte/%s"],
        [/^alternate\.de$/, "https://www.alternate.de/listing.xhtml?q=%s"],
        [/^mindfactory\.de$/, "https://www.mindfactory.de/search_result.php?search_query=%s"],
        [/^caseking\.de$/, "https://www.caseking.de/search?sSearch=%s"],
        [/^kleinanzeigen\.de$/, "https://www.kleinanzeigen.de/s-suchanfrage.html?keywords=%s"],
        [/^(store\.)?steampowered\.com$/, "https://store.steampowered.com/search/?term=%s"],
        [/^stackoverflow\.com$/, "https://stackoverflow.com/search?q=%s"],
        [/^imdb\.com$/, "https://www.imdb.com/find/?q=%s"],
        [/^pinterest\.[a-z.]+$/, "https://www.pinterest.com/search/pins/?q=%s"],
        [/^(x|twitter)\.com$/, "https://x.com/search?q=%s"],
        [/^wiki\.archlinux\.org$/, "https://wiki.archlinux.org/index.php?search=%s"],
        [/^aur\.archlinux\.org$/, "https://aur.archlinux.org/packages?K=%s"],
        [/^twitch\.tv$/, "https://www.twitch.tv/search?term=%s"],
        [/^spotify\.com$|^open\.spotify\.com$/, "https://open.spotify.com/search/%s"]
    ]

    // host -> its own search URL ("" = none found); filled by lookupSite()
    property var siteTemplates: ({})
    readonly property string siteCacheFile: Quickshell.stateDir + "/site-search.json"

    function lookupSite(host) {
        if (siteTemplates[host] !== undefined || siteProc.running && siteProc.host === host)
            return ;

        siteProc.host = host;
        siteProc.command = ["python3", "-I", Quickshell.shellPath("scripts/site-search.py"), host, siteCacheFile];
        siteProc.running = true;
    }

    // Typing "geizhals.de something" or "? geizhals.de ": look the site's search up in the background
    function lookupForTerm() {
        if (mode !== "web")
            return ;

        const m = term.match(/^(\S+)(\s|$)/);
        if (m && /\s/.test(m[2]) && isAddress(m[1]) && !builtinSite(hostOf(m[1])))
            lookupSite(hostOf(m[1]));
    }

    function hostOf(address) {
        return address.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/^www\./i, "").toLowerCase();
    }

    function builtinSite(host) {
        return siteSearches.some((e) => e[0].test(host));
    }

    // Brand symbols (Nerd Font) for the chip; "" = unknown site, the chip then shows the address
    readonly property var siteGlyphs: [
        [/^amazon\./, "\uF270"],
        [/^youtube\.com$/, "\u{F05C3}"],
        [/^github\.com$/, "\uF09B"],
        [/^reddit\.com$/, "\uF281"],
        [/^google\./, "\uF1A0"],
        [/^twitch\.tv$/, "\uF1E8"],
        [/(^|\.)spotify\.com$/, "\uF1BC"],
        [/(^|\.)wikipedia\.org$/, "\u{F05AC}"]
    ]

    function siteGlyph(host) {
        const h = host.replace(/^www\./i, "").toLowerCase();
        for (const [re, g] of siteGlyphs) {
            if (re.test(h))
                return g;
        }
        return "";
    }

    // "amazon.de " (address and a space, nothing after it yet) -> the host for the chip, otherwise ""
    function chipHost(text) {
        const m = text.match(/^\s*\?\s*(\S+)\s$/);
        if (!m || !isAddress(m[1]) || /\//.test(m[1].replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")))
            return "";

        return m[1].replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/^www\./i, "").toLowerCase();
    }

    // "amazon.de iphone" -> { host: "amazon.de", query: "iphone", url: ... }, otherwise null
    function siteSearch(text) {
        const m = text.trim().match(/^(\S+)\s+(.+)$/);
        if (!m || !isAddress(m[1]) || /\//.test(m[1].replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")))
            return null;

        const host = m[1].replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/^www\./i, "").toLowerCase();
        const q = encodeURIComponent(m[2].trim());
        for (const [re, tpl] of siteSearches) {
            if (re.test(host) && tpl)
                return { host: host, query: m[2].trim(), url: tpl.replace("%h", host).replace("%s", q) };
        }
        const own = siteTemplates[host];
        if (own)
            return { host: host, query: m[2].trim(), url: own.replace("%s", q) };

        const engine = String(Settings.get("launcher.searchUrl") || "https://duckduckgo.com/?q=%s");
        const full = encodeURIComponent("site:" + host + " " + m[2].trim());
        return { host: host, query: m[2].trim(), url: engine.includes("%s") ? engine.replace("%s", full) : engine + full };
    }

    function webTarget(text) {
        const t = text.trim();
        const site = siteSearch(t);
        if (site)
            return site.url;

        if (isAddress(t))
            return /^[a-z][a-z0-9+.-]*:\/\//i.test(t) ? t : "https://" + t;

        const url = String(Settings.get("launcher.searchUrl") || "https://duckduckgo.com/?q=%s");
        const q = encodeURIComponent(t);
        return url.includes("%s") ? url.replace("%s", q) : url + q;
    }

    // Opens the page, then focuses the browser (it may sit on another workspace, or still be starting).
    // Window class = default browser's .desktop name, or settings.json "launcher.browserClass".
    function openWeb(text) {
        const cls = String(Settings.get("launcher.browserClass") || "");
        Quickshell.execDetached(["sh", "-c",
            'xdg-open "$1"; c="$2"; [ -n "$c" ] || c=$(xdg-settings get default-web-browser | sed "s/\\.desktop$//"); ' +
            'for i in $(seq 40); do hyprctl clients -j | grep -qi "\\"class\\": *\\"$c\\"" && break; sleep 0.25; done; ' +
            'hyprctl dispatch "hl.dsp.focus({ window = \\"class:$c\\" })"',
            "sh", webTarget(text), cls]);
    }

    // inTerminal: in a new terminal that stays open with your shell; otherwise in the background
    function runCommand(text, terminal, inTerminal) {
        if (inTerminal)
            Quickshell.execDetached({
                command: [terminal, "-e", "sh", "-c", text + '; exec "${SHELL:-sh}"'],
                environment: {"SHIORI_NO_FETCH": "1"}   // the shell's greeting (fastfetch) stays out of the way
            });
        else
            Quickshell.execDetached(["sh", "-c", text]);
    }

    // reveal: show it in the file manager instead of opening it
    function openFile(file, terminal, reveal) {
        if (file.dir || reveal)
            Quickshell.execDetached([terminal, "--class", "fzfwindows", "--name", "fzfwindows", "yazi", file.path]);
        else
            Quickshell.execDetached(["xdg-open", file.path]);
    }

    onModeChanged: {
        if (mode === "emoji")
            emojiWanted = true;

        if (mode !== "files") {
            fileDelay.stop();
            fileBusy = false;
        }
    }
    onTermChanged: {
        lookupForTerm();
        if (mode !== "files")
            return ;

        if (term.length < fileMinLength) {
            fileDelay.stop();
            fileResults = [];
            fileTerm = "";
            fileBusy = false;
            return ;
        }
        fileBusy = true;
        fileDelay.restart();
    }

    FileView {
        id: usageView

        path: root.usageFile
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                root.usage = JSON.parse(text()) || {
                };
            } catch (e) {
                root.usage = {
                };
            }
        }
    }

    FileView {
        path: root.emojiWanted ? Quickshell.shellPath("resources/emoji/emoji.json") : ""
        printErrors: false
        onLoaded: root.loadEmoji(text())
    }

    // Typing pauses: search
    Timer {
        id: fileDelay

        interval: 160
        onTriggered: {
            fileProc.forTerm = root.term;
            fileProc.running = false;
            // Hidden files and what .gitignore names stay out, like in fd itself. fd stops at the first
            // 240 it meets, takeFiles() then puts the best names first. Several words = all in the name, in this order.
            fileProc.command = ["fd", "--absolute-path", "--ignore-case", "--max-results", "240", "--exclude", "node_modules", "--", root.term.split(/\s+/).map((w) => {
                return w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            }).join(".*"), root.home];
            fileProc.running = true;
        }
    }

    Process {
        id: siteProc

        property string host: ""
        property string found: ""

        stdout: StdioCollector {
            onStreamFinished: siteProc.found = text.trim()
        }

        onExited: (code) => {
            // A failed run (network) is asked again next time; "" with exit 0 = the site has no search
            if (code !== 0)
                return ;

            const next = Object.assign({}, root.siteTemplates);
            next[host] = found;
            root.siteTemplates = next;
        }
    }

    Process {
        id: fileProc

        property string forTerm: ""

        stdout: StdioCollector {
            onStreamFinished: {
                // An answer for text that has changed meanwhile is dropped
                if (root.mode !== "files" || fileProc.forTerm !== root.term)
                    return ;

                root.takeFiles(text, fileProc.forTerm);
                root.fileBusy = false;
            }
        }

    }

}
