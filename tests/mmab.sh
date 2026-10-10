#!/bin/bash
# tests/mmab.sh KVER OUT (on the Mac): wait until the phone runs KVER (a part of `uname -r`), then until
# it's idle (1-minute load < 1.0; leave the screen locked), then tests/mmbench.sh twice into OUT. The
# same procedure for every kernel compared: a fixed wait after boot measured boot activity
# (2026-10-05). Needs build/loopop and build/forkbench (tests/build.sh).
cd "$(dirname "$0")/.."
until build/s.sh 'uname -r' </dev/null 2>/dev/null | grep -q "$1"; do perl -e 'sleep 5'; done
until build/s.sh 'awk "{exit !(\$1 < 1.0)}" /proc/loadavg' </dev/null 2>/dev/null; do perl -e 'sleep 15'; done
build/s.sh 'cat > /tmp/mmbench.sh' < tests/mmbench.sh
build/s.sh 'mountpoint -q /harmattan/tmp || mount -t tmpfs -o size=2m,mode=1777 tmpfs /harmattan/tmp; cat > /harmattan/tmp/loopop; chmod 755 /harmattan/tmp/loopop' < build/loopop
build/s.sh 'cat > /harmattan/tmp/forkbench; chmod 755 /harmattan/tmp/forkbench' < build/forkbench
build/s.sh 'echo "load $(cat /proc/loadavg)"; sh /tmp/mmbench.sh; sh /tmp/mmbench.sh | tail -10; echo "load $(cat /proc/loadavg)"' </dev/null > "$2" 2>&1
