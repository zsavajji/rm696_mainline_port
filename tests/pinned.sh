# tests/pinned.sh: on the test kernel as root (build/s.sh sh -s < tests/pinned.sh), CPU pinned at 1 GHz:
# swprof thread/process x3 (NOPERF) and kbench x3, from /newroot/tmp
F=/sys/devices/system/cpu/cpu0/cpufreq
echo "== $(uname -r) pinned 1 GHz"
echo 1000000 > $F/scaling_max_freq; echo 1000000 > $F/scaling_min_freq
for k in thread process thread process thread process; do echo "$k $(NOPERF=1 chroot /newroot /tmp/swprof $k 20000)"; done
for i in 1 2 3; do chroot /newroot /tmp/kbench | grep -E "syscall|gettime|yield|pipe|threadsw|ctxswitch|pagefault|filefault|spawn|memset|memcpy" | awk '{printf "%s %s  ", $1, $2}'; echo; done
echo 600000 > $F/scaling_min_freq
