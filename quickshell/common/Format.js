.pragma library

// Shared formatters for displays (import: import "<path>/common/Format.js" as Fmt).

// Duration as "m:ss" or "h:mm:ss"; missing/negative values -> "0:00"
function clock(sec) {
    const t = Math.max(0, Math.floor(sec || 0));
    const h = Math.floor(t / 3600);
    const m = Math.floor(t % 3600 / 60);
    const ss = String(t % 60).padStart(2, "0");
    return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss;
}

// File size in B/KB/MB/GB/TB (steps of 1024), from 100 on without a decimal
function bytes(b) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let v = b;
    let i = 0;
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
    }
    return (i === 0 || v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
}

// How long ago, short: "now", "5m", "3h", "2d"; long = after that "mo" and "y". The caller gives seconds
// (rounded or not, as needed). opts: now (text under a minute), suffix (e.g. " ago"), long.
function ago(s, opts) {
    const o = opts || {};
    const suffix = o.suffix ?? "";
    if (s < 60)
        return o.now ?? "now";

    if (s < 3600)
        return Math.floor(s / 60) + "m" + suffix;

    if (s < 86400)
        return Math.floor(s / 3600) + "h" + suffix;

    if (!o.long || s < 86400 * 30)
        return Math.floor(s / 86400) + "d" + suffix;

    if (s < 86400 * 365)
        return Math.floor(s / (86400 * 30)) + "mo" + suffix;

    return Math.floor(s / (86400 * 365)) + "y" + suffix;
}
