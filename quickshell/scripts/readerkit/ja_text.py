# Read tab, Japanese: furigana and rōmaji with fugashi + unidic-lite + cutlet (their own venv, created on
# the first import, see jp_library.ensure_venv). Text markup: {kanji|reading}.

import re
import unicodedata

KANJI = "㐀-䶿一-鿿豈-﫿々〆ヶ"
KANJI_RE = re.compile("[%s]" % KANJI)
RUN_RE = re.compile("[%s]+|[^%s]+" % (KANJI, KANJI))
JA_RE = re.compile("[぀-ヿ%s]" % KANJI)


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
