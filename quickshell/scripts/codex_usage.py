#!/usr/bin/env python3
"""Summarize local Codex token-count events without reading account credentials."""

import json
import os
import tempfile
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path

CODEX_DIR = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "quickshell"
CACHE_FILE = CACHE_DIR / "codex-usage.json"


def read_session(path):
    daily = Counter()
    previous_total = 0
    limits = {}
    with path.open("rb") as stream:
        for line in stream:
            if b'"token_count"' not in line:
                continue
            try:
                event = json.loads(line)
                payload = event.get("payload")
                if event.get("type") != "event_msg" or not isinstance(payload, dict):
                    continue
                if payload.get("type") != "token_count":
                    continue
                stamp = datetime.fromisoformat(event["timestamp"])
            except (KeyError, ValueError, TypeError, AttributeError):
                continue

            snapshot = payload.get("rate_limits")
            if isinstance(snapshot, dict) and snapshot.get("limit_id") in (None, "codex"):
                windows = {
                    key: window for key in ("primary", "secondary")
                    if isinstance(window := snapshot.get(key), dict)
                    and isinstance(window.get("used_percent"), (int, float))
                }
                if windows:
                    limits = {"updated": stamp.timestamp(), **windows}

            info = payload.get("info") or {}
            total = (info.get("total_token_usage") or {}).get("total_tokens")
            if isinstance(total, int) and total > previous_total:
                daily[stamp.astimezone().date().isoformat()] += total - previous_total
                previous_total = total
    return dict(daily), limits


def load_cache():
    try:
        data = json.loads(CACHE_FILE.read_text())
        if data.get("version") == 1 and isinstance(data.get("files"), dict):
            return data["files"]
    except (OSError, ValueError, AttributeError):
        pass
    return {}


def save_cache(files):
    temp_path = None
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=CACHE_DIR, delete=False) as stream:
            temp_path = Path(stream.name)
            json.dump({"version": 1, "files": files}, stream, separators=(",", ":"))
        temp_path.replace(CACHE_FILE)
    except OSError:
        if temp_path:
            temp_path.unlink(missing_ok=True)


def usage():
    previous = load_cache()
    files = {}
    daily = Counter()
    limits = {}
    # A session can move into the archive while this reader is walking both directories.
    sessions = {path.name: path for path in (CODEX_DIR / "archived_sessions").glob("rollout-*.jsonl")}
    sessions.update({path.name: path for path in (CODEX_DIR / "sessions").rglob("rollout-*.jsonl")})
    for name, path in sessions.items():
        try:
            stat = path.stat()
            signature = [stat.st_mtime_ns, stat.st_size]
            entry = previous.get(name)
            if not entry or entry["signature"] != signature:
                totals, snapshot = read_session(path)
                entry = {"signature": signature, "daily": totals, "limits": snapshot}
        except OSError:
            continue
        files[name] = entry
        daily.update(entry["daily"])
        if entry["limits"].get("updated", 0) > limits.get("updated", 0):
            limits = entry["limits"]
    if files != previous:
        save_cache(files)

    today = date.today()
    days = [{"date": (today - timedelta(days=ago)).isoformat()} for ago in range(6, -1, -1)]
    for day in days:
        day["total"] = daily[day["date"]]
    return {
        "days": days,
        "ranges": {
            "today": {"total": days[-1]["total"]},
            "week": {"total": sum(day["total"] for day in days)},
            "all": {"total": sum(daily.values())},
        },
        "limits": limits,
    }


if __name__ == "__main__":
    print(json.dumps(usage(), separators=(",", ":")))
