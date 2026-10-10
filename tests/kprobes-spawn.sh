#!/bin/sh
# kprobes-spawn.sh PHASE N [ohmd]: on a test boot (root, outside the chroot), spawnbench PHASE with N
# spawns under kprobes on the fork, exit, reap and page-fault paths plus sched_switch; ohmd is stopped
# unless the third argument is "ohmd". The trace goes to stdout, the spawner's maps to stderr first.
# Parse with tests/kprobes-spawn.py. Each probe hit costs a few us: compare durations, not totals.
T=/sys/kernel/tracing; mountpoint -q $T || mount -t tracefs none $T; cd $T || exit 1
F=/sys/devices/system/cpu/cpu0/cpufreq; P=$(pidof ohmd)
echo 0 > tracing_on; echo 0 > events/enable; echo > kprobe_events; echo > trace; echo 16384 > buffer_size_kb
for f in copy_process dup_mmap exit_mmap release_task exit_files free_pgtables unmap_vmas pgd_alloc \
	filemap_map_pages perf_event_init_task copy_creds cgroup_exit; do
	echo "p:k/$f $f" >> kprobe_events; echo "r:k/${f}_r $f" >> kprobe_events
done
# do_page_fault can't be probed (blacklisted); handle_mm_fault(vma, address, flags, regs) instead
echo 'p:k/pf handle_mm_fault addr=%r1:x32 flags=%r2:x32' >> kprobe_events
echo 'r:k/pf_r handle_mm_fault' >> kprobe_events
echo 'p:k/do_exit do_exit' >> kprobe_events
ls events/k > /dev/null || cat error_log >&2; echo 1 > events/k/enable; echo 1 > events/sched/sched_switch/enable
echo 1000000 > $F/scaling_min_freq
[ "$3" = ohmd ] || kill -STOP $P
echo 1 > tracing_on
chroot /newroot su - user -c "SPAWNBENCH_MAPS=1 /tmp/spawnbench /tmp/tinyexit $2 $1" >&2
echo 0 > tracing_on
kill -CONT $P
echo 0 > events/enable
echo 600000 > $F/scaling_min_freq
cat trace
echo > kprobe_events	# this clears the buffer too: after the dump
