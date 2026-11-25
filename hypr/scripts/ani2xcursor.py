#!/usr/bin/env python3
"""Convert Windows cursors (.cur / .ani) into an Xcursor theme.

Usage: ani2xcursor.py [--tint COLOR] <theme-dir> NAME=FILE [NAME=FILE ...]
       e.g. default=cursor.ani pointer=hand.cur text=text.ani
NAME is the Xcursor shape (default, pointer, text, ...); known shapes also get their alias names.

--tint "#rrggbb": recolor the bluish shading (hue 180-250 deg, not grey) to the hue of COLOR,
keeping lightness and pixel structure; white, outlines and other colors stay untouched.
--tint-mode grey: recolor the greys instead (for grey/black packs like Kuro Kitty), see tint().
Used by ~/.config/wal/cursor/gen-cursor.sh to follow the pywal colors.
"""
import argparse
import colorsys
import io
import os
import pathlib
import struct

import numpy as np
from PIL import Image

XCURSOR_IMAGE = 0xFFFD0002


def parse_cur(data):
    """Return list of (size, xhot, yhot, RGBA image) from .cur/.ico bytes."""
    _, kind, count = struct.unpack("<HHH", data[:6])
    out = []
    for i in range(count):
        w, h, _, _, hx, hy, size, off = struct.unpack("<BBBBHHII", data[6 + 16 * i: 22 + 16 * i])
        w, h = w or 256, h or 256
        blob = data[off: off + size]
        if blob[:8] == b"\x89PNG\r\n\x1a\n":
            img = Image.open(io.BytesIO(blob)).convert("RGBA")
        else:
            # BMP without file header: wrap it as a single-image .ico so Pillow decodes the AND mask too
            ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, size, 22) + blob
            img = Image.open(io.BytesIO(ico)).convert("RGBA")
        out.append((w, hx if kind == 2 else 0, hy if kind == 2 else 0, img))
    return out


def chunks(b, pos, end):
    while pos + 8 <= end:
        cid, size = b[pos:pos + 4], struct.unpack("<I", b[pos + 4:pos + 8])[0]
        yield cid, pos + 8, size
        pos += 8 + size + (size & 1)


def parse_ani(data):
    """Return list of frames: (delay_ms, [(size, xhot, yhot, img), ...])."""
    assert data[:4] == b"RIFF" and data[8:12] == b"ACON", "not an .ani file"
    icons, rate, seq, default_rate = [], None, None, 10
    for cid, p, s in chunks(data, 12, len(data)):
        if cid == b"anih":
            default_rate = struct.unpack("<9I", data[p:p + 36])[7]
        elif cid == b"rate":
            rate = struct.unpack(f"<{s // 4}I", data[p:p + s])
        elif cid == b"seq ":
            seq = struct.unpack(f"<{s // 4}I", data[p:p + s])
        elif cid == b"LIST" and data[p:p + 4] == b"fram":
            icons = [parse_cur(data[q:q + n]) for c, q, n in chunks(data, p + 4, p + s) if c == b"icon"]
    order = seq or range(len(icons))
    frames = []
    for i, idx in enumerate(order):
        jiffies = rate[i] if rate else default_rate  # 1 jiffy = 1/60 s
        frames.append((round(jiffies * 1000 / 60), icons[idx]))
    return frames


def load(path):
    data = path.read_bytes()
    return parse_ani(data) if data[:4] == b"RIFF" else [(0, parse_cur(data))]


GREY_REF = 0.35  # lightness of the main fur grey in grey-mode packs (Kuro Kitty: #595959)
# grey mode works in OKLab (perceptual): fur chroma = accent chroma * CHROMA_GAIN, at most `chroma`
# (gen-cursor.conf "chroma=", default CHROMA_MAX). Calibrated on a beige palette (#e3cdb6 -> fur C 0.044);
# with HLS saturation, blue/pink/purple accents came out far more colorful than beige at equal values.
CHROMA_MAX = 0.045
CHROMA_GAIN = 1.1


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    c = min(1.0, max(0.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def to_oklab(r, g, b):
    """sRGB 0..1 -> OKLab (L, a, b)"""
    r, g, b = _lin(r), _lin(g), _lin(b)
    l_ = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m_ = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


def from_oklab(L, a, b):
    """OKLab -> sRGB 0..1 (clipped)"""
    l_ = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (_gam(4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_),
            _gam(-1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_),
            _gam(-0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_))


class TintParams:
    """Everything the recoloring derives from the target color, computed once per color."""

    def __init__(self, color, saturation=1.0, chroma=CHROMA_MAX):
        tr, tg, tb = (int(color.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
        self.th, tl, ts = colorsys.rgb_to_hls(tr, tg, tb)
        # saturation: extra factor for the recolored pixels (gen-cursor.conf "saturation=", 1 = as computed)
        self.k = max(0.4, min(1.0, ts / 0.5)) * saturation  # pale wal palettes -> softer accents
        self.lscale = max(0.35, min(0.65, tl)) / GREY_REF
        # grey mode: accent hue in OKLab, chroma capped (see CHROMA_MAX)
        _, oa, ob = to_oklab(tr, tg, tb)
        c = (oa * oa + ob * ob) ** 0.5
        self.chroma = min(chroma, c * CHROMA_GAIN) * saturation
        self.da, self.db = (oa / c * self.chroma, ob / c * self.chroma) if c > 1e-6 else (0.0, 0.0)
        self.glyph_fill = self.grey_tint(GREY_REF * self.lscale)

    def grey_tint(self, light):
        """Grey of HLS lightness `light`, tinted towards the accent hue with the capped chroma."""
        L, _, _ = to_oklab(light, light, light)
        return tuple(round(v * 255) for v in from_oklab(L, self.da, self.db))


def tint_pixel(r, g, b, mode, p):
    """New (r, g, b) for one pixel, or None to keep it.

    blue: shift bluish pixels to the hue of the color; their saturation follows how colorful it is.
    grey: colorize grey pixels (not black outlines, not white) with the color's hue at a capped chroma
          (OKLab, see CHROMA_MAX); lightness is scaled so the main fur grey (GREY_REF) lands at the
          color's lightness (clamped to 0.35..0.65 so the cat stays readable), keeping the shading steps.
    """
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if mode == "blue" and s >= 0.15 and 180 <= h * 360 <= 250:
        rgb = colorsys.hls_to_rgb(p.th, l, s * p.k)
    elif mode == "grey" and s < 0.15 and 0.05 < l < 0.9:
        return p.grey_tint(min(0.9, l * p.lscale))
    else:
        return None
    return tuple(round(v * 255) for v in rgb)


class Tinter:
    """One image prepared for recoloring. render(color) is cheap (numpy, a few distinct colors), so the
    live fade (~/.config/wal/cursor/cursor-fade.py) can call it for every step of a wallpaper switch.

    Images without grey fur in grey mode (plain black arrows, I-beam, ...) are glyphs: their opaque dark
    pixels get the accent as fill and a 1 px black outline (drawn once here), so a light accent stays
    visible on light backgrounds. Faint pixels (soft shadows, alpha < 128) stay as they are.
    """

    def __init__(self, img, mode="blue"):
        self.mode = mode
        a = np.array(img, dtype=np.uint8)
        h, w = a.shape[:2]
        self.colors, index = np.unique(a.reshape(-1, 4), axis=0, return_inverse=True)
        self.index = index.reshape(-1)
        hls = [colorsys.rgb_to_hls(r / 255, g / 255, b / 255) for r, g, b, _ in self.colors.tolist()]
        opaque = self.colors[:, 3] >= 128
        fur = any(o and s < 0.15 and 0.3 < l < 0.9 for o, (_, l, s) in zip(opaque, hls))
        self.glyph = mode == "grey" and not fur
        if self.glyph:
            solid_c = np.array([o and l < 0.9 for o, (_, l, _) in zip(opaque, hls)], dtype=bool)
            self.solid = solid_c[self.index].reshape(h, w)
            pad = np.pad(self.solid, 1)
            near = np.zeros_like(self.solid)
            for dy in range(3):
                for dx in range(3):
                    near |= pad[dy:dy + h, dx:dx + w]
            a[near & ~self.solid & (a[..., 3] < 128)] = (0, 0, 0, 255)
        self.base = a

    def render(self, color):
        """RGBA array (h, w, 4) recolored towards color ("#rrggbb" or TintParams)."""
        p = TintParams(color) if isinstance(color, str) else color
        if self.glyph:
            out = self.base.copy()
            out[self.solid, :3] = p.glyph_fill
            return out
        lut = self.colors.copy()
        for i, (r, g, b, alpha) in enumerate(self.colors.tolist()):
            if alpha:
                new = tint_pixel(r, g, b, self.mode, p)
                if new:
                    lut[i, :3] = new
        return lut[self.index].reshape(self.base.shape)


def tint(img, color, mode="blue"):
    """Recolor img (PIL RGBA) towards color, see Tinter / tint_pixel."""
    return Image.fromarray(Tinter(img, mode).render(color), "RGBA")


def add_size(frames, size):
    """Add a downscaled copy (Pillow BOX filter) of each frame's largest image at `size` px, e.g. 28 for
    a 32 px pack: smaller cursor without Hyprland scaling it on the fly. Hotspot scaled along."""
    if not size:
        return frames
    out = []
    for delay, imgs in frames:
        s, hx, hy, img = max(imgs, key=lambda i: i[0])
        if size >= s or any(i[0] == size for i in imgs):
            out.append((delay, imgs))
            continue
        im = img if isinstance(img, Image.Image) else Image.fromarray(img, "RGBA")
        f = size / s
        small = im.resize((round(im.width * f), round(im.height * f)), Image.BOX)
        out.append((delay, imgs + [(size, min(round(hx * f), small.width - 1), min(round(hy * f), small.height - 1),
                                    small)]))
    return out


def xcursor_pixels(img):
    """Xcursor pixel data: premultiplied ARGB, little-endian 32 bit."""
    a = np.asarray(img, dtype=np.uint32)
    al = a[..., 3]
    px = (al << 24) | (a[..., 0] * al // 255 << 16) | (a[..., 1] * al // 255 << 8) | (a[..., 2] * al // 255)
    return px.astype("<u4").tobytes()


def write_xcursor(path, frames):
    """frames: [(delay_ms, [(size, xhot, yhot, image), ...]), ...]; image = PIL RGBA or (h, w, 4) array."""
    images = [(size, hx, hy, delay or 50, img) for delay, imgs in frames for size, hx, hy, img in imgs]
    images.sort(key=lambda i: i[0])  # group by size, frames keep their order (stable sort)
    header = struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(images))
    toc, body = [], []
    pos = 16 + 12 * len(images)
    for size, hx, hy, delay, img in images:
        h, w = np.asarray(img).shape[:2]
        chunk = struct.pack("<9I", 36, XCURSOR_IMAGE, size, 1, w, h, hx, hy, delay) + xcursor_pixels(img)
        toc.append(struct.pack("<III", XCURSOR_IMAGE, size, pos))
        body.append(chunk)
        pos += len(chunk)
    # write atomically: running apps may read the file at any moment
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_bytes(header + b"".join(toc) + b"".join(body))
    os.replace(tmp, path)
    return images


ALIASES = {
    "default": ["left_ptr", "arrow", "top_left_arrow", "context-menu", "copy", "alias", "dnd-copy", "dnd-link",
                "center_ptr", "right_ptr", "draft"],
    "pointer": ["hand1", "hand2", "pointing_hand", "hand", "9d800788f1b08800ae810202380a0822",
                "e29285e634086352946a0e7090d73106"],
    "text": ["xterm", "ibeam", "vertical-text"],
    "help": ["question_arrow", "whats_this", "left_ptr_help", "5c6cd98b3f3ebcb1f9c7f1c204630408",
             "d9ce0ab605698f320427677b458ad60b"],
    "progress": ["left_ptr_watch", "half-busy", "00000000000000020006000e7e9ffc3f",
                 "08e8e1c95fe2fc01f976f1e063a24ccd", "3ecb610c1bf2410f44200f48c40d3599"],
    "wait": ["watch"],
    "crosshair": ["cross", "tcross", "cross_reverse", "diamond_cross"],
    "pencil": [],
    "not-allowed": ["no-drop", "forbidden", "circle", "crossed_circle", "03b6e0fcb3499374a867c041f52298f0"],
    "ns-resize": ["size_ver", "sb_v_double_arrow", "v_double_arrow", "n-resize", "s-resize", "row-resize",
                  "top_side", "bottom_side", "00008160000006810000408080010102",
                  "2870a09082c103050810ffdffffe0204"],
    "ew-resize": ["size_hor", "sb_h_double_arrow", "h_double_arrow", "e-resize", "w-resize", "col-resize",
                  "left_side", "right_side", "028006030e0e7ebffc7f7070c0600140",
                  "14fef782d02440884392942c11205230"],
    "nwse-resize": ["size_fdiag", "bd_double_arrow", "nw-resize", "se-resize", "top_left_corner",
                    "bottom_right_corner", "c7088f0f3e6c8088236ef8e1e3e70000"],
    "nesw-resize": ["size_bdiag", "fd_double_arrow", "ne-resize", "sw-resize", "top_right_corner",
                    "bottom_left_corner", "fcf1c3c7cd4491d801f1e1c78f100000"],
    "move": ["all-scroll", "fleur", "size_all", "4498f0e0c1937ffe01fd06f973665830",
             "9081237383d90e509aa00f00170e968f"],
    "up-arrow": ["sb_up_arrow", "up_arrow"],
}


def link_aliases(cdir, name):
    """Point the legacy/alias names of shape `name` at its file."""
    for a in ALIASES.get(name, []):
        link = cdir / a
        if link.is_symlink() and os.readlink(link) == name:
            continue
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(name)


def main():
    ap = argparse.ArgumentParser(description="Convert Windows cursors (.cur/.ani) into an Xcursor theme")
    ap.add_argument("--tint", metavar="COLOR", help='recolor the bluish shading, e.g. "#e29869"')
    ap.add_argument("--tint-mode", choices=["blue", "grey"], default="blue",
                    help="which pixels --tint recolors: bluish shading (Bongo Cat) or greys (Kuro Kitty)")
    ap.add_argument("--saturation", type=float, default=1.0, help="factor for the tint saturation (0.5 = paler)")
    ap.add_argument("--chroma", type=float, default=CHROMA_MAX,
                    help=f"grey mode: max. color strength (OKLab chroma, default {CHROMA_MAX}; higher = more colorful)")
    ap.add_argument("--size", type=int, default=0, help="also write a downscaled size, e.g. 28 for a 32 px pack")
    ap.add_argument("theme", type=pathlib.Path)
    ap.add_argument("cursors", nargs="+", metavar="NAME=FILE")
    args = ap.parse_args()
    cdir = args.theme / "cursors"
    cdir.mkdir(parents=True, exist_ok=True)
    for spec in args.cursors:
        name, _, src = spec.partition("=")
        if not src:
            ap.error(f"expected NAME=FILE, got {spec!r}")
        frames = load(pathlib.Path(src))
        if args.tint:
            params = TintParams(args.tint, args.saturation, args.chroma)
            frames = [(d, [(s, x, y, Image.fromarray(Tinter(img, args.tint_mode).render(params), "RGBA"))
                           for s, x, y, img in imgs]) for d, imgs in frames]
        imgs = write_xcursor(cdir / name, add_size(frames, args.size))
        print(name, sorted({(s, x, y) for s, x, y, _, _ in imgs}), "frames:", len(imgs) // len({i[0] for i in imgs}))
        link_aliases(cdir, name)
    # keep an existing index.theme (its Comment names the pack); only create a minimal one
    index = args.theme / "index.theme"
    if not index.exists():
        index.write_text(f"[Icon Theme]\nName={args.theme.name}\nInherits=Adwaita\n")


if __name__ == "__main__":
    main()
