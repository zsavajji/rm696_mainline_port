#!/bin/sh
# On the Mac: restart Harmattan's bluetoothd N times (default 10). With the phone's Bluetooth setting
# off it powers the adapter up and straight down, as at boot: the power-off that left UART2 active
# (boots 241, 244). Per restart: bluetoothd's own "HCI dev 0 up" -> "down" time from syslog (30 s =
# the tty close waiting for bytes CTS holds back) and UART2's runtime PM state and the CPU latency
# limit 3 s and 15 s after the "down".
S="$(dirname "$0")/../build/s.sh"
$S "N=${1:-10}"'
H="chroot /newroot"; U=/sys/bus/platform/devices/4806c000.serial/power; L=/newroot/var/log/syslog
st() { echo "$(cat $U/runtime_status)/$(od -An -td4 -N4 /dev/cpu_dma_latency | tr -d " ")"; }
sec() { LC_ALL=C grep -a "bluetoothd\[$1\]: HCI dev 0 $2" $L | tail -1 | awk "{split(\$3,t,\":\"); print t[1]*3600+t[2]*60+t[3]}"; }
i=0
while [ $i -lt $N ]; do
	i=$((i + 1))
	$H initctl stop xsession/bluetoothd >/dev/null 2>&1
	p=$($H initctl start xsession/bluetoothd 2>&1 | sed -n "s/.*process \([0-9]*\).*/\1/p")
	n=0; while [ $n -lt 60 ] && [ -z "$(sec $p down)" ]; do n=$((n + 1)); sleep 1; done
	sleep 3; a=$(st); sleep 12; b=$(st)
	u=$(sec $p up) d=$(sec $p down)
	echo "restart $i: up->down $([ -n "$u" -a -n "$d" ] && echo $((d - u)) || echo ?) s; UART2/latency +3 s $a, +15 s $b"
done'
