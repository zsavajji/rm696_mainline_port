# On the RAM-booted phone: load the DSP bridge, put kprobes on its ioctl/wake/map/write paths and
# start one gst-dsp decode at once (before the DSP's 5 s idle hibernation). Read trace_pipe meanwhile.
T=/sys/kernel/tracing
mount -t tracefs nodev $T 2>/dev/null
echo 1 > $T/tracing_on
chroot /newroot modprobe bridgedriver
for p in "rcv mbox_chan_received_data msg=%r1:x32" "snd mbox_send_message msg=%r1:x32" \
	"ioctl api_call_dev_ioctl cmd=%r0:x32" "wake wake_dsp" "hib handle_hibernation_from_dsp" \
	"map bridge_brd_mem_map mpu=%r1:x32 da=%r2:x32 n=%r3:x32" "unmap bridge_brd_mem_un_map da=%r1:x32 n=%r2:x32" \
	"wr bridge_brd_mem_write da=%r2:x32 n=%r3:x32" "wrint write_dsp_data da=%r2:x32 n=%r3:x32" \
	"wrext write_ext_dsp_data da=%r2:x32 n=%r3:x32" "brdwr bridge_brd_write da=%r2:x32 n=%r3:x32" \
	"flush proc_flush_memory" "inval proc_invalidate_memory" "dmm dmm_map_memory" ; do
	set -- $p; n=$1; shift
	echo "p:kprobes/$n $*" >> $T/kprobe_events 2>/dev/null || echo "dsptest: no kprobe $n" > /dev/kmsg
done
echo 1 > $T/events/kprobes/enable
echo "dsptest: decode start" > /dev/kmsg
chroot /newroot /tmp/gst-test "playbin2 uri=file:///usr/share/MProgressIndicator/themes/opengl/MainAnimation_LowNoise.mp4 video-sink=fakesink audio-sink=fakesink" 2>&1 | while read -r l; do echo "dsptest: gst: $l" > /dev/kmsg; done
echo "dsptest: decode end" > /dev/kmsg
