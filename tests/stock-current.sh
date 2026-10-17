#!/bin/sh
# On stock, as the normal user (ssh n9): the battery current and the WLAN frequency every 10 s, to compare
# with 6.18 at the same place (2026-10-16: 6.18 drew ~125 mA at an AP's 5 GHz, ~32 mA on its 2.4 GHz).
# Output MyDocs/.n9-logs/stock-current.txt: uptime, MHz, BME's battery current (mA, negative = charging).
# Start: nohup sh /home/user/MyDocs/n9-tests/stock-current.sh </dev/null >/dev/null 2>&1 &
# Stop: touch /home/user/MyDocs/.n9-logs/stock-current.stop
L=/home/user/MyDocs/.n9-logs O=$L/stock-current.txt
rm -f $L/stock-current.stop; echo "== $(date)" >> $O
while [ ! -e $L/stock-current.stop ]; do
	echo "$(cut -d' ' -f1 /proc/uptime) $(/usr/sbin/iw dev wlan0 link 2>/dev/null | awk '/freq/ {print $2}')" \
		"$(/usr/bin/bmestat | awk -F: '/battery current/ {gsub(/ /, "", $2); print $2}')" >> $O
	sleep 10
done
