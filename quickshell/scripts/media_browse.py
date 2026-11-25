#!/usr/bin/env python3
"""Folder browser of the image and video editor (services/MediaBrowserState.qml, windows/MediaBrowser.qml).

  list <folder>   first line JSON:
                    {"dir", "parent", "folders": [{"path", "name", "count", "folders", "covers"}],
                     "files": [{"path", "name", "kind": "image"|"video"}]}
                  then "T <preview>\\t<video>" per video (files and folder covers), from the shared
                  cache of video_edit.py (missing ones are created, that is why only after the JSON)
  move <target> <path>...   move (cut + paste); never overwrite: with the same name
                          "name (2).ext". One JSON line per entry {"op": "move", "from", "to"} or {"error"}
  trash <path>...         to the trash (gio trash), per entry {"op": "trash", "path"} or {"error"}
  unlock <cipher> <folder>  unlock a vault; the password comes as the first line on stdin (never as an
                          argument: it would be visible to everyone in the process list). {"ok"} or {"error": "wrong"|text}
  search <folder> <query> fuzzy search over all subfolders (fd): one JSON line {"query", "dir", "results":
                          [folders as in list or {"type": "file", "path", "name", "kind"}, each with "rel" = folder
                          relative to the search folder]}, best first; then "T" lines for videos as in list
  lock <folder>           lock a vault (fusermount3 -u, deliberately without -z). {"ok"} or {"error": "busy"|text}

Vaults (gocryptfs) as in the yazi plugin (~/.config/yazi/plugins/vault.yazi): folder "X" with a hidden
ciphertext ".x" (or ".X") next to it, containing gocryptfs.conf. "list" reports them among the subfolders as
"vault": {"cipher", "locked"} and for a locked vault itself "locked": true, "cipher".

Hidden entries stay out, sorting is natural (2 before 10) as in the editors.
"""
import json
import os
import shutil
import subprocess
import sys

# -I removes the script folder from the search path; video_edit is next to it
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from video_edit import VIDEO_EXTENSIONS, cached_thumb, encrypted_mounts, natural_key  # noqa: E402

# Same as in the yazi plugin: gocryptfs locks itself after this much inactivity
IDLE = "3m"
WRONG_PASSWORD = 12  # exit code of gocryptfs for a wrong password

IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tif", ".tiff")


def load_dir_icons():
    """Folder icons as in yazi: [icon] dirs from ~/.config/yazi/theme.toml (same name -> same icon),
    otherwise the folder icon from [icon] conds (if = "dir"). So both stay the same when you change them in yazi."""
    names, fallback = {}, "\uf07b"
    try:
        import tomllib
        with open(os.path.expanduser("~/.config/yazi/theme.toml"), "rb") as f:
            icon = tomllib.load(f).get("icon", {})
        names = {e["name"]: e["text"] for e in icon.get("dirs", []) if "name" in e and "text" in e}
        fallback = next((c["text"] for c in icon.get("conds", []) if c.get("if") == "dir" and "text" in c), fallback)
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return names, fallback


DIR_ICONS, DIR_ICON = load_dir_icons()
COVERS = 4


def kind(name):
    low = name.lower()
    if low.endswith(IMAGE_EXTENSIONS):
        return "image"
    if low.endswith(VIDEO_EXTENSIONS):
        return "video"
    return None


def hidden_names(folder):
    """Names from <folder>/.hidden (convention of Nautilus, Dolphin, Thunar): this hides folders like
    "DaVinci Resolve Media" that a program creates in a fixed place, without renaming them."""
    try:
        with open(os.path.join(folder, ".hidden"), encoding="utf-8") as f:
            return {line.strip() for line in f if line.strip()}
    except OSError:
        return set()


def scan(folder):
    folders, files = [], []
    try:
        entries = list(os.scandir(folder))
    except OSError:
        return [], []
    hidden = hidden_names(folder)
    for e in entries:
        if e.name.startswith(".") or "\n" in e.name or e.name in hidden:
            continue
        try:
            if e.is_dir():
                folders.append(e)
            elif e.is_file() and kind(e.name):
                files.append(e)
        except OSError:
            continue
    folders.sort(key=lambda e: natural_key(e.name))
    files.sort(key=lambda e: natural_key(e.name))
    return folders, files


def vault_cipher(path):
    """Ciphertext folder of a vault folder (".x" next to it with gocryptfs.conf) or None."""
    parent, name = os.path.split(path.rstrip("/"))
    for cand in ("." + name.lower(), "." + name):
        cipher = os.path.join(parent, cand)
        if os.path.isfile(os.path.join(cipher, "gocryptfs.conf")):
            return cipher
    return None


def folder_entry(path, plain=False):
    """Folder for the grid: icon (yazi), count, up to 4 covers, vault state."""
    name = os.path.basename(path)
    icon = DIR_ICONS.get(name, DIR_ICON)
    sub_cipher = vault_cipher(path)
    if sub_cipher and not os.path.ismount(path):
        return {"type": "folder", "path": path, "name": name, "count": 0, "folders": 0, "covers": [], "icon": icon,
                "vault": {"cipher": sub_cipher, "locked": True}}
    sub_folders, sub_files = scan(path)
    entry = {"type": "folder", "path": path, "name": name, "count": len(sub_files), "folders": len(sub_folders),
             "covers": [] if plain else [f.path for f in sub_files[:COVERS]], "icon": icon}
    if sub_cipher:
        entry["vault"] = {"cipher": sub_cipher, "locked": False}
    return entry


def cmd_list(folder):
    folder = os.path.abspath(os.path.expanduser(folder))
    inside = next((m for m in encrypted_mounts() if folder == m or folder.startswith(m + "/")), "")
    cipher = vault_cipher(folder)
    if cipher and not os.path.ismount(folder):
        # Locked: the folder is just an empty mount point -> password prompt instead of "empty"
        print(json.dumps({"dir": folder, "parent": os.path.dirname(folder), "locked": True, "cipher": cipher,
                          "icon": DIR_ICONS.get(os.path.basename(folder), DIR_ICON),
                          "vaultMount": "", "folders": [], "files": []}), flush=True)
        return
    folders, files = scan(folder)
    videos = [f.path for f in files if kind(f.name) == "video"]
    # In the home folder only the folder icons (as in yazi), no preview mosaics from the content
    plain = folder == os.path.expanduser("~")
    out_folders = []
    for d in folders:
        entry = folder_entry(d.path, plain)
        out_folders.append(entry)
        videos += [c for c in entry["covers"] if kind(c) == "video"]
    print(json.dumps({
        "dir": folder,
        "parent": os.path.dirname(folder) if folder != "/" else "",
        "locked": False,
        "cipher": cipher or "",
        "icon": DIR_ICONS.get(os.path.basename(folder), DIR_ICON),
        # If the folder is in an unlocked vault: its root (for the lock button)
        "vaultMount": inside,
        "folders": out_folders,
        "files": [{"path": f.path, "name": f.name, "kind": kind(f.name)} for f in files],
    }), flush=True)
    for video in videos:
        thumb = cached_thumb(video)
        if thumb:
            print(f"T {thumb}\t{video}", flush=True)


SEARCH_LIMIT = 150
# Folders whose content is only noise for a media search (game installs, dependencies)
SEARCH_SKIP = ("node_modules", "steamapps", "__pycache__", "drive_c", "site-packages", "target")


def subseq_gaps(term, text):
    """Letters of term in order in text? Then the sum of the gaps, otherwise None."""
    pos, gaps = -1, 0
    for ch in term:
        j = text.find(ch, pos + 1)
        if j < 0:
            return None
        if pos >= 0:
            gaps += j - pos - 1
        pos = j
    return gaps


def term_score(term, name, rel):
    """Hits in the name before hits in the path, contiguous before scattered, word start before word middle."""
    i = name.find(term)
    if i >= 0:
        return 1000 - i + (200 if i == 0 or not name[i - 1].isalnum() else 0)
    i = rel.find(term)
    if i >= 0:
        return 600 - min(i, 200) + (150 if i == 0 or not rel[i - 1].isalnum() else 0)
    # Scattered letters only with small gaps: otherwise almost anything matches somehow in long paths
    g = subseq_gaps(term, name)
    if g is not None and g <= len(term) * 2:
        return max(1, 300 - g * 8)
    g = subseq_gaps(term, rel)
    if g is not None and g <= len(term):
        return max(1, 100 - g * 4)
    return None


def cmd_search(folder, query):
    folder = os.path.abspath(os.path.expanduser(folder))
    terms = [t for t in query.lower().split() if t]
    exts = [e.lstrip(".") for e in IMAGE_EXTENSIONS + VIDEO_EXTENSIONS]
    cmd = ["fd", "--no-ignore-vcs", "--color", "never", "--absolute-path", "--max-results", "200000"]
    for skip in SEARCH_SKIP:
        cmd += ["--exclude", skip]
    try:
        dirs = subprocess.run(cmd + ["--type", "d", ".", folder], capture_output=True, text=True, timeout=4).stdout.split("\n")
        media = subprocess.run(cmd + ["--type", "f"] + [a for e in exts for a in ("-e", e)] + [".", folder],
                               capture_output=True, text=True, timeout=4).stdout.split("\n")
    except (OSError, subprocess.TimeoutExpired):
        dirs, media = [], []
    hidden_cache = {}

    def hidden(path):
        # .hidden applies to the direct entries of a folder: check every level of the path
        rel_parts = os.path.relpath(path, folder).split(os.sep)
        base = folder
        for part in rel_parts:
            if base not in hidden_cache:
                hidden_cache[base] = hidden_names(base)
            if part in hidden_cache[base]:
                return True
            base = os.path.join(base, part)
        return False

    scored = []
    for path, is_dir in [(p.rstrip("/"), True) for p in dirs if p] + [(p, False) for p in media if p]:
        if path == folder:
            continue
        rel = os.path.relpath(path, folder)
        name = os.path.basename(path)
        total, ok = 0, True
        for term in terms:
            s = term_score(term, name.lower(), rel.lower())
            if s is None:
                ok = False
                break
            total += s
        if not ok:
            continue
        # On a tie: shallower and shorter first
        total -= rel.count(os.sep) * 3 + len(rel) * 0.01
        scored.append((total, path, is_dir, rel))
    scored.sort(key=lambda s: -s[0])

    results, videos = [], []
    for total, path, is_dir, rel in scored:
        if len(results) >= SEARCH_LIMIT:
            break
        if hidden(path):
            continue
        rel_dir = os.path.dirname(rel)
        if is_dir:
            entry = folder_entry(path)
            videos += [c for c in entry["covers"] if kind(c) == "video"]
        else:
            entry = {"type": "file", "path": path, "name": os.path.basename(path), "kind": kind(path)}
            if entry["kind"] == "video":
                videos.append(path)
        entry["rel"] = rel_dir
        results.append(entry)
    print(json.dumps({"query": query, "dir": folder, "results": results}), flush=True)
    # Previews for the best hits (the first ones are visible), in a vault none as always
    for video in videos[:60]:
        thumb = cached_thumb(video)
        if thumb:
            print(f"T {thumb}\t{video}", flush=True)


def emit(**kw):
    print(json.dumps(kw), flush=True)


def unique_target(dest, name):
    # Folders have no extension: "Photos (2)", files "IMG_1 (2).jpg"
    base, ext = (name, "") if os.path.isdir(os.path.join(dest, name)) else os.path.splitext(name)
    candidate, n = os.path.join(dest, name), 2
    while os.path.lexists(candidate):
        candidate = os.path.join(dest, f"{base} ({n}){ext}")
        n += 1
    return candidate


def cmd_move(dest, *paths):
    dest = os.path.abspath(dest)
    for src in paths:
        src = os.path.abspath(src)
        name = os.path.basename(src)
        if os.path.dirname(src) == dest:
            continue  # already here: nothing to do
        if os.path.isdir(src) and (dest == src or dest.startswith(src + os.sep)):
            emit(error=f"Can't move \"{name}\" into itself")
            continue
        target = unique_target(dest, name)
        try:
            shutil.move(src, target)
        except OSError as e:
            emit(error=f"{name}: {e.strerror or e}")
            continue
        emit(op="move", **{"from": src, "to": target})


def cmd_trash(*paths):
    for path in paths:
        r = subprocess.run(["gio", "trash", "--", path], capture_output=True, text=True)
        if r.returncode == 0:
            emit(op="trash", path=path)
        else:
            # gio writes "gio: file:///long/path: reason" -> only show the reason
            reason = (r.stderr.strip().splitlines() or ["could not move to trash"])[-1].rsplit(": ", 1)[-1]
            emit(error=f"{os.path.basename(path)}: {reason}")


def cmd_unlock(cipher, mount):
    password = sys.stdin.readline().rstrip("\n")
    if os.path.ismount(mount):
        emit(ok=True)
        return
    # gocryptfs reads the password from stdin, mounts and then goes to the background itself
    r = subprocess.run(["gocryptfs", "-q", "-idle", IDLE, "--", cipher, mount],
                       input=password + "\n", capture_output=True, text=True)
    del password
    if r.returncode == 0:
        emit(ok=True)
    elif r.returncode == WRONG_PASSWORD:
        emit(error="wrong")
    else:
        emit(error=(r.stderr.strip().splitlines() or [f"gocryptfs exited with {r.returncode}"])[-1])


def cmd_lock(mount):
    if not os.path.ismount(mount):
        emit(ok=True)
        return
    r = subprocess.run(["fusermount3", "-u", mount], capture_output=True, text=True)
    if r.returncode == 0:
        emit(ok=True)
    elif "busy" in r.stderr.lower():
        emit(error="busy")
    else:
        emit(error=(r.stderr.strip().splitlines() or ["could not lock"])[-1])


def main():
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "list":
        cmd_list(args[1])
    elif len(args) >= 3 and args[0] == "move":
        cmd_move(args[1], *args[2:])
    elif len(args) >= 2 and args[0] == "trash":
        cmd_trash(*args[1:])
    elif len(args) == 3 and args[0] == "unlock":
        cmd_unlock(args[1], args[2])
    elif len(args) == 3 and args[0] == "search":
        cmd_search(args[1], args[2])
    elif len(args) == 2 and args[0] == "lock":
        cmd_lock(args[1])
    else:
        print("usage: media_browse.py list <folder> | move <dest> <path>... | trash <path>...", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
