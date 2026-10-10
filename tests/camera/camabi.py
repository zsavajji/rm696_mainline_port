#!/usr/bin/env python3
"""Compare the camera ABI of Nokia's 2.6.32 headers (Harmattan's) with Linux 6.18's uapi, as an ARMv7
userspace build sees them: every constant both define (macros and enum values) and every struct's
layout (field offsets, sizes). Usage: camabi.py NOKIA_TREE MAINLINE_UAPI_ROOT"""
import os, re, subprocess, sys, tempfile

CLANG = ['clang', '--target=armv7a-linux-gnueabi', '-nostdinc', '-w', '-ferror-limit=0']
HEADERS = ['linux/videodev2.h', 'linux/v4l2-subdev.h', 'linux/v4l2-mediabus.h', 'linux/media.h',
           'linux/omap3isp.h']
STUB = {'sys/time.h': 'struct timeval { long tv_sec; long tv_usec; };\n'
                      'struct timespec { long tv_sec; long tv_nsec; };\n',
        'linux/compiler.h': '#define __user\n', 'linux/version.h':
        '#define KERNEL_VERSION(a,b,c) (((a) << 16) + ((b) << 8) + (c))\n'}


def side(incs, files, tmp, generic):
    stub = os.path.join(tmp, 'stub' + str(len(os.listdir(tmp))))
    for name, text in STUB.items():
        os.makedirs(os.path.dirname(os.path.join(stub, name)), exist_ok=True)
        open(os.path.join(stub, name), 'w').write(text)
    flags = CLANG + ['-I' + stub] + ['-I' + i for i in incs] + ['-I' + generic]
    head = ''.join(f'#include <{h}>\n' for h in HEADERS)
    text = ''.join(open(f, errors='replace').read() for f in files)
    names = sorted(set(re.findall(r'\b([A-Z][A-Z0-9_]{3,})\b', text)))
    structs = sorted(set(re.findall(r'\bstruct\s+(\w+)\s*\{', text)))
    # constants: drop the names that don't compile as integers, then read them from the assembly
    body = lambda ns: head + ''.join(f'long long c_{n} = (long long)({n});\n' for n in ns)
    for _ in range(3):
        r = subprocess.run(flags + ['-S', '-o', '-', '-x', 'c', '-'], input=body(names),
                           capture_output=True, text=True)
        bad = set(re.findall(r'<stdin>:(\d+):', r.stderr))
        if not bad:
            break
        first = head.count('\n')
        names = [n for k, n in enumerate(names) if str(first + k + 1) not in bad]
    consts = {}
    for m in re.finditer(r'^c_(\w+):\n((?:\s+\.(?:long|zero)\s+-?\d+.*\n)+)', r.stdout, re.M):
        words = [int(w[1]) if w[0] == '.long' else 0
                 for w in (l.split() for l in m[2].splitlines())]
        consts[m[1]] = (words[0] & 0xffffffff) | ((words[1] & 0xffffffff if len(words) > 1 else 0) << 32)
    # struct layouts
    src = head + ''.join(f'int s_{s} = sizeof(struct {s});\n' for s in structs)
    r = subprocess.run(flags + ['-fsyntax-only', '-Xclang', '-fdump-record-layouts', '-x', 'c', '-'],
                       input=src, capture_output=True, text=True)
    layouts = {}
    for blk in r.stdout.split('*** Dumping AST Record Layout')[1:]:
        lines = blk.strip().splitlines()
        m = re.match(r'\s*0 \| (?:struct|union) (\w+)', lines[0])
        if not m:
            continue
        fields = [re.sub(r'\s+', ' ', l.strip()) for l in lines[1:] if '|' in l]
        # offset and name of each field: unions gaining members or enums becoming __u32 don't count
        layouts[m[1]] = [(f.split(' | ')[0], f.split()[-1]) for f in fields if 'anonymous' not in f
                         and 'unnamed' not in f]
    return consts, layouts


def main(nokia, ml):
    with tempfile.TemporaryDirectory() as tmp:
        generic = os.path.join(tmp, 'generic')
        os.makedirs(generic)
        os.symlink(os.path.abspath(ml + '/include/uapi/asm-generic'), generic + '/asm')
        nk = side([nokia + '/include', nokia + '/arch/arm/include'],
                  [nokia + '/include/' + h for h in HEADERS], tmp, generic)
        mm = side([ml + '/include/uapi', ml + '/arch/arm/include/uapi'],
                  [ml + '/include/uapi/' + h for h in HEADERS] +
                  [ml + '/include/uapi/linux/' + h for h in ('v4l2-controls.h', 'media-bus-format.h')], tmp,
                  generic)
    (nc, nl), (mc, mlay) = nk, mm
    print(f'constants: Nokia {len(nc)}, 6.18 {len(mc)}, both {len(set(nc) & set(mc))}')
    for n in sorted(set(nc) & set(mc)):
        if nc[n] != mc[n]:
            print(f'  DIFFERENT {n}: Nokia {nc[n]:#x}, 6.18 {mc[n]:#x}')
    only = sorted(set(nc) - set(mc))
    print(f'Nokia only ({len(only)}):', ' '.join(f'{n}={nc[n]:#x}' for n in only))
    print(f'structs: Nokia {len(nl)}, 6.18 {len(mlay)}')
    for s in sorted(set(nl) & set(mlay)):
        missing = [f for f in nl[s] if f not in mlay[s]]
        if missing:
            print(f'  DIFFERENT struct {s}: Nokia fields not at the same offset in 6.18: {missing}')
    print('Nokia-only structs:', ' '.join(sorted(set(nl) - set(mlay))))


if __name__ == '__main__':
    main(*sys.argv[1:3])
