import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

// Wallhaven.cc in the wallpaper picker: the plus button switches the tiles to search hits from
// wallhaven, a click downloads the original directly into the wallpaper folder.
// Only SFW (purity=100) -> the public API is enough, without an API key.
QtObject {
    id: root

    property bool browsing: false
    // Hits: { wid, url, thumb, resolution, file }; file = file name in the wallpaper folder.
    // ListModel instead of an array: new pages are only appended. A new array as the model
    // rebuilds the GridView completely and jumps back to the top.
    property ListModel results: ListModel {
    }
    // From here on the rows are new (for the fade-in animation of only the freshly loaded tiles)
    property int animFrom: 0
    property real appendedAt: 0
    property int page: 0
    property int lastPage: 1
    // Random sort: wallhaven returns a seed, so the following pages belong to the same mix
    property string seed: ""
    property bool loading: false
    property bool failed: false
    property string query: ""
    // ==== Filter ====
    property bool catGeneral: true
    property bool catAnime: true
    property bool catPeople: false
    // toplist | hot | date_added | random
    property string sorting: "toplist"
    property string minResolution: "1920x1080"
    readonly property bool filtersChanged: !catGeneral || !catAnime || catPeople || sorting !== "toplist" || minResolution !== "1920x1080"
    // Running/waiting downloads (wid -> true); the picker recognizes finished ones by the file name in the folder
    property var downloading: ({
    })
    property var queue: []
    // Drop answers for an outdated search term
    property int requestId: 0
    readonly property string apiUrl: "https://wallhaven.cc/api/v1/search"
    property Timer searchDelay: Timer {
        // Only search when typing has stopped briefly (every search is a network request)
        interval: 400
        onTriggered: root.fetch(true)
    }
    // Picker closed -> show the own wallpapers again on the next opening
    property Connections pickerWatch: Connections {
        function onActivePickerChanged() {
            if (PickerManager.activePicker !== "wallpaper")
                root.browsing = false;

        }

        target: PickerManager
    }
    property Process downloadProcess: Process {
        property var item: null

        onExited: (exitCode) => {
            const it = item;
            item = null;
            const d = Object.assign({
            }, root.downloading);
            delete d[it.wid];
            root.downloading = d;
            if (exitCode === 0) {
                WallpaperPickerState.reloadWallpapers();
                NotificationState.send("Wallpaper", "Downloaded", it.file, {
                    "image": WallpaperPickerState.wallpaperDir + it.file,
                    "timeout": 3000,
                    "success": true
                });
            } else {
                NotificationState.send("Wallpaper", "Download failed", it.file, {
                    "timeout": 3500
                });
            }
            root.nextDownload();
        }
    }

    // New search from page 1 (the picker then resets the scroll position)
    signal reset()

    function open() {
        browsing = true;
        query = "";
        fetch(true);
    }

    function close() {
        browsing = false;
        searchDelay.stop();
    }

    function setQuery(q) {
        if (!browsing || q.trim() === query)
            return ;

        query = q.trim();
        searchDelay.restart();
    }

    // Change filters -> search again right away (slightly delayed, in case several come in quick succession)
    function setFilter(name, value) {
        if (root[name] === value)
            return ;

        // At least one category must stay on, otherwise wallhaven returns nothing
        if (name.startsWith("cat") && !value && [catGeneral, catAnime, catPeople].filter((c) => {
            return c;
        }).length === 1)
            return ;

        root[name] = value;
        searchDelay.restart();
    }

    function resetFilters() {
        catGeneral = true;
        catAnime = true;
        catPeople = false;
        sorting = "toplist";
        minResolution = "1920x1080";
        searchDelay.restart();
    }

    // reset: new search from page 1, otherwise append the next page (endless scrolling)
    function fetch(reset) {
        if (!reset && (loading || page >= lastPage))
            return ;

        const id = ++requestId;
        const nextPage = reset ? 1 : page + 1;
        const cats = (catGeneral ? "1" : "0") + (catAnime ? "1" : "0") + (catPeople ? "1" : "0");
        const params = ["purity=100", "categories=" + cats, "atleast=" + minResolution, "ratios=landscape", "sorting=" + sorting, "page=" + nextPage];
        // Toplist with a search term: over a year, otherwise hardly anything is left of the month
        if (sorting === "toplist")
            params.push("topRange=" + (query !== "" ? "1y" : "1M"));

        if (sorting === "random" && !reset && seed !== "")
            params.push("seed=" + seed);

        if (query !== "")
            params.push("q=" + encodeURIComponent(query));

        loading = true;
        failed = false;
        if (reset) {
            results.clear();
            seed = "";
            root.reset();
        }
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || id !== root.requestId)
                return ;

            root.loading = false;
            try {
                const res = JSON.parse(xhr.responseText);
                const items = res.data.filter((w) => {
                    return w.file_type === "image/jpeg" || w.file_type === "image/png";
                }).map((w) => {
                    return {
                        "wid": w.id,
                        "url": w.path,
                        "thumb": w.thumbs.large,
                        "resolution": w.resolution,
                        "file": w.path.split("/").pop()
                    };
                });
                root.page = res.meta.current_page;
                root.lastPage = res.meta.last_page;
                if (res.meta.seed)
                    root.seed = res.meta.seed;

                root.animFrom = root.results.count;
                root.appendedAt = Date.now();
                root.results.append(items);
            } catch (e) {
                root.failed = true;
            }
        };
        xhr.open("GET", apiUrl + "?" + params.join("&"));
        xhr.send();
    }

    function isDownloaded(item) {
        return WallpaperPickerState.allWallpapers.some((w) => {
            return w.name === item.file;
        });
    }

    function download(item) {
        if (!item || downloading[item.wid] || isDownloaded(item))
            return ;

        const d = Object.assign({
        }, downloading);
        d[item.wid] = true;
        downloading = d;
        // Copy: the row in the ListModel may disappear with the next search
        queue = queue.concat([{
            "wid": item.wid,
            "url": item.url,
            "file": item.file
        }]);
        if (!downloadProcess.running)
            nextDownload();

    }

    // Download one after another: easier on the line, and wallhaven throttles many parallel requests
    function nextDownload() {
        if (queue.length === 0)
            return ;

        const it = queue[0];
        queue = queue.slice(1);
        downloadProcess.item = it;
        // First into a hidden file: otherwise the picker lists a half-downloaded image
        downloadProcess.command = ["bash", "-c", 'tmp="$2/.$3.part"; curl -fsL --max-time 180 -o "$tmp" "$1" && mv -f "$tmp" "$2/$3" || { rm -f "$tmp"; exit 1; }', "_", it.url, WallpaperPickerState.wallpaperDir.replace(/\/$/, ""), it.file];
        downloadProcess.running = true;
    }
}
