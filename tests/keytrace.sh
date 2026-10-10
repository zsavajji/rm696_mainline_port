# per touch-down: when each UI process first runs after it, and the display updates within 1.5 s
T=/sys/kernel/tracing; grep -q " $T " /proc/mounts || mount -t tracefs none $T
I=$T/events/irq/irq_handler_entry S=$T/events/sched/sched_switch
echo 0 > $T/tracing_on; echo > $T/trace; echo 4096 > $T/buffer_size_kb
echo 'irq==184 || irq==41' > $I/filter
echo 'next_comm=="meego-im-uiserv" || next_comm=="messaging-ui" || next_comm=="Xorg" || next_comm=="dbus-daemon" || next_comm=="mcompositor" || next_comm=="pulseaudio" || next_comm=="meegofeedbackd" || next_comm=="immvibed"' > $S/filter
echo 1 > $I/enable; echo 1 > $S/enable; echo 1 > $T/tracing_on; sleep $1; echo 0 > $T/tracing_on
echo 0 > $I/enable; echo 0 > $S/enable; echo 0 > $I/filter; echo 0 > $S/filter
grep -v '^#' $T/trace | sed -n 's/.* \([0-9]*\.[0-9]*\): irq_handler_entry: irq=\([0-9]*\).*/\1 irq\2/p; s/.* \([0-9]*\.[0-9]*\): sched_switch: .*next_comm=\([^ ]*\) .*/\1 \2/p' > /tmp/kt.txt
echo > $T/trace; echo 1408 > $T/buffer_size_kb
awk '$2=="irq184" { if ($1 - last > 0.15) { if (t) out(); t = $1; delete f; u = "" } last = $1; next }
  t && $1 - t < 1.5 { if ($2 == "irq41") u = u sprintf(" %.0f", ($1 - t) * 1000); else if (!($2 in f)) f[$2] = ($1 - t) * 1000 }
  function out(  k, s) { s = ""; for (k in f) s = s sprintf(" %s+%.0f", k, f[k]); printf "touch %.3f:%s | dispc ms:%s\n", t, s, u }
  END { if (t) out() }' /tmp/kt.txt
