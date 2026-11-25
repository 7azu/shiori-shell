#!/usr/bin/env python3
"""Pixel-art text cursor (I-beam with cat ears) matching the Bongo Cat cursor pack.

Writes a Windows .ani file, so it goes through the same conversion + pywal tinting as the cat
(gen-cursor.sh -> hypr/scripts/ani2xcursor.py). Colors are taken from the cat: its bluish shading
gets recolored to the wal accent, the pink ear insides stay pink.

Usage: text-cursor.py <out.ani> [--preview out.png]
"""
import io
import struct
import sys

from PIL import Image

PALETTE = {
    "o": (22, 23, 26, 255),     # outline (same dark as the cat)
    "w": (255, 255, 255, 255),  # white fur
    "b": (186, 216, 247, 255),  # light shading -> tinted
    "B": (118, 153, 201, 255),  # darker shading -> tinted
    "p": (246, 138, 152, 255),  # pink (ear insides, like the paw pads)
}
SIZE = 32          # drawn 1:1 at 32 px, the size the cat is used at
HOTSPOT = (15, 19)  # middle of the I-beam (stem x 15/16, bars y 10..29)

# 22 px wide, drawn at x = 5..26 (stem = x 15/16), y = 2..29. Big ears on purpose: on the
# small cursor they are what makes it read as a cat.
EARS_UP = [  # pointy cat ears with a pink inside, flat head line in between
    ".....o..........o.....",
    "....opo........opo....",
    "....opo........opo....",
    "...opppo......opppo...",
    "...opppo......opppo...",
    "..opppppo....opppppo..",
    "..opppppo....opppppo..",
    ".owpppppwo..owpppppwo.",
]
EARS_TWITCH = [  # right ear tip leans outwards for a moment
    ".....o...........o....",
    "....opo.........opo...",
    "....opo.........opo...",
    "...opppo......opppo...",
    "...opppo......opppo...",
    "..opppppo....opppppo..",
    "..opppppo....opppppo..",
    ".owpppppwo..owpppppwo.",
]
BODY = [  # bars at x 1..20, symmetric around the stem (x 10/11)
    ".owwwwwwwwoowwwwwwwwo.",
    ".owwwwowwwwwwwwowwwBo.",  # eyes: the top bar is the cat's head
    ".obbbbbbbbbbbbbbbbbBo.",
    ".ooooooooowbooooooooo.",
    *[".........owbo........."] * 12,
    ".ooooooooowbooooooooo.",
    ".owwwwwwwwwwwwwwwwwBo.",
    ".obbbbbbbbbbbbbbbbbBo.",
    ".oooooooooooooooooooo.",
]


def frame(ears):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for y, row in enumerate(ears + BODY):
        assert len(row) == 22, (y, row)
        for x, c in enumerate(row):
            if c != ".":
                img.putpixel((5 + x, 2 + y), PALETTE[c])
    return img


def cur_bytes(images):
    """Windows .cur with PNG payloads; images: list of (PIL image, hotspot_x, hotspot_y)."""
    pngs = []
    for img, _, _ in images:
        buf = io.BytesIO()
        img.save(buf, "PNG")
        pngs.append(buf.getvalue())
    out = struct.pack("<HHH", 0, 2, len(images))
    off = 6 + 16 * len(images)
    for (img, hx, hy), png in zip(images, pngs):
        w, h = img.size
        out += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, hx, hy, len(png), off)
        off += len(png)
    return out + b"".join(pngs)


def chunk(cid, data):
    return cid + struct.pack("<I", len(data)) + data + (b"\0" if len(data) % 2 else b"")


def ani_bytes(frames):
    """frames: list of (PIL image at SIZE, delay_ms); every frame also gets 2x and 4x versions."""
    icons = b""
    for img, _ in frames:
        sizes = [(img.resize((SIZE * k, SIZE * k), Image.Resampling.NEAREST), HOTSPOT[0] * k, HOTSPOT[1] * k) for k in (1, 2, 4)]
        icons += chunk(b"icon", cur_bytes(sizes))
    n = len(frames)
    anih = struct.pack("<9I", 36, n, n, 0, 0, 0, 0, 10, 1)  # flags 1 = frames are icons/cursors
    rate = struct.pack(f"<{n}I", *(max(1, round(d * 60 / 1000)) for _, d in frames))  # jiffies (1/60 s)
    body = b"ACON" + chunk(b"anih", anih) + chunk(b"rate", rate) + chunk(b"LIST", b"fram" + icons)
    return b"RIFF" + struct.pack("<I", len(body)) + body


def main():
    frames = [(frame(EARS_UP), 3200), (frame(EARS_TWITCH), 160)]
    with open(sys.argv[1], "wb") as f:
        f.write(ani_bytes(frames))
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        sheet = Image.new("RGBA", (SIZE * 8 * 2 + 30, SIZE * 8 + 20), (40, 40, 52, 255))
        for i, (img, _) in enumerate(frames):
            sheet.alpha_composite(img.resize((SIZE * 8, SIZE * 8), Image.Resampling.NEAREST), (10 + i * (SIZE * 8 + 10), 10))
        sheet.save(out)


if __name__ == "__main__":
    main()
