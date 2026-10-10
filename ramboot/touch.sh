#!/bin/sh
# On the Mac: the touchscreen's input frames live, over the RAM-boot ssh (for a terminal window):
# one line per SYN_REPORT with the time, the gap since the previous frame, BTN_TOUCH and each
# protocol-A contact (tracking id: x,y major pressure). X's mtev reads the same events (no grab).
cd "$(dirname "$0")/.."
while :; do
	ssh -i build/ramboot-key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 \
		-o ServerAliveInterval=5 -o ServerAliveCountMax=2 -p $(nc -z -G 2 192.168.2.15 2222 2>/dev/null && echo 2222 || echo 22) root@192.168.2.15 '
cat > /newroot/tmp/touchmon.pl <<"EOF"
my $dev = shift;
open(my $f, "<", $dev) or die "$dev: $!";
$| = 1;
my ($t0, $tl, $btn, %cur, @contacts, @other);
while (sysread($f, my $ev, 16) == 16) {
	my ($s, $us, $type, $code, $val) = unpack("l l S S l", $ev);
	my $t = $s + $us / 1e6; $t0 //= $t;
	if ($type == 1 && $code == 0x14a) { $btn = $val; next }
	if ($type == 3) { $cur{$code} = $val; next }
	if ($type == 0 && $code == 2) {
		push @contacts, sprintf("%s:%s,%s m%s p%s", map { $_ // "-" } @cur{0x39, 0x35, 0x36, 0x30, 0x3a});
		delete @cur{0x39, 0x35, 0x36, 0x30, 0x3a};
		next;
	}
	if ($type == 0 && $code == 0) {
		printf "%9.3f %+5.0fms  %-6s %s%s\n", $t - $t0, defined $tl ? ($t - $tl) * 1000 : 0,
			defined $btn ? "BTN $btn" : "", @contacts ? "[" . join("] [", @contacts) . "]" : "(no contacts)",
			%cur ? "  abs " . join(" ", map { sprintf "%x=%d", $_, $cur{$_} } sort keys %cur) : "";
		$tl = $t; undef $btn; @contacts = (); %cur = ();
		next;
	}
	push @other, "$type/$code=$val";
}
EOF
for e in /sys/class/input/event*; do
	grep -q Atmel $e/device/name && exec chroot /newroot perl /tmp/touchmon.pl /dev/input/$(basename $e)
done'
	echo "--- (no connection; retrying)"
	sleep 3
done
