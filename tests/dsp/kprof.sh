# On the RAM-booted phone, bridge loaded: entry/return probes on the bridge's call paths, one MPEG-4
# decode, the trace left in /tmp/kprof.trace for kprof.py
T=/sys/kernel/tracing
mount -t tracefs nodev $T 2>/dev/null
echo 0 > $T/tracing_on; echo > $T/trace; echo 0 > $T/events/kprobes/enable 2>/dev/null; echo > $T/kprobe_events
echo 8192 > $T/buffer_size_kb
for f in ${KPROF_FUNCS:-api_call_dev_ioctl proc_map bridge_brd_mem_map get_user_pages pte_set hw_mmu_tlb_flush_all dma_map_page_attrs dma_unmap_page_attrs node_put_message sm_interrupt_dsp mbox_send_message proc_un_map bridge_brd_mem_un_map}; do
	if grep -q -w "$f" /proc/kallsyms; then
		echo "p:kprobes/${f}_e $f" >> $T/kprobe_events
		echo "r:kprobes/${f}_x $f" >> $T/kprobe_events
	else
		echo "kprof: no $f" > /dev/kmsg
	fi
done
echo 1 > $T/events/kprobes/enable; echo 1 > $T/tracing_on
chroot /newroot /tmp/gst-test "uridecodebin uri=file:///usr/share/MProgressIndicator/themes/opengl/MainAnimation_LowNoise.mp4 name=d d. ! video/x-raw-yuv ! identity name=out ! fakesink sync=false" 2>&1 | grep EOS
echo 0 > $T/tracing_on
grep -v "^#" $T/trace > /tmp/kprof.trace; wc -l < /tmp/kprof.trace
echo 0 > $T/events/kprobes/enable
