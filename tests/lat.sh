# touch-down (maxtouch irq after >150 ms quiet) -> next DISPC irq, over $1 s; tag $2
T=/sys/kernel/tracing; grep -q " $T " /proc/mounts || mount -t tracefs none $T
E=$T/events/irq/irq_handler_entry
echo 0 > $T/tracing_on; echo > $T/trace; echo 'irq==184 || irq==41' > $E/filter; echo 1 > $E/enable
echo 1 > $T/tracing_on; sleep $1; echo 0 > $T/tracing_on; echo 0 > $E/enable; echo 0 > $E/filter
grep -o '[0-9]*\.[0-9]*: irq_handler_entry: irq=[0-9]*' $T/trace | sed 's/: irq_handler_entry: irq=/ /' > /tmp/lat-$2.txt; echo > $T/trace
awk -v tag=$2 '$2==184 { if ($1 - last > 0.15) { pend = $1; n++ } last = $1 }
  $2==41 && pend { d = ($1 - pend) * 1000; v[++k] = d; s += d; pend = 0 }
  END { m = k; for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++) if (v[j] < v[i]) { t = v[i]; v[i] = v[j]; v[j] = t }
    printf "%s: %d touch-downs, %d with an update: median %.1f ms, mean %.1f, p90 %.1f, max %.1f\n", tag, n, k, v[int((k + 1) / 2)], k ? s / k : 0, v[int(k * 0.9 + 0.5)], v[k] }' /tmp/lat-$2.txt
