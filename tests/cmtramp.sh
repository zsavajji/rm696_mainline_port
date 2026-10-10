#!/bin/sh
# On the Mac: the call-audio data path without a call (HANDOFF-CALL.md). Stops Harmattan's PulseAudio
# (it holds /dev/cmt_speech), runs build/cmtramp (tests/cmtramp.c: TEST_RAMP_PING through the modem),
# starts PulseAudio again and checks it reopened the device. Arguments go to cmtramp: "tests/cmtramp.sh 5";
# GAP_MS (default 20 ms), NOUL, PAIR and ULX too: "GAP_MS=100 tests/cmtramp.sh 10 81".
cd "$(dirname "$0")/.."
S=build/s.sh
$S 'cat > /newroot/tmp/cmtramp; chmod 755 /newroot/tmp/cmtramp' < build/cmtramp || exit 1
$S "A='$*' E='$(env | grep -E '^(GAP_MS|NOUL|PAIR|ULX)=' | tr '\n' ' ')'"'
irqs() { grep -i "ssi\|cawake\|gdd\|cmt" /proc/interrupts; }
echo "== before"; ls -l /newroot/dev/cmt_speech; irqs; cat /sys/kernel/debug/omap3_l3
chroot /newroot initctl stop pulseaudio
echo "== cmtramp $E$A"; chroot /newroot env $E /tmp/cmtramp $A; echo "exit $?"
chroot /newroot initctl start pulseaudio
echo "== after"; irqs; cat /sys/kernel/debug/omap3_l3; sleep 3
P=$(pidof pulseaudio); echo "pulseaudio $P: $(ls -l /proc/$P/fd 2>/dev/null | grep -c cmt_speech) cmt_speech fd"
dmesg | grep -av "command line" | grep -ai "ssi\|hsi\|cmt\|speech\|mcsaab\|phonet" | tail -15
rm -f /newroot/tmp/cmtramp'
