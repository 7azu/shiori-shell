# Read tab: from paragraphs to a book. Paragraphs are lists of (text, reading or "") segments; a book is
# chapters -> paragraphs -> sentences {"ja": text with furigana markup, "ro": rōmaji or transliteration}.

import os
import re
import time

from .base import BOOKS, INDEX, JAPANESE, LANG_NAME, fail, progress, read_json, write_json
from .ja_text import JA_RE, KANJI_RE, annotate, esc
from .translit import translit

OPEN_Q = "「『（(【〈《"
CLOSE_Q = "」』）)】〉》"
SENT_END = "。！？!?…"
# Other languages: letters of any script count as text; "." ends a sentence too, but Latin-style ends only
# before whitespace (3.5, e.g. stay whole); only unambiguous quote pairs (« », „ " differs between languages)
TEXT_RE = JA_RE if JAPANESE else re.compile(r"[^\W\d_]")
if not JAPANESE:
    SENT_END += "."
    OPEN_Q += "«"
    CLOSE_Q += "»"
SPACE_END = "" if JAPANESE else ".!?…"
PART_CHARS = 3000      # cut long chapters into parts of this size ...
SPLIT_ABOVE = 4500     # ... as soon as they are longer


def split_sentences(segs):
    # Paragraph -> sentences; no split inside brackets/quotes
    sents = []
    cur = []
    depth = 0
    pending = False   # end of sentence seen, closing characters may still follow
    need_space = False  # ... and it was a Latin-style end, which only counts before whitespace
    quoted = False    # ... namely at the end of a quote (「…。」と言った stays one sentence)
    for t, r in segs:
        if r:
            if pending and depth == 0:
                sents.append(cur)
                cur = []
                pending = False
            cur.append((t, r))
            continue
        buf = ""
        for c in t:
            if pending and depth == 0 and quoted and c in "とっ、":
                pending = False
            if pending and depth == 0 and need_space and c not in SENT_END and c not in CLOSE_Q and not c.isspace():
                pending = need_space = False  # 3.5, e.g. -> still the same sentence
            if pending and depth == 0 and c not in SENT_END and c not in CLOSE_Q:
                if buf:
                    cur.append((buf, ""))
                sents.append(cur)
                cur, buf = [], ""
                pending = False
            buf += c
            if c in OPEN_Q:
                depth += 1
            elif c in CLOSE_Q:
                depth = max(0, depth - 1)
                if depth == 0 and buf[-2:-1] and buf[-2] in SENT_END:
                    pending = quoted = True
            elif c in SENT_END and depth == 0:
                pending = True
                need_space = c in SPACE_END
                quoted = False
        if buf:
            cur.append((buf, ""))
    if cur:
        sents.append(cur)
    sents = [s for s in sents if "".join(t for t, _ in s).strip()]
    if not JAPANESE:
        # «…?» — said she. / т. е. слово: a "sentence" that starts with a dash or a small letter belongs to the one before
        merged = []
        for s in sents:
            head = "".join(t for t, _ in s).lstrip()[:1]
            if merged and (head in "—–-" or head.islower()):
                merged[-1] = merged[-1] + s
            else:
                merged.append(s)
        sents = merged
    return sents


def strip_segs(segs):
    # Remove whitespace at the paragraph edge (e.g. indent "　")
    segs = [list(s) for s in segs if s[0]]
    while segs and not segs[0][1] and not segs[0][0].strip():
        segs.pop(0)
    while segs and not segs[-1][1] and not segs[-1][0].strip():
        segs.pop()
    if segs and not segs[0][1]:
        segs[0][0] = segs[0][0].lstrip()
    if segs and not segs[-1][1]:
        segs[-1][0] = segs[-1][0].rstrip()
    return [tuple(s) for s in segs if s[0]]


def build_paras(paras):
    # [[(text, reading)]] per paragraph -> [[{ja, ro}]]
    built = []
    for p in paras:
        p = strip_segs(p)
        if not p:
            continue
        sents = []
        for s in split_sentences(p):
            if JAPANESE:
                ja, ro = annotate(strip_segs(s))
            else:
                # The field stays "ja" (the reader's sentence text in every language); no markup, so escape it
                plain = re.sub(r"\s+", " ", "".join(t for t, _ in strip_segs(s))).strip()
                ja, ro = esc(plain), translit(plain)
            if ja:
                sents.append({"ja": ja, "ro": ro})
        if sents:
            built.append(sents)
    return built


def para_chars(p):
    return sum(len(t) for t, _ in p)


def split_long(chapters):
    # chapters: [(title, paragraphs as segs)] -> cut long ones into parts
    res = []
    for title, paras in chapters:
        total = sum(para_chars(p) for p in paras)
        if total <= SPLIT_ABOVE:
            res.append((title, paras))
            continue
        parts, cur, n = [], [], 0
        for p in paras:
            cur.append(p)
            n += para_chars(p)
            if n >= PART_CHARS:
                parts.append(cur)
                cur, n = [], 0
        if cur:
            if parts and n < PART_CHARS / 3:
                parts[-1].extend(cur)
            else:
                parts.append(cur)
        for i, part in enumerate(parts):
            res.append(("%s (%d/%d)" % (title, i + 1, len(parts)), part))
    return res


def level_of(text):
    ja = [c for c in text if JA_RE.match(c)]
    if not ja:
        return "?", 0
    pct = round(100 * sum(1 for c in ja if KANJI_RE.match(c)) / len(ja))
    return ("Easy" if pct < 18 else "Medium" if pct < 28 else "Hard"), pct


def make_book(book_id, meta, chapters):
    chapters = split_long([(t, p) for t, p in chapters if any(TEXT_RE.search("".join(x for x, _ in q)) for q in p)])
    if not chapters:
        fail("No %s text found" % LANG_NAME)
    built = []
    alltext = []
    for i, (title, paras) in enumerate(chapters):
        progress("%s %d/%d: %s" % ("Furigana" if JAPANESE else "Chapter", i + 1, len(chapters), title))
        bp = build_paras(paras)
        if bp:
            built.append({"title": title, "paras": bp})
            alltext.append("".join(t for p in paras for t, _ in p))
    level, pct = level_of("".join(alltext)) if JAPANESE else ("", 0)
    book = dict(meta)
    book.update({"id": book_id, "level": meta.get("level") or level, "kanjiPct": pct,
                 "added": int(time.time()), "chapters": built})
    return book


def index_entry(book):
    return {k: book.get(k) for k in ("id", "title", "author", "level", "kanjiPct", "source", "cover", "coverTried", "isbn", "added", "note", "url")} | {
        "chapters": [{"title": c["title"],
                      "sentences": sum(len(p) for p in c["paras"]),
                      "chars": sum(len(s["ja"]) for p in c["paras"] for s in p),
                      "translated": all(s.get("en") for p in c["paras"] for s in p)} for c in book["chapters"]]}


def save_book(book):
    write_json(os.path.join(BOOKS, book["id"] + ".json"), book)
    idx = read_json(INDEX, {"books": []})
    books = [b for b in idx.get("books", []) if b.get("id") != book["id"]]
    books.append(index_entry(book))
    write_json(INDEX, {"books": books})
