# tests/video-playprof.sh: `ssh n9 sh -s 40 < tests/video-playprof.sh` (stock) or `build/s.sh sh -s 40 < ...` (test kernel).
# A cold-started video-suite drops its first play request (stock too): run it again if no plane comes on.
# Same on stock (as user, ssh n9) and on the test kernel (root): start Nokia Pure in Harmattan's
# video player over D-Bus, then for N s (default 40) each second the CPU idle share, the display
# controller's and the DSP mailbox's interrupts and whether a video plane is on; at the end the CPU
# ticks (user+system, 1/100 s) each process used over the window. Read-only apart from the playback.
n=${1:-40}
irq() { grep -E "$1" /proc/interrupts | head -1 | awk '{print $2}'; }
procs() { for s in /proc/[0-9]*/stat; do cat $s 2>/dev/null; done | awk '{c=$2; for (i=3; i<=NF && c !~ /\)$/; i++) c=c " " $i; print $1, c, $(i+11)+$(i+12)}'; }
uri="file:///home/user/MyDocs/Movies/Nokia Pure.mp4"
call=". /tmp/session_bus_address.user; dbus-send --session --type=method_call --dest=com.nokia.maemo.meegotouch.VideoSuiteService / com.nokia.maemo.meegotouch.VideoSuiteInterface.play array:string:\"$uri\""
if [ "$(id -u)" = 0 ]; then chroot /newroot su - user -c "$call"; O=/sys/devices/platform/omapdss; else sh -c "$call"; O=/sys/devices/platform/omapdss; fi
sleep 8
procs > /tmp/pp.0
set -- $(head -1 /proc/stat); i0=$5 t0=$(( $2 + $3 + $4 + $5 + $6 + $7 + $8 ))
d0=$(irq "DSS|DISPC") m0=$(irq " dsp$|mbox-dsp") k=0
while [ $k -lt $n ]; do
	k=$((k + 1)); sleep 1
	set -- $(head -1 /proc/stat); i1=$5 t1=$(( $2 + $3 + $4 + $5 + $6 + $7 + $8 ))
	d1=$(irq "DSS|DISPC") m1=$(irq " dsp$|mbox-dsp")
	echo "$k idle $(( 100 * (i1 - i0) / (t1 - t0 + 1) ))% dss+$((d1 - d0)) mbox+$((m1 - m0)) vid1=$(cat $O/overlay1/enabled) vid2=$(cat $O/overlay2/enabled)"
	i0=$i1 t0=$t1 d0=$d1 m0=$m1
done
procs > /tmp/pp.1
awk 'NR==FNR {a[$1]=$NF; next} ($1 in a) && $NF - a[$1] > 5 {c=$2; for (i=3; i<NF; i++) c=c " " $i; printf "%5d %s\n", $NF - a[$1], c}' /tmp/pp.0 /tmp/pp.1 | sort -rn | head -15
rm -f /tmp/pp.0 /tmp/pp.1
