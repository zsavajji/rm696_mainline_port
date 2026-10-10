#!/bin/sh
# On the Mac: a test boot's check of stock Harmattan on this kernel (memory and swap, the safety switches,
# modules, MyDocs, WLAN, Bluetooth, cameras, audio sysfs, daemons). Usage: ramboot/stockcheck.sh [MIN_UPTIME_S]
cd "$(dirname "$0")/.."
until [ "$(build/s.sh 'cut -d. -f1 /proc/uptime' 2>/dev/null)" -ge "${1:-0}" ] 2>/dev/null; do sleep 5; done
build/s.sh '
cat /proc/uptime; uname -r
echo "== memory"; grep -a "MemTotal\|SwapTotal" /proc/meminfo; grep -a "System RAM" /proc/iomem
dmesg | grep -av "command line" | grep -a "Memory: \|Ignoring RAM\|reserved mem"
echo "== switches (wd0 wd1 halt ro)"; cat /sys/class/watchdog/watchdog0/nowayout /sys/class/watchdog/watchdog1/nowayout /sys/module/twl4030_power/parameters/poweroff_halt /sys/module/onenand_omap2/parameters/read_only | tr "\n" " "; echo
echo "== modules"; cut -d" " -f1 /proc/modules | tr "\n" " "; echo
echo "== swap"; cat /proc/swaps
echo "== MyDocs"; grep -a "MyDocs" /proc/mounts | cut -d" " -f1-3
echo "== fw path"; cat /sys/module/firmware_class/parameters/path; echo
echo "== net"; ip -o addr 2>/dev/null | grep -a "wlan0\|usb0" | cut -d" " -f2,7
echo "== bt"; ls /sys/class/bluetooth/ 2>&1 | tr "\n" " "; echo
echo "== video"; ls /dev/video* 2>&1 | tr "\n" " "; echo
echo "== audio"; cat /sys/devices/platform/omap-mcbsp.2/max_tx_thres /sys/devices/platform/soc-audio.0/pmdown_time | tr "\n" " "; echo
echo "== wl1271"; cat /sys/devices/platform/wl1271/allow_adhoc
echo "== daemons"; ps | grep -a "sshd\|dsme \|Xorg\|mcompositor\|bluetoothd" | grep -v grep | cut -c1-80
echo "== dmesg errors"; dmesg | grep -av "command line" | grep -aiE "firmware|ti1273|smiapp|ramzswap|error|fail|oops|bug" | grep -av "correctable ECC" | tail -20
' 2>&1 | grep -aiv "imei\|imsi\|serial\|iccid\|dbi-uid" | sed -E "s/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/xx:xx:xx:xx:xx:xx/g"
