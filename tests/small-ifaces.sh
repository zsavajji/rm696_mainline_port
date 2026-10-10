#!/bin/sh
# On the Mac: check the small interfaces Harmattan reads (UNPORTED.md "Small interfaces") on a test
# boot. Read-only.
S="$(dirname "$0")/../build/s.sh"
$S 'R=/sys/class/i2c-adapter
echo "== keypad: $(readlink -f $R/i2c-1/1-004a/twl4030_keypad) disable_kp=$(cat $R/i2c-1/1-004a/twl4030_keypad/disable_kp)"
echo "== vbus: $(cat $R/i2c-1/1-0048/twl4030_usb/vbus)"
echo "== hw_revision: $(cat /sys/devices/omapdss/display0/hw_revision)"
T=$R/i2c-2/2-004b
for f in firmware_version config_crc nv_config_crc disable_ts wait_for_gesture; do echo "$f: $(cat $T/$f)"; done
echo "== mxt_configure_log"; cat /newroot/tmp/mxt_configure_log.txt
echo "== mce open sysfs files"; ls -l /proc/$(pidof mce)/fd | grep -a /sys/ | sed "s/.*-> //"
echo "== syslog (this boot)"; LC_ALL=C grep -a "(1970)" /newroot/var/log/syslog | grep -av "command line" |
	grep -a "hw_revision\|disable_kp\|twl4030_usb\|mxt\|nf_condition" | tail
echo "== dmesg"; dmesg | grep -v "command line" | grep -i "keypad\|twl4030_usb\|omapdss\|atmel\|mxt\|condition" | tail'
