#!/bin/sh
# Tonight's wakeup traces (2026-10-12): on the phone's terminal, as root (devel-su):
#   sh /home/user/MyDocs/n9-tests/night.sh [captures, default 4; 12 for a whole day]
# then lock it and leave it unplugged. tests/wakeups.sh: a 2-minute capture 30 min from now, then one
# every hour, into MyDocs/.n9-logs/wakeups-MMDD-HHMM-N.txt
[ "$(id -u)" = 0 ] || { echo "not root: run devel-su first (the traces need debugfs and tracefs)"; exit 1; }
W=1800 N=${1:-4} P=3480 setsid sh "$(dirname "$0")/wakeups.sh" </dev/null >/dev/null 2>&1 &
echo "wakeup traces started: the first in 30 minutes, then hourly (${1:-4})"
