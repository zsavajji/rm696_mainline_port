# tests/dsp/recovery.sh: DSP crashes and the bridge's recovery on the test kernel (root, from the
# initramfs shell: build/s.sh sh -s < tests/dsp/recovery.sh), each followed by a normal decode; then
# the bridge and mailbox messages since the start. The two crashes of boot 158 (README "DSP open
# points closed"), after one of which the mailbox queue to the DSP was full for ~25 s:
#  - a DSP MMU fault: IOCTL_UNMAP=3 (tests/ioctl-log.c) unmaps a frame buffer right after it's mapped;
#  - a DSP watchdog (WDT3) overflow: the DSP MMU's table walk switched off mid-decode, only while
#    PM_PWSTST_IVA2 reads ON in the same command (an access to an IVA2 that is off is an L3 timeout,
#    a panic, a reset into stock).
# Needs in /newroot/tmp: gst-test, ioctl-log.so, devmem (build/), t720b.mp4 (tests/dsp/dspref.sh).
rounds=${1:-2}
P="uridecodebin uri=file:///tmp/t720b.mp4 name=d d. ! video/x-raw-yuv ! identity name=out ! fakesink sync=false"
run() { chroot /newroot su - user -c "$*"; }
dm() { chroot /newroot /tmp/devmem "$@"; }
decode() { run "$1 /tmp/gst-test '$P'" 2>&1 | grep -E "^EOS|buffers|error|IOCTL_UNMAP" | tr '\n' ' '; echo; }
echo "recovery.sh: start" > /dev/kmsg
i=0
while [ $i -lt $rounds ]; do
	i=$((i + 1))
	echo "== $i: MMU fault"
	decode "IOCTL_UNMAP=3 LD_PRELOAD=/tmp/ioctl-log.so"
	sleep 3
	echo "-- next decode"
	decode ""
	echo "-- and the next"
	decode ""
	echo "== $i: WDT3 overflow"
	run "/tmp/gst-test '$P'" > /dev/null 2>&1 &
	n=0
	while [ $n -lt 25 ]; do
		sleep 0.2; n=$((n + 1))
		if [ $(( $(dm 0x483060E4) & 3 )) = 3 ]; then dm 0x5D000044 32 0x2; dm 0x5D000060 32 0x1; echo "table walk off"; break; fi
	done
	[ $n -lt 25 ] || echo "IVA2 not on in 5 s: skipped"
	sleep 15
	killall gst-test 2>/dev/null
	wait
	sleep 3
	echo "-- next decode"
	decode ""
done
echo "== messages since the start"
dmesg | grep -v 'command line' | sed -n '/recovery.sh: start/,$p' |
	grep -E "bridge|dsp|DSP|mbox|MBOX|mailbox|board state|DEH|recover|handle" | tail -60
