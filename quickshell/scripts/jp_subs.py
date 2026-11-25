#!/usr/bin/env python3
# Subtitles for videos in the language tool (services/LanguageAudioState.qml, windows/LanguageSubtitles.qml).
#
#   jp_subs.py build <video> [code name]          .subs/<name>.<lang>.vtt -> .subs/<name>.json (+ .srt for mpv)
#   jp_subs.py translate <json> <idx> [code name] translate one line (scripts/jp_translate.py, remembered in the JSON)
#   jp_subs.py words '<json-list>'                Read tab: sentences (with furigana markup) -> words with dictionary
# code/name = language of the video (default ja Japanese).
#
# build: clean up YouTube subtitles (automatic ones repeat every line as "rolling" text). Japanese: split
# every line into words with fugashi (base form, reading, furigana as in the Read tab), look up every word in
# JMdict (after that a click on a word needs no network) and refine the word times with faster-whisper.
# Other languages: words are split at spaces (no dictionary, no furigana, YouTube word times only).
# JMdict (jmdict-simplified, English) is downloaded the first time and stored as SQLite.
#
# Output: JSON lines like jp_library.py ({"progress": ...}, last {"ok": ...}).
# JSON format: {"cues": [{"s": start, "e": end, "t": text, "w": [word, ...], "en": translation?,
#                         "k": [[char offset without spaces, second], ...]? (word times, automatic only)}]}
#   word: {"t": text, "f": furigana markup, "l": base form, "lr": reading of the base form,
#          "d": {"w": headword, "r": reading, "p": part of speech, "g": [meaning, ...]} or missing}

import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jp_library as jl  # noqa: E402  (furigana, venv, JSON helpers as in the Read tab)
import jp_translate as jt  # noqa: E402  (backend choice, see there)

DICT_DB = os.path.join(jl.DATA, "jmdict.sqlite")
HOME_CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
DICT_API = "https://api.github.com/repos/scriptin/jmdict-simplified/releases/latest"
SKIP_POS = ("補助記号", "空白", "記号")

# Make JMdict parts of speech readable (the rest stays as abbreviations)
POS = {"n": "noun", "pn": "pronoun", "v1": "ichidan verb", "vs": "suru verb", "vs-i": "suru verb",
       "vk": "kuru verb", "vt": "transitive", "vi": "intransitive", "adj-i": "i-adjective",
       "adj-na": "na-adjective", "adj-no": "no-adjective", "adv": "adverb", "prt": "particle",
       "exp": "expression", "aux-v": "auxiliary verb", "aux": "auxiliary", "conj": "conjunction",
       "int": "interjection", "ctr": "counter", "suf": "suffix", "pref": "prefix", "num": "numeral",
       "cop": "copula", "adj-t": "taru adjective", "adv-to": "adverb (to)"}


def ensure_venv():
    """Like jp_library.ensure_venv, but restarts THIS script in the venv."""
    py = os.path.join(jl.VENV, "bin/python")
    if os.path.realpath(sys.prefix) == os.path.realpath(jl.VENV):
        return
    if not os.path.exists(py) or subprocess.run([py, "-c", "import fugashi, unidic_lite"],
                                                capture_output=True).returncode != 0:
        # Same venv as the Read tab, same packages (only that one needs cutlet, but it does no harm)
        jl.progress("Setting up the Japanese tokenizer (one time, ~60 MB) …")
        pkgs = ["fugashi", "unidic-lite", "cutlet"]
        uv = shutil.which("uv")
        try:
            if uv:
                subprocess.run([uv, "venv", "-q", "--allow-existing", jl.VENV], check=True, capture_output=True)
                subprocess.run([uv, "pip", "install", "-q", "--python", py] + pkgs, check=True, capture_output=True)
            else:
                subprocess.run([sys.executable, "-m", "venv", jl.VENV], check=True, capture_output=True)
                subprocess.run([py, "-m", "pip", "install", "-q"] + pkgs, check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            jl.fail("Tokenizer installation failed: " + (e.stderr or b"").decode(errors="replace")[-300:])
    os.execv(py, [py, os.path.abspath(__file__)] + sys.argv[1:])


# ───────────────────────── Dictionary ─────────────────────────

def ensure_dict():
    if os.path.exists(DICT_DB):
        return
    jl.progress("Downloading dictionary (one time, ~12 MB) …")
    rel = json.loads(jl.fetch(DICT_API))
    url = next((a["browser_download_url"] for a in rel.get("assets", [])
                if re.match(r"jmdict-eng-\d.*\.json\.zip$", a["name"])), None)
    if not url:
        jl.fail("Dictionary download not found")
    with tempfile.TemporaryDirectory() as tmp:
        z = os.path.join(tmp, "d.zip")
        with open(z, "wb") as f:
            f.write(jl.fetch(url, timeout=120))
        jl.progress("Building dictionary index …")
        with zipfile.ZipFile(z) as zf:
            data = json.loads(zf.read(zf.namelist()[0]))
    tmpdb = DICT_DB + ".tmp"
    if os.path.exists(tmpdb):
        os.remove(tmpdb)
    db = sqlite3.connect(tmpdb)
    db.execute("CREATE TABLE e (id INTEGER PRIMARY KEY, common INTEGER, j TEXT)")
    db.execute("CREATE TABLE k (key TEXT, id INTEGER)")
    for w in data["words"]:
        kanji = [k["text"] for k in w["kanji"]]
        kana = [k["text"] for k in w["kana"]]
        common = any(k.get("common") for k in w["kanji"] + w["kana"])
        senses = []
        for s in w["sense"]:
            gl = [g["text"] for g in s["gloss"] if g.get("lang", "eng") == "eng"]
            if gl:
                senses.append({"p": s.get("partOfSpeech", []), "g": gl})
        if not senses:
            continue
        eid = int(w["id"])
        db.execute("INSERT INTO e VALUES (?,?,?)", (eid, int(common), json.dumps(
            {"k": kanji, "r": kana, "s": senses}, ensure_ascii=False, separators=(",", ":"))))
        for key in set(kanji + kana):
            db.execute("INSERT INTO k VALUES (?,?)", (key, eid))
    db.execute("CREATE INDEX ki ON k(key)")
    db.commit()
    db.close()
    os.replace(tmpdb, DICT_DB)


_db = None


# Part of speech from unidic -> matching JMdict parts of speech (otherwise "画" wins for が instead of the particle)
UNIDIC_POS = {"助詞": ("prt",), "助動詞": ("aux-v", "cop", "aux"), "動詞": ("v",), "形容詞": ("adj-i",),
              "形状詞": ("adj-na", "adj-no"), "副詞": ("adv",), "名詞": ("n", "pn", "num"), "代名詞": ("pn",),
              "接頭辞": ("pref",), "接尾辞": ("suf", "ctr"), "感動詞": ("int",), "接続詞": ("conj",),
              "連体詞": ("adj-pn",)}


def pos_label(p):
    if p.startswith("v5"):
        return "godan verb"
    return POS.get(p, p)


def lookup(keys, reading, upos=""):
    """Best entry for the first spelling that exists (base form before surface)."""
    global _db
    if _db is None:
        _db = sqlite3.connect(DICT_DB)
    for key in keys:
        if not key:
            continue
        rows = _db.execute("SELECT e.common, e.j FROM k JOIN e ON e.id = k.id WHERE k.key = ?", (key,)).fetchall()
        if not rows:
            continue
        best = None
        for common, j in rows:
            e = json.loads(j)
            # matching reading > common word > spelling as kanji (instead of only listed as kana)
            want = UNIDIC_POS.get(upos, ())
            fits = any(p == w or p.startswith(w) for s in e["s"] for p in s["p"] for w in want)
            kana_key = not jl.KANJI_RE.search(key)
            score = (3 if fits else 0) + (2 if reading and reading in e["r"] else 0) + common \
                + (1 if key in e["k"] else 0) + (1 if kana_key and not e["k"] else 0)
            if best is None or score > best[0]:
                best = (score, e)
        e = best[1]
        pos = list(dict.fromkeys(pos_label(p) for p in e["s"][0]["p"][:2]))
        return {"w": e["k"][0] if e["k"] and key in e["k"] else key,
                "r": e["r"][0] if not reading or reading not in e["r"] else reading,
                "p": ", ".join(pos), "g": ["; ".join(s["g"][:4]) for s in e["s"][:4]]}
    return None


# ───────────────────────── Untertitel ─────────────────────────

TS = r"(\d+:)?\d{1,2}:\d{2}[.,]\d{3}"
NOISE_RE = re.compile(r"[\[［(（][^\]］)）]*[\]］)）]")
MERGE_MAX = 32  # characters: longer lines fit badly into the subtitle bar
MERGE_MAX_SPACED = 80  # the same for languages with spaces (their words are longer in characters)


def seconds(ts):
    parts = ts.replace(",", ".").split(":")
    return sum(float(p) * 60 ** i for i, p in enumerate(reversed(parts)))


def nospace(s):
    return re.sub(r"\s+", "", s)


def chunks(raw, start):
    """Line with word times (YouTube: "お<00:00:13.360><c>やすみ</c>…") -> [[char offset, second], …].
    Offsets count without spaces (the way the words are lined up in the UI)."""
    parts = re.split(r"<(" + TS + r")>", raw)
    out, pos, t = [], 0, start
    # re.split returns [text, time, group, text, time, group, …]
    i = 0
    while i < len(parts):
        # Sound markers do not count: they are not in the shown text
        text = nospace(NOISE_RE.sub("", re.sub(r"<[^>]+>", "", parts[i])))
        if text:
            out.append([pos, round(t, 3)])
            pos += len(text)
        if i + 1 < len(parts):
            t = seconds(parts[i + 1])
        i += 3
    return out


def parse_vtt(path, japanese=True):
    """VTT -> [[start, end, text, word times|None]]. Automatic YouTube subtitles bring every line
    several times (the old one on top, the new one below, word by word with timestamps) -> keep only new lines,
    take their word times along (for highlighting the word being spoken)."""
    raw = open(path, encoding="utf-8", errors="replace").read()
    auto = "<c>" in raw or re.search(r"<" + TS + r">", raw) is not None
    # Line by line instead of by empty lines: YouTube writes lines with just one space that look like
    # block borders and would otherwise tear time and text apart (whole sentences were missing)
    cues = []
    cur = None
    for line in raw.replace("\r", "").split("\n"):
        m = re.match(r"\s*(" + TS + r")\s+-->\s+(" + TS + r")", line)
        if m:
            cur = [seconds(m.group(1)), seconds(m.group(3)), []]
            cues.append(cur)
        elif cur is not None and re.sub(r"<[^>]+>", "", line).strip():
            cur[2].append(line)
    # Remove sound markers ([音楽], [拍手] ...) also in the middle of a line. Raw line and
    # cleaned text stay paired: the word times come from the same line as the text
    clean = lambda t: NOISE_RE.sub("", re.sub(r"<[^>]+>", "", t)).strip()
    paired = []
    for s0, e0, rawl in cues:
        pairs = [(clean(r), r) for r in rawl if clean(r)]
        if pairs:
            paired.append((s0, e0, [p[0] for p in pairs], [p[1] for p in pairs]))
        elif rawl:  # only a sound: keep it as an empty line (counts for "same line continues")
            paired.append((s0, e0, [""], [""]))
    cues = paired
    # Japanese fragments are glued together; elsewhere they are words with a space between them
    glue, merge_max, ends = ("", MERGE_MAX, tuple(jl.SENT_END)) if japanese else (" ", MERGE_MAX_SPACED, (".", "!", "?", "…"))
    out = []
    if auto:
        last = ""
        for start, end, text, rawl in cues:
            if end - start < 0.05:  # skip transition copies (10 ms)
                continue
            line = text[-1]
            if line == last:
                if out:  # same line continues -> extend
                    out[-1][1] = end
                continue
            last = line
            if not line:  # only a sound ([音楽], [拍手] ...)
                continue
            k = chunks(rawl[-1], start)
            if not jl.JA_RE.search(line) and not re.search(r"\w", line):  # only punctuation
                if out:
                    out[-1][1] = end
                    if not out[-1][2].endswith(ends):
                        out[-1][2] += line
                continue
            # Automatic lines are fragments ("…チャンネルのとも" + "です。") -> join them into sentences
            # as long as there is no sentence end in between and the line stays short
            prev = out[-1] if out else None
            if prev and not prev[2].endswith(ends) and len(prev[2]) + len(line) <= merge_max \
                    and start - prev[1] < 0.6:
                shift = len(nospace(prev[2]))
                prev[1] = end
                prev[2] += glue + line
                prev[3] = (prev[3] or []) + [[o + shift, t] for o, t in k]
                continue
            out.append([start, end, line, k])
    else:
        for start, end, text, _ in cues:
            line = " ".join(t for t in text if t)
            if not line:
                continue
            if out and out[-1][2] == line and start - out[-1][1] < 0.1:
                out[-1][1] = end
            else:
                out.append([start, end, line, None])
    return out


def ja_share(path):
    """Share of Japanese characters in the text (without times/tags)."""
    text = re.sub(r"<[^>]+>|" + TS + r"|-->|WEBVTT|Kind:.*|Language:.*|align:\S+|position:\S+", "",
                  open(path, encoding="utf-8", errors="replace").read())
    chars = [c for c in text if not c.isspace() and not c.isdigit()]
    return sum(1 for c in chars if jl.JA_RE.match(c)) / max(1, len(chars))


def find_vtt(video, code="ja"):
    d = os.path.join(os.path.dirname(video), ".subs")
    stem = os.path.splitext(os.path.basename(video))[0]
    found = glob.glob(os.path.join(glob.escape(d), glob.escape(stem) + ".*.vtt"))
    if code != "ja":
        # <stem>.<lang>.vtt with lang = code, code-XX or code-orig; real subtitles before automatic ones
        usable = [p for p in found if re.fullmatch(re.escape(code) + r"(-[\w-]+)?", os.path.basename(p)[len(stem) + 1:-4])]
        usable.sort(key=lambda p: ("orig" in os.path.basename(p)[len(stem):], p))
        return usable[0] if usable else None
    # Real subtitles (ja, ja-JP) before automatically generated ones (ja-orig) - but only if they are really
    # written in Japanese: some channels upload a romaji version as "ja"
    usable = [p for p in found if ja_share(p) >= 0.5]
    usable.sort(key=lambda p: ("orig" in os.path.basename(p)[len(stem):], p))
    return usable[0] if usable else None


def words(text):
    """Line -> words. Verb/adjective + auxiliary verbs/て stay one word (食べました -> 食べる)."""
    groups = []
    for w in jl.tagger()(text):
        f = w.feature
        pos = f.pos1 or ""
        surface = w.surface
        kana = jl.hira(f.kana) if f.kana and f.kana != "*" else surface
        kana = jl.READINGS.get(surface, kana)
        prev = groups[-1] if groups else None
        attach = prev and prev["head"] in ("動詞", "形容詞") and not w.white_space and (
            pos == "助動詞" or (pos == "助詞" and f.pos2 == "接続助詞" and surface in ("て", "で", "ちゃ", "じゃ"))
            or (pos in ("動詞", "形容詞") and f.pos2 == "非自立可能" and prev["last"] in ("て", "で")))
        # Honorific prefix + noun is one word in the dictionary (お金, ご飯)
        if prev and prev["head"] == "接頭辞" and pos == "名詞" and prev["t"] in ("お", "ご", "御"):
            prev.update({"t": prev["t"] + surface, "r": prev["r"] + kana, "head": pos, "last": surface,
                         "l": prev["t"] + surface, "lemma": prev["t"] + surface, "lr": prev["r"] + kana,
                         "fallback": surface})
            continue
        if attach:
            prev["t"] += surface
            prev["r"] += kana
            prev["last"] = surface
            continue
        lemma = (f.lemma or surface).split("-")[0]
        groups.append({"t": surface, "r": kana, "head": pos, "last": surface,
                       "l": f.orthBase if f.orthBase and f.orthBase != "*" else lemma, "lemma": lemma,
                       "lr": jl.hira(f.lForm) if f.lForm and f.lForm != "*" else kana})
    out = []
    for g in groups:
        item = {"t": g["t"]}
        if jl.KANJI_RE.search(g["t"]):
            item["f"] = jl.align(g["t"], g["r"])
        if g["head"] in SKIP_POS:
            out.append(item)
            continue
        if g["l"] != g["t"]:
            item["l"] = g["l"]
            item["lr"] = g["lr"]
        d = lookup([g["l"], g["lemma"], g["t"], g.get("fallback")], g["lr"], g["head"])
        if d:
            item["d"] = d
        out.append(item)
    return out


# ───────────────────────── Word times by speech recognition ─────────────────────────
# YouTube gives times per word only for some parts. For the rest faster-whisper (model
# "small", CPU) listens to the audio; its words are matched with the subtitles by their READING
# (hiragana) (whisper often writes kana where the subtitles have kanji) - line by line in the matching
# time window. The result is remembered in .subs/<name>.whisper.json (a rebuild does not compute again).
WHISPER_MODEL = "small"
KANA_RE = re.compile("[ぁ-ゖァ-ヺー]")


def ensure_whisper():
    """faster-whisper in the venv (optional). False = not available -> YouTube times only."""
    try:
        import faster_whisper  # noqa: F401
        return True
    except ImportError:
        pass
    uv = shutil.which("uv")
    jl.progress("Installing speech recognition (one time) …")
    cmd = [uv, "pip", "install", "-q", "--python", sys.executable, "faster-whisper"] if uv else \
        [sys.executable, "-m", "pip", "install", "-q", "faster-whisper"]
    if subprocess.run(cmd, capture_output=True).returncode != 0:
        return False
    try:
        import faster_whisper  # noqa: F401
        return True
    except ImportError:
        return False


def whisper_words(video, base):
    """[[word, start, end], …] for the whole video (remembered in <base>.whisper.json)."""
    cache = base + ".whisper.json"
    if os.path.exists(cache) and os.path.getmtime(cache) >= os.path.getmtime(video):
        return jl.read_json(cache, None)
    if not ensure_whisper():
        return None
    import numpy as np
    from faster_whisper import WhisperModel
    # Decode the audio ourselves: the bundled PyAV version does not fit every faster-whisper version
    raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", video, "-vn", "-ac", "1", "-ar", "16000",
                          "-f", "s16le", "-"], capture_output=True)
    if raw.returncode != 0 or not raw.stdout:
        return None
    audio = np.frombuffer(raw.stdout, np.int16).astype(np.float32) / 32768
    total = len(audio) / 16000
    hub = os.path.join(os.environ.get("HF_HOME") or os.path.join(HOME_CACHE, "huggingface"), "hub")
    if not glob.glob(os.path.join(hub, "models--*faster-whisper-" + WHISPER_MODEL)):
        jl.progress("Downloading speech model (one time, ~460 MB) …")
    model = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8", cpu_threads=os.cpu_count() or 4)
    segs, _ = model.transcribe(audio, language="ja", word_timestamps=True, beam_size=1, vad_filter=True)
    out = []
    for seg in segs:
        jl.progress("Timing words %d%% …" % min(99, int(seg.end / max(1, total) * 100)))
        for w in seg.words or []:
            out.append([w.word, round(float(w.start), 2), round(float(w.end), 2)])
    jl.write_json(cache, out)
    return out


_kana_cache = {}


def kana(text):
    """Reading as hiragana, kana only (punctuation, spaces, Latin are dropped)."""
    if text not in _kana_cache:
        r = []
        for w in jl.tagger()(text):
            f = w.feature
            k = f.kana if f.kana and f.kana != "*" else w.surface
            r.append(jl.READINGS.get(w.surface) or jl.hira(k))
        _kana_cache[text] = "".join(c for c in jl.hira("".join(r)) if KANA_RE.match(c))
    return _kana_cache[text]


def word_kana(item):
    """Reading of a subtitle word: from the furigana markup, otherwise via the tokenizer."""
    if item.get("f"):
        k = jl.hira(re.sub(r"\{([^|}]+)\|([^}]+)\}", r"\2", item["f"]))
        k = "".join(c for c in k if KANA_RE.match(c))
        if not jl.KANJI_RE.search(re.sub(r"\{[^}]+\}", "", item["f"])):
            return k
    return kana(item["t"])


def align(cues, ww):
    """Match subtitle words with whisper words -> per line k = [[char, second], …, [n, end]]."""
    import difflib
    # whisper as a kana stream, every character with a time (spread evenly within a word)
    wk, wt = [], []
    for text, a, b in ww:
        k = kana(text)
        for i, c in enumerate(k):
            wk.append(c)
            wt.append(a + (b - a) * i / max(1, len(k)))
    out = {}
    for ci, cue in enumerate(cues):
        lo = next((i for i, t in enumerate(wt) if t >= cue["s"] - 1.5), len(wt))
        hi = next((i for i, t in enumerate(wt) if t > cue["e"] + 1.5), len(wt))
        if hi <= lo:
            continue
        sk, owner = [], []
        for wi, item in enumerate(cue["w"]):
            for c in word_kana(item):
                sk.append(c)
                owner.append(wi)
        if not sk:
            continue
        sm = difflib.SequenceMatcher(None, sk, wk[lo:hi], autojunk=False)
        hit = {}
        matched = 0
        for a, b, size in sm.get_matching_blocks():
            for j in range(size):
                hit[a + j] = wt[lo + b + j]
            matched += size
        if matched < 0.4 * len(sk):  # too little recognized -> better not
            continue
        # Start time per word = time of its first recognized syllable
        starts = {}
        for pos, wi in enumerate(owner):
            if pos in hit and wi not in starts:
                starts[wi] = hit[pos]
        offs, p = [], 0
        for item in cue["w"]:
            offs.append(p)
            p += len(nospace(item["t"]))
        n = p
        k = []
        last_t = -1
        for wi in range(len(cue["w"])):
            if wi in starts and starts[wi] > last_t:
                k.append([offs[wi], round(starts[wi], 2)])
                last_t = starts[wi]
        if not k:
            continue
        # End: last recognized syllable + the duration of one syllable
        end = max(hit.values()) + 0.15
        if end > k[-1][1] and k[-1][0] < n:
            k.append([n, round(min(end, cue["e"]), 2)])
        out[ci] = k
    return out


# ───────────────────────── Words for the Read tab ─────────────────────────
# Sentences come with furigana markup ({kanji|reading}, from the book or from fugashi). The plain
# text is split; words that would cut a furigana unit (高校生 -> 高校 + 生) are merged,
# so the book's reading is kept. Result per sentence in DATA/words-cache.json.
WORDS_CACHE = os.path.join(jl.DATA, "words-cache.json")
WORDS_VERSION = 2


def units(markup):
    """{kanji|reading} and single characters -> [(text, reading), …]"""
    out, last = [], 0
    for m in re.finditer(r"\{([^|}]+)\|([^}]+)\}", markup):
        out += [(c, "") for c in markup[last:m.start()]]
        out.append((m.group(1), m.group(2)))
        last = m.end()
    return out + [(c, "") for c in markup[last:]]


def sentence_words(markup):
    us = units(markup)
    plain = "".join(t for t, _ in us)
    # Span of every unit in the plain text
    uspan, p = [], 0
    for t, r in us:
        uspan.append((p, p + len(t), t, r))
        p += len(t)
    # Find the tokenizer's words in the plain text again (it leaves out spaces)
    toks, p = [], 0
    for w in words(plain):
        i = plain.find(w["t"], p)
        if i < 0:
            continue
        toks.append([i, i + len(w["t"]), [w]])
        p = i + len(w["t"])
    # Do not cut a furigana unit: merge the affected words
    groups = []
    for t in toks:
        if groups and any(a < t[0] < b and r for a, b, _, r in uspan if a < groups[-1][1]):
            groups[-1][1] = t[1]
            groups[-1][2] += t[2]
        else:
            groups.append(t)
    out, p = [], 0
    for a, b, ws in groups:
        if a > p:
            out.append({"t": plain[p:a], "gap": 1})  # spaces / skipped parts
        surface = plain[a:b]
        f = "".join("{%s|%s}" % (t, r) if r else t for ua, ub, t, r in uspan if ua >= a and ub <= b)
        item = {"t": surface}
        if f != surface:
            item["f"] = f
        if len(ws) == 1:
            for k in ("l", "lr", "d"):
                if k in ws[0]:
                    item[k] = ws[0][k]
        else:
            # In the dictionary as a whole? Otherwise explain the parts one by one (六時半: 六 – six, 時 – hour, …)
            d = lookup([surface], "")
            if not d:
                parts = [w for w in ws if "d" in w]
                if parts:
                    d = {"w": surface, "r": jl.hira(re.sub(r"\{([^|}]+)\|([^}]+)\}", r"\2", f)), "p": "",
                         "g": ["%s – %s" % (w["t"], w["d"]["g"][0].split(";")[0]) for w in parts]}
            if d:
                item["d"] = d
        out.append(item)
        p = b
    if p < len(plain):
        out.append({"t": plain[p:], "gap": 1})
    return out


def words_for(sentences):
    cache = jl.read_json(WORDS_CACHE, {})
    if cache.get("_v") != WORDS_VERSION:
        cache = {"_v": WORDS_VERSION}
    todo = [s for s in dict.fromkeys(sentences) if s and s not in cache]
    if todo:
        ensure_dict()
        for s in todo:
            cache[s] = sentence_words(s)
        jl.write_json(WORDS_CACHE, cache)
    return {"ok": True, "words": {s: cache[s] for s in sentences if s in cache}}


def srt_time(s):
    ms = int(round(s * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def plain_words(text):
    """Line of a language with spaces -> words, with a " " item between them (the subtitle box sets the words
    without gaps, as Japanese needs; the space items count 0 characters for the word times)."""
    out = []
    for m in re.finditer(r"\S+", text):
        if out:
            out.append({"t": " "})
        out.append({"t": m.group(0)})
    return out


def build(video, code="ja", name="Japanese"):
    video = os.path.abspath(video)
    japanese = code == "ja"
    vtt = find_vtt(video, code)
    stem = os.path.splitext(os.path.basename(video))[0]
    base = os.path.join(os.path.dirname(video), ".subs", stem)
    if not vtt:
        return {"ok": True, "cues": 0, "note": "No %s subtitles available" % name}
    if japanese:
        ensure_dict()
    cues = parse_vtt(vtt, japanese)
    # YouTube's automatic subtitles without word times show two blocks at once: every line officially runs on
    # into the middle of the next one (up to 8 s). In the player that delayed every change -> a line ends where
    # the next one starts (the player does the same for files prepared earlier: LanguageAudioState.clipCues).
    for cur, nxt in zip(cues, cues[1:]):
        if cur[0] < nxt[0] < cur[1]:
            cur[1] = nxt[0]
    # Keep translations that were already stored when rebuilding
    old = {c["t"]: c["en"] for c in jl.read_json(base + ".json", {}).get("cues", []) if c.get("en")}
    result = []
    for i, (start, end, text, k) in enumerate(cues):
        if i % 25 == 0:
            jl.progress("Preparing subtitles %d/%d …" % (i, len(cues)))
        cue = {"s": round(start, 3), "e": round(end, 3), "t": text, "w": words(text) if japanese else plain_words(text)}
        n = len(nospace(text))
        if k and all(a[0] < b[0] for a, b in zip(k, k[1:])) and k[-1][0] < n:
            cue["k"] = k
        if text in old:
            cue["en"] = old[text]
        result.append(cue)
    # Word times: YouTube where dense enough (more exact), otherwise from speech recognition
    # (matched by the hiragana reading -> Japanese only)
    sparse = [i for i, c in enumerate(result) if len(c.get("k") or []) < max(2, len(c["w"]) // 4)] if japanese else []
    timed = 0
    if sparse:
        ww = whisper_words(video, base)
        if ww:
            jl.progress("Matching word timing …")
            got = align(result, ww)
            for i in sparse:
                if i in got:
                    result[i]["k"] = got[i]
                    timed += 1
    jl.write_json(base + ".json", {"source": os.path.basename(vtt), "cues": result})
    with open(base + ".srt", "w", encoding="utf-8") as f:
        for i, c in enumerate(result, 1):
            f.write("%d\n%s --> %s\n%s\n\n" % (i, srt_time(c["s"]), srt_time(c["e"]), c["t"]))
    return {"ok": True, "cues": len(result), "auto": "orig" in os.path.basename(vtt), "sparse": len(sparse),
            "whisperTimed": timed}


def translate(path, idx, code="ja", name="Japanese"):
    data = jl.read_json(path, None)
    idx = int(idx)
    if not data or not 0 <= idx < len(data["cues"]):
        jl.fail("Subtitle line not found")
    cue = data["cues"][idx]
    if cue.get("en"):
        return {"ok": True, "idx": idx, "en": cue["en"]}
    ctx = [c["t"] for c in data["cues"][max(0, idx - 3):idx]]
    jt.progress = jl.progress
    try:
        en = jt.translate_line(cue["t"], ctx, lang=(code, name))
    except jt.TranslateError as e:
        jl.fail("Translation failed: " + str(e))
    # read fresh: another line might have been translated in the meantime
    data = jl.read_json(path, data)
    data["cues"][idx]["en"] = en
    jl.write_json(path, data)
    return {"ok": True, "idx": idx, "en": en}


def main():
    a = sys.argv[1:]
    if a[:1] == ["build"] and len(a) in (2, 4):
        lang = tuple(a[2:4]) or ("ja", "Japanese")
        if lang[0] == "ja":
            ensure_venv()  # fugashi + JMdict; other languages need neither
        jl.out(build(a[1], *lang))
    elif len(a) == 2 and a[0] == "words":
        ensure_venv()
        jl.out(words_for(json.loads(a[1])))
    elif a[:1] == ["translate"] and len(a) in (3, 5):
        jl.out(translate(a[1], a[2], *(a[3:5] or ("ja", "Japanese"))))
    else:
        jl.fail("usage: jp_subs.py build <video> [code name] | translate <json> <idx> [code name] | words <json-list>")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001  (errors as a JSON line to the UI)
        jl.fail("%s: %s" % (type(e).__name__, e))
