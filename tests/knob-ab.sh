#!/bin/sh
# Unplugged A/B of a sysfs knob (2026-10-12): each value waits until no charger is in, then ${W:-60} s
# (screen off by then), then ${S:-120} s per value of knob P for each of V: CORE states, idle entries not entered (cpuidle
# "rejected"), wake-ups and battery current; the first value is put back at the end. Output
# MyDocs/.n9-logs/knob-ab.txt, synced after each value. On the release image (rescue ssh, root):
#   P=/sys/devices/system/cpu/cpuidle/current_governor V="menu teo" setsid sh /newroot/home/user/MyDocs/n9-tests/knob-ab.sh </dev/null >/dev/null 2>&1 &
# (the WLAN SDIO host's autosuspend: P=/sys/bus/platform/devices/480ad000.mmc/power/autosuspend_delay_ms V="100 20")
D=/sys/kernel/debug C=/sys/devices/system/cpu/cpu0/cpuidle M=/newroot/home/user/MyDocs/.n9-logs O=$M/knob-ab.txt
P=${P:-/sys/devices/system/cpu/cpuidle/current_governor} V=${V:-menu teo}
# Instead of a file, K runs a command with the value as $1, e.g. pausing a daemon:
#   K='kill -$1 $(pidof meegramd)' V="CONT STOP CONT STOP"
knob() { if [ -n "$K" ]; then eval "$K"; else echo $1 > $P; fi; }
now() { if [ -n "$K" ]; then echo "$K: $1"; else echo "$P=$(cat $P)"; fi; }
grep -q " $D " /proc/mounts || mount -t debugfs none $D
pw() { grep "^core_pwrdm" $D/pm_debug/$1 | tr ',:' '  '; }
irq() { awk -v n="$1" '$NF == n {print $2}' /proc/interrupts; }
# uptime, CORE ON/RET/OFF/INA ns, RET/OFF entries, wl12xx/mmc2/clockevent/pm_wkup interrupts, rejected
snap() {
	set -- $(pw time); t="${10} $6 $4 $8"
	set -- $(pw count); echo "$(cut -d' ' -f1 /proc/uptime) $t $6 $4 $(irq wl12xx) $(irq mmc2) $(irq clockevent)" \
		"$(irq pm_wkup) $(cat $C/state*/rejected | awk '{s += $1} END {print s}')"
}
cur() { chroot /newroot /usr/bin/bmestat | awk -F: '/battery current/ {gsub(/ /, "", $2); print $2}'; }
# each value measured unplugged: wait while a charger (the Mac's port or a wall charger) is in, then
# ${W:-60} s to settle
unplugged() {
	w=; while [ "$(cat /sys/class/power_supply/usb/present)" != 0 ]; do sleep 10; w=1; done
	[ -n "$w" ] && sleep ${W:-60}
}
phase() {
	unplugged; knob $1; sleep 10; a=$(snap); s=0 n=0
	while [ $n -lt $((${S:-120} / 10)) ]; do sleep 10; s=$((s + $(cur))); n=$((n + 1)); done
	echo "$(now $1) usb=$(cat /sys/class/power_supply/usb/present) mA=$((s / n))" >> $O
	echo "$a $(snap)" | awk '{n = NF / 2; for (i = 1; i <= n; i++) d[i] = $(i + n) - $i; t = d[1]
		printf "  %.0f s: CORE ON %.0f%% RET %.0f%% OFF %.0f%% INA %.0f%%, RET# %d OFF# %d, rejected %d; /s: wl12xx %.1f mmc2 %.1f clockevent %.1f pm_wkup %.1f\n",
		t, d[2] / 1e7 / t, d[3] / 1e7 / t, d[4] / 1e7 / t, d[5] / 1e7 / t, d[6], d[7], d[12], d[8] / t, d[9] / t, d[10] / t, d[11] / t}' >> $O
	sync
}
mkdir -p $M; echo "== $(date) ${K:-$P}: $V" >> $O
for v in $V; do phase $v; done; knob ${V%% *}
