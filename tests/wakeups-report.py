#!/usr/bin/env python3
"""Summarize a tests/wakeups.sh capture: what woke the idle phone, per second.

  python3 -I tests/wakeups-report.py build/wakeups-*.txt

Per file: the state (USB, WLAN, latency limit), CORE's time split and entries from pm_debug, the
interrupt rates (from /proc/interrupts before and after), then from the trace the hrtimer and timer
functions, workqueue functions and woken tasks per second, and the idle states picked with how long
each idle lasted.
"""
import re
import sys
from collections import Counter, defaultdict

EV = re.compile(r'\s(\d+\.\d+): (\w+): (.*)$')


def parse(path):
    snaps, cur, trace = {}, None, []
    for line in open(path, errors='replace'):
        if line.startswith('== '):
            cur = line.split()[1]
            snaps[cur] = {'head': line.strip(), 'up': float(line.split()[2]), 'pw': {}, 'irq': {}}
            continue
        m = EV.search(line)
        if m:
            trace.append((float(m.group(1)), m.group(2), m.group(3)))
            continue
        if cur and 'pm_debug/' in line and line.split(':', 1)[1].startswith('core_pwrdm'):
            kind = 'count' if '/count:' in line else 'time'
            snaps[cur]['pw'][kind] = dict((k, int(v)) for k, v in re.findall(r',(OFF|RET|INA|ON):(\d+)', line))
        elif cur and re.match(r'\s*\d+:\s+\d+\s', line):
            f = line.split()
            snaps[cur]['irq'][f[0]] = (int(f[1]), ' '.join(f[2:]).split()[-1])
    return snaps, trace


def report(path):
    snaps, trace = parse(path)
    a, b = snaps['start'], snaps['end']
    t = b['up'] - a['up']
    print(f'\n## {path}: {t:.0f} s  ({a["head"][3:]})')
    if a['pw'].get('time') and b['pw'].get('time'):
        d = {k: (b['pw']['time'][k] - a['pw']['time'][k]) / 1e9 / t * 100 for k in ('ON', 'INA', 'RET', 'OFF')}
        n = {k: b['pw']['count'][k] - a['pw']['count'][k] for k in ('RET', 'OFF')}
        print(f'CORE ON {d["ON"]:.0f}% INA {d["INA"]:.0f}% RET {d["RET"]:.0f}% OFF {d["OFF"]:.0f}%,'
              f' RET entries {n["RET"]}, OFF entries {n["OFF"]}')
    irq = sorted(((b['irq'][k][0] - a['irq'][k][0], b['irq'][k][1]) for k in b['irq'] if k in a['irq']), reverse=True)
    print('interrupts/s: ' + ', '.join(f'{name} {c / t:.1f}' for c, name in irq[:10] if c))

    ev = Counter(e for _, e, _ in trace)
    def top(event, key, n=8):
        c = Counter()
        for _, e, rest in trace:
            if e == event:
                m = re.search(key, rest)
                c[m.group(1) if m else '?'] += 1
        return ', '.join(f'{k} {v / t:.1f}' for k, v in c.most_common(n))
    print('hrtimers/s: ' + top('hrtimer_expire_entry', r'function=(\S+)'))
    print('timers/s: ' + top('timer_expire_entry', r'function=(\S+)'))
    print('work/s: ' + top('workqueue_execute_start', r'function (\S+)'))
    print('woken/s: ' + top('sched_wakeup', r'comm=(\S+)', 10))

    # idle periods: cpu_idle state=N ... state=4294967295
    picks, length, start = Counter(), defaultdict(list), None
    for ts, e, rest in trace:
        if e != 'cpu_idle':
            continue
        s = int(re.search(r'state=(\d+)', rest).group(1))
        if s != 4294967295:
            start = (ts, s)
        elif start:
            picks[start[1]] += 1
            length[start[1]].append(ts - start[0])
            start = None
    total = sum(picks.values())
    print(f'idles/s {total / t:.0f}: ' + ', '.join(
        f'C{s + 1} {picks[s] / t:.1f}/s (median {sorted(length[s])[len(length[s]) // 2] * 1000:.1f} ms)'
        for s in sorted(picks)))
    allidle = sorted(x for v in length.values() for x in v)
    if allidle:
        bins = [(0.001, '<1ms'), (0.008, '<8ms'), (0.056, '<56ms'), (0.158, '<158ms'), (1e9, '>=158ms')]
        hist, lo = [], 0
        for hi, name in bins:
            idle_s = sum(x for x in allidle if lo <= x < hi)
            hist.append(f'{name} {sum(1 for x in allidle if lo <= x < hi)} ({idle_s / t * 100:.0f}% of time)')
            lo = hi
        print('idle lengths: ' + ', '.join(hist))


if __name__ == '__main__':
    for p in sys.argv[1:]:
        report(p)
