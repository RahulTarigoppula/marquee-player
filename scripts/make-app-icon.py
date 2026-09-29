#!/usr/bin/env python3
"""Draws the Marquee app icon (a lit bulb on the crimson-trimmed marquee box) with no image
library, and writes windows/runner/resources/app_icon.ico (PNG-in-ICO: 16, 32, 48, 256)."""
import struct, zlib, pathlib

BG, BOX, INK = (0x07, 0x06, 0x0A), (0x12, 0x0E, 0x15), (0xF3, 0xE9, 0xDA)
CRIMSON, TUNGSTEN = (0xA3, 0x25, 0x2F), (0xFF, 0xC5, 0x6E)

def shade(u, v):
    """Colour and alpha at unit coords (u, v) in [0,1)."""
    r = 0.18  # rounded-square corner radius
    cu, cv = min(max(u, r), 1 - r), min(max(v, r), 1 - r)
    if (u - cu) ** 2 + (v - cv) ** 2 > r * r:
        return (0, 0, 0, 0)
    col = BG
    if 0.14 < u < 0.86 and 0.24 < v < 0.72:
        col = BOX
        # "M" as three bars and two diagonals
        x = (u - 0.30) / 0.40; y = (v - 0.33) / 0.30
        if 0 <= x <= 1 and 0 <= y <= 1:
            if x < 0.18 or x > 0.82 or (abs(x - 0.5 * y) < 0.08 and y < 0.62) or (abs((1 - x) - 0.5 * y) < 0.08 and y < 0.62):
                col = INK
    if 0.14 < u < 0.86 and 0.72 <= v < 0.745:
        col = CRIMSON  # the 1 px trim, scaled
    d = ((u - 0.5) ** 2 + (v - 0.84) ** 2) ** 0.5
    if d < 0.055:
        col = TUNGSTEN
    elif d < 0.12:
        a = (0.12 - d) / 0.065 * 0.45
        col = tuple(int(c * (1 - a) + t * a) for c, t in zip(col, TUNGSTEN))
    return (*col, 255)

def png(size):
    ss = 4
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            acc = [0, 0, 0, 0]
            for sy in range(ss):
                for sx in range(ss):
                    c = shade((x + (sx + 0.5) / ss) / size, (y + (sy + 0.5) / ss) / size)
                    for i in range(4):
                        acc[i] += c[i]
            a = acc[3] / (ss * ss)
            rgb = [int(acc[i] / max(1, acc[3] / 255)) if acc[3] else 0 for i in range(3)]
            row += bytes([min(255, v) for v in rgb] + [int(a)])
        rows.append(bytes(row))
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b''))

sizes = [16, 32, 48, 256]
images = [png(s) for s in sizes]
header = struct.pack('<HHH', 0, 1, len(sizes))
offset = 6 + 16 * len(sizes)
entries = b''
for s, img in zip(sizes, images):
    entries += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(img), offset)
    offset += len(img)
out = pathlib.Path(__file__).resolve().parent.parent / 'windows/runner/resources/app_icon.ico'
out.write_bytes(header + entries + b''.join(images))
print(f'wrote {out} ({out.stat().st_size} bytes)')
