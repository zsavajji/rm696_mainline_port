#!/bin/sh
# kprobe-time.sh "FUNC..." -- COMMAND: on a test boot (root, outside the chroot), entry and return
# probes on FUNCs while COMMAND runs; prints the trace (parse with tests/kprobe-time.py). The trace is
# dumped before the probes are removed (removing them clears the buffer).
T=/sys/kernel/tracing; mountpoint -q $T || mount -t tracefs none $T
F="$1"; shift; [ "$1" = -- ] && shift
cd $T || exit 1
echo 0 > tracing_on; echo 0 > events/enable; echo > kprobe_events; echo > trace; echo 16384 > buffer_size_kb
for f in $F; do echo "p:k/$f $f" >> kprobe_events; echo "r:k/${f}_r $f" >> kprobe_events; done
echo 1 > events/k/enable
echo 1 > tracing_on
sh -c "$*" >&2
echo 0 > tracing_on
echo 0 > events/enable
cat trace
echo > kprobe_events
