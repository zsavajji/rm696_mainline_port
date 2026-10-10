#!/bin/sh
# bb5-test.sh: on the RAM-booted phone, run ramboot/bb5-test.pl in Harmattan's root against Nokia's
# secure-environment driver (built in, kernel/n9.config). Only the KCI number is read from the command
# line (it also carries the phone's IMEI and serial).
cd "$(dirname "$0")/.."
SSH="ssh -i build/ramboot-key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 -p $(nc -z -G 2 192.168.2.15 2222 2>/dev/null && echo 2222 || echo 22) root@192.168.2.15"
$SSH 'cat > /newroot/tmp/bb5-test.pl' < ramboot/bb5-test.pl || exit 1
$SSH '
touch /tmp/stay
kci=$(sed -n "s/.*omap_sec\.kci=\([0-9]*\).*/\1/p" /proc/cmdline)
echo "KCI: $kci"
dmesg | grep -iE "omap_sec|omap_hs|secure|resource counter|PA |sec_hal" | grep -viE "command line|imei|serialnumber|dbi-uid" | tail -n 15
ls -l /dev/omap_sec && chroot /newroot perl /tmp/bb5-test.pl'
