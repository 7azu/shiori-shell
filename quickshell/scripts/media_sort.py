#!/usr/bin/env python3
"""Sort a folder by date: renames all images/videos of a folder so the oldest comes first
(button in the folder browser, windows/MediaBrowser.qml, only offered in vaults).

  plan <folder> [new|all]   reads the dates, changes nothing. Lines: {"progress": 0..1} while reading, at the end
                            {"plan": {...}} with count, sources, renames, example and "token" for apply
  apply <folder> <token> [new|all]   plans again (the token must match, otherwise the folder has changed), renames.
                            At the end {"ok": true, "renamed": n, "moved": {old: new}} or {"error": text}

Mode "new" (default): files that already follow the folder's scheme ("video_0123.mp4") stay as they
are; only the others are sorted by date and appended at the end (after the highest number). A new
video that is older than already numbered ones still ends up at the end - that is what "all" is for: everything new.

Where the date comes from (the first usable source wins):
  video  creation_time of the file (not with HandBrake: there it is the conversion date), TikTok video ID in the
         comment ("vid:v..."; the last 20 characters are an xid, its first 4 bytes a Unix timestamp =
         upload), creation_time of the streams
  image  EXIF (capture, digitization, modification), XMP/PNG text
  both   date in the file name (IMG_20230512_..., Screenshot_2023-05-12-...), then the exact date remembered in
         .alte_namen.tsv (also estimates of earlier sorts), then the modification date - but not
         when many files of the folder were copied on that day at once (then it is the copy date)
  Without a date: upload order from names like "<post>_<nr>_<medium>_..." (sequential IDs of a site),
         otherwise the previous order. Both go first: [nothing at all] [by upload ID] [by date].

Names: the existing scheme stays (common prefix + number, e.g. "video_0001", "001"), otherwise
"video_"/"bild_" + 4 digits. The extension stays. What had which name is in <parent>/.alte_namen.tsv
(columns folder, old name, new name, date, source; the old name stays the very first name).

Robust: never overwrite (renameat2 RENAME_NOREPLACE), two steps via hidden temporary names, a journal
first (.qs-sort-journal.json in the folder). If something breaks off (crash, power), the next call
(plan or apply) finishes the renaming from the journal. The list is first written as .new and
swapped at the end.
"""
import ctypes
import datetime
import errno
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from media_browse import kind, scan  # noqa: E402
from video_edit import natural_key  # noqa: E402

JOURNAL = ".qs-sort-journal.json"
TABLE = ".alte_namen.tsv"
COLUMNS = ["ordner", "alter_name", "neuer_name", "datum", "quelle"]
FMT = "%Y-%m-%d %H:%M:%S"
NOW = datetime.datetime.now()
UPLOAD_ID = re.compile(r"^(\d+)_(\d+)_(\d+)_")
XID = "0123456789abcdefghijklmnopqrstuv"
# Date in the name: 20230512_142211, 2023-05-12 14.22.11, 2023-05-12-14-22-11, just 20230512. No digit in front,
# otherwise parts of long IDs would match ("2232078_01_...")
NAME_DATE = re.compile(r"(?<![A-Za-z0-9])(20\d\d)[-_.]?([01]\d)[-_.]?([0-3]\d)"
                       r"(?:[-_. T]?([0-2]\d)[-_.:]?([0-5]\d)[-_.:]?([0-5]\d)\d{0,3})?(?![A-Za-z0-9])")
# iPhone screen recordings: "ScreenRecording_11-13-2026 12-26-46" (month first)
US_DATE = re.compile(r"(?<![A-Za-z0-9])([01]\d)-([0-3]\d)-(20\d\d)[ _]([0-2]\d)-([0-5]\d)-([0-5]\d)(?!\d)")
# The name is just a Unix timestamp (seconds or milliseconds)
EPOCH = re.compile(r"^(1\d{9})(\d{3})?$")


def emit(**kw):
    print(json.dumps(kw), flush=True)


def plausible(dt):
    return dt is not None and datetime.datetime(2000, 1, 1) <= dt <= NOW + datetime.timedelta(days=1)


def parse_date(text):
    """ISO/EXIF date -> datetime in local time (without zone) or None. With a zone ("Z", "+0200") it is converted:
    videos mostly carry UTC, iPhone .mov also local time, EXIF and file names local time - otherwise
    shots from the same evening were shifted by up to 2 h depending on the source (measured)."""
    if not text:
        return None
    m = re.match(r"\s*(\d{4})[-:](\d\d)[-:](\d\d)(?:[ T](\d\d):?(\d\d):?(\d\d)?)?(?:\.\d+)?\s*(Z|[+-]\d\d:?\d\d)?",
                 str(text))
    if not m:
        return None
    try:
        dt = datetime.datetime(*(int(p) if p else 0 for p in m.groups()[:6]))
    except ValueError:
        return None
    zone = m.group(7)
    if zone:
        if zone == "Z":
            offset = datetime.timedelta(0)
        else:
            sign = -1 if zone[0] == "-" else 1
            digits = zone[1:].replace(":", "")
            offset = sign * datetime.timedelta(hours=int(digits[:2]), minutes=int(digits[2:]))
        dt = dt.replace(tzinfo=datetime.timezone(offset)).astimezone().replace(tzinfo=None)
    return dt if plausible(dt) else None


def xid_time(vid):
    tail = vid[-20:]
    if len(tail) != 20 or any(c not in XID for c in tail):
        return None
    n = 0
    for c in tail:
        n = n * 32 + XID.index(c)
    try:
        dt = datetime.datetime.fromtimestamp((n >> 4) >> 64)
    except (OverflowError, OSError, ValueError):
        return None
    return dt if plausible(dt) and dt.year >= 2016 else None


def name_date(name):
    # "<post>_<nr>_<medium>_<code>": the code is random, digits in it are not a date
    if UPLOAD_ID.match(name):
        return None
    stem = os.path.splitext(name)[0]
    m = EPOCH.match(stem)
    if m:
        dt = datetime.datetime.fromtimestamp(int(m.group(1)))
        if plausible(dt):
            return dt
    m = US_DATE.search(name)
    if m:
        mo, d, y, h, mi, s = (int(g) for g in m.groups())
        try:
            dt = datetime.datetime(y, mo, d, h, mi, s)
        except ValueError:
            dt = None
        if plausible(dt):
            return dt
    for m in NAME_DATE.finditer(name):
        y, mo, d, h, mi, s = (int(g) if g else 0 for g in m.groups())
        try:
            dt = datetime.datetime(y, mo, d, h, mi, s)
        except ValueError:
            continue
        if plausible(dt):
            return dt
    return None


def video_dates(path):
    """Candidates from the metadata of a video, best first: [(date, source, from_handbrake)].
    Whether a HandBrake date is the conversion date is decided by make_plan for the whole folder."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags:stream_tags", "-of", "json", path],
                             capture_output=True, text=True, timeout=60).stdout
        data = json.loads(out or "{}")
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        return []
    tags = {k.lower(): v for k, v in (data.get("format", {}).get("tags") or {}).items()}
    handbrake = str(tags.get("encoder", "")).lower().startswith("handbrake")
    found = []
    for key in ("com.apple.quicktime.creationdate", "creation_time"):
        dt = parse_date(tags.get(key))
        if dt:
            found.append((dt, "meta", handbrake))
            break
    m = re.search(r"vid:(v\w+)", str(tags.get("comment", "")))
    if m:
        dt = xid_time(m.group(1))
        if dt:
            found.append((dt, "tiktok", False))
    stream = [parse_date((s.get("tags") or {}).get("creation_time")) for s in data.get("streams", [])]
    stream = [d for d in stream if d]
    if stream:
        found.append((min(stream), "stream", handbrake))
    return found


def image_dates(path):
    """[(date, source, False)] from EXIF/XMP/PNG text or []."""
    try:
        from PIL import Image
        with Image.open(path) as im:
            exif = im.getexif()
            values = dict(exif.items())
            values.update(exif.get_ifd(0x8769).items())
            for tag in (36867, 36868, 306):  # DateTimeOriginal, DateTimeDigitized, DateTime
                dt = parse_date(values.get(tag))
                if dt:
                    return [(dt, "meta", False)]
            for key, value in (im.info or {}).items():
                if isinstance(value, str) and "creation" in key.lower():
                    dt = parse_date(value)
                    if dt:
                        return [(dt, "meta", False)]
    except Exception:  # broken/unknown images: no date, continue with the other sources
        pass
    try:
        with open(path, "rb") as f:
            head = f.read(262144)
        m = re.search(rb"(?:xmp:CreateDate|photoshop:DateCreated|exif:DateTimeOriginal)[=>\"']+([0-9:T -]{10,19})", head)
        if m:
            dt = parse_date(m.group(1).decode(errors="replace"))
            if dt:
                return [(dt, "meta", False)]
    except OSError:
        pass
    return []


# ---------- .alte_namen.tsv ----------

def read_table(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return rows
    for line in lines[1:]:
        if not line.strip():
            continue
        cells = line.split("\t")
        cells += [""] * (len(COLUMNS) - len(cells))
        rows.append(dict(zip(COLUMNS, cells[:len(COLUMNS)])))
    return rows


def table_text(rows):
    return "\t".join(COLUMNS) + "\n" + "".join("\t".join(r.get(c, "") for c in COLUMNS) + "\n" for r in rows)


def write_synced(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    sync_dir(os.path.dirname(path))


def sync_dir(folder):
    try:
        fd = os.open(folder, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        pass


# ---------- Renaming ----------

_libc = ctypes.CDLL(None, use_errno=True)


def rename_noreplace(src, dst):
    """Like os.rename, but never over an existing file (then FileExistsError)."""
    try:
        r = _libc.renameat2(-100, os.fsencode(src), -100, os.fsencode(dst), 1)  # AT_FDCWD, RENAME_NOREPLACE
    except AttributeError:
        r, err = -1, errno.ENOSYS
    else:
        err = ctypes.get_errno() if r != 0 else 0
    if r == 0:
        return
    if err == errno.EEXIST:
        raise FileExistsError(errno.EEXIST, "target exists", dst)
    if err in (errno.EINVAL, errno.ENOSYS):
        # File system without RENAME_NOREPLACE: check and then rename normally
        if os.path.lexists(dst):
            raise FileExistsError(errno.EEXIST, "target exists", dst)
        os.rename(src, dst)
        return
    raise OSError(err, os.strerror(err), src)


def recover(folder):
    """Finish an interrupted sort. Returns the mapping old -> new (or None)."""
    jpath = os.path.join(folder, JOURNAL)
    try:
        with open(jpath, encoding="utf-8") as f:
            journal = json.load(f)
    except FileNotFoundError:
        return None
    entries = journal["entries"]
    if journal.get("phase", 1) == 1:
        # Step 1 interrupted: whatever still has its old name now gets its temporary name
        for e in entries:
            src, tmp = os.path.join(folder, e["from"]), os.path.join(folder, e["tmp"])
            if not os.path.lexists(tmp) and os.path.lexists(src):
                rename_noreplace(src, tmp)
        journal["phase"] = 2
        write_synced(jpath, json.dumps(journal))
    for e in entries:
        tmp, dst = os.path.join(folder, e["tmp"]), os.path.join(folder, e["to"])
        if os.path.lexists(tmp):
            rename_noreplace(tmp, dst)
    sync_dir(folder)
    table, new_table = journal.get("table"), journal.get("table") and journal["table"] + ".new"
    if new_table and os.path.exists(new_table):
        os.replace(new_table, table)
        sync_dir(os.path.dirname(table))
    os.remove(jpath)
    sync_dir(folder)
    return {os.path.join(folder, e["from"]): os.path.join(folder, e["to"]) for e in entries if e["from"] != e["to"]}


# ---------- Plan ----------

def named_check(prefix, width, total):
    """Does a name already follow the scheme? Exactly the scheme's number of digits, or more digits without a leading
    zero for a number that fits the folder size (001..999 -> 1000). A name like "1794891158.mp4"
    (Unix time) therefore does not fit scheme "001"."""
    pattern = re.compile("^" + re.escape(prefix) + r"(\d+)\.[^.]+$")

    def check(name):
        m = pattern.match(name)
        if not m:
            return None
        d = m.group(1)
        if len(d) == width or (len(d) > width and not d.startswith("0") and int(d) <= 2 * total + 10):
            return int(d)
        return None
    return check


def make_plan(folder, progress=True, mode="new"):
    folder = os.path.abspath(folder)
    _, entries = scan(folder)
    files = [e.name for e in entries if kind(e.name)]
    files.sort(key=natural_key)
    if not files:
        return {"dir": folder, "mode": mode, "total": 0, "kept": 0, "fresh": 0, "renames": [], "counts": {},
                "unknown": 0, "byUpload": 0, "blocked": [], "token": "", "first": "", "last": "", "lastKept": "",
                "scheme": "", "table": "", "_info": {}, "_order": [], "_targets": {}, "_rows": [], "_mine": {}}
    parent, label = os.path.split(folder)
    table_path = os.path.join(parent, TABLE)
    rows = read_table(table_path)
    mine = {r["neuer_name"]: r for r in rows if r["ordner"] == label}

    # Modification date only if it is not a mass copy date: on a day with many files of the folder
    stats = {n: os.stat(os.path.join(folder, n)) for n in files}
    per_day = {}
    for st in stats.values():
        day = datetime.date.fromtimestamp(st.st_mtime)
        per_day[day] = per_day.get(day, 0) + 1
    bulk = {d for d, c in per_day.items() if c >= max(5, 0.2 * len(files))}

    prefix, width = scheme(files)
    number = named_check(prefix, width, len(files))
    keep = [n for n in files if number(n) is not None] if mode == "new" else []
    keep.sort(key=number)
    # Only these get a date and a new name (mode "new": the ones not named to the scheme)
    candidates = [n for n in files if n not in set(keep)]

    found = {}
    for i, name in enumerate(candidates):
        path = os.path.join(folder, name)
        found[name] = video_dates(path) if kind(name) == "video" else image_dates(path)
        if progress and (i % 5 == 4 or i == len(candidates) - 1):
            emit(progress=round((i + 1) / len(candidates), 3))
    # HandBrake often writes the conversion date into the file: recognizable because many
    # converted files have the same day (measured: 47 on one day, otherwise at most 4). Single
    # HandBrake files carry their real date. Own compressions (video_edit.py) are called "Lavf"
    hb_days = {}
    for cands in found.values():
        for dt, _, hb in cands:
            if hb:
                hb_days[dt.date()] = hb_days.get(dt.date(), 0) + 1
    hb_total = sum(1 for c in found.values() if any(hb for _, _, hb in c))
    encode_days = {d for d, c in hb_days.items() if c >= max(5, 0.2 * hb_total)}

    info = {}
    for name in candidates:
        row = mine.get(name)
        original = row["alter_name"] if row and row["alter_name"] else name
        good = [(dt, src) for dt, src, hb in found[name] if not (hb and dt.date() in encode_days)]
        dt, src = good[0] if good else (None, None)
        if not dt:
            for candidate in (name, original):
                dt = name_date(candidate)
                if dt:
                    src = "name"
                    break
        if not dt and row and row["datum"] and not row["datum"].startswith("ca."):
            dt = parse_date(row["datum"])
            src = row["quelle"] or "liste" if dt else None
        if not dt:
            mtime = datetime.datetime.fromtimestamp(stats[name].st_mtime)
            if mtime.date() not in bulk and plausible(mtime):
                dt, src = mtime.replace(microsecond=0), "mtime"
        upload = UPLOAD_ID.match(original)
        info[name] = {"date": dt, "source": src or ("upload-id" if upload else "unbekannt"),
                      "upload": tuple(int(g) for g in upload.groups()[:2]) if upload else None,
                      "original": original, "row": row}

    position = {n: i for i, n in enumerate(files)}
    unknown = [n for n in candidates if not info[n]["date"] and not info[n]["upload"]]
    by_upload = sorted((n for n in candidates if not info[n]["date"] and info[n]["upload"]),
                       key=lambda n: (info[n]["upload"], position[n]))
    dated = sorted((n for n in candidates if info[n]["date"]), key=lambda n: (info[n]["date"], position[n]))
    fresh = unknown + by_upload + dated

    # New ones after the highest existing number; gaps (deleted files) stay
    start = (max(number(n) for n in keep) + 1) if keep else 1
    width = max(width, len(str(start + len(fresh) - 1)))
    targets = {n: n for n in keep}
    targets.update({n: f"{prefix}{start + i:0{width}d}{os.path.splitext(n)[1]}" for i, n in enumerate(fresh)})
    order = keep + fresh
    renames = [(n, targets[n]) for n in fresh if targets[n] != n]

    # Target names must not hit another file (hidden, hidden by .hidden, other extension ...)
    moving = {n for n, _ in renames}
    blocked = [t for _, t in renames if t not in moving and os.path.lexists(os.path.join(folder, t))]

    counts = {}
    for n in candidates:
        counts[info[n]["source"]] = counts.get(info[n]["source"], 0) + 1
    token = hashlib.sha256(json.dumps([folder, mode, renames,
                                       [(n, stats[n].st_size, stats[n].st_mtime_ns) for n in files]])
                           .encode()).hexdigest()[:16]
    return {"dir": folder, "label": label, "mode": mode, "total": len(files), "kept": len(keep),
            "fresh": len(fresh), "renames": renames, "counts": counts, "unknown": len(unknown),
            "byUpload": len(by_upload), "blocked": blocked, "token": token,
            "first": targets[fresh[0]] if fresh else "", "last": targets[fresh[-1]] if fresh else "",
            "lastKept": keep[-1] if keep else "", "scheme": f"{prefix}{1:0{width}d}", "table": table_path,
            "_info": info, "_order": order, "_targets": targets, "_rows": rows, "_mine": mine}


def scheme(files):
    """Existing naming scheme (prefix + number, e.g. "video_0001", "001") if at least half of the
    files are named like that (newly added ones with another name do not tip it); otherwise video_/bild_ + 4 digits."""
    parts = [m for m in (re.match(r"^(\D*?)(\d+)\.[^.]+$", n) for n in files) if m]
    if parts:
        prefixes = {}
        for p in parts:
            prefixes.setdefault(p.group(1), []).append(len(p.group(2)))
        prefix, widths = max(prefixes.items(), key=lambda kv: len(kv[1]))
        if len(widths) * 2 >= len(files):
            # Most common number of digits: a single long name (Unix time) should not pull "001" to 10 digits
            return prefix, max(set(widths), key=lambda w: (widths.count(w), w))
    kinds = {kind(n) for n in files}
    return ("video_" if kinds == {"video"} else "bild_" if kinds == {"image"} else "datei_"), 4


def public(plan):
    out = {k: v for k, v in plan.items() if not k.startswith("_")}
    out["renameCount"] = len(plan["renames"])
    out.pop("renames")
    return out


def cmd_plan(folder, mode="new"):
    folder = os.path.abspath(folder)
    recovered = recover(folder)
    plan = make_plan(folder, mode=mode)
    out = public(plan)
    if recovered is not None:
        out["recovered"] = len(recovered)
    emit(plan=out)


def cmd_apply(folder, token, mode="new"):
    folder = os.path.abspath(folder)
    recover(folder)
    plan = make_plan(folder, mode=mode)
    if plan["token"] != token:
        emit(error="The folder changed. Check again.")
        return 1
    if plan["blocked"]:
        emit(error=f"\"{plan['blocked'][0]}\" is in the way (not a photo or video?)")
        return 1
    if not plan["renames"]:
        emit(ok=True, renamed=0, moved={})
        return 0

    # New list: rows of other folders stay, own ones get a new name, date and source
    info, targets = plan["_info"], plan["_targets"]
    others = [r for r in plan["_rows"] if r["ordner"] != plan["label"]]
    mine = []
    for n in plan["_order"]:
        if n not in info:
            # Keep (mode "new"): the row stays as it is, no row is invented where there is none
            if n in plan["_mine"]:
                mine.append(plan["_mine"][n])
            continue
        i = info[n]
        old = i["row"] or {}
        if i["date"]:
            datum, quelle = i["date"].strftime(FMT), i["source"]
        else:
            # Nothing new: an earlier rough value ("ca. 2023-05") stays
            datum = old.get("datum") or "-"
            quelle = old.get("quelle") if old.get("datum") else i["source"]
        mine.append({"ordner": plan["label"], "alter_name": i["original"], "neuer_name": targets[n],
                     "datum": datum, "quelle": quelle})
    # Rows for files that no longer exist are kept (a trace of what was there once)
    gone = [r for r in plan["_rows"] if r["ordner"] == plan["label"] and r["neuer_name"] not in info]
    table = plan["table"]
    write_synced(table + ".new", table_text(others + mine + gone))
    if os.path.exists(table):
        with open(table, encoding="utf-8") as src, open(table + ".bak", "w", encoding="utf-8") as dst:
            dst.write(src.read())

    run = uuid.uuid4().hex[:8]
    entries = [{"from": a, "tmp": f".qs-sort-{run}-{k}{os.path.splitext(a)[1]}", "to": b}
               for k, (a, b) in enumerate(plan["renames"])]
    jpath = os.path.join(folder, JOURNAL)
    write_synced(jpath, json.dumps({"phase": 1, "table": table, "entries": entries}))
    total = 2 * len(entries)
    for k, e in enumerate(entries):
        rename_noreplace(os.path.join(folder, e["from"]), os.path.join(folder, e["tmp"]))
        if k % 10 == 9:
            emit(progress=round((k + 1) / total, 3))
    sync_dir(folder)
    write_synced(jpath, json.dumps({"phase": 2, "table": table, "entries": entries}))
    for k, e in enumerate(entries):
        rename_noreplace(os.path.join(folder, e["tmp"]), os.path.join(folder, e["to"]))
        if k % 10 == 9:
            emit(progress=round((len(entries) + k + 1) / total, 3))
    moved = recover(folder)  # swaps the list and deletes the journal (renaming is already done)
    emit(ok=True, renamed=len(entries), moved=moved or {})
    return 0


def main():
    args = sys.argv[1:]
    try:
        if len(args) in (2, 3) and args[0] == "plan" and args[2:] in ([], ["new"], ["all"]):
            return cmd_plan(*args[1:]) or 0
        if len(args) in (3, 4) and args[0] == "apply" and args[3:] in ([], ["new"], ["all"]):
            return cmd_apply(*args[1:]) or 0
    except OSError as e:
        emit(error=f"{os.path.basename(e.filename or '') or 'file'}: {e.strerror or e}")
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
