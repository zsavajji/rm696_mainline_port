#!/bin/sh
# The oscillator start-up time (PRM_CLKSETUP, stock's 113 cycles of 32 kHz since kernel branch
# osc-setup) A/B in one unplug: tests/wakelat measures how late each timer wake is, i.e. the exit
# latency of the idle state the CPU left, in four phases of PHASE seconds (default 75) after 20 s to
# settle:
#   A  CORE retention (OFF unarmed, as on every boot), CLKSETUP as the kernel set it
#   B  the same with CLKSETUP 328 (mainline's 10 ms default)
#   C  CORE OFF armed, CLKSETUP as the kernel set it
#   D  CORE OFF armed, CLKSETUP 328
# Replugging ends it at once; then, or after D, CLKSETUP and the OFF switches go back to what they were.
# Output: /tmp/oscsetup/{A,B,C,D}.txt (wakelat's lines), phase lines in /tmp/oscsetup/log and the
# kernel log ("oscsetup:"). MyDocs' partition is read-only during the run (as tests/coreoff1.sh).
# Needs build/wakelat and build/devmem as /newroot/tmp/{wakelat,devmem}. Run as root on the test
# kernel, then unplug (the script blanks the display 5 s later):
#   setsid sh /tmp/oscsetup.sh </dev/null >/dev/null 2>&1 &
D=/sys/kernel/debug/pm_debug O=/tmp/oscsetup CS=0x48307298
DM="chroot /newroot /tmp/devmem"
mkdir -p $O
L() { echo "oscsetup: $*" > /dev/kmsg; echo "$*" >> $O/log; }
cnt() { grep "^$1_pwrdm" $D/count | cut -d, -f2-3 | tr -d ' '; }
st() {
	touch /tmp/stay
	L "$1 up=$(cut -d' ' -f1 /proc/uptime) display=$(cat /sys/devices/omapdss/display0/enabled) clksetup=$($DM $CS 32) voltsetup2=$($DM 0x483072a0 32) core:$(cnt core) C1-7=$(cat /sys/devices/system/cpu/cpu0/cpuidle/state*/usage | tr '\n' /)"
}
present() { grep -q "PRESENT=1" /sys/class/power_supply/usb/uevent; }
cs0=$($DM $CS 32) armed0=$(cat $D/off_mode_armed) en0=$(cat $D/enable_off_mode) dis0=$(cat $D/disable_core_off)
MD=$(awk '$2 == "/mydocs" {print $1}' /proc/mounts)
back() {
	kill $W 2>/dev/null
	echo 0 > $D/off_mode_armed; echo $en0 > $D/enable_off_mode; echo $dis0 > $D/disable_core_off
	echo $armed0 > $D/off_mode_armed; $DM $CS 32 $cs0 >/dev/null
	blockdev --setrw $MD; st END; L "back as before: $1"
	dmesg | grep -av "command line" | grep -aiE "oops|bug|warn|prcm|twl|wkup|secure|I/O wakeup" |
		grep -av "oscsetup:\|ramoops" | tail -20 | while read -r l; do L "dmesg: $l"; done
	exit 0
}
# phase NAME CLKSETUP OFF(0/1)
phase() {
	$DM $CS 32 $2 >/dev/null
	if [ $3 = 1 ]; then
		echo 1 > $D/off_mode_armed; echo 1 > $D/enable_off_mode; echo 0 > $D/disable_core_off
	else
		echo 0 > $D/off_mode_armed
	fi
	st "$1 start"
	chroot /newroot /tmp/wakelat ${PHASE:-75} > $O/$1.txt & W=$!
	while kill -0 $W 2>/dev/null; do sleep 2; touch /tmp/stay; present && back "replugged in $1"; done
	st "$1 end"
}
blockdev --setro $MD
# root may ask mce to blank the display (ramboot/unlock.sh's policy, in the RAM overlay): unplugging
# lights it, and the broken power button can't turn it off
cat > /newroot/etc/dbus-1/system.d/zz-sgx-ramboot.conf <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><policy user="root"><allow send_destination="com.nokia.mce"/><allow send_destination="com.meego.usb_moded"/></policy></busconfig>
EOF
chroot /newroot dbus-send --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig
L "start: clksetup=$cs0 armed/enable/disable_core_off $armed0/$en0/$dis0"
while present; do sleep 1; touch /tmp/stay; done
L unplugged
sleep 5
chroot /newroot dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request \
	com.nokia.mce.request.req_display_state_off
sleep 15
phase A $cs0 0
phase B 0x148 0
phase C $cs0 1
phase D 0x148 1
back "all four phases"
