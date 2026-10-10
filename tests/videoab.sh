#!/bin/bash
# tests/videoab.sh BOOT: on the Mac, after a settled boot of the perf-video kernel: the DSP reference decodes and
# encodes (tests/dsp/dspref.sh) and the renderer's kernel share in video, with the bridge's whole-cache
# flush off (bridgedriver.flush_all_min_kb 0) and on (256), in that order, twice each for dspref.
set -u
cd "$(dirname "$0")/.."
B=$1 T=build S=build/s.sh   # the clips t720b.mp4, t720m.mp4 in build/ (ffmpeg, tests/dsp/dspref.sh header)
P=/sys/module/bridgedriver/parameters/flush_all_min_kb
for f in gst-test ioctl-log.so; do cat build/$f | $S "cat > /newroot/tmp/$f; chmod +x /newroot/tmp/$f"; done
for f in t720b.mp4 t720m.mp4; do cat $T/$f | $S "cat > /newroot/tmp/$f"; done
cat build/kprof | $S 'cat > /newroot/tmp/kprof; chmod +x /newroot/tmp/kprof'
$S "ls -l /newroot/tmp/ | awk '{print \$5, \$9}'; cat $P"
for v in 0 256 0 256; do
	echo "######## dspref, flush_all_min_kb=$v"
	$S "echo $v > $P; cat $P"
	$S 'sh -s' < tests/dsp/dspref.sh 2>&1 | grep -E "^==|^EOS|error|couldn|span" | sed 's/^/  /'
done | tee build/dspref-ab-$B.txt
echo "######## video: renderer kernel share, 0 then 256"
ramboot/unlock.sh >/dev/null 2>&1; sleep 4
$S "echo 0 > $P"
($S 'sh -s "Nokia Pure.mp4" 170' < tests/video-play.sh > build/video-play-ab-$B.txt 2>&1 &)
sleep 25
for v in 0 256 0 256; do
	$S "echo $v > $P"
	sleep 3
	echo "== kprof renderer 20 s, flush_all_min_kb=$v (uptime $($S 'cut -d. -f1 /proc/uptime'))"
	$S 'R=$(pgrep -f qmafw-dbus-wrap | head -1); KPROF_TASKS=$R chroot /newroot /tmp/kprof 20 1000' 2>&1 | head -6
done | tee build/kprof-video-ab-$B.txt
echo "== busy.sh video with 256" && $S 'sh -s video' < tests/busy.sh 2>&1 | head -6 | tee build/busy-video-ab-$B.txt
$S "echo 0 > $P"
echo "== dmesg errors (filtered)" && $S 'dmesg' | LC_ALL=C grep -aiv "command line\|imei\|imsi\|serial\|iccid" | LC_ALL=C grep -aiE "error|warn|fail|bug|oops|fault" | grep -av "firmware load for maxtouch\|unreliable\|vdd failed\|Failed to set regulator\|hw-breakpoint\|analog-tv\|48318000\|credp\|Aegis\|Failed to change cpu frequency\|onenand_wait\|eocz" | head -12
echo "== done"
