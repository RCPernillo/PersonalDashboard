#!/usr/bin/env python3
"""Generate the launcher icon PNG without any image libraries.

The launcher is a small, self-contained mark: four accent-orange spheres on a
black disc, echoing the face itself. Kept in code so the icon can be regenerated
at any size and never drifts from the on-watch look. Standard library only.
"""
import struct
import zlib
import sys
import math

SIZE = 64
BG = (0, 0, 0)
ORANGE = (0xFF, 0x66, 0x00)
DIMORANGE = (0x55, 0x22, 0x00)
WHITE = (0xFF, 0xFF, 0xFF)


def blank(size, color):
    return [[list(color) for _ in range(size)] for _ in range(size)]


def disc(px, cx, cy, r, color):
    for y in range(len(px)):
        for x in range(len(px)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                px[y][x] = list(color)


def ring(px, cx, cy, r, w, color):
    for y in range(len(px)):
        for x in range(len(px)):
            d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            if r - w <= d <= r:
                px[y][x] = list(color)


def build():
    px = blank(SIZE, BG)
    c = SIZE / 2.0
    # outer progress ring
    ring(px, c, c, SIZE * 0.46, 3, ORANGE)
    ring(px, c, c, SIZE * 0.46 - 3, 1, DIMORANGE)
    # four spheres
    offs = SIZE * 0.20
    r = SIZE * 0.10
    for (dx, dy) in [(-offs, offs), (-offs / 3, offs), (offs / 3, offs), (offs, offs)]:
        ring(px, c + dx, c + dy, r, 2, ORANGE)
    # centre time bar hint
    disc(px, c, c - SIZE * 0.10, 2, WHITE)
    return px


def write_png(path, px):
    size = len(px)
    raw = bytearray()
    for row in px:
        raw.append(0)  # filter type 0
        for (r, g, b) in row:
            raw += bytes((r, g, b))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return c + struct.pack(">I", crc)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "resources/drawables/launcher.png"
    write_png(out, build())
    print("wrote", out)
