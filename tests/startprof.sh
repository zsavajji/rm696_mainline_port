#!/bin/sh
# startprof.sh SECONDS: on the test kernel right after boot: the startup's CPU, per process and in the
# kernel. Per-process tick snapshots every 30 s to /tmp/sp-ticks.txt, kprof system-wide with chains for
# SECONDS to /tmp/sp-kprof.txt, I2C/sysc runtime PM call counts (kprobe hit counters, nothing recorded)
# and the C-state usage to /tmp/sp-pm.txt. Needs /newroot/tmp/kprof.
s=${1:-200}
T=/sys/kernel/tracing
grep -q " $T " /proc/mounts || mount -t tracefs none $T
echo 0 > $T/tracing_on
for f in omap_i2c_runtime_resume omap_i2c_runtime_suspend omap_i2c_xfer sysc_runtime_resume sysc_runtime_suspend \
	 omap_hwmod_enable omap_hwmod_idle clkdm_clk_enable clkdm_clk_disable omap3_enter_idle_bm; do
	grep -qw "$f" /proc/kallsyms && echo "p:sp/$f $f" >> $T/kprobe_events
done
echo 1 > $T/events/sp/enable
ticks() { for st in /proc/[0-9]*/stat; do cat $st 2>/dev/null; done | awk '{c=$2; for (i=3; i<=NF && c !~ /\)$/; i++) c=c " " $i; print $1, c, $(i+11) + $(i+12)}'; }
snap() { echo "== t=$(cut -d. -f1 /proc/uptime) load $(cut -d' ' -f1-3 /proc/loadavg) gov $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) freq $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"; ticks | sort -k3 -rn | head -14; }
pm() { echo "== t=$(cut -d. -f1 /proc/uptime)"; awk '{print $1, $2}' $T/kprobe_profile | sed 's#sp/##'; for d in /sys/devices/system/cpu/cpu0/cpuidle/state*; do echo "$(cat $d/name) $(cat $d/usage) $(cat $d/time)"; done; grep -a "^core_pwrdm\|^mpu_pwrdm\|^per_pwrdm" /sys/kernel/debug/pm_debug/count | cut -d, -f1-3; }
snap > /tmp/sp-ticks.txt; pm > /tmp/sp-pm.txt
KPROF_CHAIN=1 chroot /newroot /tmp/kprof $s 500 > /tmp/sp-kprof.txt 2>&1 &
t=0
while [ $t -lt $s ]; do sleep 30; t=$((t + 30)); snap >> /tmp/sp-ticks.txt; pm >> /tmp/sp-pm.txt; done
wait
echo 0 > $T/events/sp/enable
echo done
