#!/usr/bin/env python3
"""Drives for the stats dropdown (StatsProvider.qml): one JSON line on stdout, then it ends.

  {"disks": [{"name": "nvme1n1", "label": "System", "kind": "NVMe", "model": "Samsung SSD 990 PRO 2TB",
              "size": 2000398934016, "mounted": true, "used": 1580000000000, "total": 1960000000000,
              "percent": 85, "temp": 39.9, "system": true}, ...]}

One entry per physical drive (lsblk type "disk"), whatever it is: NVMe, SATA SSD, hard disk, USB, SD card.
- kind: "NVMe", "SSD", "HDD", "USB", "SD", "eMMC" or "Disk" (virtual drives, where the kernel cannot tell).
- used/total/percent: all mounted data filesystems of the drive together (also below LUKS and LVM). /boot,
  the EFI partition and swap do not count. percent is used / (used + free for the user), like df.
- mounted false: nothing of the drive is mounted. Its usage cannot be read then, only the size.
- temp: degrees Celsius from the kernel's hwmon (NVMe always, SATA only with the drivetemp module), else null.
- Order: system drive first, then the mounted ones by size, then the rest by size.
If "/" lies on no listed drive (ZFS, a network root ...), an entry for "/" alone comes first.

Without root. For tests: DISK_STATS_LSBLK = file with the output of the lsblk call below.
"""

import glob
import json
import os
import subprocess
import sys

COLUMNS = "NAME,PATH,TYPE,SIZE,ROTA,TRAN,MODEL,RM,FSTYPE,LABEL,MOUNTPOINTS,FSSIZE,FSUSED,FSAVAIL"
# Not drives: compressed RAM, loop files, RAM disks, floppy, optical
SKIP_NAMES = ("zram", "loop", "ram", "fd", "sr")
# Mounted, but not a place for your files
SKIP_MOUNTS = ("/boot", "/efi", "/esp")


def lsblk():
    fixture = os.environ.get("DISK_STATS_LSBLK")
    if fixture:
        with open(fixture) as fh:
            return json.load(fh)
    try:
        out = subprocess.run(["lsblk", "-J", "-b", "-o", COLUMNS], capture_output=True, text=True, timeout=10).stdout
        return json.loads(out)
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def num(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def mounts_of(node):
    return [m for m in (node.get("mountpoints") or []) if m]


def is_data_mount(mount):
    if mount == "[SWAP]":
        return False
    return not any(mount == skip or mount.startswith(skip + "/") for skip in SKIP_MOUNTS)


def walk(node):
    """The node itself and everything below it (partitions, LUKS, LVM ...)."""
    yield node
    for child in node.get("children") or []:
        yield from walk(child)


def kind_of(disk):
    name = disk.get("name") or ""
    tran = (disk.get("tran") or "").lower()
    if tran == "nvme":
        return "NVMe"
    if tran == "usb":
        return "USB"
    if name.startswith("mmcblk"):
        return "SD" if disk.get("rm") else "eMMC"
    # Virtual drives report "rotating" at random
    if tran == "virtio" or name.startswith(("vd", "xvd")):
        return "Disk"
    return "HDD" if disk.get("rota") else "SSD"


def temp_of(name):
    """hwmon of the drive: NVMe hangs it on the controller, SATA (drivetemp) on the device, both below device/."""
    for path in sorted(glob.glob(f"/sys/block/{name}/device/hwmon*/temp1_input")):
        try:
            with open(path) as fh:
                return round(int(fh.read().strip()) / 1000, 1)
        except (OSError, ValueError):
            continue
    return None


def name_of_mount(mount, label):
    if mount == "/":
        return "System"
    return label or os.path.basename(mount.rstrip("/")) or mount


def describe(disk):
    name = disk.get("name") or ""
    model = (disk.get("model") or "").strip()
    entry = {
        "name": name,
        "label": "",
        "kind": kind_of(disk),
        "model": model,
        "size": num(disk.get("size")),
        "mounted": False,
        "used": 0,
        "total": 0,
        "percent": 0,
        "temp": None if os.environ.get("DISK_STATS_LSBLK") else temp_of(name),
        "system": False,
    }
    # Every filesystem once, even if it is mounted in several places (btrfs subvolumes)
    seen = set()
    data = []
    for node in walk(disk):
        mounts = [m for m in mounts_of(node) if is_data_mount(m)]
        path = node.get("path") or node.get("name")
        if not mounts or path in seen:
            continue
        seen.add(path)
        data.append((node, mounts))
    if data:
        used = sum(num(node.get("fsused")) for node, _ in data)
        total = sum(num(node.get("fssize")) for node, _ in data)
        free = sum(num(node.get("fsavail")) for node, _ in data)
        entry["mounted"] = True
        entry["used"] = used
        entry["total"] = total
        entry["percent"] = round(100 * used / (used + free)) if used + free > 0 else 0
        entry["system"] = any("/" in mounts for _, mounts in data)
        if entry["system"]:
            entry["label"] = "System"
        else:
            node, mounts = max(data, key=lambda item: num(item[0].get("fssize")))
            entry["label"] = name_of_mount(sorted(mounts, key=len)[0], node.get("label"))
    else:
        labelled = [n for n in walk(disk) if n.get("label")]
        if labelled:
            entry["label"] = max(labelled, key=lambda n: num(n.get("size"))).get("label")
    entry["label"] = entry["label"] or model or name
    return entry


def root_alone():
    """"/" from statvfs, for systems whose root lies on no block device lsblk shows."""
    try:
        st = os.statvfs("/")
    except OSError:
        return None
    total = st.f_blocks * st.f_frsize
    free_all = st.f_bfree * st.f_frsize
    free = st.f_bavail * st.f_frsize
    used = total - free_all
    return {
        "name": "/", "label": "System", "kind": "Disk", "model": "", "size": total, "mounted": True,
        "used": used, "total": total, "percent": round(100 * used / (used + free)) if used + free > 0 else 0,
        "temp": None, "system": True,
    }


def main():
    disks = []
    for dev in lsblk().get("blockdevices") or []:
        name = dev.get("name") or ""
        if dev.get("type") != "disk" or name.startswith(SKIP_NAMES) or num(dev.get("size")) <= 0:
            continue
        disks.append(describe(dev))
    if not any(d["system"] for d in disks) and not os.environ.get("DISK_STATS_LSBLK"):
        alone = root_alone()
        if alone:
            disks.append(alone)
    disks.sort(key=lambda d: (not d["system"], not d["mounted"], -(d["total"] or d["size"])))
    json.dump({"disks": disks}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
