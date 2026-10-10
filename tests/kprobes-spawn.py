#!/usr/bin/env python3
"""kprobes-spawn.py TRACE MAPS N: from tests/kprobes-spawn.sh, per spawn and per role (the spawner, its
children): on-CPU time, the probed functions (count, inclusive wall time) and the page faults by region
(the spawner's maps) and kind (write, read, instruction fetch)."""
import re, sys
from collections import defaultdict

ev = re.compile(r'^\s*(.+?)-(\d+)\s+\[\d+\]\s+\S+\s+([\d.]+): (\w+): (.*)$')
lines = [m.groups() for m in map(ev.match, open(sys.argv[1])) if m]
maps = []
for l in open(sys.argv[2]):
    m = re.match(r'([0-9a-f]+)-([0-9a-f]+) (\S+) \S+ \S+ \S+\s*(.*)', l)
    if m:
        name = m.group(4).split('/')[-1] or '[anon]'
        maps.append((int(m.group(1), 16), int(m.group(2), 16), f"{name} {m.group(3)}"))
n = int(sys.argv[3])

def region(a):
    for s, e, name in maps:
        if s <= a < e:
            return name
    return '[unmapped]'

forks = defaultdict(int)
for comm, pid, ts, name, rest in lines:
    if name == 'copy_process' and comm.strip() == 'spawnbench':
        forks[int(pid)] += 1
parent = max(forks, key=forks.get)
first = next(float(t) for c, p, t, nm, r in lines if nm == 'copy_process' and int(p) == parent)
last = max(float(t) for c, p, t, nm, r in lines if int(p) == parent)
role = lambda comm, pid: 'parent' if pid == parent else ('child' if comm.strip() == 'spawnbench' else 'other')
stacks = defaultdict(list)
fn = defaultdict(lambda: [0, 0.0])
faults = defaultdict(lambda: [0, 0.0])
oncpu = defaultdict(float)
lastsw = None
comms = {}
for comm, pid, ts, name, rest in lines:
    pid, ts = int(pid), float(ts)
    if ts < first or ts > last:
        continue
    r = role(comm, pid)
    if name == 'sched_switch':
        a = re.search(r'prev_comm=(.*?) prev_pid=(\d+) .*next_comm=(.*?) next_pid=(\d+)', rest)
        pp = int(a.group(2))
        if lastsw is not None:
            oncpu[role(a.group(1), pp) if pp else 'idle'] += ts - lastsw
        lastsw = ts
    elif name == 'pf':
        a = re.search(r'addr=0x([0-9a-f]+) flags=0x([0-9a-f]+)', rest)
        addr, fl = int(a.group(1), 16), int(a.group(2), 16)
        kind = 'exec' if fl & 0x100 else ('write' if fl & 1 else 'read')
        stacks[(pid, 'pf')].append((ts, (r, region(addr), kind)))
    elif name == 'pf_r':
        if stacks[(pid, 'pf')]:
            t0, key = stacks[(pid, 'pf')].pop()
            faults[key][0] += 1; faults[key][1] += ts - t0
    elif name.endswith('_r'):
        f = name[:-2]
        if stacks[(pid, f)]:
            t0 = stacks[(pid, f)].pop()
            fn[(r, f)][0] += 1; fn[(r, f)][1] += ts - t0
    else:
        if name == 'do_exit':
            fn[(r, 'do_exit')][0] += 1
        else:
            stacks[(pid, name)].append(ts)
tot = last - first
print(f"spawner {parent}: {tot*1e3:.0f} ms, {tot/n*1e6:.0f} us per spawn (probes included)")
for k, t in sorted(oncpu.items(), key=lambda x: -x[1]):
    print(f"  on CPU {k:8s} {t/n*1e6:7.1f} us/spawn")
print("functions (inclusive wall time, per spawn):")
for (r, f), (k, t) in sorted(fn.items(), key=lambda x: (x[0][0], -x[1][1])):
    if r != 'other':
        print(f"  {r:7s} {f:22s} {k/n:6.2f} calls  {t/n*1e6:7.1f} us  ({t/max(k,1)*1e6:6.1f} us each)")
print("page faults (per spawn):")
tf = defaultdict(lambda: [0, 0.0])
for (r, reg, kind), (k, t) in sorted(faults.items(), key=lambda x: -x[1][1]):
    tf[r][0] += k; tf[r][1] += t
    if r != 'other' and k / n >= 0.05:
        print(f"  {r:7s} {kind:5s} {reg:40s} {k/n:5.2f}  {t/n*1e6:6.1f} us  ({t/k*1e6:5.1f} each)")
for r, (k, t) in tf.items():
    print(f"  total {r:7s} {k/n:5.2f} faults {t/n*1e6:6.1f} us")
