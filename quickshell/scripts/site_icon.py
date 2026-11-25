#!/usr/bin/env python3
# Original (colored) icon of a website for the audio dropdown (services/AudioState.qml),
# e.g. for TikTok/Reddit/Instagram, where the image would otherwise change with every short video.
# Prints the path to the cached image, otherwise nothing.
#   site_icon.py <domain>
# 1. The site itself: <link rel="apple-touch-icon"/"icon"> from the HTML, /apple-touch-icon.png
# 2. DuckDuckGo favicon service (small, but almost always there)
# The biggest image found wins (from 128 px on, the search stops).
# Cache per domain in ~/.cache/quickshell/site-icons, so only one network call per site.

import html.parser
import os
import re
import struct
import sys
import urllib.parse
import urllib.request

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quickshell", "site-icons")
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
# How an image is recognized (extension in the cache, so Qt reliably detects the format)
MAGIC = ((b"\x89PNG", ".png"), (b"\xff\xd8", ".jpg"), (b"GIF8", ".gif"), (b"RIFF", ".webp"), (b"\x00\x00\x01\x00", ".ico"))


def fetch(url, timeout=8, limit=2_000_000):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(limit), r.geturl()


def kind(data):
    for magic, ext in MAGIC:
        if data.startswith(magic):
            return ext
    head = data[:400].lstrip().lower()
    if head.startswith(b"<svg") or (head.startswith(b"<?xml") and b"<svg" in head):
        return ".svg"
    return ""


def pixels(data, ext):
    # Edge length from the file header; unknown -> 64
    try:
        if ext == ".svg":
            return 10_000
        if ext == ".png":
            return min(struct.unpack(">II", data[16:24]))
        if ext == ".ico":
            return max((data[6 + 16 * i] or 256) for i in range(struct.unpack("<H", data[4:6])[0]))
        if ext == ".webp":
            chunk = data[12:16]
            if chunk == b"VP8 ":
                return min(struct.unpack("<HH", data[26:30])) & 0x3FFF
            if chunk == b"VP8L":
                b = int.from_bytes(data[21:25], "little")
                return min((b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1)
            if chunk == b"VP8X":
                return min(int.from_bytes(data[24:27], "little"), int.from_bytes(data[27:30], "little")) + 1
    except (struct.error, IndexError, ValueError):
        pass
    return 64


class Links(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.found = []

    def handle_starttag(self, tag, attrs):
        if tag != "link":
            return
        a = dict(attrs)
        rel = (a.get("rel") or "").lower().split()
        href = a.get("href")
        if not href or not ({"icon", "apple-touch-icon", "apple-touch-icon-precomposed"} & set(rel)):
            return
        sizes = [int(n) for n in re.findall(r"(\d+)x\d+", a.get("sizes") or "")]
        size = max(sizes) if sizes else 0
        if (a.get("type") or "").endswith("svg") or href.split("?")[0].endswith(".svg"):
            size = 1000  # scales freely
        elif "apple-touch-icon" in rel[0] and not size:
            size = 180
        self.found.append((size, href))


def candidates(domain):
    try:
        page, final = fetch("https://%s/" % domain, limit=600_000)
        p = Links()
        p.feed(page.decode("utf-8", "replace"))
        for _, href in sorted(p.found, reverse=True):
            yield urllib.parse.urljoin(final, href)
    except Exception:
        pass
    yield "https://%s/apple-touch-icon.png" % domain
    yield "https://icons.duckduckgo.com/ip3/%s.ico" % domain


def main():
    if len(sys.argv) < 2:
        return
    domain = re.sub(r"[^a-z0-9.-]", "", sys.argv[1].lower())
    if not domain:
        return
    os.makedirs(CACHE, exist_ok=True)
    for f in os.listdir(CACHE):
        if f.rsplit(".", 1)[0] == domain:
            print(os.path.join(CACHE, f))
            return
    best, seen = None, set()
    for url in candidates(domain):
        if url in seen:
            continue
        seen.add(url)
        try:
            data, _ = fetch(url)
        except Exception:
            continue
        ext = kind(data)
        if not ext or len(data) < 100:
            continue
        size = pixels(data, ext)
        if not best or size > best[0]:
            best = (size, data, ext)
        if size >= 128:
            break
    if best:
        _, data, ext = best
        path = os.path.join(CACHE, domain + ext)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
        print(path)
        return


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # network gone ... -> no image, the browser icon stays
        print(f"site_icon: {e}", file=sys.stderr)
