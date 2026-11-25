#!/usr/bin/env python3
"""Read the YouTube color variables for the wal template again.

YouTube stores its colors in variables with hash names (--t3e41d7b17b187f69: #0f0f0f), which
can change with a YouTube update. Then YouTube in Zen stays black again -
simply run this script:

    ~/.config/wal/zen/youtube-tokens.py

It starts Zen invisibly with a throwaway profile (the normal Zen stays untouched), reads
the variables of the dark design of youtube.com, maps them by color value to the wal colors
and writes the marked block into ~/.config/wal/templates/zen-youtube.css. Then
~/.cache/wal/zen-youtube.css is regenerated; zen-live reloads it in the running Zen right away.
"""
import json, os, re, shutil, socket, subprocess, sys, tempfile, time

ZEN = "/opt/zen-browser-bin/zen-bin"
TEMPLATE = os.path.expanduser("~/.config/wal/templates/zen-youtube.css")
OUT = os.path.expanduser("~/.cache/wal/zen-youtube.css")
COLORS = os.path.expanduser("~/.cache/wal/colors.json")
BEGIN = "        /* >>> youtube-tokens.py (do not edit by hand) */"
END = "        /* <<< youtube-tokens.py */"
PORT = 2899


def mix(a, b, n):
    return f"color-mix(in oklch, var(--wal-{a}), var(--wal-{b}) {n}%)"


def alpha(c, n):
    return f"color-mix(in srgb, var(--wal-{c}) {n:g}%, transparent)"


# YouTube value in the dark design -> wal color. Everything else (red, green, special colors for
# Premium/AI, black overlays over videos) stays as it is.
FIXED = {
    "#0f0f0f": "var(--wal-bg)",
    "#181818": mix("bg", "fg", 4),
    "#212121": mix("bg", "fg", 7),
    "#282828": mix("bg", "fg", 10),
    "#272727": mix("bg", "fg", 12),
    "#3f3f3f": mix("bg", "fg", 18),
    "#717171": mix("fg", "bg", 60),
    "#909090": mix("fg", "bg", 45),
    "#aaa": mix("fg", "bg", 35),
    "#d9d9d9": mix("fg", "bg", 15),
    "#f1f1f1": "var(--wal-fg)",
    "#fff": "var(--wal-fg)",
    "#3ea6ff": "var(--wal-accent)",
    "#65b8ff": mix("accent", "fg", 30),
    "#263850": mix("bg", "accent", 25),
    "#515561": mix("bg", "accent", 35),
}


def map_value(v):
    v = v.strip().lower()
    if v in FIXED:
        return FIXED[v]
    m = re.fullmatch(r"rgba\((255|15),\s*\1,\s*\1,\s*([0-9.]+)\)", v)
    if m:
        return alpha("fg" if m.group(1) == "255" else "bg", float(m.group(2)) * 100)
    return None


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


READ_JS = r"""
const out = {};
const walk = (rules) => { for (const r of rules) {
    if (r.cssRules && !r.style) walk(r.cssRules);
    if (r.style && r.selectorText === '[dark]')
        for (const p of r.style) if (p.startsWith('--')) out[p] = r.style.getPropertyValue(p).trim();
}};
for (const sh of document.styleSheets) { try { walk(sh.cssRules); } catch (e) {} }
return out;
"""


def read_tokens():
    prof = tempfile.mkdtemp(prefix="zen-yt-")
    with open(os.path.join(prof, "user.js"), "w") as f:
        f.write('user_pref("ui.systemUsesDarkTheme", 1);\n'
                f'user_pref("marionette.port", {PORT});\n'
                'user_pref("browser.shell.checkDefaultBrowser", false);\n')
    zen = subprocess.Popen([ZEN, "--headless", "--marionette", "-no-remote", "--profile", prof],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        m = Marionette()
        m.cmd("WebDriver:NewSession", {"capabilities": {}})
        m.cmd("WebDriver:Navigate", {"url": "https://www.youtube.com/"})
        tokens = {}
        for _ in range(20):  # wait until YouTube's stylesheets are there
            time.sleep(1)
            tokens = m.cmd("WebDriver:ExecuteScript", {"script": READ_JS, "args": []})["value"]
            if len(tokens) > 50:
                break
        try:
            m.cmd("Marionette:Quit", {"flags": ["eForceQuit"]})
        except Exception:
            pass
        return tokens
    finally:
        try:
            zen.wait(10)
        except subprocess.TimeoutExpired:
            zen.kill()
        shutil.rmtree(prof, ignore_errors=True)


def main():
    tokens = read_tokens()
    lines = []
    for name, value in sorted(tokens.items()):
        new = map_value(value)
        if new:
            lines.append(f"        {name}: {new} !important; /* {value} */")
    if len(lines) < 10:
        sys.exit(f"Only {len(lines)} matching variables found - YouTube probably changed something, "
                 "the template stays unchanged.")
    text = open(TEMPLATE).read()
    i, j = text.index(BEGIN), text.index(END)
    text = text[:i + len(BEGIN)] + "\n" + "\n".join(lines) + "\n" + text[j:]
    open(TEMPLATE, "w").write(text)
    print(f"{len(lines)} YouTube variables written")

    # Render like wal itself (same format as the other templates)
    with open(COLORS) as f:
        c = json.load(f)
    flat = {**c["special"], **c["colors"]}
    open(OUT, "w").write(text.format(**flat))


if __name__ == "__main__":
    main()
