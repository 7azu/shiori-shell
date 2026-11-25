# Read tab: read book files (EPUB, PDF, TXT, Aozora format) into (meta, chapters).
# chapters: [(title, paragraphs)], a paragraph is a list of (text, reading or "") segments.

import html.parser
import os
import posixpath
import re
import shutil
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile

from .base import JAPANESE, LANG, fail
from .book import TEXT_RE
from .ja_text import KANJI, hira


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
