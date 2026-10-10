#!/bin/sh
# On the Mac: a health report of a Harmattan test boot, over the RAM-boot ssh (also keeps the session
# alive). No identifiers: nothing from the kernel command line.
cd "$(dirname "$0")/.."
ssh -i build/ramboot-key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null \
	-o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=15 -p $(nc -z -G 2 192.168.2.15 2222 2>/dev/null && echo 2222 || echo 22) root@192.168.2.15 '
touch /tmp/stay
echo "== uptime: $(cat /proc/uptime | cut -d" " -f1) s, load $(cut -d" " -f1-3 /proc/loadavg)"
c=/sys/devices/system/cpu/cpu0/cpufreq
if [ -d $c ]; then
	echo "== cpufreq: $(cat $c/scaling_governor), now $(cat $c/scaling_cur_freq) kHz, $(cat $c/scaling_min_freq)-$(cat $c/scaling_max_freq)"
	echo "   available: $(cat $c/scaling_available_frequencies)"
	echo "   time in state (10 ms):"; sed "s/^/     /" $c/stats/time_in_state 2>/dev/null
else
	echo "== cpufreq: none"
fi
mount -t debugfs none /sys/kernel/debug 2>/dev/null
grep -E "^ *(dpll1_ck|dpll3_ck|core_ck|l3_ick|sgx_fck|dss1_alwon_fck|mpu_ck) " /sys/kernel/debug/clk/clk_summary 2>/dev/null |
	awk "{print \"== clk \" \$1 \": \" \$5/1000000 \" MHz\"}"
for r in /sys/class/regulator/*; do
	[ "$(cat $r/name 2>/dev/null)" = "VDD1" -o "$(cat $r/name 2>/dev/null)" = "abb_mpu_iva" ] &&
		echo "== $(cat $r/name): $(cat $r/microvolts 2>/dev/null) uV"
done
echo "== swap: $(tail -n +2 /proc/swaps | tr -s " " | cut -d" " -f1,3,4 | tr "\n" ";")"
echo "== memory: $(grep -E "MemTotal|MemAvailable" /proc/meminfo | tr -s " " | tr "\n" " ")"
echo "== syspart: $(grep -c syspart /proc/mounts) mount(s)"
echo "== time: $(date -u), rtc: $(cat /sys/class/rtc/rtc0/date 2>/dev/null) $(cat /sys/class/rtc/rtc0/time 2>/dev/null)"
for p in usb vac; do
	[ -d /sys/class/power_supply/$p ] && echo "== power_supply $p: $(tr "\n" " " < /sys/class/power_supply/$p/uevent)"
done
grep -a "bme:" /newroot/var/log/syslog 2>/dev/null | grep -aE "Battery level|harg|vbat" | tail -3 | sed "s/^/== /"
P=$(dirname $(find /sys/devices -name split_timing 2>/dev/null | head -1) 2>/dev/null)
[ -n "$P" ] && echo "== panel: $(cat $P/split_timing), reverse $(cat $P/split_reverse), mid $(cat $P/split_mid_us)"
echo "== wlan: $(ls /sys/class/net | grep -v -e lo -e sit0 -e usb0 | tr "\n" " ")$(lsmod | grep -c "^wl12xx") module(s)"
echo "== input: $(grep -h "^N:" /proc/bus/input/devices | cut -d\" -f2 | tr "\n" ",")"
echo "== errors:"; dmesg | grep -iE "split update|TE not received|DSI error|APPLY error|oops|BUG:|WARNING:|twl5031_bcc|cpufreq|ti-cpufreq|opp|vdd_|TRANXDONE|wl1271|wlcore|mmc2" |
	grep -v "command line" | tail -12 | sed "s/^/   /"
'
