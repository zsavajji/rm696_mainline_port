#!/bin/sh
# On the phone, as root, BEFORE rebooting a stuck phone:  devel-su -c 'sh /home/user/MyDocs/save-phone-logs.sh'
# Writes /home/user/MyDocs/n9-logs/<date>.txt: kernel log, what every process is waiting on, camera/DSP/LED/
# thermal state, syslog tail. Identifier lines (IMEI, serial, command line...) are dropped.
D=/home/user/MyDocs/n9-logs; mkdir -p $D
F=$D/$(date +%Y%m%d-%H%M%S).txt
{
echo "== $(date) $(uname -a)"; uptime; cat /proc/loadavg
echo "== dmesg"; dmesg
echo "== process states (D = stuck in the kernel) and what they wait on"
for p in /proc/[0-9]*; do
  s=$(sed -n 's/^State:[[:space:]]*//p' $p/status 2>/dev/null); n=$(tr '\0' ' ' < $p/cmdline 2>/dev/null | cut -c1-60)
  case "$s" in R*|D*) echo "${p#/proc/} [$s] $n wchan=$(cat $p/wchan 2>/dev/null)"; cat $p/stack 2>/dev/null;; esac
done
echo "== camera/dsp processes"
for p in $(pidof camera-ui dsp-bridged dspbridged mmc_dsp 2>/dev/null) $(pgrep -f 'gst|camera|dsp' 2>/dev/null); do
  echo "-- $p $(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-80) wchan=$(cat /proc/$p/wchan 2>/dev/null)"; cat /proc/$p/stack 2>/dev/null; ls -l /proc/$p/fd 2>/dev/null | grep -a "video\|media\|dsp\|v4l"
done
echo "== top"; top -b -n 1 | head -25
echo "== interrupts"; cat /proc/interrupts
echo "== leds"; for l in /sys/class/leds/*; do echo "$l $(cat $l/brightness 2>/dev/null)"; done
echo "== power_supply"; for p in /sys/class/power_supply/*; do echo "-- $p"; grep -a "" $p/uevent 2>/dev/null; done
echo "== thermal / hwmon"; grep -a "" /sys/class/thermal/*/temp /sys/class/hwmon/*/temp* 2>/dev/null
echo "== media/v4l"; ls -l /dev/video* /dev/media* 2>/dev/null; cat /proc/meminfo | head -5
echo "== pstore"; ls -l /sys/fs/pstore 2>/dev/null
echo "== syslog (tail)"; tail -n 400 /var/log/syslog 2>/dev/null
} 2>&1 | grep -aiv "command line\|imei\|imsi\|serial\|iccid\|dbi-uid" > $F
sync; echo "saved $F ($(wc -l < $F) lines); copy it off, then reboot"
