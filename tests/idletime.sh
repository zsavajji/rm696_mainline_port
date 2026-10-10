#!/bin/sh
# idletime.sh [SECONDS]: on the test kernel: record entry and return of the idle path's transition
# walks (pwrdm_pre/post_transition and their _set variants) for SECONDS (10) and print the trace
# (parse on the Mac: mean duration per pair; the timestamps step 30.5 us, the mean over hundreds of
# pairs is fine). Leaves the counting probes (ic/) enabled.
s=${1:-10}
T=/sys/kernel/tracing
grep -q " $T " /proc/mounts || mount -t tracefs none $T
echo 0 > $T/tracing_on
echo 0 > $T/events/ic/enable 2>/dev/null
if ! grep -q "ic2/" $T/kprobe_events; then
	for f in pwrdm_pre_transition pwrdm_post_transition pwrdm_pre_transition_set pwrdm_post_transition_set; do
		grep -qw "$f" /proc/kallsyms || continue
		echo "p:ic2/${f}_in $f" >> $T/kprobe_events
		echo "r:ic2/${f}_out $f" >> $T/kprobe_events
	done
fi
echo 8192 > $T/buffer_size_kb
echo > $T/trace
echo 1 > $T/events/ic2/enable
echo 1 > $T/tracing_on
sleep $s
echo 0 > $T/tracing_on
echo 0 > $T/events/ic2/enable
echo 1 > $T/events/ic/enable 2>/dev/null
cat $T/trace
