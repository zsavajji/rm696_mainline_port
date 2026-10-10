#!/bin/sh
# Runs ON THE PHONE (test boot), fed from the Mac: build/s.sh 'sh -s MODE N [ARG]' < tests/bt-baud.sh
# Wake-heavy Bluetooth receive tests at the current ti_baud (HANDOFF-BT-BAUD.md): the chip sleeps and
# wakes again and again; prints the receive-error counters before and after. Counts only: no BD
# addresses or received data printed. bluetoothd is paused (SIGSTOP) for the run.
#   cmd N        N HCI commands (Read Local Version), 0.5-2 s apart (host wakes the chip)
#   inq N        N inquiries of 8 s (the chip's own events, it wakes the host)
#   pc N         N power cycles (hciconfig down/up)
#   loop S GAP   loopback (btloop.pl in /newroot/tmp) for S s, window 1, up to GAP s between packets
#   name N ADDR  N remote name requests to ADDR (paging, radio traffic), 0.5-2 s apart
#   sdp N ADDR   N SDP browses of ADDR (ACL data from the radio)
#   baud RATE    ti_baud=RATE, then a power cycle
#   cnt          the counters only
#   kp on|off    kprobes: every received byte (LSR, char), the wake IRQ and its handler, RTS (tiocm,
#                mctrl), runtime PM of UART2 and the serdev device, transmissions; the trace holds
#                received data (BD addresses): copy it off only to analyse it, never print it
H="chroot /newroot"
cnt() {
	e=$($H hciconfig hci0 | grep -ao "RX bytes.*errors:[0-9]*" | grep -o "errors:[0-9]*")
	u=$(grep -a "mmio:0x4806C000" /proc/tty/driver/serial | grep -o "fe:[0-9]*\|pe:[0-9]*\|brk:[0-9]*\|oe:[0-9]*" | tr "\n" " ")
	r=$(dmesg | grep -av "command line" | grep -ac "Frame reassembly")
	t=$(dmesg | grep -av "command line" | grep -ac "tx timeout\|unknown connection handle")
	w=$(grep -a "^183:" /proc/interrupts | awk '{print $2}')
	echo "$1: baud $(cat /sys/module/hci_nokia/parameters/ti_baud) rx $e uart [$u] reassembly $r timeouts/unknown $t wakeirq $w"
}
rs() { $H perl -e 'select(undef, undef, undef, 0.5 + rand 1.5)'; }
B=$(pidof bluetoothd)
[ -n "$B" ] && kill -STOP $B && trap "kill -CONT $B" EXIT
$H hciconfig hci0 up	# with the phone's Bluetooth setting off, bluetoothd powers it off between runs
m=$1 n=$2 a=$3
cnt before
case $m in
cmd)	for i in $(seq $n); do $H hcitool cmd 0x04 0x0001 >/dev/null || echo "cmd $i failed"; rs; done ;;
inq)	for i in $(seq $n); do echo "inquiry $i: $(timeout 25 $H hcitool inq --flush 2>&1 | grep -c "clock offset") devices"; done ;;
pc)	for i in $(seq $n); do $H hciconfig hci0 down; $H hciconfig hci0 up || echo "up $i failed"; sleep 2; done ;;
loop)	$H hciconfig hci0 down; GAP=$a $H perl /tmp/btloop.pl $n 1 | grep -av "^ACL\|events:"; $H hciconfig hci0 up ;;
name)	for i in $(seq $n); do timeout 10 $H hcitool name $a >/dev/null || echo "name $i failed"; rs; done ;;
sdp)	for i in $(seq $n); do timeout 20 $H sdptool browse --l2cap $a 2>&1 | grep -c "Service RecHandle" | sed "s/^/sdp $i: records /"; done ;;
kp)	grep -q " /sys/kernel/tracing " /proc/mounts || mount -t tracefs nodev /sys/kernel/tracing
	cd /sys/kernel/tracing || exit 1
	echo 0 > tracing_on; echo 0 > events/enable; echo > trace; echo > kprobe_events
	[ "$n" = on ] || exit 0
	for k in "rd serial8250_read_char lsr=%r1:x16" "ins uart_insert_char st=%r1:x16 ch=%r3:x8" \
		"wk wakeup_handler" "nrr nokia_bluetooth_runtime_resume" "nrs nokia_bluetooth_runtime_suspend" \
		"tiocm serdev_device_set_tiocm set=%r1:x32 clr=%r2:x32" "omr omap8250_runtime_resume" \
		"oms omap8250_runtime_suspend" "mctrl __omap8250_set_mctrl mctrl=%r1:x32" "txrel nokia_tx_release" \
		"deq nokia_dequeue" "nr nokia_recv n=%r2:u32 b0=+0(%r1):x8" "su nokia_setup" \
		"sd nokia_shutdown" "hc nokia_hci_close"; do
		echo "p:$k" >> kprobe_events && echo 1 > events/kprobes/${k%% *}/enable
	done
	echo "irq==89 || irq==183" > events/irq/irq_handler_entry/filter
	echo 1 > events/irq/irq_handler_entry/enable
	echo 16384 > buffer_size_kb; echo 1 > tracing_on; exit 0 ;;
baud)	echo $n > /sys/module/hci_nokia/parameters/ti_baud; $H hciconfig hci0 down; $H hciconfig hci0 up; sleep 2 ;;
esac
cnt after
