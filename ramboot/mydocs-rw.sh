#!/bin/sh
# On a test boot (initramfs side, detached: `setsid sh mydocs-rw.sh > /tmp/mydocs-rw.log 2>&1 &`):
# MyDocs read-write on the computer over USB mass storage, unmounted on the phone meanwhile (the log
# writer's remount then fails and it skips its write). Back as the init has it (read-only for
# Harmattan, the SSH gadget, which the init's loop rebinds once the gadget is gone) after the computer
# ejects it (macOS's eject doesn't reach the gadget), the cable is unplugged, or after SECONDS (the first
# argument, 1800). This writes the eMMC: only on my ask.
secs=${1:-1800}
d=/dev/mmcblk0p1 g=/sys/kernel/config/usb_gadget/n9 h=/newroot/home/user/MyDocs
log() { echo "$(date +%T) $*"; }
mydocs_ro() {
	mountpoint -q /mydocs || mount -t vfat -o ro,nodev,noexec,nosuid,noatime,nodiratime,utf8,uid=29999,shortname=mixed,dmask=000,fmask=0133,rodir $d /mydocs
	umount $h 2>/dev/null	# an empty bind the init's loop may have made meanwhile
	mount --bind /mydocs $h && mount -o remount,bind,ro $h
}

sync
umount $h || { log "Harmattan's MyDocs busy: not exported"; exit 1; }
# (busy for a moment while the init's log writer writes to it)
for i in 1 2 3 4 5 6 7 8 9 10; do umount /mydocs 2>/dev/null && break; sleep 1; done
mountpoint -q /mydocs && { log "/mydocs busy: not exported"; mydocs_ro; exit 1; }
grep -q "^$d " /proc/mounts && { log "$d still mounted: not exported"; mydocs_ro; exit 1; }
# the init's loop gives the port back to SSH unless usb_moded's flag is fresh or a gadget is loaded
touch /newroot/tmp/.ramboot-usb-legacy
echo > $g/UDC
insmod /lib/modules/usb/g_file_storage.ko file=$d ro=0 removable=1 stall=0 luns=1 ||
	{ log "insmod failed"; mydocs_ro; exit 1; }
lun=$(find /sys/devices -path '*gadget*/lun0/file' | head -1)
log "exported $d read-write ($lun)"

t=0
while sleep 2; do
	t=$((t + 2))
	f=; read f < $lun
	[ -z "$f" ] && { log "ejected by the computer"; break; }
	[ "$(cat /sys/class/power_supply/usb/present)" = 0 ] && { log "unplugged"; break; }
	[ $t -ge $secs ] && { log "$secs s: ending the export"; break; }
done
rmmod g_file_storage
sync
mydocs_ro && log "MyDocs read-only again for Harmattan"
grep "^$d " /proc/mounts | cut -d' ' -f2,4 | cut -c1-40
