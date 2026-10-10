#!/usr/bin/env python3
# Scan ARM ELF files for ioctl numbers (literal words and movw/movt pairs) of type 'V' (V4L2) and '|' (media)
import sys, struct, re, subprocess, collections
TYPES = {0x56: 'V', 0x7c: '|'}
DIRS = {0: '_IO', 1: '_IOW', 2: '_IOR', 3: '_IOWR'}
def dec(v):
    d, size, t, nr = v >> 30, (v >> 16) & 0x3fff, (v >> 8) & 0xff, v & 0xff
    return t, nr, size, d
def ok(v):
    t, nr, size, d = dec(v)
    return t in TYPES and (d != 0 or size == 0) and size < 0x400 and not (d == 0 and nr == 0)
def scan(path):
    found = collections.Counter()
    data = open(path, 'rb').read()
    for i in range(0, len(data) - 3, 2):
        v = struct.unpack_from('<I', data, i)[0]
        if ok(v) and v >> 30 and i % 4 == 0:
            found[v] += 1
    # movw/movt pairs from llvm-objdump
    out = subprocess.run(['/opt/homebrew/opt/llvm/bin/llvm-objdump', '-d', '--no-show-raw-insn', path], capture_output=True, text=True).stdout
    lo = {}
    for line in out.splitlines():
        m = re.search(r'\bmovw\s+(r\d+|ip|lr), #(0x[0-9a-f]+|\d+)', line)
        if m: lo[m.group(1)] = int(m.group(2), 0); continue
        m = re.search(r'\bmovt\s+(r\d+|ip|lr), #(0x[0-9a-f]+|\d+)', line)
        if m and m.group(1) in lo:
            v = (int(m.group(2), 0) << 16) | lo[m.group(1)]
            if ok(v): found[v] += 1
    return found
for p in sys.argv[1:]:
    f = scan(p)
    print('==', p.split('/')[-1])
    for v in sorted(f, key=lambda v: (dec(v)[0], dec(v)[1])):
        t, nr, size, d = dec(v)
        print('  %s(%r, %3d, size %3d)  0x%08x  x%d' % (DIRS[d], TYPES[t], nr, size, v, f[v]))
