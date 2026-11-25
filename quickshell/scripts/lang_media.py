#!/usr/bin/env python3
"""Metadata of the language learning library for the list view.

  lang_media.py list <folder>
  lang_media.py languages <languages-folder> <state-folder> [Name=Folder ...]
  lang_media.py create <language-folder> [--mark CHARACTER] [--image IMAGE]
  lang_media.py images

create makes the language folder, stores the character in <folder>/.language.json and copies the image as
cover.<ext> into it (tile image). images lists the newest images from Downloads/Pictures/Desktop for the
image choice when adding a language.

Prints ONE JSON object: { "<file name>": {kind, size, mtime, duration, thumb} }.
  kind      "audio" (mp3) | "video" (mp4)
  duration  seconds (ffprobe), 0 if unknown
  thumb     path to the preview image or "":
            1. <folder>/.thumbs/<name>.jpg (YouTube image, stored by the download)
            2. for videos a still image from the same cache as the video editor (video_edit.cached_thumb)

Durations go to ~/.cache/quickshell-jp-library.json (key: name + size + modification time),
so only new files need ffprobe.
"""
import datetime
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from video_edit import cached_thumb  # noqa: E402

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell-jp-library.json")
KINDS = {".mp3": "audio", ".mp4": "video"}
THUMB_EXT = (".jpg", ".webp", ".png")


def duration(path):
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        return round(float(out), 1)
    except (OSError, subprocess.SubprocessError, ValueError):
        return 0


def youtube_thumb(folder, stem):
    for ext in THUMB_EXT:
        p = os.path.join(folder, ".thumbs", stem + ext)
        if os.path.isfile(p):
            return p
    return ""


def cmd_list(folder):
    try:
        with open(CACHE) as f:
            cache = json.load(f)
    except (OSError, ValueError):
        cache = {}
    out, used = {}, {}
    try:
        names = os.listdir(folder)
    except OSError:
        names = []
    for name in names:
        stem, ext = os.path.splitext(name)
        kind = KINDS.get(ext.lower())
        if not kind:
            continue
        path = os.path.join(folder, name)
        try:
            st = os.stat(path)
        except OSError:
            continue
        key = f"{name}|{st.st_size}|{st.st_mtime_ns}"
        dur = cache.get(key)
        if dur is None:
            dur = duration(path)
        used[key] = dur
        thumb = youtube_thumb(folder, stem)
        if not thumb and kind == "video":
            thumb = cached_thumb(path) or ""
        out[name] = {"kind": kind, "size": st.st_size, "mtime": int(st.st_mtime), "duration": dur, "thumb": thumb}
    # Keep only files that still exist (deleted/changed ones drop out)
    if used != cache:
        try:
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            tmp = CACHE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(used, f)
            os.replace(tmp, CACHE)
        except OSError:
            pass
    json.dump(out, sys.stdout, ensure_ascii=False)
    print()


def stats_file(state_dir, name):
    """Like LanguageAudioState.statsFileOf: Japanese keeps its old file."""
    if name == "Japanese":
        return os.path.join(state_dir, "japanese-audio-stats.json")
    return os.path.join(state_dir, "language-stats", re.sub(r"[^A-Za-z0-9_-]", "_", name) + ".json")


# Tile images by language name, outside the language folders (synced with the private settings)
COVER_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "shiori-shell", "language-covers")


def cover_of(name, path):
    """Tile image: cover.jpg/png/webp in the language folder, otherwise ~/.config/shiori-shell/language-covers/<Name>.*
    (your own covers), otherwise ""."""
    for folder, stem in ((path, "cover"), (COVER_DIR, name)):
        for ext in (".jpg", ".png", ".webp"):
            p = os.path.join(folder, stem + ext)
            if os.path.isfile(p):
                return p
    return ""


def mark_of(path):
    """Tile character chosen by the user from <folder>/.language.json, otherwise "" (QML then uses the known one)."""
    try:
        with open(os.path.join(path, ".language.json")) as f:
            return str(json.load(f).get("mark", ""))[:4]
    except (OSError, ValueError, AttributeError):
        return ""


IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")


def cmd_create(path, mark, image):
    """Language folder + character + tile image. An existing cover.* is replaced (all extensions, otherwise
    the old one could win depending on the order in cover_of)."""
    import shutil
    os.makedirs(path, exist_ok=True)
    if mark:
        with open(os.path.join(path, ".language.json"), "w") as f:
            json.dump({"mark": mark[:4]}, f, ensure_ascii=False)
    if image:
        ext = os.path.splitext(image)[1].lower()
        if ext not in IMAGE_EXT or not os.path.isfile(image):
            print("Image not found or not a jpg/png/webp", file=sys.stderr)
            sys.exit(1)
        for old in (".jpg", ".png", ".webp"):
            try:
                os.remove(os.path.join(path, "cover" + old))
            except OSError:
                pass
        shutil.copyfile(image, os.path.join(path, "cover" + (".jpg" if ext == ".jpeg" else ext)))


def cmd_images(limit=40):
    """Newest images (jpg/png/webp) from Downloads, Pictures, Desktop (XDG folders), up to 2 levels deep, without
    hidden folders: [{path, name}] by modification time, newest first."""
    found = []
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import shiori_settings  # XDG user folders, also when they are not ~/Pictures etc.
    dirs = shiori_settings.user_dirs()
    for top in (dirs["DOWNLOAD"], dirs["PICTURES"], dirs["DESKTOP"]):
        for dirpath, dirs, files in os.walk(top):
            depth = dirpath[len(top):].count(os.sep)
            dirs[:] = [d for d in dirs if not d.startswith(".")] if depth < 2 else []
            for fn in files:
                if fn.startswith(".") or os.path.splitext(fn)[1].lower() not in IMAGE_EXT:
                    continue
                p = os.path.join(dirpath, fn)
                try:
                    found.append((os.path.getmtime(p), p, fn))
                except OSError:
                    pass
    found.sort(reverse=True)
    json.dump([{"path": p, "name": n} for _, p, n in found[:limit]], sys.stdout, ensure_ascii=False)
    print()


def cmd_languages(root, state_dir, legacy):
    """Languages for the choice tiles: [{name, dir, cover, audio, video, weekSecs, totalSecs}].
    Languages = subfolders of root (symlinks count) + fixed legacy folders (Name=Folder)."""
    langs = {}
    for pair in legacy:
        name, _, path = pair.partition("=")
        if name and path:
            langs[name] = path
    try:
        for d in os.listdir(root):
            if not d.startswith(".") and os.path.isdir(os.path.join(root, d)):
                langs.setdefault(d, os.path.join(root, d))
    except OSError:
        pass
    week_start = (datetime.date.today() - datetime.timedelta(days=6)).isoformat()
    out = []
    for name, path in sorted(langs.items(), key=lambda x: x[0].lower()):
        audio = video = 0
        try:
            for f in os.listdir(path):
                ext = os.path.splitext(f)[1].lower()
                audio += ext == ".mp3"
                video += ext == ".mp4"
        except OSError:
            pass
        try:
            with open(stats_file(state_dir, name)) as f:
                stats = json.load(f)
        except (OSError, ValueError):
            stats = {}
        week = sum(v for k, v in stats.items() if isinstance(v, (int, float)) and k >= week_start)
        total = sum(v for v in stats.values() if isinstance(v, (int, float)))
        out.append({"name": name, "dir": path, "cover": cover_of(name, path), "mark": mark_of(path), "audio": audio, "video": video,
                    "weekSecs": int(week), "totalSecs": int(total)})
    json.dump(out, sys.stdout, ensure_ascii=False)
    print()


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "list":
        cmd_list(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "languages":
        cmd_languages(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif len(sys.argv) >= 3 and sys.argv[1] == "create":
        args = sys.argv[3:]
        opt = {k: args[i + 1] for i, k in enumerate(args[:-1]) if k in ("--mark", "--image")}
        cmd_create(sys.argv[2], opt.get("--mark", "").strip(), opt.get("--image", ""))
    elif len(sys.argv) == 2 and sys.argv[1] == "images":
        cmd_images()
    else:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
