#!/bin/sh
# tests/msc-ramdisk.sh, on the test kernel, initramfs side, detached (it takes the USB port from SSH):
#   build/s.sh 'cat > /tmp/msc-ramdisk.sh' < tests/msc-ramdisk.sh
#   build/s.sh 'setsid sh /tmp/msc-ramdisk.sh [SECONDS [MB]] > /tmp/msc.log 2>&1 < /dev/null & echo started'
# USB mass storage read-write on a FAT image in RAM (nothing reaches the eMMC), with musb's tracepoints
# on. Copy a file onto it from the computer, then eject it: the SSH gadget comes back (the init's loop),
# and /tmp/msc-trace.txt has the trace. Also ends on unplug or after SECONDS (300; macOS's eject sends
# no SCSI eject, so from a Mac it ends there). MB: the image's size (48).
secs=${1:-300} mb=${2:-48}
img=/tmp/msc.img g=/sys/kernel/config/usb_gadget/n9 T=/sys/kernel/debug/tracing
log() { echo "$(date +%T) $*"; }

rm -f $img /tmp/msc-trace.txt
dd if=/dev/zero of=$img bs=1M count=$mb 2>/dev/null && mkfs.vfat -n RAMDISK $img >/dev/null ||
	{ log "no image"; exit 1; }

echo 0 > $T/tracing_on
echo > $T/trace
echo 16384 > $T/buffer_size_kb
echo 0 > $T/options/overwrite	# keep the first events: the first failure
for e in musb_log musb_isr musb_req_enq musb_req_deq musb_req_start musb_req_rx musb_req_gb; do
	echo 1 > $T/events/musb/$e/enable
done
echo 1 > $T/tracing_on

# the init's loop gives the port back to SSH unless usb_moded's flag is fresh or a gadget is loaded
touch /newroot/tmp/.ramboot-usb-legacy
echo > $g/UDC
insmod /lib/modules/usb/g_file_storage.ko file=$img ro=0 removable=1 stall=0 luns=1 ||
	{ log "insmod failed"; exit 1; }
lun=$(find /sys/devices -path '*gadget*/lun0/file' | head -1)
log "exported $img read-write"

t=0
while sleep 2; do
	t=$((t + 2))
	f=; read f < $lun
	[ -z "$f" ] && { log "ejected by the computer"; break; }
	[ "$(cat /sys/class/power_supply/usb/present)" = 0 ] && { log "unplugged"; break; }
	[ $t -ge $secs ] && { log "$secs s: ending the export"; break; }
done
echo 0 > $T/tracing_on
rmmod g_file_storage
cat $T/trace > /tmp/msc-trace.txt
for e in $T/events/musb/*/enable; do echo 0 > $e; done
echo 1 > $T/options/overwrite
echo 1408 > $T/buffer_size_kb
log "trace: $(wc -l < /tmp/msc-trace.txt) lines"
