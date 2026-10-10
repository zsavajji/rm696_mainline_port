#!/bin/bash
# tests/forkab.sh KVER OUT (on the Mac): wait until the phone runs KVER, then until it's idle (1-minute
# load < 1.0; leave the screen locked), then forkbench (chroot /harmattan, plain ext4), loopop fork200,
# spawnbench and kbench (Harmattan's root) twice each, as user at 1 GHz, into OUT. The same procedure
# for every kernel compared. Needs build/{loopop,forkbench,spawnbench,tinyexit,kbench} (tests/build.sh).
cd "$(dirname "$0")/.."
until build/s.sh 'uname -r' </dev/null 2>/dev/null | grep -q "$1"; do perl -e 'sleep 5'; done
until build/s.sh 'awk "{exit !(\$1 < 1.0)}" /proc/loadavg' </dev/null 2>/dev/null; do perl -e 'sleep 15'; done
build/s.sh 'mountpoint -q /harmattan/tmp || mount -t tmpfs -o size=2m,mode=1777 tmpfs /harmattan/tmp; mountpoint -q /harmattan/proc || mount --bind /proc /harmattan/proc; cat > /harmattan/tmp/loopop; chmod 755 /harmattan/tmp/loopop' < build/loopop
build/s.sh 'cat > /harmattan/tmp/forkbench; chmod 755 /harmattan/tmp/forkbench' < build/forkbench
for f in spawnbench tinyexit kbench; do build/s.sh "cat > /newroot/tmp/$f; chmod 755 /newroot/tmp/$f" < build/$f; done
build/s.sh 'echo "load $(cat /proc/loadavg)"; uname -r; echo 1000000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
for i in 1 2; do chroot /harmattan /bin/su user -c /tmp/forkbench 2>/dev/null | grep -E "fork|fault|VMA"; done
for i in 1 2; do chroot /harmattan /bin/su user -c "/tmp/loopop fork200 3" 2>/dev/null; done
for i in 1 2; do chroot /newroot /bin/su user -c "/tmp/spawnbench /tmp/tinyexit" 2>/dev/null | cut -c1-60 | head -6; done
for i in 1 2; do chroot /newroot /bin/su user -c /tmp/kbench 2>/dev/null | tr "\n" " " | grep -o "spawn *[0-9]* us\|pagefault *[0-9.]* us" | tr "\n" " "; echo; done
rm -f /newroot/tmp/spawnbench /newroot/tmp/tinyexit /newroot/tmp/kbench
echo 600000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq; echo "load $(cat /proc/loadavg)"' </dev/null > "$2" 2>&1
