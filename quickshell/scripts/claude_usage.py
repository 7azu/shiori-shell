#!/usr/bin/env python3
"""Claude Code token usage from the local session files (~/.claude/projects/**/*.jsonl).

Prints one JSON line on stdout (for ClaudeUsage.qml). The result per file is
cached in ~/.cache/quickshell/claude-usage.json, so only
new/changed sessions are read again.

Note: only Claude Code is counted. claude.ai in the browser stores nothing locally.
"""

import glob
import json
import os
import sys
import time
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
CONFIG_DIR = os.environ.get("CLAUDE_CONFIG_DIR", os.path.join(HOME, ".claude"))
PROJECTS = os.path.join(CONFIG_DIR, "projects")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "quickshell")
CACHE_FILE = os.path.join(CACHE_DIR, "claude-usage.json")
CACHE_VERSION = 1
FIELDS = ("in", "out", "cw", "cr")


def parse_file(path):
    """All answers with usage from a session file: [key, epoch, model, in, out, cw, cr]."""
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            msg = d.get("message")
            if d.get("type") != "assistant" or not isinstance(msg, dict):
                continue
            u = msg.get("usage")
            ts = d.get("timestamp")
            if not isinstance(u, dict) or not ts:
                continue
            model = msg.get("model") or "unknown"
            if model == "<synthetic>":
                continue
            try:
                epoch = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
            except ValueError:
                continue
            # Streamed answers appear several times in the log -> deduplicate by message.id + requestId
            key = "%s:%s" % (msg.get("id", ""), d.get("requestId", ""))
            rows.append([
                key, epoch, model,
                int(u.get("input_tokens") or 0),
                int(u.get("output_tokens") or 0),
                int(u.get("cache_creation_input_tokens") or 0),
                int(u.get("cache_read_input_tokens") or 0),
            ])
    return rows


def load_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as fh:
            c = json.load(fh)
        if c.get("v") == CACHE_VERSION:
            return c.get("files", {})
    except (OSError, ValueError):
        pass
    return {}


def save_cache(files):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump({"v": CACHE_VERSION, "files": files}, fh, separators=(",", ":"))
        os.replace(tmp, CACHE_FILE)
    except OSError:
        pass


def empty_bucket():
    return {"in": 0, "out": 0, "cw": 0, "cr": 0, "total": 0, "msgs": 0, "models": {}}


def add(bucket, row):
    _, _, model, i, o, cw, cr = row
    for k, v in zip(FIELDS, (i, o, cw, cr)):
        bucket[k] += v
    t = i + o + cw + cr
    bucket["total"] += t
    bucket["msgs"] += 1
    bucket["models"][model] = bucket["models"].get(model, 0) + t


def finish(bucket):
    models = sorted(bucket["models"].items(), key=lambda kv: -kv[1])
    bucket["models"] = [{"model": m, "total": t} for m, t in models]
    return bucket


def main():
    cache = load_cache()
    files = {}
    paths = glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True)
    for p in paths:
        try:
            st = os.stat(p)
        except OSError:
            continue
        sig = [st.st_mtime, st.st_size]
        hit = cache.get(p)
        if hit and hit.get("sig") == sig:
            files[p] = hit
            continue
        try:
            files[p] = {"sig": sig, "rows": parse_file(p)}
        except OSError:
            continue
    save_cache(files)

    seen = set()
    rows = []
    for f in files.values():
        for r in f["rows"]:
            if r[0] in seen:
                continue
            seen.add(r[0])
            rows.append(r)

    now = time.time()
    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    t_today = today.timestamp()
    t_week = (today - timedelta(days=6)).timestamp()
    t_5h = now - 5 * 3600

    ranges = {"today": empty_bucket(), "5h": empty_bucket(), "week": empty_bucket(), "all": empty_bucket()}
    days = [{"date": (today - timedelta(days=6 - i)).strftime("%Y-%m-%d"), "total": 0} for i in range(7)]
    day_index = {d["date"]: i for i, d in enumerate(days)}

    for r in rows:
        ep = r[1]
        add(ranges["all"], r)
        if ep >= t_week:
            add(ranges["week"], r)
            di = day_index.get(datetime.fromtimestamp(ep).strftime("%Y-%m-%d"))
            if di is not None:
                days[di]["total"] += r[3] + r[4] + r[5] + r[6]
        if ep >= t_today:
            add(ranges["today"], r)
        if ep >= t_5h:
            add(ranges["5h"], r)

    out = {
        "ok": True,
        "updated": int(now),
        "sessions": len(paths),
        "ranges": {k: finish(v) for k, v in ranges.items()},
        "days": days,
    }
    sys.stdout.write(json.dumps(out) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # QML should always get valid JSON
        sys.stdout.write(json.dumps({"ok": False, "error": str(e)}) + "\n")
