#!/bin/sh
# Run on STOCK Harmattan as root (devel-su), once /tmp/cmtramp is there (copied from the Mac as user):
# boot 281's TEST_RAMP_PING runs (HANDOFF-CALL.md) on stock's kernel, to tell whether the modem's stall
# with pings back to back is the modem's test mode (stock stalls too) or our kernel (stock doesn't).
# Writes nothing outside /tmp; PulseAudio is stopped for the runs and started again.
#   sh /tmp/cmtramp-stock.sh > /tmp/cmtramp-stock.txt 2>&1
[ "$(id -u)" = 0 ] || { echo "run as root (devel-su)"; exit 1; }
PATH=/sbin:/usr/sbin:/bin:/usr/bin	# devel-su's root shell has no /sbin (initctl)
f() { grep -aiv "command line\|imei\|imsi\|serial\|iccid\|msisdn"; }
st() { echo "== $1 $(date +%T)"; grep -i "ssi\|cmt" /proc/interrupts; }
uname -r
st before
initctl stop pulseaudio
echo "== spaced: GAP_MS=20, 10 pings of 81 words"; GAP_MS=20 /tmp/cmtramp 10 81; echo "exit $?"
st "after spaced"
echo "== back to back: GAP_MS=0, 5 pings of 81 words"; GAP_MS=0 /tmp/cmtramp 5 81; echo "exit $?"
sleep 8
st "after back to back"
initctl start pulseaudio
echo "== kernel log, last 40 lines"; dmesg | f | tail -40
echo "== sscd and csd, last 25 lines"; grep -a "ssc\[\|csd\[" /var/log/syslog | f | tail -25
