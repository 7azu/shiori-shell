#!/usr/bin/env python3
"""Creates the world map texture for the VPN globe (resources/globe/earth.png).

Only needs to run again if the map should look different - the result is in the repo.

    curl -LO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
    scripts/make-globe-map.py ne_50m_admin_0_countries.geojson

Equirectangular map, the channels mean (the shader pickers/shaders/globe.frag reads them like this):
    R = lines: coasts bright, borders darker
    G = lights on land (like cities at night: groups of a bright core and smaller dots)
    B = land area (mask)
Lines are widened by latitude (1/cos), so they are equally thick everywhere on the sphere.

Plus resources/globe/countries.png (grayscale, 4096x2048): value = number of the country (0 = sea), without
anti-aliasing, so the shader reads exact numbers with texelFetch; and countries.json
{ "nl": 17, ... } (ISO_A2_EH lower case -> number). With it the globe colors server countries, the selection and
the active connection as areas. A separate file instead of the alpha channel of earth.png: otherwise Qt
multiplies the colors with the alpha (premultiplied).
And countries-grid.json: the same numbers as a 1/4-degree grid (1440x720), every row run-length encoded
"number:count,...". With it the QML (VpnGlobe) knows which country is under the mouse (hover on countries).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

W, H = 4096, 2048
SS = 2  # supersampling for smooth edges
COAST_W = 2.3  # line width in pixels of the final texture
BORDER_W = 1.3
# Lights: this many groups ("cities"), per group one core and some dots around it
LIGHT_CLUSTERS = 2800
SEED = 7


def rings_of(geom):
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    for poly in polys:
        for ring in poly:
            yield ring


def to_px(lon, lat, w, h):
    return ((lon + 180.0) / 360.0 * w, (90.0 - lat) / 180.0 * h)


def hdilate(mask, radius_per_row):
    """Widen horizontally, per row with its own radius (makes up for the distortion at the poles)."""
    out = np.zeros_like(mask)
    for r in np.unique(radius_per_row):
        rows = np.nonzero(radius_per_row == r)[0]
        part = mask[rows].astype(np.int32)
        if r > 0:
            # Box filter by sum, wrapping around at the 180th meridian
            padded = np.concatenate([part[:, -r:], part, part[:, :r]], axis=1)
            csum = np.cumsum(padded, axis=1)
            csum = np.concatenate([np.zeros((len(rows), 1), np.int32), csum], axis=1)
            part = csum[:, 2 * r + 1:] - csum[:, :-(2 * r + 1)]
        out[rows] = part > 0
    return out


def vdilate(mask, r):
    out = mask.copy()
    for d in range(1, r + 1):
        out[d:] |= mask[:-d]
        out[:-d] |= mask[d:]
    return out


def main():
    src = Path(sys.argv[1])
    dst = Path(__file__).resolve().parent.parent / "resources" / "globe" / "earth.png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    feats = json.loads(src.read_text())["features"]
    # One number per country code (several parts like Indian Ocean Ter. -> AU share it); without a code its own
    codes = {}
    fid = []
    for f in feats:
        code = (f["properties"].get("ISO_A2_EH") or "-99").lower()
        if code == "-99":
            code = "_" + f["properties"].get("ADM0_A3", str(len(codes)))
        if code not in codes:
            codes[code] = len(codes) + 1
        fid.append(codes[code])
    assert len(codes) < 255
    w, h = W * SS, H * SS

    # Fill every country with its own number: where neighboring pixels differ there is a border
    # (against 0 = sea: coast). Saves intersecting the polygons.
    ids = Image.new("I", (w, h), 0)
    draw = ImageDraw.Draw(ids)
    for n, f in enumerate(feats, start=1):
        geom = f["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        for poly in polys:
            draw.polygon([to_px(x, y, w, h) for x, y in poly[0]], fill=n)
    a = np.asarray(ids)
    land = a > 0

    lat = (0.5 - (np.arange(h) + 0.5) / h) * math.pi
    stretch = 1.0 / np.maximum(np.cos(lat), 0.09)

    def edges(coast):
        dh = a != np.roll(a, -1, axis=1)
        dv = np.zeros_like(dh)
        dv[:-1] = a[:-1] != a[1:]
        sea_h = (a == 0) | (np.roll(a, -1, axis=1) == 0)
        sea_v = np.zeros_like(dh)
        sea_v[:-1] = (a[:-1] == 0) | (a[1:] == 0)
        if coast:
            return dh & sea_h, dv & sea_v
        return dh & ~sea_h, dv & ~sea_v

    def lines(coast, width):
        eh, ev = edges(coast)
        half = width * SS / 2.0
        rad = np.maximum(1, np.round(half * stretch)).astype(np.int32)
        out = hdilate(eh, rad)
        # Horizontal edges: vertically equally thick, horizontally only minimal (close gaps)
        out |= hdilate(vdilate(ev, max(1, round(half))), np.maximum(1, rad // 2))
        return out

    coast = lines(True, COAST_W)
    border = lines(False, BORDER_W)
    red = np.where(coast, 255, np.where(border, 120, 0)).astype(np.uint8)

    # Lights like cities at night: group centers spread evenly on the sphere (not on the map),
    # only on land; around every center a bright core and 2-10 smaller dots (suburbs).
    # Dots on the sea are dropped, so they do not pile up beyond coasts by themselves.
    rng = np.random.default_rng(SEED)
    lights = Image.new("L", (w, h), 0)
    ld = ImageDraw.Draw(lights)

    def dot(lo, la, r, value):
        x, y = to_px(lo, la, w, h)
        if not land[min(h - 1, max(0, int(y))), int(x) % w]:
            return
        rx = r / max(math.cos(math.radians(la)), 0.09)
        ld.ellipse([x - rx, y - r, x + rx, y + r], fill=value)

    n = 0
    while n < LIGHT_CLUSTERS:
        la = math.degrees(math.asin(rng.uniform(-1, 1)))
        lo = rng.uniform(-180, 180)
        if abs(la) > 78:
            continue
        x, y = to_px(lo, la, w, h)
        if not land[int(y), int(x) % w]:
            continue
        n += 1
        big = rng.random() < 0.15
        dot(lo, la, (1.8 if big else 1.25) * SS, 255 if big else 215)
        spread = 0.5 + rng.random() * (1.2 if big else 0.6)
        for _ in range(int(rng.integers(3, 14 if big else 7))):
            dlo = rng.normal(0, spread) / max(math.cos(math.radians(la)), 0.2)
            dla = rng.normal(0, spread)
            dot(lo + dlo, la + dla, 0.9 * SS, int(rng.integers(90, 190)))

    img = Image.merge("RGB", [
        Image.fromarray(red),
        lights,
        Image.fromarray((land * 255).astype(np.uint8)),
    ]).resize((W, H), Image.Resampling.LANCZOS)
    img.save(dst, optimize=True)
    print(f"wrote {dst} ({dst.stat().st_size // 1024} KiB)")

    # Country numbers: feature number -> code number, on 4096x2048 by nearest neighbor (no mixed values)
    lut = np.zeros(len(feats) + 1, np.uint8)
    for n, v in enumerate(fid, start=1):
        lut[n] = v
    step = (W * SS) // 4096
    cid = lut[a[step // 2::step, step // 2::step]]
    cdst = dst.parent / "countries.png"
    Image.fromarray(cid, "L").save(cdst, optimize=True)
    (dst.parent / "countries.json").write_text(json.dumps({k: v for k, v in sorted(codes.items()) if not k.startswith("_")}, indent=0) + "\n")
    print(f"wrote {cdst} ({cdst.stat().st_size // 1024} KiB), {len(codes)} countries")

    # Grid for the QML: 1440x720 (1/4 degree), rows run-length encoded
    # Hit the cell centers exactly (8192 does not divide evenly by 1440)
    xs = ((np.arange(1440) + 0.5) * w / 1440).astype(int)
    ys = ((np.arange(720) + 0.5) * h / 720).astype(int)
    grid = lut[a[np.ix_(ys, xs)]]
    rows = []
    for row in grid:
        runs = []
        start = 0
        for x in range(1, len(row) + 1):
            if x == len(row) or row[x] != row[start]:
                runs.append(f"{row[start]}:{x - start}")
                start = x
        rows.append(",".join(runs))
    gdst = dst.parent / "countries-grid.json"
    gdst.write_text(json.dumps({"w": int(grid.shape[1]), "h": int(grid.shape[0]), "rows": rows}, separators=(",", ":")) + "\n")
    print(f"wrote {gdst} ({gdst.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
