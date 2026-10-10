#!/bin/bash
# tests/glesbench-stock.sh: the GLES benchmark on stock Harmattan (ssh n9, as user, writes only the
# phone's /tmp), for comparing with the same binary on the test kernel (run there with
# `chroot /newroot su - user -c 'DISPLAY=:0 /tmp/glesbench ...'`). Two things decide the numbers and
# are printed with them:
# - the lock state: with the touch lock on (or the display off) the window is not composited and swaps
#   are unthrottled (fps about doubles): the CPU-side comparison. Unlocked + display on = the real
#   case, vsync-bound. I unlock stock's screen; this script keeps the display on via mce.
# - the environment: Harmattan's session (/etc/profile -> aegis-session) sets
#   MALLOC_MMAP_THRESHOLD_=32768 MALLOC_TRIM_THRESHOLD_=8192, so every malloc >= 32 KiB is an
#   mmap+faults+munmap (the GL blob's texture staging: 65 faults per 256 KiB upload). A plain ssh
#   command lacks it, `su - user` on the test kernel has it. Both variants are run here.
# Output to build/glesbench-stock.txt.
cd "$(dirname "$0")/.."
ENV="MALLOC_MMAP_THRESHOLD_=32768 MALLOC_TRIM_THRESHOLD_=8192"
on() { ssh n9 'dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_display_state_on' 2>/dev/null; }
state() { ssh n9 'for q in get_tklock_mode get_display_status; do dbus-send --system --print-reply --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.$q | tail -1 | tr -d " "; done' | tr '\n' ' '; }
scp -q build/glesbench n9:/tmp/glesbench || exit 1
{
	ssh n9 'uname -r; cat /proc/loadavg'
	for m in "fill 1" "fill 20" "draws 200" "tex 8 256" "swap"; do
		on
		echo "[$(state)] env: $(ssh n9 "env -i $ENV DISPLAY=:0 /tmp/glesbench $m 2>&1 | tail -1")"
	done
	on
	echo "[$(state)] no env: $(ssh n9 "env -i DISPLAY=:0 /tmp/glesbench tex 8 256 2>&1 | tail -1")"
} | tee build/glesbench-stock.txt
ssh n9 'rm -f /tmp/glesbench'
