#!/bin/sh
# Battery day log for the release image: runs in the rescue ramdisk (not Harmattan), one line a minute to
# MyDocs/.n9-logs/powerlog.txt, synced each minute so a reset or a flat battery loses at most a minute
# (cumulative counters; diff two lines for a period), the top CPU users every 10 min.
# Fields: up(s) core=ON/RET/OFF seconds core#=RET/OFF entries mpuoff# C5/C6/C7 picks, IRQ totals
# wkup/clk/mmc2/wl/i2c1, wlan=state/rx/tx packets/MHz, wlchip=awake/asleep s (wlcore only), bl=backlight usb=online vbat=mV,
# freq=s at 600/800/1000 MHz, bme=% / mAh left / battery current mA (bmestat). Start (rescue ssh, root):
#   setsid sh /newroot/home/user/MyDocs/n9-tests/powerlog.sh </dev/null >/dev/null 2>&1 &
# Stop: touch /tmp/powerlog.stop
# W=s: first wait for the cable to be unplugged, then W more seconds (to walk to the WLAN and join it);
# T=s: seconds between lines (default 60).
D=/sys/kernel/debug; grep -q " $D " /proc/mounts || mount -t debugfs none $D
[ -n "$W" ] && { while [ "$(cat /sys/class/power_supply/usb/present)" != 0 ]; do sleep 5; done; sleep $W; }
M=/newroot/home/user/MyDocs/.n9-logs; L=$M/powerlog.txt; mkdir -p $M; echo "== start $(date)" >> $L; rm -f /tmp/powerlog.stop; i=0
irq() { awk -v n="$1" '$NF == n {print $2}' /proc/interrupts; }
pw() { grep "^$1_pwrdm" $D/pm_debug/$2 | tr ',:' '  '; }
while [ ! -e /tmp/powerlog.stop ]; do
	set -- $(pw core time); ct="$((${10} / 1000000000))/$(($6 / 1000000000))/$(($4 / 1000000000))"
	set -- $(pw core count); cc="$6/$4"
	set -- $(pw mpu count); mo=$4
	n=/sys/class/net/wlan0; w=/sys/bus/platform/devices/wl12xx.2.auto/power
	c=/sys/devices/system/cpu/cpu0
	echo "$(cut -d' ' -f1 /proc/uptime) core=$ct core#=$cc mpuoff#=$mo C5-7=$(cat $c/cpuidle/state4/usage)/$(cat $c/cpuidle/state5/usage)/$(cat $c/cpuidle/state6/usage)" \
		"irq=$(irq pm_wkup)/$(irq clockevent)/$(irq mmc2)/$(irq wl12xx)$(irq wl1271)/$(irq 48070000.i2c)" \
		"wlan=$(cat $n/operstate 2>/dev/null)/$(cat $n/statistics/rx_packets 2>/dev/null)/$(cat $n/statistics/tx_packets 2>/dev/null)/$(chroot /newroot /usr/sbin/iw dev wlan0 link 2>/dev/null | awk '/freq/ {print $2}')" \
		"wlchip=$([ -e $w/runtime_active_time ] && echo $(($(cat $w/runtime_active_time) / 1000))/$(($(cat $w/runtime_suspended_time) / 1000)))" \
		"bl=$(cat /sys/class/backlight/*/brightness | head -1) usb=$(cat /sys/class/power_supply/usb/online 2>/dev/null)" \
		"vbat=$(cat /sys/bus/iio/devices/iio:device0/in_voltage12_input 2>/dev/null)" \
		"bme=$(chroot /newroot /usr/bin/bmestat 2>/dev/null | awk -F: '/pct. level|cur. capacity|battery current/ {gsub(/ /, "", $2); printf "%s/", $2}')" \
		"freq=$(awk '$1 >= 600000 && $1 <= 1000000 {printf "%d/", $2 / 100}' $c/cpufreq/stats/time_in_state)" >> $L
	[ $((i % 10)) = 0 ] && for p in /proc/[0-9]*; do
		s=$(cat $p/stat 2>/dev/null) || continue; n=${s#*(}; n=${n%%)*}; set -- ${s##*) }
		echo "$(((${12} + ${13}) / 100)) $n"
	done | sort -rn | head -6 | tr '\n' ',' | sed 's/^/  top: /;s/,$/\n/' >> $L
	sync
	i=$((i + 1)); sleep ${T:-60}
done
