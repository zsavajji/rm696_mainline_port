# dofimg.py DOF OUT.bin OUT.sym: the DOF's loadable sections at 0x20000000.. as one flat image + "addr name" symbols
import struct, sys
d = open(sys.argv[1], 'rb').read()
(strsz, entry, resh, scnnamesz, nsyms, maxstr, nscns, tscns, ver, tid, flags, esec, ck) = struct.unpack_from('<IIII HHHHHHHh I', d, 0)
off = 36 + 20
strtab = d[off:off + ((strsz + 3) & ~3)]
off += (strsz + 3) & ~3
def nm(o): return strtab[o:strtab.index(b'\0', o)].decode(errors='replace')
base, img = 0x20200000, bytearray(0x300000)
for i in range(nscns):
    so, pa, va, sz, page, fl, fpo, nip = struct.unpack_from('<iiiiHHIi', d, off + i * 28)
    name = nm(so)
    if va >= base and va + sz <= base + len(img) and fpo and sz and (fl & 0x20):
        # image packets: num_relocs, size, checksum, data (padded to 4), 12-byte relocations
        a, q, nrel_all = va - base, fpo, 0
        for _ in range(nip):
            nrel, psz, ck = struct.unpack_from('<iiI', d, q)
            img[a:a + psz] = d[q + 12:q + 12 + psz]
            a += psz
            q += 12 + ((psz + 3) & ~3) + nrel * 12
            nrel_all += nrel
        print('%-28s %#010x %#x packets %d relocs %d filled %#x' % (name, va, sz, nip, nrel_all, a - (va - base)), file=sys.stderr)
off += nscns * 28
open(sys.argv[2], 'wb').write(img)
with open(sys.argv[3], 'w') as f:
    for i in range(nsyms):
        o, val, scn, scl = struct.unpack_from('<iihh', d, off + i * 12)
        if scn > 0 and 0 <= o < len(strtab):
            f.write('%08x %s\n' % (val & 0xffffffff, nm(o)))
