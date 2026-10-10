#!/bin/sh
# On the Mac: the test kernel's console, i.e. its kernel log followed (/dev/kmsg) over the RAM-boot
# ssh, reconnecting across reboots. The command line and init's environment carry the phone's IMEI
# and serial number: filtered out.
cd "$(dirname "$0")/.."
while :; do
	ssh -i build/ramboot-key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
		-o ServerAliveInterval=5 -o ServerAliveCountMax=2 -p $(nc -z -G 2 192.168.2.15 2222 2>/dev/null && echo 2222 || echo 22) root@192.168.2.15 'cat /dev/kmsg' |
		perl -ne 'BEGIN { $| = 1 }
			next if /command line:|\b(imei|serialnumber|dbi-uid|iSerialNumber)=/;
			printf "[%12.6f] %s\n", $2 / 1e6, $3 if /^(\d+),\d+,(\d+),[^;]*;(.*)/'
	echo "--- (no connection; retrying)"
	sleep 3
done
