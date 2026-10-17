#!/bin/sh
# Why a double tap sometimes doesn't wake the display (2026-10-12; "waiting for the clock to update
# unlocks it"). On the release image (rescue ssh, root): traces mce's wake-gesture sysfs writes
# (wait_for_gesture, disable_ts, calibrate), the touch and PRCM IO-wake interrupts, display updates,
# the touch messages read (i2c, T24 gesture codes among them) and MSC events; every ${I:-10} s
# samples the touch CHG line (GPIO 61, low = messages unread), the gesture armed and CORE OFF
# entries; for ${S:-900} s or until /tmp/dtap.stop (then the trace's latest events, an 8 MB ring, are
# appended). Output MyDocs/.n9-logs/dtap.txt, synced after each sample.
# Start: setsid sh /newroot/home/user/MyDocs/n9-tests/dtap.sh </dev/null >/dev/null 2>&1 &
T=/sys/kernel/tracing D=/sys/kernel/debug M=/newroot/home/user/MyDocs/.n9-logs O=$M/dtap.txt
grep -q " $T " /proc/mounts || mount -t tracefs none $T; mkdir -p $M
grep -q " $D " /proc/mounts || mount -t debugfs none $D
TS=$(ls -d /sys/bus/i2c/drivers/atmel_mxt_ts/*-004b) G=/sys/class/gpio/gpio61
[ -e $G ] || echo 61 > /sys/class/gpio/export	# the CHG level (an IRQ line only isn't in debugfs)
irqs=$(awk '/maxtouch|pm_io|DISPC/ {sub(":", "", $1); printf "%sirq==%s", s, $1; s=" || "}' /proc/interrupts)
cd $T; echo 0 > tracing_on; echo 0 > events/enable; echo > kprobe_events; echo > trace; echo 8192 > buffer_size_kb
echo "p:k/wfg mxt_wait_for_gesture_store buf=+0(%r2):string" >> kprobe_events
echo "p:k/dts mxt_disable_ts_store buf=+0(%r2):string" >> kprobe_events
echo "p:k/cal mxt_calibrate_store" >> kprobe_events
echo "p:k/inev input_event type=%r1:u32 code=%r2:u32 value=%r3:s32" >> kprobe_events
echo "type == 4" > events/k/inev/filter
echo "$irqs" > events/irq/irq_handler_entry/filter
b=${TS##*/}; echo "adapter_nr == ${b%%-*} && addr == 75" > events/i2c/i2c_reply/filter	# the touch messages read
echo 1 > events/k/enable; echo 1 > events/irq/irq_handler_entry/enable; echo 1 > events/i2c/i2c_reply/enable
echo "== start $(cut -d' ' -f1 /proc/uptime) irqs: $irqs probes: $(cut -d' ' -f1 kprobe_events | tr '\n' ' ')" >> $O
echo 1 > tracing_on; i=0; rm -f /tmp/dtap.stop
while [ $i -lt $((${S:-900} / ${I:-10})) ] && [ ! -e /tmp/dtap.stop ]; do
	echo "$(cut -d' ' -f1 /proc/uptime) chg=$(cat $G/value)" \
		"armed=$(cat $TS/wait_for_gesture) dis=$(cat $TS/disable_ts)" \
		"off#=$(grep ^core_pwrdm $D/pm_debug/count | cut -d, -f2) irq=$(awk '/maxtouch/ {print $2}' /proc/interrupts)" >> $O
	sync; i=$((i + 1)); sleep ${I:-10}
done
echo 0 > tracing_on; cat trace >> $O
echo 0 > events/k/enable; echo 0 > events/irq/irq_handler_entry/enable; echo 0 > events/i2c/i2c_reply/enable
echo 0 > events/irq/irq_handler_entry/filter; echo 0 > events/i2c/i2c_reply/filter
echo > kprobe_events; echo 61 > /sys/class/gpio/unexport
sync
