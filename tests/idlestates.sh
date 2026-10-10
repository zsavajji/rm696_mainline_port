# tests/idlestates.sh [SECONDS]: on the test kernel, what the idle states did over SECONDS (60):
# entries and residency per state, and the domains' RET counts (pm_debug/count, debugfs).
s=${1:-60} C=/sys/devices/system/cpu/cpu0/cpuidle
grep -q " /sys/kernel/debug " /proc/mounts || mount -t debugfs none /sys/kernel/debug
ret() { sed -n 's/^\(mpu_pwrdm\|core_pwrdm\|per_pwrdm\) .*,RET:\([0-9]*\),.*/\1 \2/p' /sys/kernel/debug/pm_debug/count; }
snap() { for d in $C/state*; do echo "$(cat $d/name) $(cat $d/usage) $(cat $d/time)"; done; }
snap > /tmp/is.0; ret > /tmp/pc.0; sleep $s
snap > /tmp/is.1; ret > /tmp/pc.1
echo "$s s: state entries/s residency%"
paste /tmp/is.0 /tmp/is.1 | awk -v s=$s '{printf "%s %.1f %.1f%%\n", $1, ($5 - $2) / s, ($6 - $3) / s / 10000}'
paste /tmp/pc.0 /tmp/pc.1 | awk -v s=$s '{printf "%s RET %.1f/s\n", $1, ($4 - $2) / s}'
rm -f /tmp/is.0 /tmp/is.1 /tmp/pc.0 /tmp/pc.1
