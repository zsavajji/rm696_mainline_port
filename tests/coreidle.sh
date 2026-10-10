#!/bin/sh
# CORE idle vs the USB cable, read-only: a line every ${S:-5} s to /tmp/coreidle.txt, ${N:-360} lines or
# until /tmp/coreidle.stop. core/usbhost = pm_debug OFF,RET,INA counts (usbhost moves only when
# omap_sram_idle() lets CORE try to sleep); otg/musb/twl = runtime status + active s;
# cm = CM_FCLKEN1/3_CORE, ICLKEN1_CORE (bit 4 hsotgusb), IDLEST1_CORE (bit 4 OTG standby, 5 OTG idle),
# ICLKEN_WKUP, IDLEST_WKUP. Start: setsid sh /tmp/coreidle.sh </dev/null >/dev/null 2>&1 &
D=/sys/kernel/debug; grep -q " $D " /proc/mounts || mount -t debugfs none $D
P=/sys/bus/platform/devices L=/tmp/coreidle.txt i=0
rm -f /tmp/coreidle.stop
cnt() { grep "^$1_pwrdm" $D/pm_debug/count | cut -d, -f2-4 | tr -d 'OFRETINA:'; }
rpm() { echo "$(cut -c1-3 $P/$1/power/runtime_status)$(($(cat $P/$1/power/runtime_active_time) / 1000))"; }
while [ ! -e /tmp/coreidle.stop ] && [ $i -lt ${N:-360} ]; do
	echo "$(cut -d' ' -f1 /proc/uptime) vbus=$(cat $P/twl4030_usb/vbus) bl=$(cat /sys/class/backlight/*/brightness | head -1)" \
		"core=$(cnt core) usbhost=$(cnt usbhost) C5=$(cat /sys/devices/system/cpu/cpu0/cpuidle/state4/usage)" \
		"otg=$(rpm 480ab400.target-module) musb=$(rpm musb-hdrc.0.auto) twl=$(rpm twl4030_usb)" \
		"cm=$(/tmp/devmem-ro 0x48004a00 0x48004a08 0x48004a10 0x48004a20 0x48004c10 0x48004c20 | cut -d' ' -f2 | tr '\n' ' ')" \
		"l3=$(sed 's/.*holds //' $D/omap3_l3)" >> $L
	i=$((i + 1))
	sleep ${S:-5}
done
