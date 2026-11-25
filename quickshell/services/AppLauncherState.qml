import QtQuick
import Quickshell
pragma Singleton

// App list of the launcher. Comes from Quickshell's DesktopEntries (reads the .desktop files of all
// XDG folders and reports changes): newly installed apps show up without restarting the shell.
// Before, a bash loop over fixed folders ran once at start.
Singleton {
    id: root

    readonly property bool launcherVisible: PickerManager.isOpen("app")
    // All apps as light objects { name, exec, icon, terminal, file }, sorted by name
    property var allApps: []
    property bool appsLoaded: false
    // The first access triggers the reading; the result comes shortly after
    readonly property var entries: DesktopEntries.applications.values

    // For the call at start (shell.qml): only makes sure this service is created
    function loadApps() {
    }

    function rebuild() {
        // Blacklist: exact names (case-insensitive) OR unique
        // exec fragments. Short generic words like "draw", "calc",
        // "base", "math" were removed, because they wrongly hid other apps
        // like drawio.
        const blacklistExact = ["qt5", "assistant", "designer", "linguist", "qdbus", "qv4l2", "qvidcap", "avahi", "bch", "hvd", "javaws", "nvidiasettings", "displaytest", "iconbrowser", "system-config", "stoken", "emu-manager", "cmake", "texdoctk", "uuctl", "wpgtk", "xgps", "wine", "rofi", "xfce", "ark", "blackmagic", "cppcheck", "lstopo", "openjdk", "rmpc", "electron", "advanced network", "htop", "libreoffice base", "libreoffice calc", "libreoffice draw", "libreoffice impress", "libreoffice math"];
        // Exec-based filters: check the exec command, not the name.
        const blacklistExec = ["libreoffice --base", "libreoffice --calc", "libreoffice --draw", "libreoffice --impress", "libreoffice --math"];
        const apps = [];
        const seen = {
        };
        for (const e of entries) {
            if (!e || e.noDisplay)
                continue;

            const name = (e.name || "").trim();
            // Remove placeholders like %U: start without a file/URL
            const exec = (e.execString || "").replace(/%[fFuUikcnvezt]/g, "").trim();
            const nameLower = name.toLowerCase();
            const execLower = exec.toLowerCase();
            const isBlacklisted = blacklistExact.some((item) => {
                return nameLower === item;
            }) || blacklistExec.some((item) => {
                return execLower.includes(item);
            });
            // Same name several times (e.g. an own copy in ~/.local/share/applications): only once
            if (!name || !exec || isBlacklisted || seen[name])
                continue;

            seen[name] = true;
            apps.push({
                "name": name,
                "exec": exec,
                "icon": e.icon || "",
                "terminal": e.runInTerminal === true,
                "file": e.id
            });
        }
        // The shell's own settings window is found like an app (settings/SettingsWindow.qml)
        if (!seen["Shiori Settings"])
            apps.push({
            "name": "Shiori Settings",
            "exec": "qs ipc call settings open ''",
            "icon": "preferences-system",
            "terminal": false,
            "file": "shiori-settings"
        });

        apps.sort((a, b) => {
            return a.name.localeCompare(b.name);
        });
        allApps = apps;
        if (apps.length > 0)
            appsLoaded = true;

    }

    function toggle() {
        PickerManager.toggle("app");
    }

    function close() {
        if (PickerManager.isOpen("app"))
            PickerManager.close();

    }

    function open() {
        PickerManager.open("app");
    }

    onEntriesChanged: rebuild()
    // When opening with an empty list, rebuild right away: DesktopEntries reads again when a .desktop file
    // changes anywhere (update, Steam ...), and may briefly have reported an empty list then
    onLauncherVisibleChanged: {
        if (launcherVisible && allApps.length === 0)
            rebuild();

    }

    // Should there really be no app at all: do not show "Loading apps…" forever
    Timer {
        interval: 4000
        running: true
        onTriggered: root.appsLoaded = true
    }

}
