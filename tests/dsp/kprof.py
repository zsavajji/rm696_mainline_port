# kprof.py TRACE: pair kprobe entry (_e) / return (_x) events per task into durations, print per function
import re, sys, collections
stacks = collections.defaultdict(list)
d = collections.defaultdict(list)
for l in open(sys.argv[1], errors='replace'):
    m = re.match(r'\s*(\S+)\s+\[\d+\]\s+\S+\s+([\d.]+):\s+(\S+)_(e|x):', l)
    if not m:
        continue
    task, t, f, k = m.group(1), float(m.group(2)), m.group(3), m.group(4)
    st = stacks[(task, f)]
    if k == 'e':
        st.append(t)
    elif st:
        d[f].append((t - st.pop()) * 1e6)
for f, v in sorted(d.items(), key=lambda x: -sum(x[1])):
    v.sort()
    print('%-28s n %6d total %9.0f us avg %8.1f med %8.1f max %9.1f' % (f, len(v), sum(v), sum(v) / len(v), v[len(v) // 2], v[-1]))
