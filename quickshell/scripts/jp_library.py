#!/usr/bin/env python3
# Books for the Read tab of the Japanese tool (services/LanguageReadingState.qml).
#
#   jp_library.py scan                    import new files from the books folder (setting "books")
#   jp_library.py import <file>...        import EPUB / TXT (also Aozora format) / PDF
#   jp_library.py isbn <isbn>             book data (NDL, OpenLibrary) + free full texts on Aozora
#   jp_library.py aozora-search <text>    search the Aozora Bunko catalog (title, author, reading)
#   jp_library.py aozora-import <id>      download and import an Aozora work
#   jp_library.py translate <book> <ch>   translate a chapter into English (backend: scripts/jp_translate.py)
#   jp_library.py covers                  look for missing covers of imported books (also after every scan)
#   jp_library.py delete <book>           remove a book (its file in the import folder is ignored afterwards)
#
# Output: JSON lines. {"progress": "..."} in between, the last line is the result
# ({"ok": true, ...} or {"ok": false, "error": "..."}).
# The commands are here; the parts they are built from are in scripts/readerkit/ (see its __init__.py).

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jp_translate as jt  # noqa: E402
from readerkit.base import (BOOKS, COVERS, IMPORT_DIR, IMPORTED, INDEX, JAPANESE, LANG, LANG_NAME,  # noqa: E402
                            VENV, fail, fetch, out, progress, read_json, write_json)
from readerkit.book import make_book, save_book  # noqa: E402
from readerkit.catalog import (aozora_catalog, aozora_search, fetch_cover, find_cover,  # noqa: E402
                               isbn_lookup)
from readerkit.parsers import decode, parse_aozora, parse_epub, parse_pdf, parse_txt  # noqa: E402

EXTS = (".epub", ".txt", ".pdf", ".md")


# ───────────────────────── venv (fugashi, cutlet) ─────────────────────────

def ensure_venv():
    py = os.path.join(VENV, "bin/python")
    if os.path.realpath(sys.prefix) == os.path.realpath(VENV):
        return
    if not os.path.exists(py) or subprocess.run([py, "-c", "import fugashi, cutlet, unidic_lite"], capture_output=True).returncode != 0:
        progress("Setting up the furigana tokenizer (one time, ~60 MB) …")
        pkgs = ["fugashi", "unidic-lite", "cutlet"]
        uv = shutil.which("uv")
        try:
            if uv:
                subprocess.run([uv, "venv", "-q", "--allow-existing", VENV], check=True, capture_output=True)
                subprocess.run([uv, "pip", "install", "-q", "--python", py] + pkgs, check=True, capture_output=True)
            else:
                subprocess.run([sys.executable, "-m", "venv", VENV], check=True, capture_output=True)
                subprocess.run([py, "-m", "pip", "install", "-q"] + pkgs, check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            fail("Tokenizer installation failed: " + (e.stderr or b"").decode(errors="replace")[-300:])
    os.execv(py, [py, os.path.abspath(__file__)] + sys.argv[1:])


# ───────────────────────── Import ─────────────────────────

def import_file(path):
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        fail("File not found: " + path)
    if JAPANESE:
        ensure_venv()
    ext = os.path.splitext(path)[1].lower()
    progress("Reading " + os.path.basename(path))
    if ext == ".epub":
        meta, chapters = parse_epub(path)
    elif ext == ".pdf":
        meta, chapters = parse_pdf(path)
    elif ext in (".txt", ".md"):
        meta, chapters = parse_txt(path)
    else:
        fail("Unknown format (EPUB, TXT or PDF)")
    book_id = "file-" + hashlib.sha1(path.encode()).hexdigest()[:10]
    cover = meta.pop("_cover", None)
    if cover:
        os.makedirs(COVERS, exist_ok=True)
        cp = os.path.join(COVERS, book_id + cover[1])
        with open(cp, "wb") as f:
            f.write(cover[0])
        meta["cover"] = cp
    elif meta.get("isbn"):
        meta["cover"] = fetch_cover(meta["isbn"], book_id)
    meta["coverTried"] = bool(meta.get("cover") or meta.get("isbn"))
    meta["source"] = ext[1:]
    meta["path"] = path
    book = make_book(book_id, meta, chapters)
    save_book(book)
    imp = read_json(IMPORTED, {})
    imp[path] = {"mtime": os.path.getmtime(path), "id": book_id}
    write_json(IMPORTED, imp)
    return book


def aozora_import(work_id):
    w = aozora_catalog().get(work_id.zfill(6))
    if not w:
        fail("Aozora work %s not found" % work_id)
    progress("Loading 「%s」 from Aozora …" % w["title"])
    try:
        z = zipfile.ZipFile(io.BytesIO(fetch(w["url"], 60)))
    except Exception as e:
        fail("Download failed: %s" % e)
    txt = next((n for n in z.namelist() if n.lower().endswith(".txt")), None)
    if not txt:
        fail("No text in the Aozora archive")
    text = decode(z.read(txt))
    ensure_venv()
    chapters = parse_aozora(text, w["title"])
    meta = {"title": w["title"], "author": w["author"], "source": "aozora", "url": w["card"],
            "note": "" if w["modern"] else "Old spelling (旧字旧仮名)"}
    progress("Searching cover …")
    cover = find_cover(w["title"], w["author"], "aozora-" + w["id"], w["reading"])
    meta["cover"] = cover or ""
    meta["coverTried"] = cover is not None
    book = make_book("aozora-" + w["id"], meta, chapters)
    save_book(book)
    return book


# ───────────────────────── Library ─────────────────────────

def fill_covers():
    # Fetch missing covers of imported books (tried once per book)
    idx = read_json(INDEX, {"books": []})
    found = 0
    for b in idx.get("books", []):
        if b.get("cover") or b.get("coverTried"):
            continue
        progress("Searching cover: " + b.get("title", ""))
        cover = fetch_cover(b["isbn"], b["id"]) if b.get("isbn") else ""
        if not cover and b.get("source") == "aozora":
            w = aozora_catalog().get(b["id"].split("-")[-1], {})
            cover = find_cover(b["title"], b.get("author", ""), b["id"], w.get("reading", ""))
            if cover is None:
                continue
        p = os.path.join(BOOKS, b["id"] + ".json")
        book = read_json(p, None)
        if not book:
            continue
        book["cover"] = cover
        book["coverTried"] = True
        write_json(p, book)
        save_book(book)
        found += bool(cover)
    return {"ok": True, "covers": found}


def scan():
    os.makedirs(IMPORT_DIR, exist_ok=True)
    imp = read_json(IMPORTED, {})
    todo = []
    for root, _, files in os.walk(IMPORT_DIR):
        for f in sorted(files):
            p = os.path.join(root, f)
            if f.lower().endswith(EXTS) and not f.startswith("."):
                e = imp.get(p)
                if not e or (not e.get("ignored") and e.get("mtime") != os.path.getmtime(p)):
                    todo.append(p)
    if not todo:
        fill_covers()
        return {"ok": True, "imported": [], "errors": []}
    if JAPANESE:
        ensure_venv()
    done, errors = [], []
    for p in todo:
        # Errors of one book should not hold up the rest: each in its own subprocess
        r = subprocess.run([sys.executable, os.path.abspath(__file__), "import", p], capture_output=True, text=True)
        last = {}
        for line in r.stdout.splitlines():
            try:
                last = json.loads(line)
            except ValueError:
                continue
            if "progress" in last:
                print(line, flush=True)
        if last.get("ok"):
            done.append(last.get("title", os.path.basename(p)))
        else:
            errors.append("%s: %s" % (os.path.basename(p), last.get("error") or r.stderr.strip()[-200:] or "Error"))
            imp = read_json(IMPORTED, {})
            imp[p] = {"mtime": os.path.getmtime(p), "id": "", "error": True}
            write_json(IMPORTED, imp)
    fill_covers()
    return {"ok": True, "imported": done, "errors": errors}


def delete(book_id):
    p = os.path.join(BOOKS, book_id + ".json")
    book = read_json(p, {})
    if os.path.exists(p):
        os.remove(p)
    cover = book.get("cover") or ""
    if cover.startswith(COVERS) and os.path.exists(cover):
        os.remove(cover)
    idx = read_json(INDEX, {"books": []})
    write_json(INDEX, {"books": [b for b in idx.get("books", []) if b.get("id") != book_id]})
    imp = read_json(IMPORTED, {})
    for k, v in imp.items():
        if v.get("id") == book_id:
            v["ignored"] = True
    write_json(IMPORTED, imp)
    return {"ok": True, "deleted": book_id}


def translate(book_id, ch):
    p = os.path.join(BOOKS, book_id + ".json")
    book = read_json(p, None)
    if not book:
        fail("Book not found")
    ch = int(ch)
    if not 0 <= ch < len(book["chapters"]):
        fail("Chapter not found")
    jt.progress = progress
    cfg = jt.settings()
    name = jt.provider(cfg)
    if not name:
        fail("Translation is off (setting translation.provider)")
    label = jt.NAMES[name]
    sents = [s for para in book["chapters"][ch]["paras"] for s in para if not s.get("en")]
    plain = lambda s: re.sub(r"\{([^|}]+)\|[^}]+\}", r"\1", s["ja"])

    def ask(part):
        try:
            got = jt.translate_batch([plain(s) for _, s in part], name, cfg, (LANG, LANG_NAME))
        except jt.TranslateError as e:
            return str(e)
        for (_, s), en in zip(part, got):
            if en:
                s["en"] = en
        return ""

    todo = list(enumerate(sents))
    # Language models get small batches (one prompt each); DeepL and Argos take more per call
    step = 30 if name in jt.LLMS else 200
    for i in range(0, len(todo), step):
        part = todo[i:i + step]
        progress("Translating %d–%d of %d (%s) …" % (i + 1, i + len(part), len(sents), label))
        err = ask(part)
        if err and not any(s.get("en") for _, s in todo):
            fail("Translation failed: " + err)  # nothing works (missing CLI, key, setup): stop right away
        write_json(p, book)
    missing = [(i, s) for i, s in todo if not s.get("en")]
    if missing and name in jt.LLMS:
        # Language models sometimes leave single ids out: ask once more for those
        progress("Translating %d missing sentences (%s) …" % (len(missing), label))
        ask(missing)
        missing = [(i, s) for i, s in missing if not s.get("en")]
        write_json(p, book)
    save_book(book)
    return {"ok": True, "translated": len(sents) - len(missing), "missing": len(missing), "provider": name}


def main():
    a = sys.argv[1:]
    if not a:
        fail("Command missing")
    cmd = a[0]
    try:
        if cmd == "scan":
            out(scan())
        elif cmd == "import":
            for p in a[1:]:
                b = import_file(p)
                out({"ok": True, "id": b["id"], "title": b["title"]})
        elif cmd == "isbn":
            out(isbn_lookup(" ".join(a[1:])))
        elif cmd == "aozora-search":
            out({"ok": True, "results": aozora_search(" ".join(a[1:]))})
        elif cmd == "aozora-import":
            b = aozora_import(a[1])
            out({"ok": True, "id": b["id"], "title": b["title"]})
        elif cmd == "translate":
            out(translate(a[1], a[2]))
        elif cmd == "covers":
            out(fill_covers())
        elif cmd == "delete":
            out(delete(a[1]))
        else:
            fail("Unknown command: " + cmd)
    except SystemExit:
        raise
    except Exception as e:
        fail("%s: %s" % (type(e).__name__, e))


if __name__ == "__main__":
    main()
