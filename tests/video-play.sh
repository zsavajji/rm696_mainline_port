# tests/video-play.sh, on the test kernel (build/s.sh sh -s CLIP [SECONDS] < tests/video-play.sh): clear the
# panel's update_stats, play MyDocs/Movies/CLIP (or MyDocs/CLIP for a path) in Harmattan's Videos app (again if a cold-started
# video-suite dropped the request), wait until the video plane goes off (or SECONDS), print the stats
clip=$1 max=${2:-300}
case $clip in */*) ;; *) clip=Movies/$clip;; esac
U=/sys/class/backlight/display0/device O=/sys/devices/platform/omapdss/overlay2
play() { chroot /newroot su - user -c ". /tmp/session_bus_address.user; dbus-send --session --type=method_call --dest=com.nokia.maemo.meegotouch.VideoSuiteService / com.nokia.maemo.meegotouch.VideoSuiteInterface.play array:string:\"file:///home/user/MyDocs/$clip\""; }
echo 0 > $U/update_stats
play; sleep 12
[ "$(cat $O/enabled)" = 1 ] || { play; sleep 12; }
t0=$(cut -d. -f1 /proc/uptime)
echo "playing: plane $(cat $O/input_size) -> $(cat $O/output_size) at $(cat $O/position)"
while [ "$(cat $O/enabled)" = 1 ] && [ $(( $(cut -d. -f1 /proc/uptime) - t0 )) -lt $max ]; do sleep 2; done
echo "played $(( $(cut -d. -f1 /proc/uptime) - t0 + 12 )) s"
cat $U/update_stats
grep -a "A lot of buffers" /newroot/var/log/syslog | tail -1
