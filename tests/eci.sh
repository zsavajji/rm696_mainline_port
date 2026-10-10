#!/bin/sh
# On the Mac: the AV jack's buttons and ECI accessories on a test boot (HANDOFF-ECI.md). Read-only.
# Prints the driver's state, then the "ECI Accessory" key/switch events for N seconds (default 20)
# while I plug and press: "tests/eci.sh 30".
S="$(dirname "$0")/../build/s.sh"
$S "N=${1:-20}"'
echo "== probe"; dmesg | grep -i "ACI\|jack buttons\|AV jack\|ECI" | tail -20
echo "== irq"; grep twl5031_aci /proc/interrupts
echo "== input"; grep -B1 -A4 "ECI Accessory" /proc/bus/input/devices
ls -l /newroot/dev/input/eci /newroot/dev/input/accessory 2>&1
echo "== memory"; od -An -tx1 /sys/devices/platform/ECI_accessory.0/memory 2>&1
echo "== ohmd, qmkeyd (this boot)"; LC_ALL=C grep -a "(1970)" /newroot/var/log/syslog |
	grep -a "accessories:\|qmkeyd\|eci" | tail -15
E=$(grep -A4 "ECI Accessory" /proc/bus/input/devices | sed -n "s/.*Handlers=.*\(event[0-9]*\).*/\1/p")
[ -n "$E" ] || exit 0
echo "== $E events for $N s (type code value; 1 = key, 5 = switch)"
timeout $N chroot /newroot perl -e "open F, q(<), q(/dev/input/$E) or die; \$| = 1;
	while (sysread(F, \$b, 16) == 16) { (\$s, \$u, \$t, \$c, \$v) = unpack(q(LLSSl), \$b);
		printf qq(%d.%03d %d %d %d\n), \$s, \$u / 1000, \$t, \$c, \$v if \$t }"
echo "== after"; dmesg | grep -i "AV jack\|ECI" | tail -5; grep twl5031_aci /proc/interrupts'
