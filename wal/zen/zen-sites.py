#!/usr/bin/env python3
"""pywal colors for any websites in Zen (an extension of zen-youtube.css to many sites).

Idea: modern sites store their colors in CSS variables (GitHub: --bgColor-default ...). Instead of
rebuilding every site by hand, `scan` reads the variables of the DARK design from an invisible
Zen instance (throwaway profile, the normal Zen stays untouched) and maps every color by its position
between the page background and page text to the wal colors:
  neutral tones       -> mix background..foreground (the same relative lightness as on the page)
  darker than the BG  -> background darkened (inset surfaces)
  brand color (links) -> color4 (lighter/darker as on the page)
  red/green/yellow ...-> stay (fixed meaning: error, success, warning)
  semi-transparent black tones (shadows, dimming) stay.
Result: ~/.config/wal/zen/sites.json (data), from it `build` makes ~/.cache/wal/zen-sites.css, which
zen-live (~/.config/wal/zen-live/zen-live.cfg) loads live. Colors as var(--wal-*) fade softly on a
wallpaper change (zen-live registers --wal-* as <color>); variables in the triple format
("13, 17, 23" for rgb(var(--x))) cannot be derived from a color in CSS, they are computed here
as numbers and jump.

    zen-sites.py scan <name> <url> <domain>...  read a site (again), entry in sites.json
    zen-sites.py build [palette-json]           build the CSS (without a palette: ~/.cache/wal/colors.json)
    zen-sites.py shot <url> <out.png> [--plain] screenshot with (or without) the colors
    zen-sites.py list                           registered sites

Called by: Quickshell (scripts/zen_colors.py, at the start of the wallpaper wave) and
~/.config/hypr/scripts/wallpaper-apps.sh (in case Quickshell is not running).
"""
import base64
import json
import math
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path.home()
ZEN = "/opt/zen-browser-bin/zen-bin"
SITES = Path(__file__).resolve().with_name("sites.json")
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "wal"
OUT = CACHE / "zen-sites.css"
PORT = 2897
EASE = "900ms cubic-bezier(0.455, 0.03, 0.515, 0.955)"


# ---------- Colors ----------

def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin_to_srgb(c):
    c = min(max(c, 0.0), 1.0)
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def to_oklch(rgb):
    r, g, b = (srgb_to_lin(x / 255) for x in rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def from_oklch(L, C, H):
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return tuple(round(lin_to_srgb(x) * 255) for x in (r, g, bl))


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hsl_rgb(h, s, l):
    s, l = s / 100, l / 100
    k = lambda n: (n + h / 30) % 12
    a = s * min(l, 1 - l)
    f = lambda n: l - a * max(-1, min(k(n) - 3, 9 - k(n), 1))
    return tuple(round(f(n) * 255) for n in (0, 8, 4))


def rgb_hsl(rgb):
    r, g, b = (x / 255 for x in rgb)
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        return 0, 0, l * 100
    d = mx - mn
    s = d / (1 - abs(2 * l - 1))
    h = (60 * ((g - b) / d % 6) if mx == r else 60 * ((b - r) / d + 2) if mx == g else 60 * ((r - g) / d + 4))
    return h, s * 100, l * 100


NUM = r"(\d+(?:\.\d+)?)"
COLORISH = re.compile(r"color|bg|background|text|fg|foreground|border|surface|accent|primary|secondary|"
                      r"canvas|fill|stroke|shadow|outline|neutral|gray|grey|base|link|muted", re.I)


def parse(name, value):
    """-> (format, (r, g, b), alpha) or None. format: css | rgb-comma | rgb-space | hsl-space"""
    v = value.strip().lower()
    # light-dark(light, dark) (ArchWiki): Zen runs in dark mode -> the second value
    m = re.fullmatch(r"light-dark\((.*)\)", v)
    if m:
        depth, inner = 0, m.group(1)
        for i, ch in enumerate(inner):
            depth += ch == "("
            depth -= ch == ")"
            if ch == "," and depth == 0:
                p = parse(name, inner[i + 1:])
                return ("css",) + p[1:] if p and p[0] == "css" else None
        return None
    if v in ("white", "#fff", "#ffffff"):
        return "css", (255, 255, 255), 1.0
    if v == "black":
        return "css", (0, 0, 0), 1.0
    m = re.fullmatch(r"#([0-9a-f]{3,8})", v)
    if m:
        h = m.group(1)
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        if len(h) not in (6, 8):
            return None
        return "css", hex_rgb(h[:6]), int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    m = re.fullmatch(rf"rgba?\(\s*{NUM}[\s,]+{NUM}[\s,]+{NUM}\s*(?:[,/]\s*{NUM}(%?))?\s*\)", v)
    if m:
        a = float(m.group(4)) / (100 if m.group(5) else 1) if m.group(4) else 1.0
        return "css", tuple(round(float(m.group(i))) for i in (1, 2, 3)), a
    m = re.fullmatch(rf"hsla?\(\s*{NUM}(?:deg)?[\s,]+{NUM}%[\s,]+{NUM}%\s*(?:[,/]\s*{NUM}(%?))?\s*\)", v)
    if m:
        a = float(m.group(4)) / (100 if m.group(5) else 1) if m.group(4) else 1.0
        return "css", hsl_rgb(*(float(m.group(i)) for i in (1, 2, 3))), a
    # Triples only for names that sound like a color ("0 0 0" can also be an offset)
    if not COLORISH.search(name):
        return None
    m = re.fullmatch(r"(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})", v)
    if m:
        return "rgb-comma", tuple(int(m.group(i)) for i in (1, 2, 3)), 1.0
    m = re.fullmatch(r"(\d{1,3}) (\d{1,3}) (\d{1,3})", v)
    if m:
        return "rgb-space", tuple(int(m.group(i)) for i in (1, 2, 3)), 1.0
    m = re.fullmatch(rf"{NUM}(?:deg)? {NUM}% {NUM}%", v)
    if m:
        return "hsl-space", hsl_rgb(*(float(m.group(i)) for i in (1, 2, 3))), 1.0
    return None


def hue_diff(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


# ---------- Mapping ----------
# Spec = [base, target, percent, alpha]: base/target from bg, fg, accent, black; target None = pure

def classify(rgb, alpha, ref):
    L, C, H = to_oklch(rgb)
    Lb, Lf = ref["bg"][0], ref["fg"][0]
    span = max(Lf - Lb, 0.2)
    acc = ref.get("accent")
    # Keep shadows/dimming (semi-transparent near-black)
    if alpha < 1 and L < 0.2 and C < 0.05:
        return None
    # Tinted grays (AniList: blue-gray text, C ~0.05) are neutral, not accent
    if C < 0.065 or (C < 0.08 and (L < 0.25 or L > 0.9)):
        if L < Lb - 0.015:
            return ["bg", "black", round(min(60, (Lb - L) / max(Lb, 0.05) * 100)), alpha]
        t = round(min(max((L - Lb) / span, 0), 1) * 100)
        if t <= 1:
            return ["bg", None, 0, alpha]
        if t >= 99:
            return ["fg", None, 0, alpha]
        return ["bg", "fg", t, alpha]
    if acc and hue_diff(H, acc[2]) < 28:
        # Hue/saturation of color4, lightness as on the page: this way the contrast the page intended
        # for its buttons (white text on purple) stays, even with a light color4
        return ["accentL", None, round(L, 3), alpha]
    return None


def css_expr(spec):
    base, other, pct, alpha = spec
    if base == "accentL":
        a = f" / {round(alpha, 3):g}" if alpha < 0.999 else ""
        return f"oklch(from var(--wal-accent) {pct:g} c h{a})"
    e = f"var(--wal-{base})"
    if other:
        o = "black" if other == "black" else f"var(--wal-{other})"
        e = f"color-mix(in oklch, {e}, {o} {pct}%)"
    if alpha < 0.999:
        e = f"color-mix(in srgb, {e} {round(alpha * 100, 1):g}%, transparent)"
    return e


def mix_oklch(c1, c2, t):
    L1, C1, H1 = c1
    L2, C2, H2 = c2
    if C1 < 1e-4:
        H1 = H2
    if C2 < 1e-4:
        H2 = H1
    dh = (H2 - H1 + 540) % 360 - 180
    return L1 + (L2 - L1) * t, C1 + (C2 - C1) * t, (H1 + dh * t) % 360


def numeric(spec, pal):
    base, other, pct, _ = spec
    if base == "accentL":
        _, C, H = to_oklch(pal["accent"])
        return from_oklch(pct, C, H)
    c = to_oklch(pal[base])
    if other:
        c = mix_oklch(c, to_oklch((0, 0, 0) if other == "black" else pal[other]), pct / 100)
    return from_oklch(*c)


# ---------- Remote-controlling Zen (like youtube-tokens.py) ----------

class Marionette:
    def __init__(self):
        for _ in range(60):
            try:
                self.s = socket.create_connection(("127.0.0.1", PORT))
                break
            except OSError:
                time.sleep(0.5)
        else:
            sys.exit("Zen (Marionette) not reachable")
        self.buf, self.id = b"", 0
        self.recv()

    def recv(self):
        while b":" not in self.buf:
            self.buf += self.s.recv(65536)
        n, rest = self.buf.split(b":", 1)
        while len(rest) < int(n):
            rest += self.s.recv(1 << 20)
        self.buf = rest[int(n):]
        return json.loads(rest[:int(n)])

    def cmd(self, name, params=None):
        self.id += 1
        data = json.dumps([0, self.id, name, params or {}]).encode()
        self.s.sendall(str(len(data)).encode() + b":" + data)
        r = self.recv()
        if r[2]:
            raise RuntimeError(f"{name}: {r[2].get('message')}")
        return r[3]


class Zen:
    """Invisible Zen with a throwaway profile; css = content for userContent.css (user sheet)."""

    def __init__(self, css=""):
        self.prof = tempfile.mkdtemp(prefix="zen-sites-")
        Path(self.prof, "user.js").write_text(
            'user_pref("ui.systemUsesDarkTheme", 1);\n'
            'user_pref("layout.css.prefers-color-scheme.content-override", 0);\n'
            'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);\n'
            f'user_pref("marionette.port", {PORT});\n'
            'user_pref("browser.shell.checkDefaultBrowser", false);\n'
            'user_pref("datareporting.policy.dataSubmissionEnabled", false);\n')
        if css:
            Path(self.prof, "chrome").mkdir()
            Path(self.prof, "chrome", "userContent.css").write_text(css)
        self.proc = subprocess.Popen([ZEN, "--headless", "--marionette", "-no-remote", "--profile", self.prof],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.m = Marionette()
        self.m.cmd("WebDriver:NewSession", {"capabilities": {}})
        self.m.cmd("WebDriver:SetWindowRect", {"width": 1280, "height": 900})

    def open(self, url, wait=6):
        self.m.cmd("WebDriver:Navigate", {"url": url})
        time.sleep(wait)

    def js(self, script):
        return self.m.cmd("WebDriver:ExecuteScript", {"script": script, "args": []})["value"]

    def shot(self, path):
        data = self.m.cmd("WebDriver:TakeScreenshot", {"full": False})["value"]
        Path(path).write_bytes(base64.b64decode(data))

    def close(self):
        try:
            self.m.cmd("Marionette:Quit", {"flags": ["eForceQuit"]})
        except Exception:
            pass
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        shutil.rmtree(self.prof, ignore_errors=True)


SCAN_JS = r"""
const root = document.documentElement, body = document.body || root;
const cs = getComputedStyle(body);
const read = (el) => { const s = getComputedStyle(el), o = {};
    for (let i = 0; i < s.length; i++) { const n = s[i]; if (n.startsWith('--')) o[n] = s.getPropertyValue(n).trim(); }
    return o; };
const tokens = read(body);
// Areas with their own color scheme: selectors with variables that sound like a theme and match an element
// BELOW body (GitHub: <header data-color-mode=dark>; Reddit: .theme-beta matches html AND the
// header). There the page sets its variables again, which would undo the override on html/body
// -> per area all variables set there, values read at that element.
// Only collect here (selector -> variable names); the page may not read stylesheets from foreign domains
// (CDN, Reddit) -> their addresses are returned, scan loads them itself (SCOPE_JS evaluates).
const decls = {}, blocked = [], themeRe = /dark|theme|color-mode|scheme|night/i;
// Split a selector list only at commas OUTSIDE of brackets (:is(.a, .b), Claude)
const splitSel = (text) => { const out = []; let depth = 0, cur = '';
    for (const ch of text) {
        if (ch === '(' || ch === '[') depth++;
        else if (ch === ')' || ch === ']') depth--;
        if (ch === ',' && depth === 0) { out.push(cur); cur = ''; } else cur += ch;
    }
    out.push(cur); return out; };
const walk = (rules) => { for (const r of rules) {
    if (r.style && r.selectorText) {
        const names = []; for (const p of r.style) if (p.startsWith('--')) names.push(p);
        if (names.length) for (const s of splitSel(r.selectorText)) { const t = s.trim();
            if (themeRe.test(t)) decls[t] = [...new Set([...(decls[t] || []), ...names])]; }
    }
    if (r.cssRules) walk(r.cssRules);
} };
for (const sh of [...document.styleSheets, ...(document.adoptedStyleSheets || [])]) {
    try { walk(sh.cssRules); } catch (e) { if (sh.href) blocked.push(sh.href); } }
// Text colors weighted by the amount of text (body.color says nothing on some pages, DuckDuckGo)
const text = {};
const tw = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
for (let n, cnt = 0; (n = tw.nextNode()) && cnt < 4000;) {
    const s = n.textContent.trim();
    if (!s || !n.parentElement) continue;
    const r = n.parentElement.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    cnt++;
    const c = getComputedStyle(n.parentElement).color;
    text[c] = (text[c] || 0) + s.length;
}
const links = {};
for (const a of Array.from(document.querySelectorAll('a')).slice(0, 500)) { const c = getComputedStyle(a).color; links[c] = (links[c] || 0) + 1; }
const area = {};
for (const el of Array.from(document.querySelectorAll('body, body *')).slice(0, 4000)) {
    const st = getComputedStyle(el), r = el.getBoundingClientRect(), a = Math.min(r.width, 1280) * Math.min(r.height, 900);
    if (a > 0 && st.backgroundColor !== 'rgba(0, 0, 0, 0)') area[st.backgroundColor] = (area[st.backgroundColor] || 0) + a;
}
return {tokens, decls, blocked, htmlBg: getComputedStyle(root).backgroundColor, bodyBg: cs.backgroundColor,
        color: cs.color, text, links, area};
"""


SCOPE_JS = r"""
const root = document.documentElement, body = document.body || root, scopes = {};
for (const [sel, names] of Object.entries(arguments[0])) {
    let el;
    try { el = [...document.querySelectorAll(sel)].find(e => e !== root && e !== body); } catch (e) { continue; }
    if (!el) continue;
    const s = getComputedStyle(el), vals = {};
    for (const n of names) { const v = s.getPropertyValue(n).trim(); if (v) vals[n] = v; }
    if (Object.keys(vals).length) scopes[sel] = vals;
}
return scopes;
"""

THEME_SEL = re.compile(r"dark|theme|color-mode|scheme|night", re.I)


def split_selectors(text):
    """Split a selector list only at commas outside of brackets (:is(.a, .b))."""
    out, depth, cur = [], 0, ""
    for ch in text:
        depth += ch in "(["
        depth -= ch in ")]"
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    return out + [cur]


def balanced(sel):
    """Unbalanced brackets would swallow all following sites in the sheet."""
    for o, c in ("()", "[]"):
        depth = 0
        for ch in sel:
            depth += ch == o
            depth -= ch == c
            if depth < 0:
                return False
        if depth:
            return False
    return sel.count('"') % 2 == 0 and sel.count("'") % 2 == 0 and not re.search(r"[{};]", sel)


def blocked_decls(urls):
    """Theme rules from stylesheets the page may not read: load them ourselves and split them roughly
    (innermost blocks 'selector { ... }', also in @media)."""
    import urllib.request
    decls = {}
    for url in urls[:30]:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"})
            css = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", "replace")
        except Exception as error:
            print(f"  stylesheet not loaded: {url[:80]} ({error})", file=sys.stderr)
            continue
        css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
        for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
            names = re.findall(r"(--[\w-]+)\s*:", body)
            if not names:
                continue
            for s in split_selectors(sel):
                s = s.strip()
                if s and not s.startswith("@") and THEME_SEL.search(s):
                    decls[s] = sorted(set(decls.get(s, [])) | set(names))
    return decls


def reference(scan):
    """Page background, text and accent color of the page (OKLCH)."""
    bg = None
    for v in (scan["bodyBg"], scan["htmlBg"]):
        p = parse("color", v)
        if p and p[2] > 0.5:
            bg = p[1]
            break
    if bg is None and scan["area"]:
        p = parse("color", max(scan["area"], key=scan["area"].get))
        bg = p[1] if p else None
    # Text: the lightest neutral color among the frequent text colors (main text, not the muted one)
    fg = None
    weights = {}
    for c, n in scan.get("text", {}).items():
        p = parse("color", c)
        if p and p[2] > 0.5:
            weights[p[1]] = weights.get(p[1], 0) + n
    if weights:
        top = max(weights.values())
        cands = [to_oklch(rgb) for rgb, n in weights.items() if n >= top * 0.1]
        cands = [c for c in cands if c[1] < 0.06] or cands
        fg = max(cands)
    if fg is None:
        p = parse("color", scan["color"])
        fg = to_oklch(p[1] if p else (255, 255, 255))
    ref = {"bg": to_oklch(bg or (28, 27, 34)), "fg": fg}
    best = 0
    for c, n in scan["links"].items():
        p = parse("color", c)
        if p and to_oklch(p[1])[1] > 0.05 and n > best:
            best, ref["accent"] = n, to_oklch(p[1])
    if "accent" not in ref:
        # the most frequent strong color among the variables
        buckets = {}
        for name, v in scan["tokens"].items():
            p = parse(name, v)
            if p:
                L, C, H = to_oklch(p[1])
                if C > 0.08 and 0.45 < L < 0.85:
                    buckets.setdefault(round(H / 20), []).append((L, C, H))
        if buckets:
            group = max(buckets.values(), key=len)
            ref["accent"] = sorted(group)[len(group) // 2]
    return ref


def cmd_scan(name, url, domains):
    zen = Zen()
    try:
        zen.open(url, wait=8)
        scan = zen.js(SCAN_JS)
        decls = scan["decls"]
        for sel, names in blocked_decls(scan["blocked"]).items():
            decls[sel] = sorted(set(decls.get(sel, [])) | set(names))
        scan["scopes"] = zen.m.cmd("WebDriver:ExecuteScript", {"script": SCOPE_JS, "args": [decls]})["value"]
        shots = HOME / ".cache" / "zen-sites-shots"
        shots.mkdir(parents=True, exist_ok=True)
        zen.shot(shots / f"{name}-before.png")
    finally:
        zen.close()
    ref = reference(scan)
    if ref["bg"][0] > 0.5:
        sys.exit(f"{name}: the page is light (no dark mode detected) - not added.")
    def mapped(values):
        out, kept = {}, 0
        for tname, value in sorted(values.items()):
            p = parse(tname, value)
            if not p:
                continue
            spec = classify(p[1], p[2], ref)
            if spec is None:
                kept += 1
                continue
            out[tname] = {"spec": spec, "fmt": p[0], "orig": value}
        return out, kept

    tokens, kept = mapped(scan["tokens"])
    if len(tokens) < 5:
        sys.exit(f"{name}: no color variables (colors fixed in the CSS) - not added.")
    scopes = {}
    for sel, values in scan["scopes"].items():
        m, _ = mapped(values)
        if m:
            scopes[sel] = m
    sites = json.loads(SITES.read_text()) if SITES.exists() else {}
    extra = sites.get(name, {}).get("extra")  # hand additions survive a new scan
    sites[name] = {"url": url, "domains": domains, "tokens": tokens, "scopes": scopes}
    if extra:
        sites[name]["extra"] = extra
    SITES.write_text(json.dumps(sites, indent=1, sort_keys=True) + "\n")
    acc = ref.get("accent")
    print(f"{name}: {len(tokens)} colors mapped, {kept} unchanged, scopes {len(scopes)}, "
          f"BG L={ref['bg'][0]:.2f}, Text L={ref['fg'][0]:.2f}, Akzent " +
          (f"L={acc[0]:.2f} H={acc[2]:.0f}" if acc else "none"))


# ---------- Building the CSS ----------

def palette_from(arg):
    # To test another palette without a wallpaper change: ZEN_SITES_PALETTE='["#..", ... 16x]'
    arg = arg or os.environ.get("ZEN_SITES_PALETTE")
    if arg:
        p = json.loads(arg)
    else:
        c = json.loads((CACHE / "colors.json").read_text())["colors"]
        p = [c[f"color{i}"] for i in range(16)]
    return {"bg": hex_rgb(p[0]), "fg": hex_rgb(p[15]), "accent": hex_rgb(p[4]), "hex": p}


def declarations(tokens, pal):
    decl = []
    for tname, t in sorted(tokens.items()):
        if not re.fullmatch(r"--[\w-]+", tname):
            continue
        spec, fmt = t["spec"], t["fmt"]
        if fmt == "css":
            value = css_expr(spec)
        else:
            r, g, b = numeric(spec, pal)
            if fmt == "rgb-comma":
                value = f"{r}, {g}, {b}"
            elif fmt == "rgb-space":
                value = f"{r} {g} {b}"
            else:
                h, s, l = rgb_hsl((r, g, b))
                value = f"{h:.1f} {s:.1f}% {l:.1f}%"
        decl.append(f"        {tname}: {value} !important;")
    return "\n".join(decl)


def render(pal, only=None):
    sites = json.loads(SITES.read_text()) if SITES.exists() else {}
    out = ["/* Generated by ~/.config/wal/zen/zen-sites.py build - do not edit by hand */"]
    for name, site in sorted(sites.items()):
        if only and name != only:
            continue
        doms = ", ".join(f'domain("{d}")' for d in site["domains"])
        # Base on html/body (beats every page rule there with !important), areas with their own
        # scheme each with their selector
        blocks = [("html, body", site["tokens"])] + sorted(
            (sel, toks) for sel, toks in site.get("scopes", {}).items() if balanced(sel))
        rules = "\n".join(f"    {sel} {{\n{declarations(toks, pal)}\n    }}" for sel, toks in blocks)
        # "extra" in sites.json: hand CSS for colors the page sets fixed instead of via a variable
        if site.get("extra"):
            rules += "\n    " + site["extra"]
        out.append(f"""
/* {name} */
@-moz-document {doms} {{
    html {{
        --wal-bg: {pal['hex'][0]};
        --wal-fg: {pal['hex'][15]};
        --wal-accent: {pal['hex'][4]};
        transition: --wal-bg {EASE}, --wal-fg {EASE}, --wal-accent {EASE};
    }}
{rules}
}}""")
    return "\n".join(out) + "\n"


def cmd_build(arg):
    if not CACHE.is_dir():
        return
    css = render(palette_from(arg))
    tmp = OUT.with_name(OUT.name + ".tmp")
    tmp.write_text(css)
    os.replace(tmp, OUT)  # zen-live reads by path: never half written


def cmd_shot(url, out, plain):
    css = "" if plain else render(palette_from(None))
    zen = Zen(css)
    try:
        zen.open(url, wait=8)
        zen.shot(out)
    finally:
        zen.close()


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "scan" and len(a) >= 4:
        cmd_scan(a[1], a[2], a[3:])
    elif a[0] == "build":
        cmd_build(a[1] if len(a) > 1 else None)
    elif a[0] == "shot" and len(a) >= 3:
        cmd_shot(a[1], a[2], "--plain" in a)
    elif a[0] == "list":
        for name, s in sorted(json.loads(SITES.read_text()).items()):
            print(f"{name:14} {len(s['tokens']):4d} Farben  {' '.join(s['domains'])}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
