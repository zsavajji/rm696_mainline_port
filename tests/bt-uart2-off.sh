#!/bin/sh
# On the Mac: does UART2 (Bluetooth) idle once Bluetooth is off? Races HCI commands against the
# adapter's power-off N times (default 20), the way bluetoothd's boot-time up/down does, and reports
# slow power-offs (30 s = the tty close waiting for bytes CTS holds back) and UART2's runtime PM
# state and the CPU latency limit after each slow one and at the end (a leaked reference heals at the
# next power-on). Fixed: UART2 "suspended", latency 2000000000 (none);
# the bug: "active", 555. Pauses bluetoothd meanwhile (BT_GOTCHAS "Testing it").
S="$(dirname "$0")/../build/s.sh"
$S "N=${1:-20}"'
U=/sys/bus/platform/devices/4806c000.serial/power
H="chroot /newroot"
state() { echo "$1: UART2 $(cat $U/runtime_status) usage=$(cat $U/runtime_usage 2>/dev/null || echo ?)" \
	"latency=$(od -An -td4 -N4 /dev/cpu_dma_latency | tr -d " ")"; }
state before
B=$(pidof bluetoothd); [ -n "$B" ] && kill -STOP $B
trap "[ -n \"$B\" ] && kill -CONT $B" EXIT
slow=0 i=0
while [ $i -lt $N ]; do
	i=$((i + 1))
	timeout 20 $H hciconfig hci0 up || { echo "up $i failed"; continue; }
	for c in 1 2 3; do timeout 5 $H hcitool cmd 0x04 0x0009 >/dev/null 2>&1 & done
	t=$(date +%s); timeout 40 $H hciconfig hci0 down; d=$(($(date +%s) - t))
	[ $d -ge 5 ] && { slow=$((slow + 1)); sleep 2; state "down $i took ${d} s"; }
	wait
done
echo "$N cycles, $slow slow power-offs"
$H hciconfig hci0 | grep -a "UP\|DOWN\|errors"
sleep 2; state after'
