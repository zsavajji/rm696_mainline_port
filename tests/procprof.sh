# tests/procprof.sh: during Nokia Pure in the Videos app, sample the renderer's and pulseaudio's own CPU
# time (kprof KPROF_TASKS: per-thread CPU-clock events, as user) on stock (ssh n9 sh -s) or the test
# kernel (build/s.sh sh -s). Needs /tmp/kprof (/newroot/tmp on the test kernel), the screen unlocked.
if [ -d /newroot ]; then run() { chroot /newroot su - user -c "$*"; }; prof() { chroot /newroot sh -c "$*"; }
else run() { sh -c "$*"; }; prof() { sh -c "$*"; }; fi	# root on 6.18: kallsyms is hidden from users
O=/sys/devices/platform/omapdss/overlay2
play() { run ". /tmp/session_bus_address.user; dbus-send --session --type=method_call --dest=com.nokia.maemo.meegotouch.VideoSuiteService / com.nokia.maemo.meegotouch.VideoSuiteInterface.play array:string:\"file:///home/user/MyDocs/Movies/Nokia Pure.mp4\""; }
echo "== $(uname -r)"
for p in qmafw-dbus-wrap pulseaudio; do
	[ "$(cat $O/enabled)" = 1 ] || { play; sleep 10; }
	[ "$(cat $O/enabled)" = 1 ] || { play; sleep 10; }
	pid=$(for d in /proc/[0-9]*; do [ "$(sed -n 's/^Name:[[:space:]]*//p' $d/status 2>/dev/null)" = $p ] && echo ${d#/proc/}; done | head -1)
	echo "-- $p ($pid), video plane $(cat $O/enabled)"
	prof "KPROF_TASKS=$pid /tmp/kprof 15 1000" | head -25
done
