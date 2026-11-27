#!/usr/bin/env python3
"""Weather for the calendar panel (services/WeatherState.qml). One JSON line:

  {"ok": true, "place": "Tokyo", "region": "Japan", "source": "search", "unit": "c",
   "now": {"temp": 12.3, "feels": 10.1, "code": 61, "day": true, "wind": 14.0},
   "days": [{"date": "2026-11-27", "code": 3, "max": 9.1, "min": 2.0}, ...]}

or {"ok": false, "error": "offline" | "unknown place" | "no place" | "bad answer", "place": "<asked>"}.

  weather.py [--place NAME] [--unit c|f]

Where: the place the user typed (setting weather.place), looked up once at Open-Meteo's geocoding
service and then remembered in ~/.cache/quickshell/weather-places.json. Without a place: the same rough
position the night light uses (scripts/tz_location.py: location.json, else the main city of the time
zone). Data: api.open-meteo.com, no key and no account; only the coordinates are sent.

`code` is the WMO weather code, turned into a symbol and words in WeatherState.

For tests: WEATHER_FIXTURE = a file with the forecast answer (and WEATHER_GEO_FIXTURE for the place
search), then nothing is asked on the network.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

import tz_location

GEO_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
TIMEOUT = 8
DAYS = 7


def cache_file():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "quickshell", "weather-places.json")


def read_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def fetch(url, params, fixture_env):
    fixture = os.environ.get(fixture_env)
    if fixture:
        return read_json(fixture)
    request = urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers={"User-Agent": "shiori-shell"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as answer:
        return json.load(answer)


def search_place(name):
    """The typed place -> {name, region, lat, lon}. Remembered, so each place is asked only once."""
    key = name.strip().lower()
    cache = read_json(cache_file())
    if not isinstance(cache, dict):
        cache = {}
    hit = cache.get(key)
    if isinstance(hit, dict) and "lat" in hit and not os.environ.get("WEATHER_GEO_FIXTURE"):
        return hit
    data = fetch(GEO_URL, {"name": name.strip(), "count": 1, "language": "en", "format": "json"}, "WEATHER_GEO_FIXTURE")
    results = (data or {}).get("results") or []
    if not results:
        return None
    first = results[0]
    place = {"name": first.get("name") or name.strip(), "region": first.get("country") or "",
             "lat": first["latitude"], "lon": first["longitude"]}
    cache[key] = place
    try:
        os.makedirs(os.path.dirname(cache_file()), exist_ok=True)
        with open(cache_file(), "w") as fh:
            json.dump(cache, fh)
    except OSError:
        pass
    return place


def rough_place():
    """No place typed: location.json or the main city of the time zone, as for the night light."""
    found = tz_location.from_file() or tz_location.from_zone()
    if not found:
        return None
    zone = found.get("zone") or ""
    name = zone.split("/")[-1].replace("_", " ") if zone else ""
    return {"name": name, "region": "", "lat": found["lat"], "lon": found["lon"], "source": found["source"]}


def forecast(place, unit):
    params = {
        "latitude": place["lat"],
        "longitude": place["lon"],
        "current": "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
        "forecast_days": DAYS,
        "timezone": "auto",
    }
    if unit == "f":
        params["temperature_unit"] = "fahrenheit"
        params["wind_speed_unit"] = "mph"
    data = fetch(FORECAST_URL, params, "WEATHER_FIXTURE")
    if not isinstance(data, dict):
        raise ValueError("no forecast")
    current = data["current"]
    daily = data["daily"]
    days = []
    for i, date in enumerate(daily["time"]):
        days.append({"date": date, "code": int(daily["weather_code"][i]),
                     "max": daily["temperature_2m_max"][i], "min": daily["temperature_2m_min"][i]})
    return {
        "now": {"temp": current["temperature_2m"], "feels": current["apparent_temperature"],
                "code": int(current["weather_code"]), "day": bool(current["is_day"]),
                "wind": current["wind_speed_10m"]},
        "days": days,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--place", default="")
    parser.add_argument("--unit", default="c", choices=("c", "f"))
    args = parser.parse_args()
    asked = args.place.strip()

    def fail(error):
        json.dump({"ok": False, "error": error, "place": asked}, sys.stdout)
        sys.stdout.write("\n")

    try:
        if asked:
            place = search_place(asked)
            if not place:
                return fail("unknown place")
            source = "search"
        else:
            place = rough_place()
            if not place:
                return fail("no place")
            source = place["source"]
        result = forecast(place, args.unit)
    except (urllib.error.URLError, TimeoutError, OSError):
        return fail("offline")
    except (KeyError, TypeError, ValueError, IndexError):
        return fail("bad answer")
    result.update({"ok": True, "place": place["name"], "region": place["region"], "source": source, "unit": args.unit})
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
