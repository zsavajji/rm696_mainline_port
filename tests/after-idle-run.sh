#!/bin/bash
# tests/after-idle-run.sh BOOT IMAGE: on the Mac, the measurement sequence for a freshly booted test
# kernel (2026-10-08, HANDOFF-PERF.md 0g): wait for INIT_DONE (uptime >= 200 s, load < 1, ondemand),
# re-arm the image under test, copy the phone-side scripts, then: idle count as booted (display off by
# then), unlock, screen-on idle count + walk timing, video count + walk timing, 30 s idlestates, kernel
# log errors, save the logs. Output in build/idlecount-BOOT-*.txt, idle-walk-BOOT-*.txt, after-run-BOOT.txt.
set -u
cd "$(dirname "$0")/.."
B=$1 IMG=$2 T=tests
S=build/s.sh
echo "== waiting for a settled boot"
for i in $(seq 1 60); do
	read -r up load gov < <($S 'echo $(cut -d. -f1 /proc/uptime) $(cut -d" " -f1 /proc/loadavg) $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)' 2>/dev/null)
	[ -n "${up:-}" ] && [ "$up" -ge 200 ] && [ "$gov" = ondemand ] && [ "${load%.*}" -lt 1 ] && break
	sleep 10
done
echo "uptime $up load $load governor $gov"
echo "== re-arm $IMG"
pgrep -f 'ramboot/arm.sh' >/dev/null || osascript -e "tell application \"iTerm2\" to create window with default profile command \"$PWD/ramboot/arm.sh $PWD/$IMG\"" >/dev/null
cat $T/idlecount.sh | $S 'cat > /tmp/idlecount.sh'
cat $T/idletime.sh | $S 'cat > /tmp/idletime.sh'
echo "== 1. as booted"
$S 'sh /tmp/idlecount.sh 20 as-booted' | tee build/idlecount-$B-asbooted.txt
echo "== 2. unlock, screen-on idle"
ramboot/unlock.sh >/dev/null 2>&1; sleep 5
$S 'sh /tmp/idlecount.sh 20 screen-on-idle' | tee build/idlecount-$B-screenon.txt
$S 'sh /tmp/idletime.sh 10' > build/idle-walk-trace-$B-screenon.txt
echo "-- walk timing, screen-on idle:"; LC_ALL=C awk -f $T/idletime-parse.awk build/idle-walk-trace-$B-screenon.txt | tee build/idle-walk-$B-screenon.txt
echo "== 3. video"
($S 'sh -s "Nokia Pure.mp4" 90' < tests/video-play.sh > build/video-play-$B.txt 2>&1 &)
sleep 18
echo "plane $($S 'cat /sys/devices/platform/omapdss/overlay2/enabled')"
$S 'sh /tmp/idlecount.sh 20 video' | tee build/idlecount-$B-video.txt
$S 'sh /tmp/idletime.sh 10' > build/idle-walk-trace-$B-video.txt
echo "-- walk timing, video:"; LC_ALL=C awk -f $T/idletime-parse.awk build/idle-walk-trace-$B-video.txt | tee build/idle-walk-$B-video.txt
sleep 45
echo "-- video-play:"; head -3 build/video-play-$B.txt
echo "== 4. idlestates 30 s (screen on, idle)"
$S 'sh -s 30' < tests/idlestates.sh | tee build/idlestates-$B.txt
echo "== 5. kernel log: errors/warnings (filtered)"
$S 'dmesg' | LC_ALL=C grep -aiv "command line\|imei\|imsi\|serial\|iccid" | LC_ALL=C grep -aiE "error|warn|fail|bug|oops|underflow" | grep -av "firmware load for maxtouch\|unreliable\|vdd failed\|Failed to set regulator\|hw-breakpoint\|analog-tv\|48318000\|credp\|Aegis\|Failed to change cpu frequency\|onenand_wait" | head -15
echo "== 6. save logs $B"
ramboot/save-logs.sh $B 2>&1 | tail -1
echo "== done"
