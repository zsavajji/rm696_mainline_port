#!/bin/sh
# On the Mac: the counterpart of ramboot/unlock.sh (run that first, for its D-Bus policy): blanking
# allowed again, the display off and locked, for idle measurements.
cd "$(dirname "$0")/.."
build/s.sh 'chroot /newroot sh -c "
gconftool-2 -s -t int /system/osso/dsm/display/inhibit_blank_mode 0
dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_tklock_mode_change string:locked
dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_display_state_off
sleep 2
for q in get_display_status get_tklock_mode; do
	dbus-send --system --print-reply --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.\$q | tail -1
done
"'
