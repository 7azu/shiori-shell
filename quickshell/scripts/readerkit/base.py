# Read tab: reader language, folders and the helpers every part needs (output, JSON files, downloads).
#
# Output of the scripts: JSON lines. {"progress": "..."} in between, the last line is the result
# ({"ok": true, ...} or {"ok": false, "error": "..."}).
# Library: ~/.local/share/quickshell/jp-reader/{index.json, books/<id>.json, covers/}

import json
import os
import sys
import urllib.request

HOME = os.path.expanduser("~")
JP_DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share"), "quickshell/jp-reader")
# Reader language, set by services/LanguageReadingState.qml for every call (default: Japanese, as before).
# Japanese keeps its old folders and gets furigana + rōmaji; any other language gets plain sentences, a Latin
# transliteration where its script needs one (Cyrillic, Greek), its own data folder and its own books folder.
LANG = os.environ.get("SHIORI_READER_LANG") or "ja"
LANG_NAME = os.environ.get("SHIORI_READER_LANG_NAME") or "Japanese"
JAPANESE = LANG == "ja"
DATA = os.environ.get("SHIORI_READER_DATA") or JP_DATA
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "quickshell/jp-reader")
BOOKS = os.path.join(DATA, "books")
COVERS = os.path.join(DATA, "covers")
INDEX = os.path.join(DATA, "index.json")
IMPORTED = os.path.join(DATA, "imported.json")
# fugashi/cutlet (Japanese only), shared with jp_subs.py: always in the Japanese folder
VENV = os.path.join(JP_DATA, "venv")
SCRIPTS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if SCRIPTS not in sys.path:
    sys.path.insert(0, SCRIPTS)
import shiori_settings  # noqa: E402

# Japanese: setting "books" (default $DOCUMENTS/JapaneseBooks); other languages: <language folder>/Books
IMPORT_DIR = os.environ.get("SHIORI_READER_BOOKS") or shiori_settings.folder("books")
UA = "Mozilla/5.0 (X11; Linux x86_64) quickshell-jp-reader"


def out(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def progress(msg):
    out({"progress": msg})


def fail(msg):
    out({"ok": False, "error": msg})
    sys.exit(0)


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def fetch(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()
