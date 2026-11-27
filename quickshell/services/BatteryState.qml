// Battery state for the bar icon and dropdown, vendor independent via UPower
// (runs on practically every Linux laptop). Only a real laptop battery counts;
// not controllers, mice etc. Without a battery (desktop PC): hasBattery = false.
// Power profiles (Saver/Balanced/Performance) only if power-profiles-daemon is running.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
pragma Singleton

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool hasBattery: device !== null && device.ready && device.isLaptopBattery && device.isPresent
    // Depending on the version UPower gives 0..1 or 0..100 -> always 0..100
    readonly property real percent: {
        if (!hasBattery)
            return 0;

        const p = device.percentage;
        return Math.max(0, Math.min(100, p <= 1 ? p * 100 : p));
    }
    readonly property bool charging: hasBattery && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: hasBattery && device.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery
    readonly property real watts: hasBattery ? Math.abs(device.changeRate) : 0
    readonly property real health: {
        if (!hasBattery)
            return 0;

        const h = device.healthPercentage;
        return h <= 1 && h > 0 ? h * 100 : h;
    }
    readonly property real energy: hasBattery ? device.energy : 0
    readonly property real energyCapacity: hasBattery ? device.energyCapacity : 0
    readonly property real timeToEmpty: hasBattery ? device.timeToEmpty : 0
    readonly property real timeToFull: hasBattery ? device.timeToFull : 0
    // Power profiles
    property bool hasProfiles: false
    // Only query if the service is running (otherwise Quickshell warns on every start)
    readonly property int profile: hasProfiles ? PowerProfiles.profile : -1

    // Remaining time as "2h 14m"
    function fmtDuration(secs) {
        if (!secs || secs <= 0)
            return "";

        const m = Math.round(secs / 60);
        if (m >= 60)
            return Math.floor(m / 60) + "h " + (m % 60) + "m";

        return m + "m";
    }

    // Short status for dropdown/tooltip
    function statusText() {
        if (!hasBattery)
            return "on AC power";

        if (full)
            return "fully charged";

        if (charging)
            return timeToFull > 0 ? fmtDuration(timeToFull) + " to full" : "charging";

        if (!onBattery)
            return "plugged in";

        return timeToEmpty > 0 ? fmtDuration(timeToEmpty) + " left" : "on battery";
    }

    // Color by charge: low = warning color, almost empty = error color
    function levelColor() {
        if (!hasBattery)
            return WalColors.withAlpha(WalColors.color7, 0.3);

        // Never the warning color while charging
        return charging ? Theme.accent : Theme.levelTone(percent);
    }

    // ---- Low battery: a note at 15 %, an urgent one at 5 %, each once per discharge ----
    readonly property var warnLevels: [15, 5]
    // The lowest level already warned about since the last charge (100 = none yet)
    property int warned: 100

    // The level to warn about now, or 0. Pure, so it can be tried without a battery
    function lowWarning(percent, warnedAt) {
        let hit = 0;
        for (let i = 0; i < warnLevels.length; i++) {
            if (percent <= warnLevels[i] && warnedAt > warnLevels[i])
                hit = warnLevels[i];

        }
        return hit;
    }

    function checkLow() {
        if (!hasBattery || !onBattery || charging) {
            warned = 100;
            return ;
        }
        const level = lowWarning(percent, warned);
        if (level === 0)
            return ;

        warned = level;
        const left = timeToEmpty > 0 ? " · " + fmtDuration(timeToEmpty) + " left" : "";
        NotificationState.send("Battery", level <= 5 ? "Battery almost empty" : "Battery low", Math.round(percent) + " %" + left + (level <= 5 ? " · plug in the charger" : ""), {
            "icon": level <= 5 ? "battery-empty" : "battery-caution",
            "keep": true,
            "critical": level <= 5
        });
    }

    onPercentChanged: checkLow()
    onChargingChanged: checkLow()
    onOnBatteryChanged: checkLow()

    function setProfile(p) {
        if (hasProfiles)
            PowerProfiles.profile = p;

    }

    // power-profiles-daemon there? (new and old D-Bus name)
    Process {
        running: true
        command: ["sh", "-c", "busctl --system status org.freedesktop.UPower.PowerProfiles >/dev/null 2>&1 || busctl --system status net.hadess.PowerProfiles >/dev/null 2>&1"]
        onExited: (code) => {
            root.hasProfiles = code === 0;
        }
    }

}
