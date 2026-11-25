.pragma library

function limitWindow(w, now, updated) {
    const unknown = {known: false, used: 0, left: 0, resetMs: 0};
    if (!w)
        return unknown;

    const percent = w.used_percentage ?? w.utilization;
    if (typeof percent !== "number" || !Number.isFinite(percent))
        return unknown;

    let r = w.resets_at;
    let resetMs = 0;
    if (typeof r === "number")
        resetMs = r > 1e+12 ? r : r * 1000;
    else if (typeof r === "string" && r !== "")
        resetMs = Date.parse(r) || 0;
    if (resetMs > 0 ? resetMs <= now : now - updated * 1000 > 900000)
        return unknown;
    const used = Math.max(0, Math.min(100, percent));
    return {
        "known": true,
        "used": used,
        "left": 100 - used,
        "resetMs": resetMs
    };
}

// 8040000 ms -> "2h 14m"
function resetIn(ms, nowMs) {
    if (!ms)
        return "";

    const m = Math.max(0, Math.round((ms - nowMs) / 60000));
    if (m >= 1440)
        return Math.floor(m / 1440) + "d " + Math.floor((m % 1440) / 60) + "h";

    if (m >= 60)
        return Math.floor(m / 60) + "h " + (m % 60) + "m";

    return m + "m";
}

// 1234 -> "1.2K", 5106890 -> "5.11M"
function fmt(n) {
    n = Number(n) || 0;
    if (n >= 1e+09)
        return (n / 1e+09).toFixed(2) + "B";

    if (n >= 1e+06)
        return (n / 1e+06).toFixed(n >= 1e+08 ? 0 : (n >= 1e+07 ? 1 : 2)) + "M";

    if (n >= 1000)
        return (n / 1000).toFixed(n >= 100000 ? 0 : 1) + "K";

    return String(n);
}
