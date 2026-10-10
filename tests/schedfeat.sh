#!/bin/sh
# On the phone (root, test kernel with sched_prof): swprof thread/process switch time and the
# sched_prof totals under each scheduler feature setting given (e.g. NO_DELAY_DEQUEUE; "base" = as is).
# Each setting is undone after its run. Needs /newroot/tmp/swprof.
D=/sys/kernel/debug; F=/sys/devices/system/cpu/cpu0/cpufreq
mountpoint -q $D || mount -t debugfs none $D
echo 1000000 > $F/scaling_max_freq; echo 1000000 > $F/scaling_min_freq
for s in "$@"; do
	[ "$s" = base ] || echo $s > $D/sched/features
	for k in thread process thread process; do
		echo 1 > $D/sched_prof
		t=$(NOPERF=1 chroot /newroot /tmp/swprof $k 20000)
		echo "$s $k $t | $(awk '/switches/{k=$1} k!="kernel/idle:" && /block|pick next|switch_mm|finish_task/{s=s" "$(NF-1)} /try_to_wake/{print "block/pick/mm/finish" s ", ttwu " $(NF-1)}' $D/sched_prof)"
	done
	case $s in base) ;; NO_*) echo ${s#NO_} > $D/sched/features ;; *) echo NO_$s > $D/sched/features ;; esac
done
echo 0 > $D/sched_prof; echo 600000 > $F/scaling_min_freq
