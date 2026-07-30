#!/usr/bin/env python3
"""Generate the optional "liquid swirl" background as a baked bitmap.

Domain-warped value-noise contours: dark (black) ground with thin, dim,
flowing light lines. Baked at build time because evaluating this much noise
live on the watch every redraw would blow the frame budget many times over;
a one-shot bitmap blit at redraw is cheap.

Kept deliberately dim and thin: on the FR165 AMOLED panel every lit pixel
costs power, so this trades a little battery for texture. It is off by default
and never drawn in night / always-on / battery-saver frames.

Standard library only (no PIL): writes an indexed PNG with a small grey ramp.
"""
import struct
import zlib
import math
import sys

W = 390
SCALE = 3.2        # noise cells across the image (fewer = bigger swirls)
OCTAVES = 4
NBANDS = 6.5       # how many contour bands across the noise range
EDGE = 0.075       # line half-thickness in band units (smaller = thinner)
WARP = 3.4         # domain-warp strength

# Grey ramp (index 0 = black ground). Neutral white-ish, kept dim on purpose:
# bright enough to read as "white lines", dark enough to spare the battery.
PALETTE = [(0, 0, 0), (34, 34, 36), (72, 72, 76), (120, 120, 124), (172, 172, 176)]


def _hash(ix, iy):
    n = (ix * 374761393 + iy * 668265263) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return (n & 0xFFFFFF) / float(0xFFFFFF)


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def _vnoise(x, y):
    ix = math.floor(x)
    iy = math.floor(y)
    fx = x - ix
    fy = y - iy
    tx = _smooth(fx)
    ty = _smooth(fy)
    a = _hash(ix, iy)
    b = _hash(ix + 1, iy)
    c = _hash(ix, iy + 1)
    d = _hash(ix + 1, iy + 1)
    top = a + (b - a) * tx
    bot = c + (d - c) * tx
    return top + (bot - top) * ty


def _fbm(x, y):
    v = 0.0
    amp = 0.5
    freq = 1.0
    for _ in range(OCTAVES):
        v += amp * _vnoise(x * freq, y * freq)
        amp *= 0.5
        freq *= 2.0
    return v


def _intensity(px, py):
    x = px / float(W) * SCALE
    y = py / float(W) * SCALE
    # Domain warp: displace the sample point by another noise field so the
    # bands bend and flow instead of running straight.
    wx = _fbm(x + 0.0, y + 0.0)
    wy = _fbm(x + 5.2, y + 1.3)
    q = _fbm(x + WARP * wx + 1.7, y + WARP * wy + 9.2)
    # Distance to the nearest band boundary -> a thin line there.
    f = (q * NBANDS) % 1.0
    dist = min(f, 1.0 - f)
    if dist >= EDGE:
        return 0.0
    return 1.0 - (dist / EDGE)


def build():
    rows = []
    for py in range(W):
        row = bytearray()
        for px in range(W):
            inten = _intensity(px, py)
            idx = int(round(inten * (len(PALETTE) - 1)))
            if idx < 0:
                idx = 0
            elif idx > len(PALETTE) - 1:
                idx = len(PALETTE) - 1
            row.append(idx)
        rows.append(row)
        if py % 40 == 0:
            print("  row", py, "/", W)
    return rows


def write_png(path, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)          # filter type 0
        raw += row

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    plte = bytearray()
    for (r, g, b) in PALETTE:
        plte += bytes((r, g, b))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", W, W, 8, 3, 0, 0, 0)   # 8-bit, colour type 3 (indexed)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"PLTE", bytes(plte)))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "resources/drawables/pattern.png"
    write_png(out, build())
    print("wrote", out)
