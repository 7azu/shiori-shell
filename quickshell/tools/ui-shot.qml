import Quickshell
import Quickshell.Wayland
import QtQuick
import "windows"
import "services"

// Test setup for tools/ui-shot: renders the REAL image/video editor windows on the GPU and saves
// screenshots without disturbing the running shell or the screen. The windows are 1x1 pixel on the
// overlay layer (invisible, click-through, no keyboard); their content is stretched to screen size
// and captured with grabToImage. The background layer does not work: covered -> no frames, no screenshot.
// Own singletons (own qs instance): states of the running shell stay untouched.
// Controlled by environment variables (set by tools/ui-shot):
//   UI_WHICH image|video, UI_FILE, UI_OUT, UI_WAIT ms, UI_EDIT 1, UI_BROWSE 1, UI_FRAMES n, UI_W, UI_H,
//   UI_SET "name=value;name2=value" (properties of the editor window, value as JSON, otherwise text),
//   UI_CALL "objectName.function" (call after opening the browser, e.g. mediaBrowser.openSort)
ShellRoot {
    id: root

    readonly property string which: Quickshell.env("UI_WHICH") || "image"
    readonly property string file: Quickshell.env("UI_FILE") || ""
    readonly property string out: Quickshell.env("UI_OUT") || "/tmp/ui-shot.png"
    readonly property int waitMs: Number(Quickshell.env("UI_WAIT") || 3000)
    readonly property bool edit: Quickshell.env("UI_EDIT") === "1"
    readonly property bool browse: Quickshell.env("UI_BROWSE") === "1"
    readonly property int frames: Number(Quickshell.env("UI_FRAMES") || 0)
    readonly property string sets: Quickshell.env("UI_SET") || ""
    readonly property string call: Quickshell.env("UI_CALL") || ""
    readonly property int shotW: Number(Quickshell.env("UI_W") || 2560)
    readonly property int shotH: Number(Quickshell.env("UI_H") || 1440)
    readonly property var win: which === "image" ? img : vid
    property var content: null
    property int frame: 0

    function findByName(item, name) {
        if (!item)
            return null;

        if (item.objectName === name)
            return item;

        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = findByName(kids[i], name);
            if (r)
                return r;

        }
        return null;
    }

    function grab(path, last) {
        content.grabToImage((r) => {
            console.log("UI-SHOT saved", r.saveToFile(path), path);
            if (last)
                Qt.quit();

        });
    }

    ScreenshotEditor {
        id: img

        implicitWidth: 1
        implicitHeight: 1
        anchors.right: false
        anchors.bottom: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-ui-shot"
        mask: Region {
        }
    }

    VideoEditor {
        id: vid

        implicitWidth: 1
        implicitHeight: 1
        anchors.right: false
        anchors.bottom: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "qs-ui-shot"
        mask: Region {
        }
    }

    // 1) Open the file
    Timer {
        interval: 600
        running: true
        onTriggered: {
            if (root.which === "image")
                ScreenshotEditorState.openFolderFile(root.file);
            else
                VideoEditorState.open(root.file);
            muteTimer.start();
            setupTimer.start();
        }
    }

    // Otherwise the test player plays to the real speakers
    Timer {
        id: muteTimer

        interval: 300
        onTriggered: {
            if (root.which === "video")
                vid.muted = true;

        }
    }

    // 2) Stretch the content to screen size, set up the view
    Timer {
        id: setupTimer

        interval: root.waitMs
        onTriggered: {
            root.content = root.findByName(root.win.contentItem, "editorRoot");
            if (!root.content) {
                console.log("UI-SHOT error: editor did not open (file readable? supported format?)");
                Qt.quit();
                return ;
            }
            root.content.anchors.fill = undefined;
            root.content.width = root.shotW;
            root.content.height = root.shotH;
            if (root.edit)
                root.win.enlarged = false;

            actionTimer.start();
        }
    }

    // 3) Action (browser) and capture: one image after settling or an image sequence from the action
    Timer {
        id: actionTimer

        interval: 900
        onTriggered: {
            for (const pair of root.sets.split(";")) {
                const cut = pair.indexOf("=");
                if (cut <= 0)
                    continue;

                const raw = pair.substring(cut + 1);
                let value;
                try {
                    value = JSON.parse(raw);
                } catch (e) {
                    value = raw;
                }
                root.win[pair.substring(0, cut)] = value;
            }
            if (root.frames > 0) {
                if (root.browse)
                    root.win.openBrowser();

                frameTimer.start();
                return ;
            }
            if (root.browse) {
                root.win.openBrowser();
                finalTimer.interval = 1800;
            }
            if (root.call !== "") {
                callTimer.start();
                finalTimer.interval += 2500;
            }
            finalTimer.start();
        }
    }

    // Call a function of an element (UI_CALL) when the browser is ready
    Timer {
        id: callTimer

        interval: 1500
        onTriggered: {
            const cut = root.call.lastIndexOf(".");
            const target = root.findByName(root.win.contentItem, root.call.substring(0, cut));
            if (target)
                target[root.call.substring(cut + 1)]();
            else
                console.log("UI-SHOT error: no item named " + root.call.substring(0, cut));
        }
    }

    Timer {
        id: finalTimer

        interval: 600
        onTriggered: root.grab(root.out, true)
    }

    Timer {
        id: frameTimer

        interval: 70
        repeat: true
        onTriggered: {
            const last = root.frame >= root.frames - 1;
            root.grab(root.out.replace(/\.png$/, "_f" + root.frame + ".png"), last);
            root.frame++;
            if (last)
                stop();

        }
    }

    // Emergency brake, in case something hangs
    Timer {
        interval: root.waitMs + 15000
        running: true
        onTriggered: {
            console.log("UI-SHOT error: timeout");
            Qt.quit();
        }
    }

}
