#!/bin/sh
# On the Mac: arm 0xFFFF with a copy of the last build or of the image given (a new build can't change what's loading),
# visibly, in its own terminal window. Connect the phone (or reboot it) to load the test kernel.
cd "$(dirname "$0")/.."
cp "${1:-build/zImage-n9}" build/zImage-n9-boot
echo "--- armed $(date +%T)" >> build/arm.log
# A 0xFFFF started before NOLO is on USB doesn't see it on this Mac (it waits forever, and the phone
# boots stock: 2026-10-04), and one started while the phone is up in one of stock's USB modes (mass
# storage 0x518, SDK...: 0x0421:0x05xx) gives up ("No device detected"): always wait for NOLO itself
# (a Nokia device in none of those modes) first, then 0xFFFF finds it at once
nokia_ids() { ioreg -p IOUSB -l -w0 | awk '/\+-o /{if (v == 1057) print p; v = p = ""}
	/"idProduct" = /{p = $NF} /"idVendor" = /{v = $NF} END{if (v == 1057) print p}'; }
while :; do
	echo "--- waiting for NOLO (reboot the phone)"
	until nokia_ids | grep -qvE '^13(0[0-9]|1[01])$'; do sleep 0.1; done
	out=$(build/0xFFFF -m kernel:build/zImage-n9-boot -l -b 2>&1 | tee /dev/tty | sed -E 's/(serial number string: ).*/\1<redacted>/' | tee -a build/arm.log)
	case "$out" in *"No device detected"*) ;; *) break ;; esac
done
echo "--- 0xFFFF exited; this window closes in 60 s (return closes it now)"
read -t 60 x
