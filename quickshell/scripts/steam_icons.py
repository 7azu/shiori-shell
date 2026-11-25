#!/usr/bin/env python3
"""Sharper icons for Steam games in the app launcher.

For desktop shortcuts Steam only stores the sizes contained in the official app icon -
for many games only 32-64 px, which get upscaled and pixelated in the launcher (~74 px, times scaling).
The games' .exe mostly contains a 256 px icon. This script extracts it with wrestool/icotool
(package icoutils) and stores ONLY missing sizes in ~/.local/share/icons/hicolor; Steam's
own files stay untouched. After new games simply run it again.

  steam_icons.py            add icons
  steam_icons.py --dry-run  only show what would happen
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
APPS = HOME / ".local/share/applications"
ICONS = HOME / ".local/share/icons/hicolor"
STEAM = HOME / ".local/share/Steam"
TARGET = 128  # from this size on an icon counts as sharp enough
SIZES = (128, 256)  # these sizes are added (if the source is big enough)
SKIP_EXE = re.compile(r"crash|unins|redist|setup|vc_?redist|dxsetup|ue4prereq|uerprereq|easyanticheat|"
                      r"battleye|be_service|helper|report|dotnet|directx|install|unrealfrontend|editor|"
                      r"shadercompile|unrealpak|unrealinsights|benchmark", re.I)

dry = "--dry-run" in sys.argv


def log(msg):
    print(msg, flush=True)


def library_dirs():
    vdf = STEAM / "steamapps/libraryfolders.vdf"
    dirs = []
    if vdf.exists():
        dirs = [Path(p) for p in re.findall(r'"path"\s+"([^"]+)"', vdf.read_text(errors="ignore"))]
    return dirs or [STEAM]


def install_dir(appid):
    for lib in library_dirs():
        acf = lib / f"steamapps/appmanifest_{appid}.acf"
        if acf.exists():
            m = re.search(r'"installdir"\s+"([^"]+)"', acf.read_text(errors="ignore"))
            if m:
                d = lib / "steamapps/common" / m.group(1)
                if d.is_dir():
                    return d
    return None


def existing_sizes(icon):
    sizes = []
    for d in ICONS.glob("*x*"):
        if (d / "apps" / f"{icon}.png").exists():
            try:
                sizes.append(int(d.name.split("x")[0]))
            except ValueError:
                pass
    return sizes


def steam_games():
    """(name, appid, icon name) from the Steam shortcuts."""
    for f in sorted(APPS.glob("*.desktop")):
        text = f.read_text(errors="ignore")
        m = re.search(r"steam://rungameid/(\d+)", text)
        icon = re.search(r"^Icon=(.+)$", text, re.M)
        name = re.search(r"^Name=(.+)$", text, re.M)
        # Only Steam's own icon names: some shortcuts simply use "steam" - that is the
        # icon of the Steam client itself and must not be overwritten
        if m and icon and icon.group(1).strip() == f"steam_icon_{m.group(1)}":
            yield (name.group(1) if name else f.stem), m.group(1), icon.group(1).strip()


def exe_icons(exe, tmp):
    """Biggest icon of an .exe as (edge length, PNG path) or None."""
    ico_dir = Path(tempfile.mkdtemp(dir=tmp))
    r = subprocess.run(["wrestool", "-x", "-t", "14", "-o", str(ico_dir), str(exe)],
                       capture_output=True)
    if r.returncode != 0:
        return None
    best = None
    for ico in ico_dir.glob("*.ico"):
        out = subprocess.run(["icotool", "-l", str(ico)], capture_output=True, text=True).stdout
        for line in out.splitlines():
            idx = re.search(r"--index=(\d+)", line)
            w = re.search(r"--width=(\d+)", line)
            h = re.search(r"--height=(\d+)", line)
            bd = re.search(r"--bit-depth=(\d+)", line)
            if not (idx and w and h) or w.group(1) != h.group(1):
                continue
            size = int(w.group(1)) or 256  # 0 = 256 in the ICO format
            depth = int(bd.group(1)) if bd else 0
            key = (size, depth)
            if best is None or key > best[0]:
                best = (key, ico, int(idx.group(1)))
    if best is None:
        return None
    (size, _), ico, index = best
    png_dir = Path(tempfile.mkdtemp(dir=tmp))
    subprocess.run(["icotool", "-x", f"--index={index}", "-o", str(png_dir), str(ico)], capture_output=True)
    pngs = list(png_dir.glob("*.png"))
    return (size, pngs[0]) if pngs else None


def name_score(exe, game, folder):
    """Prefer the main program: name similar to the game/folder, not nested too deep."""
    stem = re.sub(r"[^a-z0-9]", "", exe.stem.lower())
    want = {re.sub(r"[^a-z0-9]", "", s.lower()) for s in (game, folder.name)}
    s = 0
    if any(w and (w in stem or stem in w) for w in want if len(stem) > 2):
        s += 2
    if re.search(r"shipping|win64|launcher", exe.stem, re.I):
        s += 1
    s -= len(exe.relative_to(folder).parts) * 0.1
    return s


def difference(png, ref):
    """Image distance (0 = same, 1 = completely different): candidate scaled down to the reference size, both
    on a black background (so transparency counts too)."""
    size = subprocess.run(["magick", "identify", "-format", "%w", str(ref)],
                          capture_output=True, text=True).stdout.strip() or "32"
    r = subprocess.run(["magick", "(", str(png), "-background", "black", "-alpha", "remove", "-resize",
                        f"{size}x{size}!", ")", "(", str(ref), "-background", "black", "-alpha", "remove",
                        "-resize", f"{size}x{size}!", ")", "-metric", "RMSE", "-compare", "-format",
                        "%[distortion]", "info:"], capture_output=True, text=True)
    try:
        return float((r.stdout or r.stderr).split()[0].strip("()"))
    except (ValueError, IndexError):
        return 1.0


# From this distance on, the exe icon is a different image (engine logo, tool ...) than Steam's icon.
# Measured: right hits up to ~0.31 (Steam renders border/background differently), wrong ones from ~0.37
MAX_DIFF = 0.33


def png_icons(folder):
    """Native Linux games (e.g. Factorio) store their icon as a PNG: square *icon*.png from TARGET on."""
    for png in folder.rglob("*icon*.png"):
        if len(png.relative_to(folder).parts) > 5:
            continue
        dims = subprocess.run(["magick", "identify", "-format", "%w %h", str(png)],
                              capture_output=True, text=True).stdout.split()
        if len(dims) == 2 and dims[0] == dims[1] and int(dims[0]) >= TARGET:
            yield png, (int(dims[0]), png)


def best_icon(game, folder, ref, tmp):
    """Biggest exe/PNG icon that looks like Steam's (small) icon. Without a reference: by name/size."""
    exes = [p for p in folder.rglob("*.exe") if not SKIP_EXE.search(p.name)]
    exes.sort(key=lambda p: -name_score(p, game, folder))
    candidates = [(exe, exe_icons(exe, tmp)) for exe in exes[:40]]
    if ref:  # PNGs only with an image comparison, otherwise any UI icon could win
        candidates += list(png_icons(folder))
    best = None  # (key, png, source, distance, size)
    for exe, res in candidates:
        if not res or res[0] < TARGET:
            continue
        diff = difference(res[1], ref) if ref else 0.0
        if diff > MAX_DIFF:
            continue
        key = (-diff, res[0]) if ref else (res[0], 0)
        if best is None or key > best[0]:
            best = (key, res[1], exe, diff, res[0])
    if best:
        _, png, exe, diff, size = best
        return size, png, exe.relative_to(folder), diff
    return None


def main():
    if not shutil.which("wrestool"):
        sys.exit("icoutils fehlt: sudo pacman -S icoutils")
    changed = False
    with tempfile.TemporaryDirectory() as tmp:
        for game, appid, icon in steam_games():
            have = existing_sizes(icon)
            if have and max(have) >= TARGET:
                continue
            folder = install_dir(appid)
            if folder is None:
                log(f"-  {game}: not installed, skipped")
                continue
            ref = ICONS / f"{max(have)}x{max(have)}/apps/{icon}.png" if have else None
            found = best_icon(game, folder, ref, tmp)
            if found is None or found[0] <= max(have, default=0):
                log(f"-  {game}: no matching bigger icon found in the program files")
                continue
            size, png, exe, diff = found
            new = [s for s in SIZES if s <= size and s not in have]
            log(f"+  {game}: {size}px from {exe} (difference {diff:.2f}) -> "
                f"{', '.join(f'{s}px' for s in new) or 'nothing new'}")
            for s in new:
                dest = ICONS / f"{s}x{s}/apps/{icon}.png"
                if dry:
                    continue
                dest.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["magick", str(png), "-resize", f"{s}x{s}", str(dest)], check=True)
                changed = True
    if changed:
        # Qt/GTK read the index; without an update new sizes might be ignored
        subprocess.run(["gtk-update-icon-cache", "-f", "-t", str(ICONS)], capture_output=True)
        log("Icon-Cache aktualisiert")


if __name__ == "__main__":
    main()
