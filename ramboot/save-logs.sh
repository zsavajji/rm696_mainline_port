#!/bin/sh
# On the Mac: save a test boot's kernel log and Harmattan syslog as build/ramboot-{dmesg,syslog}-N.txt,
# before any reset. Identifiers are removed: the kernel command line, MAC addresses, IMEI/IMSI/serial
# fields and any run of 14+ digits. Usage: ramboot/save-logs.sh N
set -e
cd "$(dirname "$0")/.."
[ -n "$1" ] || { echo "usage: $0 N" >&2; exit 1; }
redact() {
	LC_ALL=C grep -av "command line" | LC_ALL=C sed -E \
		-e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/xx:xx:xx:xx:xx:xx/g' \
		-e 's/((imei|imsi|serial ?number|iccid|msisdn)[^0-9a-z]{0,4})[0-9A-Za-z]+/\1<redacted>/gI' \
		-e 's/[0-9]{14,}/<redacted>/g'
}
build/s.sh dmesg | redact > build/ramboot-dmesg-$1.txt
build/s.sh 'cat /newroot/var/log/syslog' | redact > build/ramboot-syslog-$1.txt
# Nothing identifying may be left
! LC_ALL=C grep -aiE "(imei|imsi|serial ?number)[^0-9a-z]{0,4}[0-9]|[0-9]{14,}" \
	build/ramboot-dmesg-$1.txt build/ramboot-syslog-$1.txt
wc -l build/ramboot-dmesg-$1.txt build/ramboot-syslog-$1.txt
