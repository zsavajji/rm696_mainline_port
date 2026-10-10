#!/usr/bin/env python3
# Dump a Nokia smiapp register-list firmware (struct smia_meta_reglist, 32-bit offsets, little endian)
import struct, sys
TYPES = {0: 'STANDBY', 1: 'POWERON', 2: 'RESUME', 3: 'STREAMON', 4: 'STREAMOFF', 5: 'DISABLED', 10: 'MODE'}
for path in sys.argv[1:]:
    d = open(path, 'rb').read()
    magic, = struct.unpack_from('<I', d, 0)
    ver = d[4:36].split(b'\0')[0].decode(errors='replace')
    offs, i = [], 36
    while struct.unpack_from('<I', d, i)[0]:
        offs.append(struct.unpack_from('<I', d, i)[0]); i += 4
    print(f'{path.split("/")[-1]}: magic {magic:#x} version "{ver}" lists {len(offs)}')
    for o in offs:
        typ, = struct.unpack_from('<I', d, o)
        m = struct.unpack_from('<12H3I2I3I', d, o + 4)
        sw, sh, sx, sy, sww, swh, w, h, wx, wy, ww, wh, pclk, opsys, ext, num, den, maxexp, fmt, sens = m
        nregs, p = 0, o + 4 + struct.calcsize('<12H3I2I3I')
        while struct.unpack_from('<H', d, p)[0] != 0xff: nregs += 1; p += 8
        f = struct.pack('<I', fmt).decode(errors='replace') if fmt else '-'
        print(f'  {TYPES.get(typ, typ):9} {ww}x{wh} of {w}x{h} (sensor win {sww}x{swh}) {f} {num}/{den}s '
              f'pclk {pclk/1e6:.2f} opsys {opsys/1e6:.2f} ext {ext/1e6:.1f} MHz maxexp {maxexp} sens {sens/65536:.2f} regs {nregs}')
