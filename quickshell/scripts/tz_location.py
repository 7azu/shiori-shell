#!/usr/bin/env python3
"""Where this machine roughly is, for sunrise and sunset (services/NightLight.qml). One JSON line:

  {"lat": 52.5, "lon": 13.37, "source": "timezone", "zone": "Europe/Berlin"}

Nothing is asked on the network. Sources, in this order:
- ~/.config/quickshell-local/location.json ({"lat": .., "lon": ..}), the same file the VPN globe reads.
  "source": "file".
- The time zone: its main city from the system's zone table (zone1970.tab). The sun times are then off
  by up to half an hour inside a large zone, which is fine for a night light. "source": "timezone".
Neither works: {"lat": null, "lon": null, "source": "none"}.

For tests: TZ_LOCATION_FILE = another location.json, TZ_LOCATION_ZONE = a zone name instead of the system's.
"""

import json
import os
import re
import sys

ZONE_TABLES = ("/usr/share/zoneinfo/zone1970.tab", "/usr/share/zoneinfo/zone.tab")


def from_file():
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    path = os.environ.get("TZ_LOCATION_FILE") or os.path.join(config, "quickshell-local", "location.json")
    try:
        with open(path) as fh:
            data = json.load(fh)
        lat, lon = float(data["lat"]), float(data["lon"])
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    return {"lat": lat, "lon": lon, "source": "file", "zone": ""}


def system_zone():
    zone = os.environ.get("TZ_LOCATION_ZONE")
    if zone:
        return zone
    # /etc/localtime links to .../zoneinfo/<Area>/<City>
    try:
        target = os.path.realpath("/etc/localtime")
    except OSError:
        target = ""
    if "/zoneinfo/" in target:
        return target.split("/zoneinfo/", 1)[1]
    try:
        with open("/etc/timezone") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def degrees(text):
    """ISO 6709 part as the table writes it: +DDMM, +DDMMSS, +DDDMM or +DDDMMSS."""
    sign = -1 if text[0] == "-" else 1
    digits = text[1:]
    # Latitude has 2 degree digits (4 or 6 in all), longitude 3 (5 or 7)
    deg_len = 2 if len(digits) in (4, 6) else 3
    deg = int(digits[:deg_len])
    minutes = int(digits[deg_len:deg_len + 2])
    seconds = int(digits[deg_len + 2:] or 0)
    return sign * (deg + minutes / 60 + seconds / 3600)


def from_zone():
    zone = system_zone()
    if not zone:
        return None
    for table in ZONE_TABLES:
        try:
            with open(table) as fh:
                for line in fh:
                    if line.startswith("#"):
                        continue
                    parts = line.rstrip("\n").split("\t")
                    if len(parts) < 3 or parts[2] != zone:
                        continue
                    found = re.fullmatch(r"([+-]\d{4}(?:\d{2})?)([+-]\d{5}(?:\d{2})?)", parts[1])
                    if not found:
                        continue
                    return {"lat": round(degrees(found.group(1)), 3), "lon": round(degrees(found.group(2)), 3),
                            "source": "timezone", "zone": zone}
        except OSError:
            continue
    return None


def main():
    place = from_file() or from_zone() or {"lat": None, "lon": None, "source": "none", "zone": ""}
    json.dump(place, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
