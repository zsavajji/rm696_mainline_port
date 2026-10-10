# On the RAM-booted phone (sh): SmartReflex class 1.5 (rm696 sr1p5). The CPU pinned at each OPP,
# then L3 at each level; at each: the VP's voltage and md5sum of a cached library in a loop against
# its checksum. Idle states stay on (a calibrating VDD keeps itself out of retention). Then the
# calibrated table and the boot's SR messages.
# sh sr1p5test.sh [SECONDS per OPP]; needs /tmp/devmem-ro (build/devmem-ro).
secs=${1:-20}
F=/sys/devices/system/cpu/cpu0/cpufreq L3=/sys/kernel/debug/omap3_l3 D=/tmp/devmem-ro
Lib=/newroot/usr/lib/libQtGui.so.4.7.4
grep -q " /sys/kernel/debug " /proc/mounts || mount -t debugfs none /sys/kernel/debug
vp() { v=0x$($D $1 | cut -d' ' -f2); echo $((600000 + 12500 * (v & 0xff))); }	# TWL: 0.6 V + 12.5 mV x vsel
loop() {
	n=0 bad=0 t0=$(cut -d. -f1 /proc/uptime)
	while [ $(( $(cut -d. -f1 /proc/uptime) - t0 )) -lt $secs ]; do
		[ "$(md5sum $Lib | cut -c1-32)" = "$ref" ] || bad=$((bad + 1))
		n=$((n + 1))
	done
}
echo "autocomp VDD1 $(cat /sys/power/sr_vdd1_autocomp) VDD2 $(cat /sys/power/sr_vdd2_autocomp)"
ref=$(md5sum $Lib | cut -c1-32)
min0=$(cat $F/scaling_min_freq) max0=$(cat $F/scaling_max_freq)
for khz in 300000 600000 800000 1000000; do
	echo 300000 > $F/scaling_min_freq; echo $khz > $F/scaling_max_freq; echo $khz > $F/scaling_min_freq
	sleep 1
	loop
	echo "$khz kHz: VP1 $(vp 0x483072C0) uV, $n checksums, $bad wrong"
done
echo 300000 > $F/scaling_min_freq; echo $max0 > $F/scaling_max_freq; echo $min0 > $F/scaling_min_freq
for l3 in low high; do
	echo $l3 > $L3
	sleep 1
	loop
	echo "L3 $l3: VP2 $(vp 0x483072E0) uV, $n checksums, $bad wrong"
done
echo auto > $L3
echo "sr_calib (VDD, nominal, next start, calibrated; uV):"
cat /sys/kernel/debug/sr_calib
echo "SR disable timeouts this boot: $(dmesg | grep -v 'command line' | grep -c 'disable timedout')"
dmesg | grep -v 'command line' | grep -iE 'smartreflex|class 1.5|TRANXDONE|VP.*(idle|disable)' | tail -5
