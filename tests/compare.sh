# tests/compare.sh: the same measurements on stock and on the test kernel, as user, with Harmattan's own
# governor (no pinning: root on stock is mine), the time at each CPU frequency recorded around each.
#   stock:       scp/cat build/kbench build/tlbbench to /tmp, then  ssh n9 sh -s < tests/compare.sh
#   test kernel: copy them to /newroot/tmp, then  build/s.sh sh -s < tests/compare.sh
# kbench x3, tlbbench, then 20 s of Nokia Pure in the Videos app (started over D-Bus, again if a
# cold-started video-suite dropped it): user and system CPU time of the renderer, pulseaudio and Xorg.
# Writes only to /tmp (a tmpfs).
if [ -d /newroot ]; then
	run() { chroot /newroot su - user -c "$*"; }
	O=/sys/devices/platform/omapdss/overlay2
else
	run() { sh -c "$*"; }
	O=/sys/devices/platform/omapdss/overlay2
fi
C=/sys/devices/system/cpu/cpu0/cpufreq
tis() { cat $C/stats/time_in_state | tr '\n' ' '; }
tisdiff() { echo "$1|$2" | awk -F'|' '{n = split($1, a, " "); split($2, b, " ")
	for (i = 1; i < n; i += 2) if (b[i + 1] - a[i + 1] > 0) printf "%d MHz %d0 ms  ", a[i] / 1000, b[i + 1] - a[i + 1]}'; echo; }
echo "== $(uname -r), governor $(cat $C/scaling_governor), $(cat $C/scaling_min_freq)-$(cat $C/scaling_max_freq) kHz"
for r in 1 2 3; do
	a=$(tis); run /tmp/kbench | grep -E "cgroup|syscall|gettime|yield|pipe|threadsw|ctxswitch|pagefault|filefault|spawn|memset|memcpy" |
		awk '{printf "%s %s  ", $1, ($1 == "cgroup" ? $2 ":" $3 : $2)}'; echo
	echo "   at: $(tisdiff "$a" "$(tis)")"
done
a=$(tis); run /tmp/tlbbench | tr '\n' ' ' | tr -s ' '; echo; echo "   at: $(tisdiff "$a" "$(tis)")"
play() { run ". /tmp/session_bus_address.user; dbus-send --session --type=method_call --dest=com.nokia.maemo.meegotouch.VideoSuiteService / com.nokia.maemo.meegotouch.VideoSuiteInterface.play array:string:\"file:///home/user/MyDocs/Movies/Nokia Pure.mp4\""; }
play; sleep 10
[ "$(cat $O/enabled)" = 1 ] || { play; sleep 10; }
snap() { for s in /proc/[0-9]*/stat; do cat $s 2>/dev/null; done | awk '{c=$2; for (i=3; i<=NF && c !~ /\)$/; i++) c=c " " $i; if (c ~ /qmafw-dbus-wrap|pulseaudio|Xorg/) print $1, c, $(i+11), $(i+12)}'; }
echo "video plane $(cat $O/enabled) $(cat $O/input_size)"
# context switches of each process's threads (voluntary, involuntary), all switches and interrupts
csw() { for p in /proc/[0-9]*; do c=$(sed -n "s/^Name:[[:space:]]*//p" $p/status 2>/dev/null); case "$c" in qmafw-dbus-wrap|pulseaudio|Xorg)
	cat $p/task/*/status 2>/dev/null | awk -v c=$c '/^voluntary_ctxt/{v+=$2} /^nonvoluntary_ctxt/{n+=$2} END{print c, v, n}';; esac; done
	awk '/^ctxt/{print "all", $2, 0}' /proc/stat; awk 'NR > 1 {for (i = 2; i <= NF && $i ~ /^[0-9]+$/; i++) n += $i} END{print "irqs", n, 0}' /proc/interrupts; }
snap > /tmp/cmp.0; csw > /tmp/csw.0; a=$(tis); up0=$(cat /proc/uptime); sleep 20; up1=$(cat /proc/uptime); snap > /tmp/cmp.1; csw > /tmp/csw.1
# per-process ticks charge whole ticks to whoever runs at the tick (biased for short bursts, and HZ differs:
# 250 here, 128 on stock); the whole system's busy share comes from the idle time
echo "$up0 $up1" | awk '{printf "busy %.1f%% of %.1f s\n", 100 - 100 * ($4 - $2) / ($3 - $1), $3 - $1}'
awk 'NR == FNR {u[$1] = $3; s[$1] = $4; next} ($3 - u[$1] + $4 - s[$1]) > 2 {printf "%-20s user %4d system %4d\n", $2, $3 - u[$1], $4 - s[$1]}' /tmp/cmp.0 /tmp/cmp.1
awk 'NR == FNR {v[$1] = $2; n[$1] = $3; next} {printf "%-16s switches %6d + %5d involuntary\n", $1, $2 - v[$1], $3 - n[$1]}' /tmp/csw.0 /tmp/csw.1
echo "   at: $(tisdiff "$a" "$(tis)")"
rm -f /tmp/cmp.0 /tmp/cmp.1 /tmp/csw.0 /tmp/csw.1
