#!/usr/bin/env python3
"""On the Mac: analyse a tests/bt-baud.sh 'kp on' trace (received bytes + wake/RTS/runtime PM events)
WITHOUT printing received data. 1) H4 (Nokia, word-aligned) framing over the inserted bytes: one line per
wake cycle with stray bytes, line errors or a bad length (-v: every cycle), packets as type/event:length.
2) For each RTS raise: the delay to the first received byte, whether the host-wakeup IRQ came just before
(the chip woke the host), that byte's line errors (LSR & 0x1e; 0x0c = framing + parity error).
The trace holds received data (BD addresses): keep it in a private scratch dir, delete it after.
Usage: bt-baud-trace.py TRACE [-v]"""
import re, sys
from collections import Counter
ev_re = re.compile(r'\s(\d+\.\d+): (\w+): (.*)$')
HDR = {2: (4, lambda h: h[2] | h[3] << 8), 3: (3, lambda h: h[2]), 4: (2, lambda h: h[1]),
       6: (1, lambda h: h[0]), 7: (1, lambda h: h[0]), 8: (2, lambda h: h[1])}
verbose = '-v' in sys.argv
events = []
for line in open(sys.argv[1], errors='replace'):
    m = ev_re.search(line)
    if not m: continue
    t, name, rest = float(m.group(1)), m.group(2), m.group(3)
    args = dict(re.findall(r'(\w+)=(\S+)', rest))
    events.append((t, name, args))

# framing state
state = 'type'; pkt = []; need = 0; hdrlen = 0; pad = False
out = []        # per cycle report items
cycle_t0 = None; lines = []; cur = []; lsr_next = None; nerr = 0; stray = 0
def flush_pkt(desc):
    cur.append(desc)
def report():
    global cur
    if cur: lines.append(' '.join(cur))
    cur = []
last = {}
for t, name, a in events:
    if name == 'irq_handler_entry':
        if a.get('irq') == '183':
            cur.append('W@%.6f' % t); last['W'] = t
        continue
    if name in ('su', 'sd', 'hc'):    # set-up, shutdown, close: the driver's parser starts over after a close
        cur.append('%s@%.6f' % (name, t))
        if name == 'hc': state = 'type'; pkt = []; pad = False
        continue
    if name in ('nrr', 'nrs', 'omr', 'oms', 'txrel', 'wk'):
        if verbose or name in ('nrr', 'nrs', 'omr', 'oms'):
            cur.append('%s@%.6f' % (name, t))
        last[name] = t
        if name == 'nrs': report()
        continue
    if name == 'tiocm':
        cur.append('RTS%s@%.6f' % ('+' if a['set'] != '0x0' else '-', t)); continue
    if name == 'rd':
        lsr_next = int(a['lsr'], 16); continue
    if name != 'ins': continue
    st = int(a['st'], 16); ch = int(a['ch'], 16)
    err = (lsr_next or 0) & 0x1e
    lsr_next = None
    if err:
        cur.append('LSR%02x@%.6f(state %s, in pkt %s)' % (err, t, state, '/'.join('%02x' % b for b in pkt[:3]) if pkt else '-'))
    if st & 0x10:   # break: dropped by IGNBRK
        continue
    if pad:
        pad = False
        if state == 'type': continue
    if state == 'type':
        if ch in HDR:
            pkt = [ch]; hdrlen = HDR[ch][0]; state = 'hdr'; pkt_t = t
        else:
            stray += 1
            if not cur or not cur[-1].startswith('stray'):
                cur.append('stray@%.6f' % t)
            cur[-1] = re.sub(r'(x\d+)?$', '', cur[-1]) + 'x%d' % (int(re.search(r'x(\d+)$', cur[-1]).group(1)) + 1 if re.search(r'x(\d+)$', cur[-1]) else 1)
        continue
    pkt.append(ch)
    if state == 'hdr' and len(pkt) == 1 + hdrlen:
        need = HDR[pkt[0]][1](pkt[1:])
        if need > 1021:
            cur.append('BADLEN(%02x len %d)@%.6f' % (pkt[0], need, t)); state = 'type'; pkt = []; continue
        state = 'data'
    if state == 'data' and len(pkt) == 1 + hdrlen + need:
        d = '%02x' % pkt[0] + ('/%02x' % pkt[1] if pkt[0] in (4, 8) else '') + ':%d' % need
        cur.append(d)
        pad = len(pkt) % 2 == 1
        state = 'type'; pkt = []
report()
for l in lines:
    if verbose or 'stray' in l or 'LSR' in l or 'BADLEN' in l:
        print(l)
print('cycles %d, stray bytes %d' % (len(lines), stray))

# RTS raises
ev = [(t, n, ' '.join('%s=%s' % kv for kv in a.items())) for t, n, a in events]
c = Counter()
for i, (t, n, a) in enumerate(ev):
    if n != 'tiocm' or 'set=0x0 ' in a + ' ': continue
    chip = any(e[1] == 'irq_handler_entry' and 'irq=183' in e[2] for e in ev[max(0, i - 6):i])
    for t2, n2, a2 in ev[i + 1:]:
        if n2 == 'tiocm': c[(chip, 'no byte', '-')] += 1; break
        if n2 == 'rd':
            d = round((t2 - t) * 1e6)
            c[(chip, '<200 us' if d < 200 else '>=200 us', '0x%02x' % (int(re.search(r'lsr=(\S+)', a2).group(1), 16) & 0x1e))] += 1
            break
for (chip, d, e), v in sorted(c.items()):
    print('%-14s first byte %-9s errors %s: %d' % ('chip woke host' if chip else 'host first', d, e, v))
