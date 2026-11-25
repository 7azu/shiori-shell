#!/usr/bin/env python3
"""GPU values and CPU temperature for the stats display (StatsProvider.qml), independent of the vendor.

Runs permanently and writes one JSON line to stdout every 2 seconds:
  {"gpu": {"kind": "dedicated|integrated|none", "vendor": "AMD", "name": "...", "usage": 17, "temp": 54},
   "cpuTemp": 61.2}
usage/temp are null if the driver does not provide them.

GPU choice: dedicated GPU before integrated; if there is none, kind = "none".
  AMD:    gpu_busy_percent; dedicated/integrated by the gpu_metrics header
          (format_revision 1 = dGPU, >= 2 = APU), otherwise by the VRAM size
  NVIDIA: always dedicated; values via nvidia-smi (if installed)
  Intel:  Arc (DG1/DG2/Battlemage) dedicated, otherwise integrated; usage from the
          idle time (RC6 or gtidle) between two measurements, without root
"""

import glob
import json
import os
import re
import subprocess
import sys
import time

INTERVAL = 2.0
VENDORS = {"0x10de": "NVIDIA", "0x1002": "AMD", "0x8086": "Intel"}


def read(path, default=None):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return default


def read_int(path):
    v = read(path)
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def pci_name(slot):
    """Short name from lspci, e.g. 'Radeon RX 9070 XT'; otherwise None."""
    try:
        out = subprocess.run(["lspci", "-s", slot, "-mm"], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.findall(r'"([^"]*)"', out)
    if len(m) < 3:
        return None
    name = m[2]
    # "Navi 48 [Radeon RX 9070/9070 XT/9070 GRE]" -> the part in square brackets is the marketing name
    br = re.search(r"\[([^\]]+)\]", name)
    return (br.group(1) if br else name).strip()


def intel_is_discrete(device_id):
    d = int(device_id, 16)
    return (0x5690 <= d <= 0x56FF) or (0xE200 <= d <= 0xE2FF) or (0x4905 <= d <= 0x4909)


def classify(vendor, dev):
    if vendor == "0x10de":
        return "dedicated"
    if vendor == "0x1002":
        try:
            with open(os.path.join(dev, "gpu_metrics"), "rb") as fh:
                hdr = fh.read(4)
            if len(hdr) == 4:
                return "dedicated" if hdr[2] == 1 else "integrated"
        except OSError:
            pass
        vram = read_int(os.path.join(dev, "mem_info_vram_total")) or 0
        return "dedicated" if vram >= 3 * 1024 ** 3 else "integrated"
    if vendor == "0x8086":
        return "dedicated" if intel_is_discrete(read(os.path.join(dev, "device"), "0x0")) else "integrated"
    return "integrated"


def detect():
    gpus = []
    for card in sorted(glob.glob("/sys/class/drm/card*")):
        if not re.search(r"card\d+$", card):
            continue
        dev = os.path.join(card, "device")
        vendor = read(os.path.join(dev, "vendor"))
        if not vendor:
            continue
        slot = os.path.basename(os.path.realpath(dev))
        gpus.append({
            "card": card,
            "dev": dev,
            "slot": slot,
            "vendorId": vendor,
            "vendor": VENDORS.get(vendor, "GPU"),
            "kind": classify(vendor, dev),
            "name": pci_name(slot) or VENDORS.get(vendor, "GPU"),
        })
    gpus.sort(key=lambda g: 0 if g["kind"] == "dedicated" else 1)
    return gpus[0] if gpus else None


def hwmon_temp(dev, prefer=("edge", "junction")):
    """Temperature from the GPU's hwmon (in degrees C)."""
    for h in glob.glob(os.path.join(dev, "hwmon", "hwmon*")):
        temps = {}
        for inp in glob.glob(os.path.join(h, "temp*_input")):
            label = read(inp.replace("_input", "_label"), os.path.basename(inp)).lower()
            v = read_int(inp)
            if v:
                temps[label] = v / 1000
        for p in prefer:
            if p in temps:
                return temps[p]
        if temps:
            return next(iter(temps.values()))
    return None


class IntelBusy:
    """Usage from the idle time difference (RC6 for i915, gtidle for xe)."""

    def __init__(self, gpu):
        cands = [os.path.join(gpu["card"], "gt", "gt0", "rc6_residency_ms"),
                 os.path.join(gpu["card"], "power", "rc6_residency_ms")]
        cands += glob.glob(os.path.join(gpu["dev"], "tile0", "gt0", "gtidle", "idle_residency_ms"))
        self.path = next((c for c in cands if read_int(c) is not None), None)
        self.prev = None

    def sample(self):
        if not self.path:
            return None
        now = time.monotonic() * 1000
        idle = read_int(self.path)
        if idle is None:
            return None
        prev, self.prev = self.prev, (now, idle)
        if not prev or now - prev[0] <= 0:
            return None
        busy = 100 * (1 - (idle - prev[1]) / (now - prev[0]))
        return max(0, min(100, round(busy)))


def nvidia_sample(slot):
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=pci.bus_id,utilization.gpu,temperature.gpu",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return None, None
    for line in out.splitlines():
        parts = [p.strip() for p in line.split(",")]
        # nvidia-smi: "00000000:01:00.0", sysfs: "0000:01:00.0"
        if len(parts) >= 3 and parts[0].lower().endswith(slot.lower()[-7:]):
            try:
                return int(parts[1]), float(parts[2])
            except ValueError:
                return None, None
    return None, None


def cpu_temp():
    by_name = {}
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        by_name.setdefault(read(os.path.join(h, "name"), ""), []).append(h)
    # (hwmon name, preferred labels) in priority: AMD, Intel, ARM
    for name, labels in (("k10temp", ("tctl", "tdie")), ("zenpower", ("tdie", "tctl")),
                         ("coretemp", ("package id 0",)), ("cpu_thermal", ()), ("soc_thermal", ())):
        for h in by_name.get(name, []):
            temps = {}
            for inp in sorted(glob.glob(os.path.join(h, "temp*_input"))):
                v = read_int(inp)
                if v:
                    temps[read(inp.replace("_input", "_label"), os.path.basename(inp)).lower()] = v / 1000
            for l in labels:
                if l in temps:
                    return temps[l]
            if temps:
                return max(temps.values())
    # Fallback: thermal zones (package sensor preferred)
    zones = {}
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        v = read_int(os.path.join(z, "temp"))
        if v:
            zones[read(os.path.join(z, "type"), "")] = v / 1000
    for t in ("x86_pkg_temp", "cpu-thermal", "acpitz"):
        if t in zones:
            return zones[t]
    return max(zones.values()) if zones else None


def main():
    gpu = detect()
    intel = IntelBusy(gpu) if gpu and gpu["vendorId"] == "0x8086" else None
    while True:
        out = {"gpu": {"kind": "none"}, "cpuTemp": cpu_temp()}
        if gpu:
            usage = temp = None
            if gpu["vendorId"] == "0x1002":
                usage = read_int(os.path.join(gpu["dev"], "gpu_busy_percent"))
                temp = hwmon_temp(gpu["dev"])
            elif gpu["vendorId"] == "0x10de":
                usage, temp = nvidia_sample(gpu["slot"])
            elif intel:
                usage = intel.sample()
                temp = hwmon_temp(gpu["dev"], prefer=("pkg", "gt"))
            out["gpu"] = {"kind": gpu["kind"], "vendor": gpu["vendor"], "name": gpu["name"],
                          "usage": usage, "temp": round(temp) if temp is not None else None}
        if out["cpuTemp"] is not None:
            out["cpuTemp"] = round(out["cpuTemp"], 1)
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
        time.sleep(INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
