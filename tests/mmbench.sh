# on the phone (root, the RAM-boot side; tests/mmab.sh copies it): loopop's mmap variants and forkbench
# as user, chrooted into the read-only ext4 (stock's paths and filesystem), at a pinned 1 GHz
mountpoint -q /harmattan/tmp || mount -t tmpfs -o size=2m,mode=1777 tmpfs /harmattan/tmp
mountpoint -q /harmattan/proc || mount --bind /proc /harmattan/proc
echo 1000000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
uname -r
for m in mmap amap fixed afixed unmap0 mmaponly mprotect split split; do chroot /harmattan /bin/su user -c "/tmp/loopop $m 3" 2>/dev/null; done
chroot /harmattan /bin/su user -c "/tmp/forkbench" 2>/dev/null | grep -E "mmap|anon|mprotect|VMA|booster|stat|open"
echo 600000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
