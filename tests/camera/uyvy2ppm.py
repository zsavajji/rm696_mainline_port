#!/usr/bin/env python3
"""UYVY frame (ispcap's ISPCAP_SAVE) to a PPM image. Usage: uyvy2ppm.py IN.yuv WIDTH HEIGHT OUT.ppm"""
import sys

src, w, h, dst = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
d = open(src, 'rb').read()
out = bytearray()
clip = lambda v: 0 if v < 0 else 255 if v > 255 else int(v)
for i in range(0, w * h * 2, 4):
    u, y0, v, y1 = d[i] - 128, d[i + 1] - 16, d[i + 2] - 128, d[i + 3] - 16
    for y in (y0, y1):
        out += bytes((clip(1.164 * y + 1.596 * v), clip(1.164 * y - 0.392 * u - 0.813 * v),
                      clip(1.164 * y + 2.017 * u)))
open(dst, 'wb').write(b'P6 %d %d 255\n' % (w, h) + bytes(out))
