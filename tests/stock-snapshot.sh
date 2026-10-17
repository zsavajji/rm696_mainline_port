#!/bin/sh
# On the Mac, read-only over `ssh n9` (stock): one line of cumulative idle counters, appended to build/stock-snapshots.txt.
# Same fields as tests/powerlog.sh where stock has them: uptime, CORE ON/RET/OFF seconds, CORE RET/OFF entries,
# MPU OFF entries, wake IRQ totals, WLAN packets, battery. Take one right after boot and one at the end of the day.
cd "$(dirname "$0")/.."
ssh -o ConnectTimeout=10 n9 '
D=/sys/kernel/debug/pm_debug; [ -r $D/time ] || { echo "no $D (debugfs not mounted: ask the user)"; exit 1; }
pw() { grep "^$1_pwrdm" $D/$2 | tr ",:" "  "; }
ct=$(pw core time | awk "{printf \"%d/%d/%d (ina %d)\", \$10 / 1e9, \$6 / 1e9, \$4 / 1e9, \$8 / 1e9}") # ns overflow ash
set -- $(pw core count); cc="$6/$4"; set -- $(pw mpu count); mo=$4
n=/sys/class/net/wlan0
echo "$(date +%T) up=$(cut -d" " -f1 /proc/uptime) core=$ct core#=$cc mpuoff#=$mo" \
 "wlan=$(cat $n/operstate 2>/dev/null)/$(cat $n/statistics/rx_packets 2>/dev/null)/$(cat $n/statistics/tx_packets 2>/dev/null)" \
 "usb=$(cat /sys/class/power_supply/usb/online 2>/dev/null) bat=$(/usr/bin/bmestat | awk -F: "/pct. level|cur. capacity|battery current/ {gsub(/ /, \"\", \$2); printf \"%s/\", \$2}")"
grep -aE "^ *[0-9]+:.* (gp.?timer|i2c|mmc|wl12xx|twl4030|pm_wkup|musb)" /proc/interrupts | awk "{s=0; for(i=2;i<=NF&&\$i ~ /^[0-9]+\$/;i++) s+=\$i; print \"  irq\", \$NF, s}"
' 2>&1 | tee -a build/stock-snapshots.txt
