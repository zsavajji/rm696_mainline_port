#!/bin/sh
# What wakes an idle phone (2026-10-12: stock idles in CORE OFF ~93% of a WLAN-up night, 6.18 ~8%).
# On the release image, as root (rescue ssh, or devel-su on the phone: tests/night.sh): waits until no charger is in
# (U=1: don't), then ${W:-240} s for the screen to blank, then traces ${S:-120} s of timers, hrtimers, IRQs, workqueue items, task
# wakeups, idle states and CPU latency limits; counters before and after; ${N:-1} captures ${P:-600} s
# apart. Output MyDocs/.n9-logs/wakeups-MMDD-HHMM-0.txt..., synced after each capture.
# Start: setsid sh /newroot/home/user/MyDocs/n9-tests/wakeups.sh </dev/null >/dev/null 2>&1 &
T=/sys/kernel/tracing D=/sys/kernel/debug C=/sys/devices/system/cpu/cpu0/cpuidle
R=/newroot; [ -d $R/home/user ] || R=	# rescue ssh: Harmattan under /newroot; the phone's root shell: /
M=$R/home/user/MyDocs/.n9-logs
E="timer/timer_expire_entry timer/hrtimer_expire_entry irq/irq_handler_entry workqueue/workqueue_execute_start
 sched/sched_wakeup power/cpu_idle power/cpu_idle_miss power/pm_qos_update_target"
grep -q " $T " /proc/mounts || mount -t tracefs none $T
grep -q " $D " /proc/mounts || mount -t debugfs none $D
snap() {
	echo "== $1 $(cut -d' ' -f1 /proc/uptime) usb=$(cat /sys/class/power_supply/usb/present)" \
		"wlan=$(cat /sys/class/net/wlan0/operstate) bl=$(cat /sys/class/backlight/*/brightness | head -1)" \
		"lat=$(od -An -td4 -N4 /dev/cpu_dma_latency | tr -d ' ')"
	grep . /sys/class/drm/*/dpms /sys/class/drm/*/enabled 2>/dev/null
	grep "^core_pwrdm\|^mpu_pwrdm" $D/pm_debug/count $D/pm_debug/time
	for s in $C/state*; do echo "$(cat $s/name) lat=$(cat $s/latency) res=$(cat $s/residency) usage=$(cat $s/usage) time=$(cat $s/time)"; done
	cat /proc/interrupts
}
[ -n "$U" ] || while [ "$(cat /sys/class/power_supply/usb/present)" != 0 ]; do sleep 10; done
sleep ${W:-240}
mkdir -p $M; R=$(date +%m%d-%H%M); cd $T; echo 0 > tracing_on; echo 8192 > buffer_size_kb; i=0
while :; do
	O=$M/wakeups-$R-$i.txt; echo > trace
	for e in $E; do echo 1 > events/$e/enable; done
	snap start > $O
	echo 1 > tracing_on; sleep ${S:-120}; echo 0 > tracing_on
	snap end >> $O; cat trace >> $O
	for e in $E; do echo 0 > events/$e/enable; done
	sync
	i=$((i + 1)); [ $i -lt ${N:-1} ] || break; sleep ${P:-600}
done
