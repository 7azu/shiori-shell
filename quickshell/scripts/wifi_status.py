#!/usr/bin/env python3
# Wi-Fi state for services/WifiState.qml, as one JSON line:
#   {"device", "state", "connection", "radio", "ip", "saved": [names], "networks": [...]}
# networks: one entry per SSID (strongest access point), sorted: active, saved, signal.
#   {"ssid", "signal", "security", "secure", "inUse", "saved", "freq", "band"}
# The source is nmcli in terse mode (-t): fields separated by ":", ":" inside a field as "\:".
# Does not scan itself (--rescan no); WifiState rescans ("nmcli device wifi rescan").

import json
import subprocess


def nmcli(*args):
    try:
        out = subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=8)
        return out.stdout if out.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def fields(line):
    # Split a terse line: "\:" and "\\" are escaped
    out, cur, esc = [], [], False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def main():
    res = {"device": "", "state": "", "connection": "", "radio": False, "ip": "", "saved": [], "networks": []}

    # First Wi-Fi device (p2p-dev-* is not a separate adapter)
    for line in nmcli("-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device").splitlines():
        f = fields(line)
        if len(f) >= 4 and f[1] == "wifi":
            res["device"], res["state"], res["connection"] = f[0], f[2].split(" ")[0], f[3]
            break

    res["radio"] = nmcli("radio", "wifi").strip() == "enabled"

    for line in nmcli("-t", "-f", "NAME,TYPE", "connection", "show").splitlines():
        f = fields(line)
        if len(f) >= 2 and f[1] == "802-11-wireless":
            res["saved"].append(f[0])

    if res["device"] and res["state"] == "connected":
        addr = nmcli("-g", "IP4.ADDRESS", "device", "show", res["device"]).strip().splitlines()
        res["ip"] = addr[0].split("/")[0] if addr else ""

    if res["device"] and res["radio"]:
        best = {}
        for line in nmcli("-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ", "device", "wifi", "list", "--rescan", "no").splitlines():
            f = fields(line)
            if len(f) < 5 or f[1] == "":
                continue  # hidden networks without a name
            try:
                signal = int(f[2])
            except ValueError:
                signal = 0
            sec = f[3].strip()
            try:
                freq = int(f[4].split()[0])
            except (ValueError, IndexError):
                freq = 0
            n = {
                "ssid": f[1],
                "signal": signal,
                "security": "" if sec in ("", "--") else sec,
                "secure": sec not in ("", "--"),
                "inUse": f[0].strip() == "*",
                "saved": f[1] in res["saved"],
                "freq": freq,
                "band": "6 GHz" if freq >= 5925 else ("5 GHz" if freq >= 4900 else ("2.4 GHz" if freq else "")),
            }
            old = best.get(n["ssid"])
            if old is None or n["inUse"] or (not old["inUse"] and n["signal"] > old["signal"]):
                best[n["ssid"]] = n
        res["networks"] = sorted(best.values(), key=lambda n: (not n["inUse"], not n["saved"], -n["signal"], n["ssid"].lower()))

    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
