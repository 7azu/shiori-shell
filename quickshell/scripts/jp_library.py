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
# Library: ~/.local/share/quickshell/jp-reader/{index.json, books/<id>.json, covers/}
# Furigana/rōmaji with fugashi + unidic-lite + cutlet in their own venv (created on the first
# import). Text markup: {kanji|reading}.

import csv
import hashlib
import html.parser
import io
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shiori_settings  # noqa: E402
import jp_translate as jt  # noqa: E402

# Japanese: setting "books" (default $DOCUMENTS/JapaneseBooks); other languages: <language folder>/Books
IMPORT_DIR = os.environ.get("SHIORI_READER_BOOKS") or shiori_settings.folder("books")
AOZORA_CSV = os.path.join(CACHE, "aozora.csv")
AOZORA_LIST = "https://www.aozora.gr.jp/index_pages/list_person_all_extended_utf8.zip"
UA = "Mozilla/5.0 (X11; Linux x86_64) quickshell-jp-reader"
EXTS = (".epub", ".txt", ".pdf", ".md")

KANJI = "㐀-䶿一-鿿豈-﫿々〆ヶ"
KANJI_RE = re.compile("[%s]" % KANJI)
RUN_RE = re.compile("[%s]+|[^%s]+" % (KANJI, KANJI))
JA_RE = re.compile("[぀-ヿ%s]" % KANJI)
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


_tagger = None
_katsu = None


def tagger():
    global _tagger
    if _tagger is None:
        import fugashi
        _tagger = fugashi.Tagger()
    return _tagger


def katsu():
    global _katsu
    if _katsu is None:
        import cutlet
        _katsu = cutlet.Cutlet()
        _katsu.use_foreign_spelling = False
    return _katsu


# ───────────────────────── Furigana + Rōmaji ─────────────────────────

def hira(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


TRANSLIT = {
    # Cyrillic (Russian, plus Ukrainian/Belarusian/Serbian/Bulgarian letters), simple English-style spelling
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i", "й": "y",
    "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
    "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu",
    "я": "ya", "і": "i", "ї": "yi", "є": "ye", "ґ": "g", "ў": "w", "ј": "j", "љ": "lj", "њ": "nj", "ћ": "ć",
    "ђ": "đ", "џ": "dž",
    # Greek (modern, simple)
    "α": "a", "ά": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "έ": "e", "ζ": "z", "η": "i", "ή": "i", "θ": "th",
    "ι": "i", "ί": "i", "ϊ": "i", "ΐ": "i", "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "x", "ο": "o", "ό": "o",
    "π": "p", "ρ": "r", "σ": "s", "ς": "s", "τ": "t", "υ": "y", "ύ": "y", "ϋ": "y", "ΰ": "y", "φ": "f", "χ": "ch",
    "ψ": "ps", "ω": "o", "ώ": "o",
}
TRANSLIT_RE = re.compile("[%s]" % "".join(TRANSLIT), re.I)


def translit(text):
    """Latin transliteration for scripts the reader shows a second line for; "" for everything else."""
    if not TRANSLIT_RE.search(text):
        return ""
    out = []
    for c in text:
        low = c.lower()
        if low in TRANSLIT:
            t = TRANSLIT[low]
            out.append(t.capitalize() if c != low else t)
        else:
            out.append(c)
    return "".join(out)


def esc(s):
    return s.replace("{", "｛").replace("}", "｝").replace("|", "｜")


def ruby(text, reading):
    return "{%s|%s}" % (esc(text), esc(reading)) if reading and reading != text else esc(text)


def align(surface, reading):
    # 食べ物 + たべもの -> {食|た}べ{物|もの}; if that fails, the whole word gets the reading
    runs = RUN_RE.findall(surface)
    if len(runs) == 1:
        return ruby(surface, reading)
    pat = "".join("(.+?)" if KANJI_RE.match(r) else "(" + re.escape(hira(r)) + ")" for r in runs)
    m = re.fullmatch(pat, reading)
    if not m:
        return ruby(surface, reading)
    return "".join(ruby(r, m.group(i + 1)) if KANJI_RE.match(r) else esc(r) for i, r in enumerate(runs))


# unidic reads these mostly in a formal/rare way; in a learning context the everyday reading is meant
READINGS = {"私": "わたし", "日本": "にほん", "日本人": "にほんじん", "日本語": "にほんご", "方々": "かたがた",
            "何時": "なんじ", "何人": "なんにん", "今日": "きょう", "明日": "あした", "昨日": "きのう"}

# Rōmaji spelling: を = o, compounds together
ROMAJI_FIX = [(r"\b([Ww])o\b", lambda m: "O" if m.group(1) == "W" else "o"), (r"\b([Nn])ippon\b", r"\1ihon"),
              (r"\b([Nn])ihon (go|jin)\b", r"\1ihon\2"), (r" (tari|dari)\b", r"\1"), (r"\s*/\s*", " "),
              (r"\.{3,}|…+", "…")]

# ── Numbers + counters: unidic reads 七時 as なな, 三十分 as ふん ... ──
NUM_DIGITS = {"〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
NUM_UNITS = {"十": 10, "百": 100, "千": 1000}
NUM_RE = re.compile(r"^(?:[〇零一二三四五六七八九十百千万]+|[0-9０-９]+)$")
DIGIT_KANA = ["", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]
GEM = {"いち": "いっ", "ろく": "ろっ", "はち": "はっ", "じゅう": "じゅっ", "ひゃく": "ひゃっ"}


def _h_row(plain, p, b):
    # ふん/ほん/ひき/はい: after っ -> p, after さん/なん -> b (分: also よん -> ぷん)
    d = {"*": plain}
    for e, g in GEM.items():
        if e != "なん":
            d[e] = (g, p)
    d["さん"] = (None, b)
    d["なん"] = (None, b)
    return d


def _gem_row(form, which=("いち", "はち", "じゅう")):
    d = {"*": form}
    for e in which:
        d[e] = (GEM[e], form)
    return d


COUNTERS = {
    "分": dict(_h_row("ふん", "ぷん", "ぷん"), よん=(None, "ぷん")),
    "本": _h_row("ほん", "ぽん", "ぼん"), "匹": _h_row("ひき", "ぴき", "びき"), "杯": _h_row("はい", "ぱい", "ばい"),
    "回": _gem_row("かい", ("いち", "ろく", "はち", "じゅう", "ひゃく")),
    "階": dict(_gem_row("かい", ("いち", "ろく", "はち", "じゅう", "ひゃく")), さん=(None, "がい"), なん=(None, "がい")),
    "個": _gem_row("こ", ("いち", "ろく", "はち", "じゅう", "ひゃく")),
    "冊": _gem_row("さつ"), "歳": _gem_row("さい"), "才": _gem_row("さい"), "週間": _gem_row("しゅうかん"),
    "時": {"*": "じ", "よん": ("よ", "じ"), "なな": ("しち", "じ"), "きゅう": ("く", "じ")},
    "時間": {"*": "じかん", "よん": ("よ", "じかん"), "なな": ("しち", "じかん"), "きゅう": ("く", "じかん")},
    "月": {"*": "がつ", "よん": ("し", "がつ"), "なな": ("しち", "がつ"), "きゅう": ("く", "がつ")},
    "人": {"*": "にん", "よん": ("よ", "にん")}, "年": {"*": "ねん", "よん": ("よ", "ねん")},
    "円": {"*": "えん", "よん": ("よ", "えん")}, "枚": {"*": "まい"}, "番": {"*": "ばん"}, "度": {"*": "ど"},
    "倍": {"*": "ばい"}, "日": {"*": "にち"},
}
DATES = {2: "ふつか", 3: "みっか", 4: "よっか", 5: "いつか", 6: "むいか", 7: "なのか", 8: "ようか", 9: "ここのか",
         10: "とおか", 14: "じゅうよっか", 20: "はつか", 24: "にじゅうよっか"}


def kanji_int(s):
    s = unicodedata.normalize("NFKC", s)
    if s.isdigit():
        return int(s)
    if all(c in NUM_DIGITS for c in s) and len(s) > 1:   # 二〇二六
        return int("".join(str(NUM_DIGITS[c]) for c in s))
    total = section = num = 0
    for c in s:
        if c in NUM_DIGITS:
            num = NUM_DIGITS[c]
        elif c in NUM_UNITS:
            section += (num or 1) * NUM_UNITS[c]
            num = 0
        elif c == "万":
            total += (section + num) * 10000
            section = num = 0
    return total + section + num


def num_kana(n):
    if n == 0:
        return "ぜろ"
    if n >= 10000:
        return num_kana(n // 10000) + "まん" + (num_kana(n % 10000) if n % 10000 else "")
    out = ""
    th, h, t, o = n // 1000, n // 100 % 10, n // 10 % 10, n % 10
    if th:
        out += {1: "せん", 3: "さんぜん", 8: "はっせん"}.get(th, DIGIT_KANA[th] + "せん")
    if h:
        out += {1: "ひゃく", 3: "さんびゃく", 6: "ろっぴゃく", 8: "はっぴゃく"}.get(h, DIGIT_KANA[h] + "ひゃく")
    if t:
        out += ("" if t == 1 else DIGIT_KANA[t]) + "じゅう"
    return out + DIGIT_KANA[o]


def counter_kana(n, counter, prev=""):
    # n = None: 何 + counter
    if counter == "人" and n in (1, 2):
        return "ひとり" if n == 1 else "ふたり"
    if counter == "日" and n is not None:
        if prev.endswith("月") and n == 1:
            return "ついたち"
        if n in DATES:
            return DATES[n]
        if n == 1:
            return None   # 一日: いちにち/ついたち, unidic decides
    if counter == "歳" and n == 20:
        return "はたち"
    row = COUNTERS[counter]
    base = "なん" if n is None else num_kana(n)
    for end in sorted((k for k in row if k != "*"), key=len, reverse=True):
        if base.endswith(end):
            repl, form = row[end]
            return base[:len(base) - len(end)] + (repl if repl is not None else end) + form
    return base + row["*"]


def reading_fixes(toks):
    # -> [(start, end, text, reading)] for number+counter, 〜曜日, rendaku errors at the start of a word
    fixes = []
    i = 0
    while i < len(toks):
        a, b, s, k, pos, base = toks[i]
        if s == "日" and i > 0 and toks[i - 1][2].endswith("曜") and toks[i - 1][1] == a:
            pa, _, ps, pk, _, _ = toks[i - 1]
            fixes.append((pa, b, ps + s, pk + "び"))
        elif NUM_RE.match(s) or s == "何":
            j = i
            while j + 1 < len(toks) and NUM_RE.match(toks[j + 1][2]) and toks[j + 1][0] == toks[j][1] and s != "何":
                j += 1
            nxt = toks[j + 1] if j + 1 < len(toks) and toks[j + 1][0] == toks[j][1] else None
            num_text = "".join(t[2] for t in toks[i:j + 1])
            n = None if s == "何" else kanji_int(num_text)
            prev = toks[i - 1][2] if i > 0 and toks[i - 1][1] == a else ""
            if nxt and nxt[2] in COUNTERS:
                r = counter_kana(n, nxt[2], prev)
                if r:
                    fixes.append((a, nxt[1], num_text + nxt[2], r))
                i = j + 2
                continue
            if n is not None and j > i and KANJI_RE.search(num_text):
                fixes.append((a, toks[j][1], num_text, num_kana(n)))
            i = j + 1
            continue
        elif s[0] in NUM_DIGITS and len(s) > 1 and KANJI_RE.search(s[1:]) and k:
            fixes.append((a, b, s, k))   # 一日, 十分 ...: unidic's reading, but also for the rōmaji
        elif pos == "名詞" and base and k != base and len(k) == len(base) and k[1:] == base[1:] and \
                (i == 0 or toks[i - 1][4] not in ("名詞", "接頭辞") or toks[i - 1][1] != a):
            fixes.append((a, b, s, base))   # 箱の中: バコ -> はこ
        i += 1
    return fixes


def annotate(segs):
    # segs: [(text, reading or "")] (readings from the source take precedence) -> (markup, rōmaji)
    plain = "".join(t for t, _ in segs)
    explicit = []
    pos = 0
    for t, r in segs:
        if r:
            explicit.append((pos, pos + len(t), t, r))
        pos += len(t)
    toks = []
    cur = 0
    for w in tagger()(plain):
        s = w.surface
        i = plain.find(s, cur)
        if i < 0:
            continue
        f = w.feature
        kana = getattr(f, "kana", None)
        base = getattr(f, "kanaBase", None)
        toks.append((i, i + len(s), s, hira(kana) if kana and kana != "*" else "",
                     getattr(f, "pos1", ""), hira(base) if base and base != "*" else ""))
        cur = i + len(s)
    free = lambda a, b: not any(e[0] < b and e[1] > a for e in explicit)
    for a, b, s, k, _, _ in toks:
        if s in READINGS and free(a, b):
            explicit.append((a, b, s, READINGS[s]))
    for fa, fb, ft, fr in reading_fixes(toks):
        if free(fa, fb):
            explicit.append((fa, fb, ft, fr))
    explicit.sort()
    toks = [t[:4] for t in toks]
    res = []
    cur = 0
    for a, b, s, k in toks:
        if b <= cur:
            continue
        if a < cur:
            res.append(esc(plain[cur:b]))
            cur = b
            continue
        if cur < a:
            res.append(esc(plain[cur:a]))
            cur = a
        hits = [e for e in explicit if e[0] < b and e[1] > a]
        if hits:
            for ea, eb, et, er in hits:
                if cur < ea:
                    res.append(esc(plain[cur:ea]))
                if ea >= cur:
                    res.append(align(et, er) if KANJI_RE.search(et) else esc(et))
                    cur = eb
            if cur < b:
                res.append(esc(plain[cur:b]))
                cur = b
        else:
            res.append(align(s, k) if KANJI_RE.search(s) and k else esc(s))
            cur = b
    res.append(esc(plain[cur:]))
    return "".join(res), romaji(plain, explicit)


def romaji(plain, explicit):
    # Pass fixed readings (source, numbers, names) through cutlet as placeholders, otherwise
    # it splits the kana again ("momo tarou")
    if not JA_RE.search(plain):
        return plain.strip()
    src, p, subs = "", 0, {}
    for n, (ea, eb, et, er) in enumerate(explicit):
        key = "zq" + "".join(chr(97 + int(c)) for c in str(n)) + "zq"
        subs[key] = er
        src += plain[p:ea] + " " + key + " "
        p = eb
    src += plain[p:]
    try:
        ro = katsu().romaji(src).strip()
        for key, er in subs.items():
            rr = katsu().romaji(er).replace(" ", "").lower()
            ro = re.sub(key, lambda m: rr, ro, flags=re.I)
    except Exception:
        return ""
    for a, b in ROMAJI_FIX:
        ro = re.sub(a, b, ro)
    ro = re.sub(r" +([,.!?;:”」])", r"\1", re.sub(r"\s+", " ", ro)).strip()
    return re.sub(r"^([\"“'(]*)([a-z])", lambda m: m.group(1) + m.group(2).upper(), ro)


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


# ───────────────────────── Sources ─────────────────────────

def ruby_line(line):
    # Aozora ruby: ｜漢字《かんじ》 or 漢字《かんじ》 (base = the kanji right before)
    segs = []
    pos = 0
    for m in re.finditer(r"《([^》]*)》", line):
        before = line[pos:m.start()]
        reading = m.group(1)
        if "｜" in before:
            i = before.rindex("｜")
            plain, base = before[:i], before[i + 1:]
        else:
            k = re.search("[%s]+$" % KANJI, before)
            if not k:
                segs.append((before, ""))
                pos = m.end()
                continue
            plain, base = before[:k.start()], k.group(0)
        if plain:
            segs.append((plain.replace("｜", ""), ""))
        if base:
            segs.append((base, hira(reading)))
        pos = m.end()
    if pos < len(line):
        segs.append((line[pos:].replace("｜", ""), ""))
    return segs


def parse_aozora(text, title_hint):
    lines = text.replace("\r\n", "\n").split("\n")
    # Header: title, author, then the character legend between two dashed lines
    dash = [i for i, l in enumerate(lines[:80]) if re.match(r"^-{10,}", l)]
    body = lines[dash[1] + 1:] if len(dash) >= 2 else lines
    for i, l in enumerate(body):
        if l.startswith("底本："):
            body = body[:i]
            break
    chapters = []
    title, paras = "", []
    for l in body:
        h = re.search(r"［＃「(.+?)」は[大中小]見出し］", l)
        if h or re.search(r"［＃(大|中|小)見出し］", l):
            if paras:
                chapters.append((title or title_hint, paras))
            title, paras = (h.group(1) if h else re.sub(r"［＃[^］]*］|《[^》]*》|｜", "", l).strip()), []
            continue
        l = re.sub(r"※?［＃[^］]*］", "", l)
        if l.strip():
            paras.append(ruby_line(l))
    if paras:
        chapters.append((title or title_hint, paras))
    if len(chapters) > 1:
        chapters = [(t if t != title_hint or i == 0 else "%s %d" % (t, i + 1), p) for i, (t, p) in enumerate(chapters)]
    return chapters


def decode(raw):
    # Old non-UTF-8 files: the usual legacy encoding of the language
    legacy = {"ja": ("cp932", "euc_jp"), "ru": ("cp1251",), "uk": ("cp1251",), "bg": ("cp1251",), "sr": ("cp1251",),
              "be": ("cp1251",), "el": ("cp1253",), "zh": ("gb18030", "big5"), "ko": ("cp949",)}.get(LANG, ("cp1252",))
    for enc in ("utf-8-sig",) + legacy:
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            pass
    return raw.decode("utf-8", errors="replace")


def parse_txt(path):
    with open(path, "rb") as f:
        text = decode(f.read())
    name = os.path.splitext(os.path.basename(path))[0]
    lines = text.replace("\r\n", "\n").split("\n")
    if re.search(r"《[^》]+》|［＃", text):
        title = lines[0].strip() or name
        author = lines[1].strip() if len(lines) > 1 and len(lines[1].strip()) < 40 else ""
        return {"title": title, "author": author}, parse_aozora(text, title)
    if JAPANESE:
        paras = [ruby_line(l) for l in lines if l.strip() and not l.lstrip().startswith("#")]
    else:
        paras = [[(" ".join(l.strip() for l in block.split("\n")), "")]
                 for block in re.split(r"\n\s*\n", "\n".join(lines))
                 if block.strip() and not block.lstrip().startswith("#")]
    return {"title": name}, [(name, paras)]


def parse_pdf(path):
    if not shutil.which("pdftotext"):
        fail("pdftotext missing (package poppler)")
    r = subprocess.run(["pdftotext", "-enc", "UTF-8", path, "-"], capture_output=True)
    text = r.stdout.decode("utf-8", errors="replace")
    if len(TEXT_RE.findall(text)) < 50:
        fail("PDF without a text layer (probably a scan) – OCR is not supported, better use an EPUB")
    name = os.path.splitext(os.path.basename(path))[0]
    # pdftotext breaks every line: join lines into paragraphs, empty line = new paragraph
    paras, cur = [], ""
    for l in text.replace("\f", "\n\n").split("\n"):
        l = l.strip()
        if not l:
            if cur:
                paras.append(ruby_line(cur))
            cur = ""
        elif JAPANESE or not cur:
            cur += l
        elif cur.endswith("-") and l[:1].islower():
            cur = cur[:-1] + l  # word split at the line end
        else:
            cur += " " + l
    if cur:
        paras.append(ruby_line(cur))
    note = "From PDF – order and furigana may be mixed up" if JAPANESE else "From PDF – the order may be mixed up"
    return {"title": name, "note": note}, [(name, paras)]


class XhtmlText(html.parser.HTMLParser):
    # XHTML -> paragraphs of (text, reading); <ruby>base<rt>reading</rt></ruby> is kept
    BLOCK = {"p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "section", "tr", "dd", "dt"}
    SKIP = {"script", "style", "head", "title", "rp"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.paras = []
        self.cur = []
        self.skip = 0
        self.in_ruby = 0
        self.in_rt = 0
        self.base = ""
        self.rt = ""
        self.heading = ""
        self.in_h = 0

    def flush(self):
        if any(t.strip() for t, _ in self.cur):
            self.paras.append(self.cur)
        self.cur = []

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif tag == "ruby":
            self.in_ruby += 1
            self.base = ""
        elif tag == "rt":
            self.in_rt += 1
            self.rt = ""
        elif tag == "br":
            self.flush()
        elif tag in self.BLOCK:
            self.flush()
            if tag in ("h1", "h2", "h3"):
                self.in_h += 1

    def handle_startendtag(self, tag, attrs):
        if tag == "br":
            self.flush()

    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag == "rt":
            self.in_rt = max(0, self.in_rt - 1)
            if self.in_ruby:
                self.cur.append((self.base, hira(self.rt.strip())))
                self.base = ""
        elif tag == "ruby":
            self.in_ruby = max(0, self.in_ruby - 1)
            if self.base:
                self.cur.append((self.base, ""))
            self.base = ""
        elif tag in self.BLOCK:
            if tag in ("h1", "h2", "h3") and self.in_h:
                self.in_h -= 1
                if not self.heading:
                    self.heading = "".join(t for t, _ in self.cur).strip()
            self.flush()

    def handle_data(self, data):
        if self.skip:
            return
        # Japanese has no spaces, so a line break in the source is nothing; elsewhere it is a space
        data = data.replace("\n", "" if JAPANESE else " ")
        if self.in_rt:
            self.rt += data
        elif self.in_ruby:
            self.base += data
        else:
            self.cur.append((data, ""))

    def result(self):
        self.flush()
        return self.paras


def parse_epub(path):
    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        fail("Not a valid EPUB file")
    names = set(z.namelist())
    if "META-INF/encryption.xml" in names:
        enc = z.read("META-INF/encryption.xml").decode(errors="replace")
        if "EncryptedData" in enc and "font" not in enc.lower():
            fail("EPUB is DRM-protected – only DRM-free EPUBs can be imported")
    ns = {"c": "urn:oasis:names:tc:opendocument:xmlns:container", "opf": "http://www.idpf.org/2007/opf",
          "dc": "http://purl.org/dc/elements/1.1/", "ncx": "http://www.daisy.org/z3986/2005/ncx/"}
    opf_path = ET.fromstring(z.read("META-INF/container.xml")).find(".//c:rootfile", ns).get("full-path")
    base = posixpath.dirname(opf_path)
    opf = ET.fromstring(z.read(opf_path))
    md = opf.find("opf:metadata", ns)

    def dc(tag):
        el = md.find("dc:" + tag, ns) if md is not None else None
        return (el.text or "").strip() if el is not None and el.text else ""

    isbn = ""
    for el in (md.findall("dc:identifier", ns) if md is not None else []):
        digits = re.sub(r"[^0-9X]", "", (el.text or "").upper())
        if len(digits) in (10, 13) and ("isbn" in (el.text or "").lower() or digits.startswith("97")):
            isbn = digits
    manifest = {}
    cover_id = ""
    for it in opf.find("opf:manifest", ns):
        manifest[it.get("id")] = (posixpath.normpath(posixpath.join(base, urllib.parse.unquote(it.get("href")))), it.get("media-type"), it.get("properties") or "")
        if "cover-image" in (it.get("properties") or ""):
            cover_id = it.get("id")
    for m in (md.findall("opf:meta", ns) if md is not None else []):
        if m.get("name") == "cover" and m.get("content") in manifest and not cover_id:
            cover_id = m.get("content")
    # Chapter titles from the table of contents (EPUB3 nav or EPUB2 ncx)
    titles = {}
    for href, mt, props in manifest.values():
        try:
            if "nav" in props.split():
                doc = z.read(href).decode("utf-8", errors="replace")
                for a in re.finditer(r'<a[^>]+href="([^"#]+)[^"]*"[^>]*>(.*?)</a>', doc, re.S):
                    t = re.sub(r"<rt>.*?</rt>|<[^>]+>", "", a.group(2)).strip()
                    titles.setdefault(posixpath.normpath(posixpath.join(posixpath.dirname(href), urllib.parse.unquote(a.group(1)))), html.unescape(t))
            elif mt == "application/x-dtbncx+xml":
                ncx = ET.fromstring(z.read(href))
                for np in ncx.iter("{%s}navPoint" % ns["ncx"]):
                    lab = np.find("ncx:navLabel/ncx:text", ns)
                    src = np.find("ncx:content", ns)
                    if lab is not None and src is not None:
                        p = posixpath.normpath(posixpath.join(posixpath.dirname(href), urllib.parse.unquote(src.get("src").split("#")[0])))
                        titles.setdefault(p, (lab.text or "").strip())
        except (KeyError, ET.ParseError):
            pass
    chapters = []
    spine = opf.find("opf:spine", ns)
    for ref in spine:
        item = manifest.get(ref.get("idref"))
        if not item or "html" not in (item[1] or ""):
            continue
        try:
            raw = z.read(item[0]).decode("utf-8", errors="replace")
        except KeyError:
            continue
        p = XhtmlText()
        p.feed(raw)
        paras = p.result()
        text = "".join(t for q in paras for t, _ in q)
        if len(TEXT_RE.findall(text)) < 15:
            continue
        title = titles.get(item[0]) or p.heading or "Chapter %d" % (len(chapters) + 1)
        # Files without their own entry in the table of contents belong to the chapter before
        if chapters and item[0] not in titles and not p.heading:
            chapters[-1][1].extend(paras)
        else:
            chapters.append((title, paras))
    if not chapters:
        fail("EPUB contains no text (only images, e.g. manga or fixed pages)")
    meta = {"title": dc("title") or os.path.splitext(os.path.basename(path))[0], "author": dc("creator"), "isbn": isbn}
    if cover_id:
        try:
            meta["_cover"] = (z.read(manifest[cover_id][0]), posixpath.splitext(manifest[cover_id][0])[1] or ".jpg")
        except KeyError:
            pass
    return meta, chapters


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


# ───────────────────────── ISBN ─────────────────────────

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


# ───────────────────────── Bibliothek ─────────────────────────

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
