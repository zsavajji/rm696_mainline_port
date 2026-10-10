#!/bin/sh
# CORE OFF, first run (branch core-off): one unplug, four phases, everything logged to the kernel
# log (/dev/kmsg: ramoops keeps it if the phone resets; the next test boot copies it to MyDocs) and to
# /tmp/coreoff1.log (RAM: survives a kernel log flood). saves= is all/positive/failed.
#   P1  0-2 min   OFF not armed: CORE retention as before (the IO chain around it is new)
#   P2  2-3 min   MPU OFF only (disable_core_off 1)
#   P3  3-7 min   CORE OFF, CPU at 600 MHz and L3 pinned low (a stale scratchpad can't matter);
#                 an RTC alarm at +60 s (TWL interrupt, sys_nirq); I press volume up
#                 twice between minutes 4 and 5 (TWL keypad, sys_nirq)
#   P4  7 min-    CORE OFF with cpufreq and the L3 policy live (the scratchpad re-saves)
# Replugging USB ends it at once: OFF disarmed, clocks back. MyDocs' partition is set read-only for
# the run (the init's log writer then can't remount it rw), so a memory fault can't reach it.
# Run as root on the test kernel, display off and locked, Bluetooth off, then unplug:
#   setsid sh /tmp/coreoff1.sh </dev/null >/dev/null 2>&1 &
# P1=s to P4=s in the environment set the phases' lengths (default 120, 60, 240, 600). RADIO=1 makes the
# modem talk over SSI in every phase: mce's cellular radio off at :30 of each minute, on at :00.
# BT=1: Bluetooth up (bluetoothd paused, as tests/coretest-bt.sh) and an inquiry every 20 s (the chip
# wakes the host for its results and the Inquiry Complete), each logged: hcitool's exit status (143 =
# killed by the timeout: Inquiry Complete lost, then cancelled), devices found, CORE's OFF/RET counts
# before and after; logs UART2's (ttyS1) frame/break/overrun counters and runtime-active ms, hci0's errors.
# PADOFF=s (with BT=1): s seconds into P4 UART2's RTS and TX pads (0x2176, 0x2178) get OFF-mode values
# that hold them high whichever polarity OFFOUT_EN has (OFF_EN, OFFOUT_VAL, OFF pull-up, OFFOUT_EN
# clear: driven high or pulled up): RTS deasserted and TX idle while CORE is OFF. Stock had none. Needs
# build/devmem as /newroot/tmp/devmem.
D=/sys/kernel/debug/pm_debug CF=/sys/devices/system/cpu/cpu0/cpufreq L3=/sys/kernel/debug/omap3_l3
DM="chroot /newroot /tmp/devmem"
L() { echo "coreoff1: $*" > /dev/kmsg; echo "$*" >> /tmp/coreoff1.log; }
cnt() { grep "^$1_pwrdm" $D/count | cut -d, -f2-3 | tr -d ' '; }
btst() { [ -n "$BT" ] && printf 'uart2=%s u2act=%s hci=%s ' \
	"$(grep '^1:' /proc/tty/driver/serial | grep -o '\(rx\|fe\|pe\|brk\|oe\):[0-9]*' | tr '\n' ,)" \
	"$(cat /sys/bus/platform/devices/4806c000.serial/power/runtime_active_time)" \
	"$(chroot /newroot hciconfig hci0 | grep -o 'errors:[0-9]*' | tr '\n' ,)"; }
# never print hcitool's output: other people's device addresses
inq() { c=$(cnt core); o=$(timeout 12 chroot /newroot hcitool inq --flush 2>&1); r=$?
	[ $r = 0 ] || chroot /newroot hcitool cmd 0x01 0x0002 >/dev/null 2>&1
	L "inq $1: rc=$r found=$(echo "$o" | grep -c 'clock offset') core:$c -> $(cnt core)"; }
pads() { for a in 0x48002176 0x48002178; do v=$($DM $a 16); $DM $a 16 $(( (v & ~0x3a00) | $1 )) >/dev/null; done
	L "pads $2: RTS $($DM 0x48002176 16) TX $($DM 0x48002178 16)"; }
radio() { chroot /newroot dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request \
	com.nokia.mce.request.req_radio_states_change uint32:$1 uint32:2 2>/dev/null; }
irqs() { btst; printf 'ssierr=%s pn=%s/%s ' "$(dmesg | grep -v coreoff1: | grep -c 'spurious SSI error')" \
	"$(cat /sys/class/net/phonet0/statistics/rx_packets)" "$(cat /sys/class/net/phonet0/statistics/tx_packets)"
	for n in pm_io pm_wkup TWL4030-PIH twl4030_keypad rtc0 maxtouch wakeup wl12xx cawake PORT gdd_mpu cmt_rst_ind; do
	printf '%s=%s ' $n "$(awk -v n=$n '$NF == n {print $2}' /proc/interrupts)"; done; }
cstates() { for s in 3 4 5 6; do cat /sys/devices/system/cpu/cpu0/cpuidle/state$s/usage; done | tr '\n' /; }
st() {
	touch /tmp/stay
	L "$1 up=$(cut -d' ' -f1 /proc/uptime) core:$(cnt core) per:$(cnt per) mpu:$(cnt mpu) dss:$(cnt dss) C4-7=$(cstates) saves=$(cat $D/secure_ram_saves)/$(cat $D/secure_ram_save_positive 2>/dev/null)/$(cat $D/secure_ram_save_fails) $(irqs)"
}
present() { grep -q "PRESENT=1" /sys/class/power_supply/usb/uevent; }
# wait N seconds, logging every 30 s; 1 if USB came back
run() {
	t=0; while [ $t -lt $1 ]; do
		sleep 5; t=$((t + 5)); touch /tmp/stay
		present && return 1
		[ -n "$RADIO" ] && [ $((t % 60)) = 30 ] && radio 0
		[ -n "$RADIO" ] && [ $((t % 60)) = 0 ] && radio 2
		[ -n "$BT" ] && [ $((t % 20)) = 10 ] && (inq "$2+$t" &)
		[ -n "$PADOFF" ] && [ "$2" = P4 ] && [ $t = "$PADOFF" ] && pads 0x3a00 "high in OFF"
		[ $((t % 30)) = 0 ] && st "$2+$t"
	done; return 0
}
maxf=$(cat $CF/scaling_max_freq)
back() {
	echo 0 > $D/off_mode_armed; echo 1 > $D/disable_core_off; [ -n "$RADIO" ] && radio 2
	[ -n "$PADOFF" ] && pads 0 "as stock"
	[ -n "$BT" ] && { sleep 12; chroot /newroot hciconfig hci0 down; kill -CONT $(pidof bluetoothd) 2>/dev/null; }
	echo $maxf > $CF/scaling_max_freq; echo auto > $L3
	blockdev --setrw $MD; st END; L "OFF disarmed, clocks back: $1"
	dmesg | grep -av "command line" | grep -iE "I/O wakeup|secure_sram|spurious|SSI|twl|wkup|prcm|l3-|In-band|Bluetooth|serial0" | tail -30 |
		while read -r l; do L "dmesg: $l"; done
	exit 0
}
[ -n "$BT" ] && { kill -STOP $(pidof bluetoothd) 2>/dev/null; chroot /newroot hciconfig hci0 up; }
MD=$(awk '$2 == "/mydocs" {print $1}' /proc/mounts)
blockdev --setro $MD
echo 1 > /sys/class/leds/debug::sleep/brightness	# the indicator: dark while the device sleeps
L "start: armed/enable/disable_core_off $(cat $D/off_mode_armed)/$(cat $D/enable_off_mode)/$(cat $D/disable_core_off), PM_WKEN_WKUP $(/tmp/devmem-ro 0x48306ca0 2>/dev/null) (EN_IO, bit 8, only in idle)"
st P0
while present; do sleep 1; touch /tmp/stay; done
L unplugged
st P1;	run ${P1:-120} P1 || back "replugged in P1"
echo 1 > $D/disable_core_off; echo 1 > $D/off_mode_armed; echo 1 > $D/enable_off_mode
st P2;	run ${P2:-60} P2 || back "replugged in P2"
echo 600000 > $CF/scaling_max_freq; echo low > $L3; echo 0 > $D/disable_core_off
echo 0 > /sys/class/rtc/rtc0/wakealarm; echo $(($(cat /sys/class/rtc/rtc0/since_epoch) + 60)) > /sys/class/rtc/rtc0/wakealarm
st P3;	run ${P3:-240} P3 || back "replugged in P3"
echo $maxf > $CF/scaling_max_freq; echo auto > $L3
st P4;	run ${P4:-600} P4 || back "replugged in P4"
back "10 min in P4"
