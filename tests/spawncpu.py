#!/usr/bin/env python3
"""spawncpu.py LOG: per phase of tests/spawncpu.sh, the CPU split (ticks) and the processes that used it."""
import re, sys

snaps, cur = {}, None
for l in open(sys.argv[1]):
    if l.startswith('== '):
        cur = snaps.setdefault(l[3:].strip(), {'procs': {}})
    elif l.startswith('cpu '):
        cur['cpu'] = list(map(int, l.split()[1:8]))
    elif cur is not None and re.match(r'\d+ \(', l):
        pid, rest = l.split(' (', 1)
        comm, f = rest.rsplit(') ', 1)
        f = f.split()
        cur['procs'][int(pid)] = (comm, int(f[11]), int(f[12]))	# utime, stime
for ph in ['idle', '0', '2', '3']:
    a, b = snaps.get('before ' + ph), snaps.get('after ' + ph)
    if not a or not b:
        continue
    c = [y - x for x, y in zip(a['cpu'], b['cpu'])]
    tot = sum(c)
    print(f"== phase {ph}: {tot} ticks; user {c[0]+c[1]} system {c[2]} idle {c[3]} iowait {c[4]} irq {c[5]} softirq {c[6]}")
    rows = []
    for pid, (comm, u, s) in b['procs'].items():
        u0, s0 = a['procs'].get(pid, (comm, 0, 0))[1:]
        if u - u0 + s - s0 > 0:
            rows.append((u - u0 + s - s0, u - u0, s - s0, comm, pid))
    for t, u, s, comm, pid in sorted(rows, reverse=True)[:12]:
        print(f"  {comm:20s} {pid:6d}  user {u:4d}  system {s:4d}  ({100 * t / tot:4.1f}%)")
