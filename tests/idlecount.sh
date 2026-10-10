#!/bin/sh
# idlecount.sh [SECONDS] [LABEL]: on the test kernel (initramfs shell, root): count the idle path's
# power-domain accesses and the 32k reads of pm_dbg_update_time per idle cycle over SECONDS (20),
# with kprobes whose events are enabled but not recorded (tracing_on 0: the hit counters in
# kprobe_profile count, the ring buffer stays untouched). Also the C-state usage split and the
# interrupt total. Read-only on the phone (tracefs only). omap_sram_idle() is __cpuidle text (kprobe
# blacklist): idle cycles = omap3_enter_idle_bm() hits.
s=${1:-20} label=${2:-run}
T=/sys/kernel/tracing C=/sys/devices/system/cpu/cpu0/cpuidle
grep -q " $T " /proc/mounts || mount -t tracefs none $T
echo 0 > $T/tracing_on
if ! grep -q . $T/kprobe_events; then
	for f in omap3_enter_idle_bm _pwrdm_state_switch pm_dbg_update_time \
		 omap3_pwrdm_read_pwrst omap3_pwrdm_read_prev_pwrst omap3_pwrdm_read_next_pwrst \
		 omap3_pwrdm_set_next_pwrst omap3_pwrdm_clear_all_prev_pwrst \
		 omap3_pwrdm_read_logic_pwrst omap3_pwrdm_read_prev_logic_pwrst \
		 omap3_pwrdm_read_prev_mem_pwrst omap3xxx_prm_clear_mod_irqs omap3_l3_idle_enter \
		 omap_vp_forceupdate_scale; do
		grep -qw "$f" /proc/kallsyms && echo "p:ic/$f $f" >> $T/kprobe_events
	done
	echo 1 > $T/events/ic/enable
fi
snap() {
	awk '{print $1, $2}' $T/kprobe_profile | sed 's#ic/##'
	for d in $C/state*; do echo "$(cat $d/name) $(cat $d/usage) $(cat $d/time)"; done
	echo "irqs $(awk '/^ *[0-9]+:/ {s += $2} END {print s}' /proc/interrupts)"
	echo "freq $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
}
snap > /tmp/ic.0
sleep $s
snap > /tmp/ic.1
echo "== $label: $s s (uptime $(cut -d. -f1 /proc/uptime), $(head -1 /sys/kernel/debug/omap3_l3 2>/dev/null | cut -d';' -f1), display brightness $(cat /sys/class/backlight/display0/brightness) lpm $(cat /sys/class/backlight/display0/device/lpm))"
paste /tmp/ic.0 /tmp/ic.1 | awk -v s=$s '
	$1 == "omap3_enter_idle_bm" { idle = $4 - $2 }
	$1 ~ /^C[0-9]/ { cd[$1] = $5 - $2; ct[$1] = $6 - $3; corder[cn++] = $1; next }
	{ d[$1] = $4 - $2; order[n++] = $1 }
	END {
		printf "idle cycles %d (%.0f/s)\n", idle, idle / s
		for (i = 0; i < cn; i++) printf "%s %d entries, %.1f%% of the time\n", corder[i], cd[corder[i]], ct[corder[i]] / s / 10000
		for (i = 0; i < n; i++) {
			k = order[i]
			if (k == "irqs") printf "interrupts %d (%.0f/s)\n", d[k], d[k] / s
			else if (k != "freq" && k != "omap3_enter_idle_bm") printf "%-34s %8d  %6.2f per idle\n", k, d[k], idle ? d[k] / idle : 0
		}
	}'
rm -f /tmp/ic.0 /tmp/ic.1
