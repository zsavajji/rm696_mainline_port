#!/usr/bin/env python3
"""kprobe-time.py TRACE N [COMM]: per probed function (from tests/kprobe-time.sh), calls and inclusive
wall time per unit of N (spawns, loops), for tasks named COMM if given (else all)."""
import re, sys
from collections import defaultdict

ev = re.compile(r'^\s*(.+?)-(\d+)\s+\[\d+\]\s+\S+\s+([\d.]+): (\w+): ')
n = int(sys.argv[2]); comm = sys.argv[3] if len(sys.argv) > 3 else None
st = defaultdict(list); acc = defaultdict(lambda: [0, 0.0])
for l in open(sys.argv[1]):
    m = ev.match(l)
    if not m or (comm and m.group(1).strip() != comm):
        continue
    pid, ts, name = int(m.group(2)), float(m.group(3)), m.group(4)
    if name.endswith('_r'):
        f = name[:-2]
        if st[(pid, f)]:
            t0 = st[(pid, f)].pop(); acc[f][0] += 1; acc[f][1] += ts - t0
    else:
        st[(pid, name)].append(ts)
for f, (k, t) in sorted(acc.items(), key=lambda x: -x[1][1]):
    print(f"  {f:32s} {k/n:6.2f} calls  {t/n*1e6:7.1f} us  ({t/k*1e6:6.1f} us each)")
