#!/bin/sh
# butter.sh: frame pacing on the RAM-booted phone, from the Mac. The same injected strokes
# (ramboot/swipe.pl) under each CPU setting; per run, the panel's update intervals in TE periods
# (sysfs update_stats: 1 = 60 fps, 2+ = a frame shown twice), the time at each CPU frequency and the
# entries into CORE retention or deeper (C5+).
#   butter.sh flick|page COUNT [IDLE_LATENCY_US:MIN_KHZ:SPLIT_LATE_US ...]
# Default settings: the late start off and on (2 ms), with stock's display idle limit.
# The display must be on and unlocked (see the boot workflow).
cd "$(dirname "$0")/.."
mode=${1:-flick} count=${2:-6}; shift 2 2>/dev/null
SSH="ssh -i build/ramboot-key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 -p $(nc -z -G 2 192.168.2.15 2222 2>/dev/null && echo 2222 || echo 22) root@192.168.2.15"
$SSH 'cat > /newroot/tmp/swipe.pl' < ramboot/swipe.pl || exit 1
$SSH "mode=$mode count=$count sh -s ${*:-6000:300000:0 6000:300000:2000}" <<'EOF'
touch /tmp/stay
P=/sys/class/backlight/display0/device
F=/sys/devices/system/cpu/cpu0/cpufreq
ev=$(sed -n '/Name="Atmel mXT Touchscreen"/,/^H:/s/.*\(event[0-9]*\).*/\1/p' /proc/bus/input/devices)
[ -n "$ev" ] || { echo "no touchscreen"; exit 1; }
min0=$(cat $F/scaling_min_freq)	# the phone's own floor (a min_freq job sets 600 MHz), restored after
deep() { n=0; for s in /sys/devices/system/cpu/cpu0/cpuidle/state[4-9]; do [ -d $s ] && n=$((n + $(cat $s/usage))); done; echo $n; }
for cfg in "$@"; do
	idle=${cfg%%:*} rest=${cfg#*:}; min=${rest%%:*} late=${rest#*:}
	echo $idle > $P/idle_latency_us
	echo $min > $F/scaling_min_freq
	echo $late > $P/split_late_us
	echo 0 > $P/update_stats
	t0=$(cat $F/stats/time_in_state | tr '\n' ' ') d0=$(deep)
	chroot /newroot perl /tmp/swipe.pl /dev/input/$ev $mode $count
	t1=$(cat $F/stats/time_in_state | tr '\n' ' ') d1=$(deep)
	freq=$(echo "$t0|$t1" | awk -F'|' '{n=split($1,a," "); split($2,b," "); for(i=1;i<n;i+=2) printf "%d:%dms ", a[i]/1000, (b[i+1]-a[i+1])*10}')
	echo "idle $idle us, min $min kHz, late $late us | $(cat $P/update_stats) | $freq| C5+ $((d1 - d0))"
done
echo 6000 > $P/idle_latency_us; echo $min0 > $F/scaling_min_freq; echo 2000 > $P/split_late_us
EOF
