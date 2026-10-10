# On the RAM-booted phone (sh): SmartReflex on VDD1 at one CPU frequency, under load.
# sh srtest.sh KHZ SECONDS: C3 and deeper off (SR isn't stopped around MPU retention yet), the CPU
# pinned at KHZ, SR on (it starts at the next voltage change), md5sum of a cached library in a loop
# against its SR-off checksum, the VP1 voltage sampled; then SR off and everything back.
# Needs /tmp/devmem-ro (build/devmem-ro).
khz=$1 secs=${2:-45}
C=/sys/devices/system/cpu/cpu0 F=/sys/devices/system/cpu/cpu0/cpufreq
SR=/sys/kernel/debug/smartreflex/smartreflex_mpu_iva D=/tmp/devmem-ro
L=/newroot/usr/lib/libQtGui.so.4.7.4
vsel() { $D 0x483072C0 | cut -d' ' -f2 | cut -c7-8; }
ref=$(md5sum $L | cut -c1-32)
for n in 2 3 4 5 6; do echo 1 > $C/cpuidle/state$n/disable; done
min0=$(cat $F/scaling_min_freq) max0=$(cat $F/scaling_max_freq)
other=300000; [ $khz = 300000 ] && other=600000
echo $other > $F/scaling_min_freq; echo $other > $F/scaling_max_freq
echo $khz > $F/scaling_max_freq; echo $khz > $F/scaling_min_freq
echo $other > $F/scaling_min_freq; echo $other > $F/scaling_max_freq
sleep 0.3
nominal=$(vsel)
echo 1 > $SR/autocomp
echo $khz > $F/scaling_max_freq; echo $khz > $F/scaling_min_freq
sleep 1
n=0 bad=0 vs=
t0=$(cut -d. -f1 /proc/uptime)
while [ $(( $(cut -d. -f1 /proc/uptime) - t0 )) -lt $secs ]; do
	[ "$(md5sum $L | cut -c1-32)" = "$ref" ] || bad=$((bad + 1))
	n=$((n + 1)) vs="$vs $(vsel)"
done
echo 0 > $SR/autocomp
sleep 0.3
off=$(vsel)
echo $max0 > $F/scaling_max_freq; echo $min0 > $F/scaling_min_freq
for n2 in 2 3 4 5 6; do echo 0 > $C/cpuidle/state$n2/disable; done
echo "$khz kHz: $n checksums, $bad wrong | VP1 vsel nominal $nominal, with SR:$(echo $vs | tr ' ' '\n' | sort | uniq -c | awk '{printf " %sx%s", $2, $1}'), SR off $off"
