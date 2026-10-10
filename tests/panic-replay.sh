# tests/panic-replay.sh, on the test kernel (build/s.sh sh -s ROUNDS < tests/panic-replay.sh): boot 181's
# panic (a queued task_struct.rcu with a NULL callback, after DSP decodes ended mid-stream) replayed:
# per round a Main-profile 720 decode ended by gst-test's own timeout and one killed after 10 s, while
# short-lived processes keep exiting. Needs /newroot/tmp/gst-test and the clips in
# MyDocs/test-videos. Prints the kernel's debug-object and slub reports, if any.
rounds=${1:-3}
clip=/home/user/MyDocs/test-videos/PXL_20260924_122614565_MAIN_720.mp4
pipe="uridecodebin uri=file://$clip name=d d. ! video/x-raw-yuv ! identity name=out ! fakesink sync=false"
run() { chroot /newroot su - user -c "$*"; }
reports() { dmesg | grep -av "command line" | grep -aE "ODEBUG|BUG |Poison|Redzone|Object|INFO: |rcu_head|refcount|WARNING" | tail -20; }

dmesg -c > /dev/null
# exiting tasks: each one's task_struct goes through call_rcu(delayed_put_task_struct)
( while [ ! -e /tmp/replay.stop ]; do chroot /newroot /bin/true; done ) &
rm -f /tmp/replay.stop
for r in $(seq 1 $rounds); do
	echo "== round $r $(cut -d' ' -f1 /proc/uptime)"
	run "/tmp/gst-test '$pipe'" 2>&1 | grep -E "^EOS|^timeout|error|couldn"
	run "/tmp/gst-test '$pipe'" > /dev/null 2>&1 &
	sleep 10
	pkill -9 -f "gst-test.*MAIN_720" && echo "killed mid-decode"
	sleep 5
	reports
done
touch /tmp/replay.stop
wait
echo "== done $(cut -d' ' -f1 /proc/uptime)"
reports
dmesg | grep -av "command line" | grep -aiE "bridge|dsp|mmu" | tail -8
