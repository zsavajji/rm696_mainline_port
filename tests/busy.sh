# tests/busy.sh [video]: 20 s of the whole system's busy share (from idle time), CPU frequencies, all
# processes' ticks (top 12) and interrupts by source; with "video", during Nokia Pure in the Videos app.
# Stock: ssh n9 sh -s [video] < tests/busy.sh; test kernel: build/s.sh sh -s [video] < tests/busy.sh
if [ -d /newroot ]; then run() { chroot /newroot su - user -c "$*"; }; else run() { sh -c "$*"; }; fi
O=/sys/devices/platform/omapdss/overlay2 C=/sys/devices/system/cpu/cpu0/cpufreq
play() { run ". /tmp/session_bus_address.user; dbus-send --session --type=method_call --dest=com.nokia.maemo.meegotouch.VideoSuiteService / com.nokia.maemo.meegotouch.VideoSuiteInterface.play array:string:\"file:///home/user/MyDocs/Movies/Nokia Pure.mp4\""; }
if [ "$1" = video ]; then for i in 1 2 3; do [ "$(cat $O/enabled)" = 1 ] || { play; sleep 10; }; done; fi
echo "== $(uname -r) $1: video plane $(cat $O/enabled)"
ticks() { for s in /proc/[0-9]*/stat; do cat $s 2>/dev/null; done | awk '{c=$2; for (i=3; i<=NF && c !~ /\)$/; i++) c=c " " $i; print $1, c, $(i+11) + $(i+12)}'; }
ticks > /tmp/b.0; cat /proc/interrupts > /tmp/i.0; t0=$(cat $C/stats/time_in_state | tr '\n' ' '); u0=$(cat /proc/uptime)
sleep 20
u1=$(cat /proc/uptime); t1=$(cat $C/stats/time_in_state | tr '\n' ' '); cat /proc/interrupts > /tmp/i.1; ticks > /tmp/b.1
echo "$u0 $u1" | awk '{printf "busy %.1f%% of %.1f s\n", 100 - 100 * ($4 - $2) / ($3 - $1), $3 - $1}'
echo "$t0|$t1" | awk -F'|' '{n = split($1, a, " "); split($2, b, " "); for (i = 1; i < n; i += 2) if (b[i+1] - a[i+1] > 0) printf "%d MHz %d0 ms  ", a[i] / 1000, b[i+1] - a[i+1]; print ""}'
awk 'NR == FNR {t[$1] = $NF; next} ($1 in t) && $NF - t[$1] > 0 {n = $NF - t[$1]; $NF = ""; print n, $0}' /tmp/b.0 /tmp/b.1 | sort -rn | head -12
awk 'NR == FNR {a[$1] = $2; next} {d = $2 - a[$1]; if (d > 0) {$2 = ""; print d, $0}}' /tmp/i.0 /tmp/i.1 | sort -rn | head -12
rm -f /tmp/b.0 /tmp/b.1 /tmp/i.0 /tmp/i.1
