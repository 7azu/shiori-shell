#!/usr/bin/env python3
"""Finds the search URL of a website for the launcher's "?" search ("geizhals.de monitor").

  site-search.py <host> <cache.json>

Prints a URL template with %s where the search term goes, or nothing if the site has no usable search.
First the site's OpenSearch description (<link rel="search">), then a GET search form on the start page.
Answers are cached in <cache.json> as { "<host>": "<template or empty>" }; network errors are not cached.
"""
import json
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
FIELD_NAMES = {"q", "query", "search", "s", "k", "keyword", "keywords", "text", "term", "searchterm", "suche", "qs", "searchtext"}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,application/xml,*/*"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return r.read(1_500_000).decode(r.headers.get_content_charset() or "utf-8", "replace"), r.geturl()


def attrs(tag):
    return {m.group(1).lower(): m.group(3) for m in re.finditer(r'([\w:-]+)\s*=\s*(["\'])(.*?)\2', tag, re.S)}


def from_opensearch(html, base):
    for tag in re.findall(r"<link\b[^>]*>", html, re.I):
        a = attrs(tag)
        if "opensearch" not in a.get("type", "").lower() or "href" not in a:
            continue
        xml, _ = fetch(urllib.parse.urljoin(base, a["href"]))
        for el in ET.fromstring(xml).iter():
            if not el.tag.endswith("Url") or el.get("method", "get").lower() != "get":
                continue
            if el.get("type", "text/html") not in ("text/html", "application/xhtml+xml"):
                continue
            tpl = el.get("template", "")
            tpl = re.sub(r"[&?][^=&{}]+=\{[^}]*\?\}", "", tpl)          # optional parameters out
            tpl = re.sub(r"\{searchTerms\??\}", "%s", tpl)
            tpl = re.sub(r"\{[^}]*\}", "", tpl)
            tpl = tpl.replace("?&", "?").replace("&&", "&")
            if "%s" in tpl:
                return urllib.parse.urljoin(base, tpl)
    return ""


def from_form(html, base):
    for form in re.findall(r"<form\b.*?</form>", html, re.I | re.S):
        head = re.match(r"<form\b[^>]*>", form, re.I).group(0)
        fa = attrs(head)
        if fa.get("method", "get").lower() != "get":
            continue
        field, hidden = None, []
        for tag in re.findall(r"<input\b[^>]*>", form, re.I):
            a = attrs(tag)
            name, kind = a.get("name", ""), a.get("type", "text").lower()
            if kind == "hidden" and name:
                hidden.append((name, a.get("value", "")))
            elif field is None and name and (kind == "search" or (kind == "text" and name.lower() in FIELD_NAMES) or name.lower() in FIELD_NAMES):
                field = name
        if field is None:
            continue
        action = urllib.parse.urljoin(base, fa.get("action", "") or base)
        query = "&".join(urllib.parse.quote(n) + "=" + urllib.parse.quote(v) for n, v in hidden + [(field, "")])
        query = re.sub(re.escape(urllib.parse.quote(field)) + "=$", urllib.parse.quote(field) + "=%s", query)
        return action + ("&" if "?" in action else "?") + query
    return ""


def main():
    host, cache_path = sys.argv[1], sys.argv[2]
    try:
        cache = json.load(open(cache_path))
    except Exception:
        cache = {}
    if host in cache:
        print(cache[host])
        return
    try:
        html, base = fetch("https://" + host + "/")
    except Exception:
        sys.exit(1)
    tpl = ""
    for step in (from_opensearch, from_form):
        try:
            tpl = step(html, base)
        except Exception:
            tpl = ""
        if tpl:
            break
    cache[host] = tpl
    try:
        json.dump(cache, open(cache_path, "w"), indent=1)
    except Exception:
        pass
    print(tpl)


main()
