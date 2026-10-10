# dofsym.py DOF [--secs] NAME...: sections and symbols of a TI DSP/BIOS DOF image (/lib/dsp/*.dof)
import struct, sys
d = open(sys.argv[1], 'rb').read()
(strsz, entry, resh, scnnamesz, nsyms, maxstr, nscns, tscns, ver, tid, flags, esec, ck) = struct.unpack_from('<IIII HHHHHHHh I', d, 0)
off = 36 + 20
strtab = d[off:off + ((strsz + 3) & ~3)]
off += (strsz + 3) & ~3
secs = []
for i in range(nscns):
    so, pa, va, sz, page, fl, fpo, nip = struct.unpack_from('<iiiiHHIi', d, off + i * 28)
    name = strtab[so:strtab.index(b'\0', so)].decode()
    secs.append((name, pa, va, sz, fl))
off += nscns * 28
def nm(o): return strtab[o:strtab.index(b'\0', o)].decode(errors='replace')
want = sys.argv[2:]
print('entry %#x nsyms %d nscns %d' % (entry, nsyms, nscns))
if '--secs' in want:
    for s in secs: print('%-40s run %#010x load %#010x size %#x flags %#x' % s)
for i in range(nsyms):
    o, val, scn, scl = struct.unpack_from('<iihh', d, off + i * 12)
    n = nm(o) if 0 <= o < len(strtab) else '?'
    if any(w in n for w in want if not w.startswith('--')):
        print('%-40s val %#010x scn %d class %d' % (n, val & 0xffffffff, scn, scl))
