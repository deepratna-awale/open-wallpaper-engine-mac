"""Writes bars.png: a 512x256 RGBA image, transparent, with a red bar (x 40-219) and a blue bar (x 292-471),
both y 98-157, and a 4 px black tick at each bar's outer end so a turn reads. Plain Python 3 (zlib only).

    python make_bars.py            # bars.png next to this script
"""
import os, struct, zlib

W, H = 512, 256


def pixel(x, y):
    if 98 <= y < 158:
        if 40 <= x < 220:
            return (0, 0, 0, 255) if x < 44 else (220, 30, 30, 255)
        if 292 <= x < 472:
            return (0, 0, 0, 255) if x >= 468 else (30, 60, 220, 255)
    return (0, 0, 0, 0)


def png(path):
    raw = b''.join(b'\0' + bytes(c for x in range(W) for c in pixel(x, y)) for y in range(H))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 6, 0, 0, 0)) + \
        chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(path, 'wb').write(data)


if __name__ == '__main__':
    png(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bars.png'))
