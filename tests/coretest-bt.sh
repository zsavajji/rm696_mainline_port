#!/bin/sh
# On the phone (ramboot shell, root; start it detached, then unplug USB): CORE retention with
# Bluetooth on (branch bt-idle). Bluetooth on with bluetoothd paused, the sleep indicator on (it blinks
# while CORE retains); unplugged, every 40 s: CORE's OFF/RET/INA/ON counts, C5 entries, UART2's runtime
# status, the CPU latency limit (display off through mce: needs ramboot's mce policy); an inquiry at +80 s (the chip waking the host from CORE idle), BT off
# at +160 s for comparison. Ends at the replug or after ~5 min. Read: dmesg | grep coretest-bt
L() { echo "coretest-bt: $*" > /dev/kmsg; }
H="chroot /newroot"; U=/sys/bus/platform/devices/4806c000.serial/power
st() { L "$1 up=$(cut -d' ' -f1 /proc/uptime) $(grep ^core_pwrdm /sys/kernel/debug/pm_debug/count | cut -d, -f2-5)" \
	"C5=$(cat /sys/devices/system/cpu/cpu0/cpuidle/state4/usage) UART2=$(cat $U/runtime_status)" \
	"lat=$(od -An -td4 -N4 /dev/cpu_dma_latency | tr -d ' ') hci0=$($H hciconfig hci0 | grep -ao 'UP RUNNING\|DOWN')"; }
present() { grep -q "PRESENT=1" /sys/class/power_supply/usb/uevent; }
B=$(pidof bluetoothd); kill -STOP $B
$H hciconfig hci0 up
echo 1 > /sys/class/leds/debug::sleep/brightness
st P0
while present; do sleep 1; done
L unplugged
# ramboot/unlock.sh's inhibit_blank_mode 3 makes mce ignore a display-off request, and a panel left on keeps
# CORE out (its 6 ms idle limit): normal blanking, locked, display off
$H gconftool-2 -s -t int /system/osso/dsm/display/inhibit_blank_mode 0
$H dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_tklock_mode_change string:locked
$H dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_display_state_off
sleep 5; st U0
n=0
while ! present && [ $n -lt 7 ]; do
	sleep 40; n=$((n + 1)); st U$n
	[ $n = 2 ] && { L "inquiry: $(timeout 25 $H hcitool inq --flush 2>&1 | grep -c 'clock offset') devices"; st U2i; }
	[ $n = 4 ] && { $H hciconfig hci0 down; L "BT off"; }
done
L "end"; st E; kill -CONT $B
