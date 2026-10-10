#!/bin/sh
# On the Mac: play a quiet 4 s 440 Hz tone (10% amplitude) through Harmattan's PulseAudio on the
# test boot, and report where it went: each card's PCM state, the headphone path's DAPM widgets
# and the TPA6140A2's control/volume registers (2: bits 7-6 mute).
cd "$(dirname "$0")/.."
build/s.sh '
[ -f /newroot/tmp/tone.wav ] || chroot /newroot perl -e '\''my $r = 48000; my $d = ""; for my $i (0 .. $r * 4 - 1) { my $v = int(3277 * sin(2 * 3.14159265 * 440 * $i / $r)); $d .= pack("s<s<", $v, $v) } open(F, ">", "/tmp/tone.wav") or die; print F "RIFF", pack("V", 36 + length $d), "WAVEfmt ", pack("VvvVVvv", 16, 1, 2, $r, $r * 4, 4, 16), "data", pack("V", length $d), $d'\''
[ -f /newroot/tmp/.asoundrc ] || printf "pcm.pulse { type pulse }\nctl.pulse { type pulse }\n" > /newroot/tmp/.asoundrc
(chroot /newroot env HOME=/tmp aplay -q -D pulse /tmp/tone.wav > /tmp/aplay.log 2>&1 &)
sleep 1.5
for p in /proc/asound/card*/pcm0p/sub0/status; do echo "$p: $(head -1 $p)"; done
D=/sys/kernel/debug/asoc/dfl61-dac33
for w in Headphone "TPA6140A2 Left PGA" "TPA6140A2 Left Mute"; do f=$(find $D -path "*dapm/$w" | head -1); [ -n "$f" ] && head -1 "$f"; done
chroot /newroot perl -e '\''open(F, "+<", "/dev/i2c-2") or die; ioctl(F, 0x706, 0x60) or die; for $r (1, 2) { syswrite(F, chr($r)); sysread(F, $b, 1); printf "tpa reg %d = %02x\n", $r, ord $b }'\''
sleep 3; cat /tmp/aplay.log'
