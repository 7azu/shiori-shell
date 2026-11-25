#!/usr/bin/env python3
"""Trash following the freedesktop spec (for services/TrashState.qml).

  trash.py list            -> JSON list of all entries
  trash.py restore <id>    -> back to the original place, never overwrites (otherwise " (1)" etc.)
  trash.py delete <id>     -> delete for good
  trash.py empty           -> delete everything for good

<id> is the file name under Trash/files, percent-encoded: file names do not have to be valid
UTF-8, and this way they survive the trip through QML and fit straight into a file:// URL.
"""
import datetime
import json
import os
import shutil
import stat
import sys
from urllib.parse import quote, unquote_to_bytes

DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
TRASH = os.path.join(DATA_HOME, "Trash")
FILES = os.path.join(TRASH, "files")
INFO = os.path.join(TRASH, "info")

KINDS = {
    "image": "png jpg jpeg gif webp bmp svg avif heic tiff ico",
    "video": "mp4 mkv webm mov avi m4v wmv flv",
    "audio": "mp3 flac ogg opus wav m4a aac wma",
    "archive": "zip tar gz xz bz2 zst 7z rar deb rpm iso",
    "doc": "pdf doc docx odt txt md rtf epub xls xlsx ods csv ppt pptx odp",
    "code": "py js ts qml lua sh c h cpp hpp rs go java html css json toml yaml yml xml service conf",
}
EXT_KIND = {ext: kind for kind, exts in KINDS.items() for ext in exts.split()}


def read_info(name):
    """Returns (original path as bytes or None, timestamp)."""
    path = os.path.join(INFO, name + ".trashinfo")
    origin, stamp = None, None
    try:
        with open(path, "rb") as f:
            for line in f.read().splitlines():
                if line.startswith(b"Path="):
                    origin = unquote_to_bytes(line[5:].decode("ascii", "replace"))
                elif line.startswith(b"DeletionDate="):
                    try:
                        stamp = datetime.datetime.fromisoformat(line[13:].decode()).timestamp()
                    except ValueError:
                        pass
        if stamp is None:
            stamp = os.stat(path).st_mtime
    except OSError:
        pass
    return origin, stamp


def folder_stats(path):
    """Size and number of files; follows no links."""
    size, count = 0, 0
    stack = [path]
    while stack:
        try:
            with os.scandir(stack.pop()) as it:
                for entry in it:
                    try:
                        st = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if stat.S_ISDIR(st.st_mode):
                        stack.append(entry.path)
                    else:
                        size += st.st_size
                        count += 1
        except OSError:
            continue
    return size, count


def describe(name):
    full = os.path.join(FILES, name)
    st = os.lstat(full)
    origin, stamp = read_info(name)
    is_dir = stat.S_ISDIR(st.st_mode)
    size, count = folder_stats(full) if is_dir else (st.st_size, 0)
    # Without .trashinfo the origin is unknown: then it can only be deleted
    shown = os.fsdecode(origin) if origin else name
    label = os.path.basename(shown.rstrip("/")) or shown
    ext = label.rsplit(".", 1)[-1].lower() if "." in label[1:] else ""
    kind = "folder" if is_dir else "link" if stat.S_ISLNK(st.st_mode) else EXT_KIND.get(ext, "file")
    return {
        "id": quote(os.fsencode(name), safe=""),
        "name": label.encode("utf-8", "replace").decode(),
        "origin": os.path.dirname(shown).encode("utf-8", "replace").decode() if origin else "",
        "ts": int(stamp if stamp is not None else st.st_mtime),
        "isDir": is_dir,
        "kind": kind,
        "ext": ext,
        "size": size,
        "count": count,
    }


def cmd_list():
    entries = []
    try:
        names = os.listdir(FILES)
    except OSError:
        names = []
    for name in names:
        try:
            entries.append(describe(name))
        except OSError:
            continue
    json.dump(entries, sys.stdout)


def name_from_id(entry_id):
    """The name must never lead out of the trash (deleting is final)."""
    name = os.fsdecode(unquote_to_bytes(entry_id))
    if not name or "/" in name or "\0" in name or name in (".", ".."):
        raise ValueError("Invalid entry")
    if not os.path.lexists(os.path.join(FILES, name)):
        raise ValueError("Entry is no longer in the trash")
    return name


def remove_tree(path):
    def make_writable(func, target, _exc):
        # Write-protected folders (e.g. Go module caches) cannot be emptied otherwise
        os.chmod(os.path.dirname(target), stat.S_IRWXU)
        if not os.path.islink(target) and os.path.isdir(target):
            os.chmod(target, stat.S_IRWXU)
        func(target)

    if os.path.isdir(path) and not os.path.islink(path):
        os.chmod(path, stat.S_IRWXU)
        shutil.rmtree(path, onexc=make_writable)
    else:
        os.unlink(path)


def remove_info(name):
    try:
        os.unlink(os.path.join(INFO, name + ".trashinfo"))
    except FileNotFoundError:
        pass


def free_target(target):
    if not os.path.lexists(target):
        return target
    stem, ext = os.path.splitext(target)
    n = 1
    while os.path.lexists(f"{stem} ({n}){ext}"):
        n += 1
    return f"{stem} ({n}){ext}"


def cmd_restore(entry_id):
    name = name_from_id(entry_id)
    origin, _ = read_info(name)
    if not origin:
        raise ValueError("Original location unknown")
    origin = os.fsdecode(origin)
    if not os.path.isabs(origin):
        raise ValueError("Original location is ambiguous")
    target = free_target(origin)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.move(os.path.join(FILES, name), target)
    remove_info(name)
    return {"restoredTo": target.encode("utf-8", "replace").decode()}


def cmd_delete(entry_id):
    name = name_from_id(entry_id)
    remove_tree(os.path.join(FILES, name))
    remove_info(name)
    return {}


def cmd_empty():
    failed = 0
    try:
        names = os.listdir(FILES)
    except OSError:
        names = []
    for name in names:
        try:
            remove_tree(os.path.join(FILES, name))
            remove_info(name)
        except OSError:
            failed += 1
    # "empty" also cleans up orphans without a matching file
    try:
        for info in os.listdir(INFO):
            if info.endswith(".trashinfo") and not os.path.lexists(os.path.join(FILES, info[: -len(".trashinfo")])):
                os.unlink(os.path.join(INFO, info))
    except OSError:
        pass
    if failed:
        raise ValueError(f"{failed} entries could not be deleted")
    return {}


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "list":
        cmd_list()
        return 0
    try:
        if command == "restore":
            result = cmd_restore(sys.argv[2])
        elif command == "delete":
            result = cmd_delete(sys.argv[2])
        elif command == "empty":
            result = cmd_empty()
        else:
            raise ValueError("Unbekannter Befehl")
    except (OSError, ValueError, IndexError) as err:
        print(json.dumps({"ok": False, "error": str(err)}))
        return 1
    print(json.dumps({"ok": True, **result}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
