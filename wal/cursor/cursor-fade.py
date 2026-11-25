#!/usr/bin/env python3
"""Live cursor color fade on a wallpaper switch (driven by ~/.config/quickshell/services/CursorColorFade.qml).

Quickshell blends its colors (WalColors) in steps from the start of the wallpaper wave and sends the
cursor accent (vivid accent rule, as in gen-cursor.sh) here as lines on stdin:

    step #from #to T   a running fade: old accent, new accent, progress 0..1
    final #to          end color (also for switches without a fade)

A step is a cross-fade of two finished cursors (rendered once in the old and once in the new accent,
then mixed pixel by pixel), not a cursor tinted with a mixed accent: mixing two accents rotates the hue
through colors neither palette has (olive -> bright green -> blue).

The source cursors of the active theme (<theme>/src, settings in <theme>/gen-cursor.conf, see
gen-cursor.sh) are decoded once and kept as ani2xcursor.Tinter templates; one color costs ~3 ms.

Hyprland ignores `setcursor` with the theme it already has, and gen-cursor.sh's workaround (switch to
Adwaita and back) would flash Adwaita on every step. Steps therefore go into two scratch themes
<theme>-fade-a / -b (files in $XDG_RUNTIME_DIR = RAM, linked from ~/.local/share/icons) and Hyprland
alternates between them; `final` writes the real theme and switches back to it. Old steps that piled
up while one was being applied are dropped (only the newest line counts).

While fading, Hyprland's cursor:sync_gsettings_theme is switched off, otherwise every step would write
the scratch theme name to gsettings (GTK apps reloading 20x/s, gen-cursor.sh reading the wrong theme).
"""
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import threading
import time

import numpy as np

sys.path.insert(0, str(pathlib.Path.home() / ".config/hypr/scripts"))
from ani2xcursor import (CHROMA_MAX, TintParams, Tinter, add_size, link_aliases,  # noqa: E402  # pyright: ignore[reportMissingImports]
                         load, write_xcursor)

ICONS = pathlib.Path.home() / ".local/share/icons"
RUNTIME = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "cursor-fade"
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
FADE_SUFFIX = re.compile(r"-fade-[ab]$")


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout.strip()


def gsetting(key):
    return run("gsettings", "get", "org.gnome.desktop.interface", key).strip("'")


def conf(theme_dir, key, default):
    try:
        lines = (theme_dir / "gen-cursor.conf").read_text().splitlines()
    except OSError:
        return default
    vals = [ln.split("=", 1)[1].strip() for ln in lines if ln.startswith(key + "=")]
    return vals[-1] if vals else default


def number(theme_dir, key, default, kind=float):
    try:
        return kind(conf(theme_dir, key, str(default)))
    except ValueError:
        return default


class Theme:
    """Active cursor theme with its prepared source cursors."""

    def __init__(self, name):
        self.name = name
        self.dir = ICONS / name
        self.src = self.dir / "src"
        self.settings = Theme.read_settings(self.dir)
        self.mode, self.saturation, self.chroma, self.size = self.settings
        self.files = sorted(f for f in self.src.glob("*") if f.suffix in (".ani", ".cur") and f.is_file())
        self.signature = self.sig()
        # shape -> [(delay, [(size, xhot, yhot, Tinter), ...]), ...]
        self.shapes = {f.stem: [(d, [(s, x, y, Tinter(img, self.mode)) for s, x, y, img in imgs])
                                for d, imgs in load(f)] for f in self.files}
        self.usable = "default" in self.shapes
        self.cache = {}  # color -> rendered shapes (the two ends of a fade)

    @staticmethod
    def read_settings(theme_dir):
        """tint mode, saturation factor, max chroma, extra size from gen-cursor.conf (as gen-cursor.sh)"""
        return (conf(theme_dir, "tint", "blue"), number(theme_dir, "saturation", 1.0),
                number(theme_dir, "chroma", CHROMA_MAX), number(theme_dir, "size", 0, int))

    def sig(self):
        try:
            return tuple((f.name, f.stat().st_mtime_ns) for f in self.files)
        except OSError:
            return None

    def render(self, color):
        """shape -> frames with RGBA arrays, tinted towards color (cached: a fade needs the same two)"""
        color = color.lower()
        if color not in self.cache:
            if len(self.cache) > 4:
                self.cache.clear()
            p = TintParams(color, self.saturation, self.chroma)
            self.cache[color] = {name: [(d, [(s, x, y, t.render(p)) for s, x, y, t in imgs]) for d, imgs in frames]
                                 for name, frames in self.shapes.items()}
        return self.cache[color]

    def mix(self, a, b, t):
        """Cross-fade of two rendered sets (same shapes, frames and sizes): a at t=0, b at t=1."""
        out = {}
        for name, frames_a in a.items():
            out[name] = [(d, [(s, x, y, np.rint(ia.astype(np.float32) * (1 - t) + ib.astype(np.float32) * t)
                               .astype(np.uint8))
                              for (s, x, y, ia), (_, _, _, ib) in zip(imgs_a, imgs_b)])
                         for (d, imgs_a), (_, imgs_b) in zip(frames_a, b[name])]
        return out

    def write(self, cdir, rendered):
        cdir.mkdir(parents=True, exist_ok=True)
        for name, frames in rendered.items():
            write_xcursor(cdir / name, add_size(frames, self.size))
            link_aliases(cdir, name)

    def scratch(self, slot):
        """Scratch theme <name>-fade-<slot>: files in RAM, linked into ~/.local/share/icons."""
        name = f"{self.name}-fade-{slot}"
        real = RUNTIME / name
        (real / "cursors").mkdir(parents=True, exist_ok=True)
        index = real / "index.theme"
        if not index.exists():
            index.write_text(f"[Icon Theme]\nName={name}\nComment=Scratch theme for the live color fade "
                             f"(~/.config/wal/cursor/cursor-fade.py)\nHidden=true\nInherits={self.name}\n")
        link = ICONS / name
        if not (link.is_symlink() and os.readlink(link) == str(real)):
            if link.is_symlink():
                link.unlink()
            if not link.exists():
                link.symlink_to(real)
        return name, real / "cursors"


class Fader:
    def __init__(self):
        self.theme = None
        self.slot = "a"
        self.size = 32
        self.last = 0.0
        self.sync_restore = None  # previous cursor:sync_gsettings_theme while a fade runs
        self.target = None        # end color of the running fade (for an aborted fade)

    def refresh(self):
        """At the start of a fade: re-read theme name/size, reload the sources if they changed."""
        name = FADE_SUFFIX.sub("", gsetting("cursor-theme") or os.environ.get("XCURSOR_THEME", ""))
        try:
            self.size = int(gsetting("cursor-size") or 32)
        except ValueError:
            self.size = 32
        if not name:
            self.theme = None
            return
        t = self.theme
        if t is None or t.name != name or t.sig() != t.signature or Theme.read_settings(ICONS / name) != t.settings:
            try:
                self.theme = Theme(name)
            except Exception as e:  # broken/missing pack: stay idle
                print(f"cursor-fade: {name}: {e}", file=sys.stderr)
                self.theme = None

    def set_sync(self, on):
        lua = "hl.config({ cursor = { sync_gsettings_theme = %s } })" % ("true" if on else "false")
        run("hyprctl", "eval", lua)

    def step(self, frm, to, t):
        th = self.theme
        if th is None:
            return
        self.target = to
        if self.sync_restore is None:
            try:
                opt = json.loads(run("hyprctl", "getoption", "cursor:sync_gsettings_theme", "-j"))
                self.sync_restore = bool(opt.get("bool", opt.get("int", True)))
            except (ValueError, AttributeError):
                self.sync_restore = True
            self.set_sync(False)
        self.slot = "b" if self.slot == "a" else "a"
        name, cdir = th.scratch(self.slot)
        th.write(cdir, th.mix(th.render(frm), th.render(to), max(0.0, min(1.0, t))))
        run("hyprctl", "setcursor", name, str(self.size))

    def final(self, to):
        self.target = None
        th = self.theme
        if th is None or not to:
            if self.sync_restore is not None:
                self.set_sync(self.sync_restore)
                self.sync_restore = None
            return
        th.write(th.dir / "cursors", th.render(to))
        (th.dir / ".tint-stamp").write_text(f"{th.mode} {to.lower()}\n")
        run("hyprctl", "setcursor", th.name, str(self.size))
        if self.sync_restore is not None:
            self.set_sync(self.sync_restore)
            self.sync_restore = None

    def handle(self, cmd):
        now = time.monotonic()
        if now - self.last > 1.0:  # new fade (or a lone final): check theme + sources
            self.refresh()
        self.last = now
        if not self.theme or not self.theme.usable:
            return
        if cmd[0] == "step":
            self.step(cmd[1], cmd[2], float(cmd[3]))
        else:
            self.final(cmd[1])


def parse(line):
    p = line.split()
    if len(p) == 4 and p[0] == "step" and HEX.match(p[1]) and HEX.match(p[2]):
        try:
            float(p[3])
            return tuple(p)
        except ValueError:
            return None
    if len(p) == 2 and p[0] == "final" and HEX.match(p[1]):
        return tuple(p)
    return None


def loop(fader, latest, cond):
    """Apply the newest command until stdin closes."""
    while True:
        with cond:
            while not latest:
                # a fade that never got its final (Quickshell reloaded mid-fade): settle on its end color
                # in the real theme instead of staying on a scratch theme
                if not cond.wait(timeout=2.0) and not latest and fader.target:
                    latest.append(("final", fader.target))
            cmd = latest.pop()
        if cmd[0] == "eof":
            break
        try:
            fader.handle(cmd)
        except Exception as e:
            print(f"cursor-fade: {' '.join(cmd)}: {e}", file=sys.stderr)


def main():
    fader = Fader()
    fader.refresh()  # decode the sources now, not on the first step
    latest = []
    cond = threading.Condition()

    def reader():
        for line in sys.stdin:
            cmd = parse(line)
            if cmd:
                with cond:
                    # a pending final must not be swallowed by a step of the next fade
                    if not (latest and latest[0][0] == "final" and cmd[0] == "step"):
                        latest[:] = [cmd]
                    cond.notify()
        with cond:
            latest[:] = [("eof",)]
            cond.notify()

    threading.Thread(target=reader, daemon=True).start()
    # Quickshell gone (setpriv --pdeathsig TERM) or stdin closed: leave no scratch theme behind
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        loop(fader, latest, cond)
    finally:
        if fader.sync_restore is not None:  # stopped mid-fade
            try:
                fader.final(fader.target)
            except Exception:
                fader.set_sync(fader.sync_restore)


if __name__ == "__main__":
    main()
