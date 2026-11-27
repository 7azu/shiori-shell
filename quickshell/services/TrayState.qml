pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

// Tray programs (Steam, chat apps, input method ...): what they are and which ones are shown. The panel
// A right-click on the logo of the bar opens a drawer with their icons (bar/TrayDrawer.qml); their menus
// and the keyboard go through the panel bar/TrayPanel.qml.
// The programs announce themselves over D-Bus (StatusNotifierItem); Quickshell's SystemTray is the place
// they report to. It only starts once it is asked for, so with the icon off nothing reports here.
// Hidden ones: ids in settings.json, "tray": { "hidden": ["Fcitx"] } (hide and show in the panel).
Singleton {
    id: root

    // Switched on and off in the settings ("Bar & Features"); off means no tray at all
    readonly property bool enabled: BarIcons.shown("tray")
    readonly property var all: enabled ? SystemTray.items.values : []
    readonly property var hiddenIds: {
        const h = Settings.get("tray.hidden");
        return Array.isArray(h) ? h : [];
    }
    // In the panel: also list the hidden ones (dimmed), to bring one back
    property bool showHidden: false
    // Programs that were just told to exit. They take a few seconds to shut down and to take their icon
    // away; the icon goes at once. If one is still there after exitPatience (it asked "really quit?" and
    // the answer was no), its icon comes back.
    property var exiting: []
    readonly property int exitPatience: 12000
    readonly property var items: all.filter((item) => {
        return exiting.indexOf(item) === -1 && (showHidden || !isHidden(item));
    })
    readonly property int count: items.length
    readonly property int hiddenCount: all.filter((item) => {
        return isHidden(item);
    }).length
    // A program wants attention (a new message ...)
    readonly property bool attention: all.some((item) => {
        return !isHidden(item) && item.status === Status.NeedsAttention;
    })

    // ids of the programs that cannot be brought up with a click: all they have is their menu
    // (scripts/tray_probe.py asks D-Bus, Quickshell itself does not say)
    property var menuOnly: []

    // Words a program's menu uses for "bring my window up" and for "quit", best first. Steam has no
    // entry called Open: its Library is the window.
    readonly property var openWords: ["open", "show", "restore", "library", "öffnen", "anzeigen"]
    readonly property var exitWords: ["exit", "quit", "beenden", "schließen", "close"]
    // A service (input method, network ...) has no window of its own; what it can open is its settings
    readonly property var settingsWords: ["settings", "preferences", "configure", "configuration", "einstellungen", "konfigurieren"]
    // The program whose context menu (Open / Exit) is shown, and where (bar/TrayContextMenu); menuX = middle
    // of its icon on the bar's screen
    property var menuProgram: null
    property bool menuOpen: false
    property real menuX: 0
    property double menuClosedAt: 0

    signal toggleRequested()

    // Entries of a program's menu, top level (its menu is kept loaded by the openers below)
    function entriesOf(item) {
        const at = all.indexOf(item);
        const opener = at >= 0 ? openers.objectAt(at) : null;
        return opener && opener.children ? opener.children.values : [];
    }

    // First entry of the menu whose text begins with one of the words (anywhere: has it as one of its
    // words, "Input Method Settings"); the earlier word wins
    function findEntry(item, words, anywhere) {
        const entries = entriesOf(item).filter((e) => {
            return !e.isSeparator && e.enabled && !e.hasChildren;
        });
        for (const word of words) {
            for (const e of entries) {
                // "_Quit": the underscore only marks the access key
                const text = String(e.text || "").replace(/_/g, "").trim().toLowerCase();
                if (text === word || text.startsWith(word + " ") || (anywhere && (" " + text + " ").includes(" " + word + " ")))
                    return e;

            }
        }
        return null;
    }

    // Bring the program's window up. Where the program cannot do that itself (menuOnly, see below), its
    // menu entry for it is used; without one it is started again, which makes most programs show their window.
    function open(item) {
        if (menuOnly.indexOf(item.id) === -1) {
            item.activate();
            return ;
        }
        const entry = findEntry(item, openWords);
        if (entry) {
            entry.triggered();
            return ;
        }
        const app = DesktopEntries.heuristicLookup(item.id) || DesktopEntries.heuristicLookup(nameOf(item));
        if (app)
            app.execute();

    }

    // The program says of itself that it is a service or a piece of hardware, not an application
    function isService(item) {
        return item.category === Category.SystemServices || item.category === Category.Hardware;
    }

    // "Open" of the context menu: something to look at. A menu entry for it wins; a service (the input
    // method: a plain click only switches the layout) opens its settings; anything else is opened like by a click.
    function show(item) {
        let entry = findEntry(item, openWords);
        if (!entry && isService(item))
            entry = findEntry(item, settingsWords, true);

        if (entry)
            entry.triggered();
        else
            open(item);
    }

    function canExit(item) {
        return findEntry(item, exitWords) !== null;
    }

    // Quit the program through its own menu entry (nothing is killed)
    function exit(item) {
        const entry = findEntry(item, exitWords);
        if (!entry)
            return ;

        entry.triggered();
        exiting = exiting.concat([item]);
        exitTimer.restart();
    }

    // The context menu of item below the point centerX; a second right-click on the same icon closes it
    function openMenu(item, centerX) {
        // That second click also counts as "a click elsewhere" and has just closed the menu: do not reopen it
        const justClosed = menuProgram === item && Date.now() - menuClosedAt < 250;
        if (justClosed || (menuOpen && menuProgram === item)) {
            closeMenu();
            return ;
        }
        menuProgram = item;
        menuX = centerX;
        menuOpen = true;
    }

    function closeMenu() {
        if (!menuOpen)
            return ;

        menuOpen = false;
        menuClosedAt = Date.now();
    }

    function isHidden(item) {
        return hiddenIds.indexOf(item.id) !== -1;
    }

    function setHidden(item, on) {
        const list = hiddenIds.filter((id) => {
            return id !== item.id;
        });
        if (on)
            list.push(item.id);

        Settings.set("tray.hidden", list);
    }

    function nameOf(item) {
        return item.title || item.tooltipTitle || item.id || "";
    }

    // Second line: what the program says about itself right now, if that is more than its name
    function detailOf(item) {
        const name = nameOf(item);
        const tip = String(item.tooltipTitle || "").trim();
        if (tip !== "" && tip !== name)
            return tip;

        // The description may carry markup: plain text only
        return String(item.tooltipDescription || "").replace(/<[^>]*>/g, "").trim();
    }

    function toggle() {
        toggleRequested();
    }

    // A program came or went: look again, a moment later (it registers before it is ready to be asked)
    onAllChanged: {
        probeDelay.restart();
        // Gone for real: forget it
        if (exiting.length > 0)
            exiting = exiting.filter((item) => {
            return all.indexOf(item) !== -1;
        });

    }

    // Still there after all: show it again
    Timer {
        id: exitTimer

        interval: root.exitPatience
        onTriggered: root.exiting = []
    }

    // One per program: keeps its menu loaded, so "Open" and "Exit" find their entries at once
    Instantiator {
        id: openers

        model: root.all

        delegate: QsMenuOpener {
            required property var modelData

            menu: modelData.hasMenu ? modelData.menu : null
        }

    }

    Timer {
        id: probeDelay

        interval: 400
        onTriggered: {
            if (root.all.length === 0) {
                root.menuOnly = [];
                return ;
            }
            probe.running = false;
            probe.running = true;
        }
    }

    Process {
        id: probe

        command: [Qt.resolvedUrl("../scripts/tray_probe.py").toString().replace("file://", "")]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const ids = JSON.parse(text).menuOnly;
                    root.menuOnly = Array.isArray(ids) ? ids : [];
                } catch (e) {
                }
            }
        }

    }

}
