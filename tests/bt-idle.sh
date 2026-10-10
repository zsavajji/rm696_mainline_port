#!/bin/sh
# On the Mac: Bluetooth and UART2 idle on a test boot (branch bt-idle). Pauses bluetoothd, then:
# UART2 with Bluetooth off and on (idle: "suspended", latency 2000000000 = no limit; 555 = UART2
# held), three inquiries at RTS delays 0 and 20 ms (the chip's own events through the wake path:
# UART2 resumed, then RTS), the loopback receive test, power-off races (tests/bt-downrace.pl), and
# the kernel log's runtime PM underflows, reassembly failures and command timeouts. Copies
# btloop.pl and bt-downrace.pl to the phone's /newroot/tmp. Counts only: no BD addresses printed.
cd "$(dirname "$0")"
S=../build/s.sh
$S 'cat > /newroot/tmp/btloop.pl' < btloop.pl && $S 'cat > /newroot/tmp/bt-downrace.pl' < bt-downrace.pl || exit 1
$S 'H="chroot /newroot"; P=/sys/module/hci_nokia/parameters/rts_delay_us; U=/sys/bus/platform/devices/4806c000.serial/power
st() { echo "$1: hci0 $($H hciconfig hci0 | grep -ao "UP RUNNING\|DOWN") UART2 $(cat $U/runtime_status) latency=$(od -An -td4 -N4 /dev/cpu_dma_latency | tr -d " ")"; }
idle() { a=$(cat $U/runtime_active_time) s=$(cat $U/runtime_suspended_time); sleep $2
	echo "$1, $2 s: UART2 active $(($(cat $U/runtime_active_time) - a)) ms, suspended $(($(cat $U/runtime_suspended_time) - s)) ms"; }
lg() { dmesg | grep -v "command line" | grep -c "$1"; }
u0=$(lg "usage count underflow") r0=$(lg "Frame reassembly") c0=$(lg "command .*tx timeout")
B=$(pidof bluetoothd); kill -STOP $B; trap "kill -CONT $B" EXIT
$H hciconfig hci0 down; sleep 2; st "BT off"; idle "BT off" 10
$H hciconfig hci0 up; sleep 3; st "BT on"; idle "BT on, quiet" 10
for d in 0 20000; do
	echo $d > $P
	for k in 1 2 3; do echo "rts_delay_us=$d inquiry $k: $(timeout 25 $H hcitool inq --flush 2>&1 | grep -c "clock offset") devices"; done
done
echo 0 > $P
$H hciconfig hci0 | grep -a errors
$H hciconfig hci0 down; echo "btloop: $($H perl /tmp/btloop.pl 15 2>&1 | grep -a "sent")"
echo "power-off races: $($H perl /tmp/bt-downrace.pl 10 20 | tail -1)"
sleep 3; st "after"
echo "kernel log: $(($(lg "usage count underflow") - u0)) rpm underflows, $(($(lg "Frame reassembly") - r0)) reassembly failures, $(($(lg "command .*tx timeout") - c0)) command timeouts"'
