#!/bin/sh
# CORE retention with the screen on and with WLAN associated (HANDOFF-PERF 0i), one unplug, logged to
# /tmp/screenon.log and the kernel log. Waits for USB to go, then (P1=s P2=s P3=s, default 90 each):
#   P1  display on, unlocked and still (no input), WLAN associated
#   P2  display off (mce), WLAN associated
#   P3  as P2 with WLAN's L3 hold not counted (debugfs omap3_l3 "-wlan")
# and puts the display back on. Each phase: CORE's OFF/RET counts, C-state picks (usage) and residency
# (ms), L3's time at OPP50/OPP100 and switches, wl12xx interrupts. Replugging USB ends it at once.
# Run as root on the test kernel, screen unlocked and kept on (ramboot/unlock.sh), WLAN up:
#   setsid sh /tmp/screenon-core.sh </dev/null >/dev/null 2>&1 &
D=/sys/kernel/debug/pm_debug L3=/sys/kernel/debug/omap3_l3 CI=/sys/devices/system/cpu/cpu0/cpuidle
L() { echo "screenon: $*" > /dev/kmsg; echo "$*" >> /tmp/screenon.log; }
present() { grep -q "PRESENT=1" /sys/class/power_supply/usb/uevent; }
mce() { chroot /newroot dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request \
	com.nokia.mce.request.$1 2>/dev/null; }
snap() {
	echo "core $(grep '^core_pwrdm' $D/count | cut -d, -f2-3 | tr -d ' ')"
	echo "use $(cat $CI/state*/usage | tr '\n' ' ')"
	echo "ms $(for s in $CI/state*/time; do echo $(($(cat $s) / 1000)); done | tr '\n' ' ')"
	echo "wl $(awk '$NF == "wl12xx" {print $2}' /proc/interrupts)"
	echo "l3 $(cat $L3)"
}
phase() {
	a=$(snap); t=0
	while [ $t -lt $2 ]; do sleep 5; t=$((t + 5)); touch /tmp/stay; present && { L "$1: USB back, stop"; return 1; }; done
	b=$(snap)
	L "$1 ($2 s): $(echo "$a" | grep ^core) -> $(echo "$b" | grep ^core | cut -d' ' -f2)"
	for k in use ms wl; do
		L "  $k: $(echo "$a" | grep ^$k | cut -d' ' -f2-) -> $(echo "$b" | grep ^$k | cut -d' ' -f2-)"
	done
	L "  l3 before: $(echo "$a" | grep ^l3 | cut -d' ' -f2-)"
	L "  l3 after:  $(echo "$b" | grep ^l3 | cut -d' ' -f2-)"
}
rm -f /tmp/screenon.log
L "start $(uname -v), waiting for USB to go"
while present; do sleep 1; touch /tmp/stay; done
sleep 10	# the USB hold's lowering delay, musb's autosuspend
mce req_display_state_on
phase P1 ${P1:-90} && { mce req_display_state_off; phase P2 ${P2:-90}; } &&
	{ echo -wlan > $L3; phase P3 ${P3:-90}; }
echo +wlan > $L3
mce req_display_state_on
# STRESS=s: display on, md5sum of a cached library (10 MB in SDRAM) against its first checksum with 1 s
# pauses between, for s seconds: CORE retains in the pauses (C5: 100 ms pauses only give C1/C2), so the
# data is checked across the idle path's L3 switches (debugfs "lowered in idle")
if [ -n "$STRESS" ] && ! present; then
	lib=/newroot/usr/lib/libQtGui.so.4.7.4
	low() { sed 's/.* \([0-9]*\) lowered in idle.*/\1/' $L3; }
	ref=$(md5sum $lib | cut -c1-32) n=0 bad=0 a=$(low) c=$(grep '^core_pwrdm' $D/count | cut -d, -f3)
	t0=$(cut -d. -f1 /proc/uptime)
	while [ $(($(cut -d. -f1 /proc/uptime) - t0)) -lt $STRESS ] && ! present; do
		[ "$(md5sum $lib | cut -c1-32)" = "$ref" ] || bad=$((bad + 1))
		n=$((n + 1)); touch /tmp/stay; sleep 1
	done
	L "STRESS: $n checksums, $bad wrong; lowered in idle $a -> $(low); core $c -> $(grep '^core_pwrdm' $D/count | cut -d, -f3)"
fi
L "end"
