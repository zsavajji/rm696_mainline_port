#!/bin/sh
# On the Mac: after a test boot reaches the UI, let root talk to mce and usb_moded (a D-Bus policy in
# the RAM overlay), keep the display on (gconf, RAM only), turn it on and unlock it.
cd "$(dirname "$0")/.."
build/s.sh '
cat > /newroot/etc/dbus-1/system.d/zz-sgx-ramboot.conf <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><policy user="root"><allow send_destination="com.nokia.mce"/><allow send_destination="com.meego.usb_moded"/></policy></busconfig>
EOF
chroot /newroot sh -c "
dbus-send --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig
gconftool-2 -s -t int /system/osso/dsm/display/inhibit_blank_mode 3
gconftool-2 -s -t bool /system/osso/dsm/locks/touchscreen_keypad_autolock_enabled false
dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_display_state_on
dbus-send --system --print-reply --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_tklock_mode_change string:unlocked >/dev/null && echo unlocked
"'
