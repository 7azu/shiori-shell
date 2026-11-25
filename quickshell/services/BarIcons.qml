// Which icons the bar shows and in which order
// (right-click the logo = edit: click = on/off, drag = move).
// File (created on the first change): ~/.config/quickshell-local/bar-icons.json
//   { "hidden": ["media", "stats"], "order": { "left": ["apps", "clipboard"], "right": ["vpn", "claude"] } }

import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

Singleton {
    id: root

    // IDs of the hidden icons. Unknown IDs do not matter -> new icons are on by default.
    property var hidden: []
    // Order per group ("left" = drawer, "right" = icon group on the right). "power" stands on its own
    // at the far right: only on/off, a "power" from older files is ignored by orderOf.
    property var order: ({
    })
    readonly property string localFile: MachineConfig.dir + "/bar-icons.json"

    function shown(id) {
        return hidden.indexOf(id) === -1;
    }

    function toggle(id) {
        const list = hidden.slice();
        const i = list.indexOf(id);
        if (i === -1)
            list.push(id);
        else
            list.splice(i, 1);
        hidden = list;
        save();
    }

    // Order of a group: saved IDs (only known ones). New icons that did not exist when saving
    // come after their predecessor from the default order (e.g. Wi-Fi after
    // Bluetooth), instead of at the end.
    function orderOf(group, defaults) {
        const out = Array.isArray(order[group]) ? order[group].filter((id) => {
            return defaults.indexOf(id) !== -1;
        }) : [];
        for (let i = 0; i < defaults.length; i++) {
            const id = defaults[i];
            if (out.indexOf(id) !== -1)
                continue;

            let at = 0;
            for (let j = i - 1; j >= 0; j--) {
                const k = out.indexOf(defaults[j]);
                if (k !== -1) {
                    at = k + 1;
                    break;
                }
            }
            out.splice(at, 0, id);
        }
        return out;
    }

    // persist = false while dragging (only reorder live), it is saved on release
    function setOrder(group, ids, persist) {
        const o = Object.assign({
        }, order);
        o[group] = ids;
        order = o;
        if (persist)
            save();

    }

    // Renamed icons: old IDs from files saved earlier (anime picker -> media picker)
    function renamed(id) {
        return id === "anime" ? "media" : id;
    }

    function applyRaw(raw) {
        let cfg = {
        };
        try {
            cfg = JSON.parse(raw && raw.length > 0 ? raw : "{}");
        } catch (e) {
            console.warn("BarIcons: bar-icons.json invalid:", e);
        }
        hidden = Array.isArray(cfg.hidden) ? cfg.hidden.filter((x) => {
            return typeof x === "string";
        }).map(renamed) : [];
        const o = {
        };
        if (cfg.order && typeof cfg.order === "object") {
            for (const g in cfg.order) o[g] = Array.isArray(cfg.order[g]) ? cfg.order[g].map(renamed) : cfg.order[g]
        }
        order = o;
    }

    function save() {
        cfgFile.setText(JSON.stringify({
            "hidden": hidden,
            "order": order
        }, null, 2) + "\n");
    }

    FileView {
        id: cfgFile

        path: root.localFile
        printErrors: false
        onLoaded: root.applyRaw(text())
        onLoadFailed: root.applyRaw("")
    }

}
