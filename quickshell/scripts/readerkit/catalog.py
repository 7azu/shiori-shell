# Read tab: where books and covers come from. Aozora Bunko catalog (public domain works), ISBN lookup
# (NDL, OpenLibrary) and covers (Google Books, OpenLibrary, Amazon).

import csv
import hashlib
import io
import json
import os
import re
import time
import unicodedata
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile

from .base import CACHE, COVERS, fail, fetch, progress
from .ja_text import hira

AOZORA_CSV = os.path.join(CACHE, "aozora.csv")
AOZORA_LIST = "https://www.aozora.gr.jp/index_pages/list_person_all_extended_utf8.zip"


# ───────────────────────── ISBN + covers ─────────────────────────

def norm_isbn(s):
    d = re.sub(r"[^0-9Xx]", "", s).upper()
    if len(d) == 10:
        core = "978" + d[:9]
        check = (10 - sum(int(c) * (1 if i % 2 == 0 else 3) for i, c in enumerate(core)) % 10) % 10
        return core + str(check)
    return d if len(d) == 13 else ""


def isbn10(i13):
    if not i13.startswith("978"):
        return ""
    core = i13[3:12]
    c = (11 - sum((10 - k) * int(d) for k, d in enumerate(core)) % 11) % 11
    return core + ("X" if c == 10 else str(c))


# Placeholders instead of covers (Google: "image not available" as JPEG / gray PNG; Amazon: 1x1 GIF)
NO_COVER_MD5 = {"d7c21c65fc861fc5128753e9e091b23c", "e89e0e364e83c0ecfba5da41007c9a2c"}


def real_image(data):
    if len(data) < 2000 or data[:3] == b"GIF" or hashlib.md5(data).hexdigest() in NO_COVER_MD5:
        return False
    return not (data[:8] == b"\x89PNG\r\n\x1a\n" and data[25:26] == b"\x00")   # grayscale PNG = placeholder


def cover_urls(isbn, sources):
    urls = {"google": "https://books.google.com/books/content?vid=ISBN%s&printsec=frontcover&img=1&zoom=1" % isbn,
            "openlibrary": "https://covers.openlibrary.org/b/isbn/%s-L.jpg?default=false" % isbn}
    if isbn10(isbn):
        urls["amazon"] = "https://images-na.ssl-images-amazon.com/images/P/%s.09.LZZZZZZZ.jpg" % isbn10(isbn)
    return [urls[s] for s in sources if s in urls]


def fetch_cover(isbn, name, sources=("google", "openlibrary", "amazon")):
    # Google Books has almost all Japanese editions; Amazon (ISBN-10 = ASIN) last, because for
    # books without a scan it returns a generated "COVER COMING SOON" that cannot be detected
    for url in cover_urls(isbn, sources):
        try:
            data = fetch(url, 10)
        except Exception:
            continue
        if not real_image(data):
            continue
        d = CACHE if name.startswith("isbn-") else COVERS
        os.makedirs(d, exist_ok=True)
        ext = ".png" if data[:4] == b"\x89PNG" else ".jpg"
        path = os.path.join(d, name + ext)
        with open(path, "wb") as f:
            f.write(data)
        return path
    return ""


def find_cover(title, author, name, reading=""):
    # No ISBN (e.g. Aozora): search modern editions via the NDL, take the first with a cover. Only editions
    # whose title or title reading starts with the work (ごん狐 = ゴンギツネ); anthologies show another work
    q = urllib.parse.urlencode({"title": title, "creator": author, "cnt": 40})
    rss = None
    for _ in range(2):   # the NDL sometimes answers very slowly
        try:
            rss = ET.fromstring(fetch("https://ndlsearch.ndl.go.jp/api/opensearch?" + q, 40))
            break
        except Exception:
            pass
    if rss is None:
        return None
    n = {"dc": "http://purl.org/dc/elements/1.1/", "dcndl": "http://ndl.go.jp/dcndl/terms/"}
    want_t, want_r = norm(title), norm(reading)
    isbns = []
    for item in rss.iter("item"):
        t = norm(item.findtext("dc:title", "", n))
        r = norm(item.findtext("dcndl:titleTranscription", "", n))
        if not (t.startswith(want_t) or (want_r and r.startswith(want_r))):
            continue
        # Volumes of a series with several stories (e.g. graded reader "レベル2, vol. 3"): the cover shows another work
        if any(re.search(r"vol\.|レベル\s*\d", d.text or "") for d in item.findall("dc:description", n)):
            continue
        for el in item.findall("dc:identifier", n):
            if "ISBN" in (el.get("{http://www.w3.org/2001/XMLSchema-instance}type") or ""):
                i = norm_isbn(el.text or "")
                if i and i not in isbns:
                    isbns.append(i)
    for sources in (("google", "openlibrary"), ("amazon",)):
        for i in isbns[:8]:
            c = fetch_cover(i, name, sources)
            if c:
                return c
    return ""


def isbn_lookup(raw):
    isbn = norm_isbn(raw)
    if not isbn:
        fail("Not a valid ISBN")
    info = {}
    try:
        rss = ET.fromstring(fetch("https://ndlsearch.ndl.go.jp/api/opensearch?isbn=" + isbn))
        item = rss.find("channel/item")
        if item is not None:
            n = {"dc": "http://purl.org/dc/elements/1.1/", "dcndl": "http://ndl.go.jp/dcndl/terms/"}
            g = lambda t: (item.findtext(t, "", n) or "").strip()
            creators = [re.sub(r",\s*", "", c.text or "") for c in item.findall("dc:creator", n)]
            info = {"title": g("dc:title"), "titleReading": g("dcndl:titleTranscription"),
                    "author": "・".join(creators[:3]), "publisher": g("dc:publisher"), "year": g("dc:date"),
                    "url": g("link"), "source": "NDL"}
    except Exception:
        pass
    if not info:
        try:
            j = json.loads(fetch("https://openlibrary.org/api/books?bibkeys=ISBN:%s&format=json&jscmd=data" % isbn))
            b = j.get("ISBN:" + isbn)
            if b:
                info = {"title": b.get("title", ""), "author": ", ".join(a["name"] for a in b.get("authors", [])[:3]),
                        "publisher": ", ".join(p["name"] for p in b.get("publishers", [])[:1]),
                        "year": b.get("publish_date", ""), "url": b.get("url", ""), "source": "OpenLibrary"}
        except Exception:
            pass
    if not info:
        fail("Nothing found for this ISBN")
    info["isbn"] = isbn
    info["cover"] = fetch_cover(isbn, "isbn-" + isbn)
    # Freely available? Only Aozora (public domain works) - main title without subtitle/translation
    short = re.split(r"\s[=:：]\s|\s*[（(]", info["title"])[0].strip()
    free = [w for w in aozora_search(short, 8) if norm(w["title"]) == norm(short)] if short else []
    return {"ok": True, "book": info, "free": free}


# ───────────────────────── Aozora Bunko ─────────────────────────

def norm(s):
    return hira(unicodedata.normalize("NFKC", s or "")).lower().replace(" ", "").replace("　", "")


def aozora_catalog():
    if not os.path.exists(AOZORA_CSV) or time.time() - os.path.getmtime(AOZORA_CSV) > 14 * 86400:
        progress("Loading Aozora catalog …")
        try:
            z = zipfile.ZipFile(io.BytesIO(fetch(AOZORA_LIST, 60)))
            os.makedirs(CACHE, exist_ok=True)
            with open(AOZORA_CSV, "wb") as f:
                f.write(z.read(z.namelist()[0]))
        except Exception as e:
            if not os.path.exists(AOZORA_CSV):
                fail("Aozora catalog not reachable: %s" % e)
    works = {}
    with open(AOZORA_CSV, encoding="utf-8-sig", newline="") as f:
        rows = csv.reader(f)
        next(rows, None)
        for r in rows:
            if len(r) < 51 or r[10] != "なし" or not r[45].endswith(".zip"):
                continue
            w = works.get(r[0])
            name = r[15] + r[16]
            if w is None:
                works[r[0]] = w = {"id": r[0], "title": r[1], "reading": r[2], "subtitle": r[4],
                                   "kids": bool(re.search(r"\bK", r[8])), "modern": r[9] == "新字新仮名",
                                   "author": "", "authorReading": "", "url": r[45], "card": r[13]}
            if r[23] == "著者" and not w["author"]:
                w["author"], w["authorReading"] = name, r[17] + r[18]
    return works


def public(w):
    return {k: w[k] for k in ("id", "title", "subtitle", "author", "kids", "modern")}


def aozora_search(query, limit=30):
    q = norm(query)
    if not q:
        return []
    scored = []
    for w in aozora_catalog().values():
        t, tr, a, ar = norm(w["title"]), norm(w["reading"]), norm(w["author"]), norm(w["authorReading"])
        if q == t or q == tr:
            s = 100
        elif t.startswith(q) or tr.startswith(q):
            s = 60
        elif q in t or q in tr:
            s = 40
        elif q in a or q in ar:
            s = 30
        else:
            continue
        s += (15 if w["kids"] else 0) + (10 if w["modern"] else -20)
        scored.append((-s, w["title"], w))
    scored.sort(key=lambda x: (x[0], x[1]))
    return [public(w) for _, _, w in scored[:limit]]
