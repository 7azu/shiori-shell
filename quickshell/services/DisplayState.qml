pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Monitors for the "Displays" page of the settings window (settings/DisplaysPage): arrangement,
// resolution, refresh rate, scale, rotation and on/off.
//
// The page edits a draft (one entry per monitor). "Apply" sets it live through `hyprctl eval
// hl.monitor{...}` and asks for 15 s whether to keep it; without an answer it goes back, so a mode the
// monitor cannot show never sticks. "Keep" writes ~/.config/hypr/modules/displays.lua, which hyprland.lua
// loads after monitors.lua (this machine only, ignored by git): the hand-written monitors.lua stays as it
// is, displays.lua overrides its monitor lines.
//
// Positions are Hyprland's layout coordinates: a monitor takes (width / scale) x (height / scale) there,
// with width and height swapped when it is turned by 90 or 270 degrees.
Singleton {
    id: root

    // [{ name, model, width, height, refresh, x, y, scale, transform, enabled, modes: [{ w, h, hz }] }]
    property var monitors: []
    // name -> { w, h, hz, x, y, scale, transform, enabled }; what the page shows and edits
    property var draft: ({
    })
    // The values before "Apply" (for the way back) and the seconds left to keep them
    property var before: null
    property int confirmLeft: 0
    readonly property bool confirming: confirmLeft > 0
    // Monitor names are shown big on every screen for a moment ("Identify")
    property bool identifying: false
    readonly property string file: Quickshell.env("HOME") + "/.config/hypr/modules/displays.lua"
    readonly property bool dirty: {
        for (const m of monitors) {
            if (!same(draft[m.name], stateOf(m)))
                return true;

        }
        return false;
    }

    function refresh() {
        if (!listProc.running)
            listProc.running = true;

    }

    function stateOf(m) {
        return {
            "w": m.width,
            "h": m.height,
            "hz": m.refresh,
            "x": m.x,
            "y": m.y,
            "scale": m.scale,
            "transform": m.transform,
            "enabled": m.enabled
        };
    }

    function same(a, b) {
        if (!a || !b)
            return a === b;

        return a.w === b.w && a.h === b.h && Math.abs(a.hz - b.hz) < 0.01 && a.x === b.x && a.y === b.y && Math.abs(a.scale - b.scale) < 0.001 && a.transform === b.transform && a.enabled === b.enabled;
    }

    // Size in layout coordinates
    function logical(d) {
        const w = Math.round(d.w / d.scale), h = Math.round(d.h / d.scale);
        return d.transform % 2 === 1 ? {
            "w": h,
            "h": w
        } : {
            "w": w,
            "h": h
        };
    }

    function rectOf(d) {
        const s = logical(d);
        return {
            "x": d.x,
            "y": d.y,
            "w": s.w,
            "h": s.h
        };
    }

    // The nearest free place for monitor `name` near (x, y) that touches another one: beside it,
    // edges and centers aligned when close. In layout coordinates of the given draft.
    function placeFree(dr, name, x, y) {
        const me = logical(dr[name]);
        const others = Object.keys(dr).filter((n) => {
            return n !== name && dr[n].enabled;
        }).map((n) => {
            return rectOf(dr[n]);
        });
        if (others.length === 0)
            return {
            "x": 0,
            "y": 0
        };

        const overlaps = (cx, cy) => {
            return others.some((o) => {
                return cx < o.x + o.w && cx + me.w > o.x && cy < o.y + o.h && cy + me.h > o.y;
            });
        };
        const near = 60;
        const align = (v, lo, hi, opts) => {
            let c = Math.max(lo, Math.min(hi, v));
            for (const o of opts) {
                if (Math.abs(v - o) < near)
                    c = o;

            }
            return Math.round(c);
        };
        const cands = [];
        for (const o of others) {
            // The shared edge stays long enough to move the pointer across (a corner alone is no use)
            const shareY = Math.min(200, me.h / 4, o.h / 4), shareX = Math.min(200, me.w / 4, o.w / 4);
            const ay = align(y, o.y - me.h + shareY, o.y + o.h - shareY, [o.y, o.y + o.h - me.h, o.y + (o.h - me.h) / 2]);
            const ax = align(x, o.x - me.w + shareX, o.x + o.w - shareX, [o.x, o.x + o.w - me.w, o.x + (o.w - me.w) / 2]);
            cands.push([o.x + o.w, ay], [o.x - me.w, ay], [ax, o.y + o.h], [ax, o.y - me.h]);
        }
        let best = null, bestD = Infinity;
        for (const c of cands) {
            if (overlaps(c[0], c[1]))
                continue;

            const dd = Math.hypot(c[0] - x, c[1] - y);
            if (dd < bestD) {
                bestD = dd;
                best = c;
            }
        }
        return best ? {
            "x": Math.round(best[0]),
            "y": Math.round(best[1])
        } : {
            "x": Math.round(x),
            "y": Math.round(y)
        };
    }

    function edit(name, patch) {
        const next = Object.assign({
        }, draft);
        const old = rectOf(next[name]);
        next[name] = Object.assign({
        }, next[name], patch);
        // A monitor that got another size (resolution, scale, rotation) keeps its neighbors at its
        // edges: those to the right and below move by the difference, the rest is pushed out of the way
        const now = rectOf(next[name]);
        const dw = now.w - old.w, dh = now.h - old.h;
        if ((dw !== 0 || dh !== 0) && next[name].enabled) {
            for (const n of Object.keys(next)) {
                if (n === name || !next[n].enabled)
                    continue;

                const r = rectOf(next[n]);
                const moved = Object.assign({
                }, next[n]);
                if (r.x >= old.x + old.w - 1)
                    moved.x += dw;

                if (r.y >= old.y + old.h - 1 && r.x < old.x + old.w && r.x + r.w > old.x)
                    moved.y += dh;

                next[n] = moved;
            }
            for (const n of Object.keys(next)) {
                if (n === name || !next[n].enabled)
                    continue;

                const r = rectOf(next[n]);
                if (r.x < now.x + now.w && r.x + r.w > now.x && r.y < now.y + now.h && r.y + r.h > now.y) {
                    const at = placeFree(next, n, r.x, r.y);
                    next[n] = Object.assign({
                    }, next[n], at);
                }
            }
        }
        draft = next;
    }

    function resetDraft() {
        const d = {
        };
        for (const m of monitors) d[m.name] = stateOf(m)
        draft = d;
    }

    function luaOf(name, d) {
        if (!d.enabled)
            return 'hl.monitor({ output = "' + name + '", disabled = true })';

        return 'hl.monitor({ output = "' + name + '", mode = "' + d.w + 'x' + d.h + '@' + d.hz.toFixed(2) + '", position = "' + d.x + 'x' + d.y + '", scale = ' + Number(d.scale.toFixed(3)) + ', transform = ' + d.transform + ', disabled = false })';
    }

    function send(states) {
        const lines = [];
        for (const name in states) lines.push(luaOf(name, states[name]))
        if (lines.length === 0)
            return ;

        // One eval per monitor, monitors that turn on first (so there is never none)
        lines.sort((a, b) => {
            return (a.indexOf("disabled = true") >= 0 ? 1 : 0) - (b.indexOf("disabled = true") >= 0 ? 1 : 0);
        });
        const script = lines.map((l) => {
            return "hyprctl eval '" + l.replace(/'/g, "") + "' >/dev/null";
        }).join("; ");
        applyProc.command = ["sh", "-c", script];
        applyProc.running = true;
    }

    // Set the draft live and start the question
    function apply() {
        if (!dirty || confirming)
            return ;

        const old = {
        }, changed = {
        };
        for (const m of monitors) {
            if (!same(draft[m.name], stateOf(m))) {
                old[m.name] = stateOf(m);
                changed[m.name] = draft[m.name];
            }
        }
        before = old;
        send(changed);
        confirmLeft = 15;
        countdown.restart();
    }

    function keep() {
        countdown.stop();
        confirmLeft = 0;
        before = null;
        save();
    }

    function revert() {
        countdown.stop();
        confirmLeft = 0;
        if (before)
            send(before);

        before = null;
    }

    // displays.lua: every monitor as it is in the draft
    function save() {
        const lines = ["-- Written by the Displays page of the shell settings (quickshell/services/DisplayState.qml).", "-- Loaded after monitors.lua and overrides its monitor lines; delete this file to go back to them.", ""];
        for (const m of monitors) lines.push(luaOf(m.name, draft[m.name]))
        saveView.setText(lines.join("\n") + "\n");
    }

    function identify() {
        identifying = true;
        identifyTimer.restart();
    }

    function parse(text) {
        let list = [];
        try {
            list = JSON.parse(text) || [];
        } catch (e) {
            return ;
        }
        const out = list.map((m) => {
            const seen = {
            };
            const modes = [];
            for (const s of m.availableModes || []) {
                const r = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
                if (!r)
                    continue;

                const mode = {
                    "w": Number(r[1]),
                    "h": Number(r[2]),
                    "hz": Math.round(Number(r[3]) * 100) / 100
                };
                const key = mode.w + "x" + mode.h + "@" + mode.hz;
                if (seen[key])
                    continue;

                seen[key] = true;
                modes.push(mode);
            }
            modes.sort((a, b) => {
                return b.w * b.h - a.w * a.h || b.hz - a.hz;
            });
            return {
                "name": m.name,
                "model": String((m.make || "") + " " + (m.model || "")).trim() || m.description || m.name,
                "width": m.width,
                "height": m.height,
                "refresh": Math.round(m.refreshRate * 100) / 100,
                "x": m.x,
                "y": m.y,
                "scale": m.scale,
                "transform": m.transform,
                "enabled": !m.disabled,
                "modes": modes
            };
        });
        out.sort((a, b) => {
            return a.x - b.x || a.y - b.y;
        });
        monitors = out;
        // The live state is the start of the draft; while the question runs the draft is what is live
        if (!confirming)
            resetDraft();

    }

    Process {
        id: listProc

        command: ["hyprctl", "monitors", "all", "-j"]

        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }

    }

    Process {
        id: applyProc

        onExited: refreshLater.restart()
    }

    Timer {
        id: refreshLater

        interval: 900
        onTriggered: root.refresh()
    }

    Timer {
        id: countdown

        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmLeft--;
            if (root.confirmLeft <= 0)
                root.revert();

        }
    }

    Timer {
        id: identifyTimer

        interval: 2600
        onTriggered: root.identifying = false
    }

    FileView {
        id: saveView

        path: root.file
        printErrors: false
    }

}
