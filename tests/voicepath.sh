#!/bin/sh
# On the Mac: the call-audio hardware without a call (no SIM needed). Sets the TWL card's controls as
# PulseAudio's earpiece and internal-microphone paths do (nokia-dfl61-twl4030-output-earpiece.conf,
# -input-internal-microphones.conf), plays a quiet tone to the earpiece and records 2 s from the
# digital mics; reports the earpiece path's DAPM state and the recording's level. PulseAudio
# reapplies its own paths when it next opens the card.
cd "$(dirname "$0")/.."
build/s.sh '
A="chroot /newroot amixer -q -c 0 sset"
$A "DAC1 Analog" off; $A "DAC2 Analog" on; $A "DAC2 Analog" 12
for c in "Earpiece Mixer AudioL1" "Earpiece Mixer AudioR1" "Earpiece Mixer Voice" HandsfreeL; do $A "$c" off; done
$A "Earpiece Mixer AudioL2" on; $A Earpiece 2
$A TX1 Digimic0
[ -f /newroot/tmp/tone.wav ] || { echo "no /tmp/tone.wav (run tests/tone.sh once)"; exit 1; }
(chroot /newroot aplay -q -D hw:0 /tmp/tone.wav > /tmp/aplay-ep.log 2>&1 &)
sleep 1
D=/sys/kernel/debug/asoc/dfl61-twl4030
for w in Earpiece "Earpiece Mixer" "Earpiece PGA" "DAC Left2" "DAC Right1"; do f=$(find $D -path "*dapm/$w" | head -1); [ -n "$f" ] && head -1 "$f"; done
sleep 4; cat /tmp/aplay-ep.log
chroot /newroot arecord -q -D hw:0 -f S16_LE -r 48000 -c 2 -d 3 /tmp/mic.wav 2>&1
# the left mic per 0.5 s: the first second is the high-pass filter settling, then room noise
chroot /newroot perl -e '\''open(F, "<", "/tmp/mic.wav") or die "$!"; binmode F; read(F, $h, 44); my (@b, $i); while (read(F, $d, 4) == 4) { my ($l) = unpack("s<", $d); my $k = int($i++ / 24000); $b[$k][0]++; $b[$k][1] += $l; $b[$k][2] += $l * $l; $b[$k][3] = abs($l) if abs($l) > ($b[$k][3] // 0) } for my $k (0 .. $#b) { my ($n, $s, $s2, $p) = @{$b[$k]}; my $m = $s / $n; printf "mic %.1fs: mean %6.1f std %5.1f peak %5d\n", $k / 2, $m, sqrt($s2 / $n - $m * $m), $p }'\''
'
