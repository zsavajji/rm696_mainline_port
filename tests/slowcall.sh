#!/bin/sh
# Why bme_RX-71 and dsme spend ms per run in the kernel once CORE sleeps (2026-10-16: 0.8 / 2.3 ms per
# run unplugged, 0.04 / 0.18 ms on USB). On the release image (rescue ssh, root): waits for the charger
# to go out, ${W:-60} s, then traces ${S:-120} s in its own trace instance (the top-level buffer is
# left alone): their switches, wake-ups and syscalls, I2C, runtime PM, clocks, IRQs.
# Kprobe events in group sc (made beforehand in kprobe_events) are traced too. Output
# MyDocs/.n9-logs/slowcall.txt. Start:
#   setsid sh /newroot/home/user/MyDocs/n9-tests/slowcall.sh </dev/null >/dev/null 2>&1 &
T=/sys/kernel/debug/tracing; I=$T/instances/slowcall M=/newroot/home/user/MyDocs/.n9-logs O=$M/slowcall.txt
grep -q " /sys/kernel/debug " /proc/mounts || mount -t debugfs none /sys/kernel/debug
B=$(pidof bme_RX-71) D=$(pidof dsme)
while [ "$(cat /sys/class/power_supply/usb/present)" != 0 ]; do sleep 10; done; sleep ${W:-60}
mkdir -p $I; echo 4096 > $I/buffer_size_kb
F="prev_pid == $B || next_pid == $B || prev_pid == $D || next_pid == $D"
echo "$F" > $I/events/sched/sched_switch/filter
echo "pid == $B || pid == $D" > $I/events/sched/sched_wakeup/filter
echo "common_pid == $B || common_pid == $D" > $I/events/raw_syscalls/filter
for e in sched/sched_switch sched/sched_wakeup raw_syscalls i2c rpm clk/clk_enable clk/clk_disable irq/irq_handler_entry; do
	echo 1 > $I/events/$e/enable
done
[ -d $I/events/sc ] && echo 1 > $I/events/sc/enable
sleep ${S:-120}; echo 0 > $I/tracing_on
{ echo "== $(date) bme=$B dsme=$D"; cat $I/trace; } > $O; sync
for e in sched raw_syscalls i2c rpm clk irq sc; do [ -d $I/events/$e ] && echo 0 > $I/events/$e/enable; done; rmdir $I
