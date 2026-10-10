# redraw census over $1 s (<=25), own tracefs instance "redraw"; read-only otherwise
T=/sys/kernel/tracing; I=$T/instances/redraw; mkdir $I || exit 1
P=/sys/devices/platform/68000000.ocp/48050000.dss/4804fc00.encoder/4804fc00.encoder:panel@0
X=$(pidof Xorg); PS="$X $(pidof sysuid) $(pidof mcompositor) $(pidof messaging-ui) $(pidof meego-im-uiserver) $(pidof meegotouchhome) $(pidof meegram) $(pidof meegramd)"
cpu() { for p in $PS; do echo "$p $(cut -d' ' -f2,14,15 /proc/$p/stat)"; done; }
echo 2048 > $I/buffer_size_kb
echo 'comm=="sysuid" || comm=="Xorg" || comm=="mcompositor" || comm=="messaging-ui" || comm=="meego-im-uiserv" || comm=="meegotouchhome"' > $I/events/sched/sched_wakeup/filter
echo "id == 54 && common_pid == $X" > $I/events/raw_syscalls/sys_enter/filter
cpu > /tmp/rd-c0; i0=$(awk '$1=="41:"{print $2}' /proc/interrupts); u0=$(cut -d'|' -f1 $P/update_stats)
echo 1 > $I/events/sched/sched_wakeup/enable; echo 1 > $I/events/raw_syscalls/sys_enter/enable
sleep $1; echo 0 > $I/tracing_on
echo 0 > $I/events/sched/sched_wakeup/enable; echo 0 > $I/events/raw_syscalls/sys_enter/enable
cpu > /tmp/rd-c1; i1=$(awk '$1=="41:"{print $2}' /proc/interrupts); u1=$(cut -d'|' -f1 $P/update_stats)
grep -v '^#' $I/trace > /tmp/rd-trace.txt; rmdir $I
echo "lpm=$(cat $P/lpm) dss irqs (hw): $((i1 - i0)) in $1 s; update_stats $u0 -> $u1"
echo "Xorg OMAPFB_UPDATE_WINDOW: $(grep -c 40444f36 /tmp/rd-trace.txt)"
echo "wakeups (wakee <- waker):"; sed -n 's/^ *\(.*\)-[0-9]* *\[.*sched_wakeup: comm=\([^ ]*\) .*/\2 <- \1/p' /tmp/rd-trace.txt | sort | uniq -c | sort -rn | head -14
echo "cpu ticks (1/100 s) in $1 s:"; paste /tmp/rd-c0 /tmp/rd-c1 | awk '{d = $7 + $8 - $3 - $4; if (d) print " ", $2, d}'
