#!/usr/bin/env python3
"""Screenshot of the RAM-booted N9's framebuffer (what X shows, not DSS video planes) as PNG.
Usage: tests/camera/fbshot.py OUT.png   (from the sgx directory; uses build/s.sh)"""
import re, struct, subprocess, sys, zlib

geo = subprocess.run(['build/s.sh', 'cd /sys/class/graphics/fb0; cat stride pan modes'],
                     capture_output=True, text=True, check=True).stdout.split()
stride = int(geo[0])
xoff, yoff = map(int, geo[1].split(','))
w, h = 854, 480
for m in geo[2:]:
    r = re.match(r'U:(\d+)x(\d+)p', m)	# the progressive mode, not TV-out's
    if r:
        w, h = int(r[1]), int(r[2])
raw = subprocess.run(['build/s.sh', f'dd if=/dev/fb0 bs={stride} skip={yoff} count={h} 2>/dev/null'],
                     capture_output=True, check=True).stdout
assert len(raw) >= stride * h, f'short read: {len(raw)}'
rows = bytearray()
for y in range(h):
    rows.append(0)
    for x in range(xoff, xoff + w):
        p, = struct.unpack_from('<H', raw, y * stride + 2 * x)
        rows += bytes(((p >> 11) << 3, ((p >> 5) & 63) << 2, (p & 31) << 3))
chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) \
    + chunk(b'IDAT', zlib.compress(bytes(rows), 6)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
print(f'{sys.argv[1]}: {w}x{h} from y {yoff}')
