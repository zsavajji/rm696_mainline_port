#!/usr/bin/perl
# On the phone (Harmattan's perl, in the chroot; root; hci0 down, bluetoothd stopped): sustained
# Bluetooth UART receive test without a remote device. hci0 through the HCI user channel (the
# kernel's stack stays out), the controller in local loopback (it echoes every ACL packet), then
# ACL packets of random size and content with sequence numbers for SECONDS, WINDOW outstanding;
# every echo is checked byte for byte. The user channel refuses (EBUSY) an hci whose boot-time
# power-on failed (no firmware yet: HCI_SETUP stays set): re-probe the driver first (BT_GOTCHAS.md).
# GAP=s: up to s seconds (random) before each packet, so the chip sleeps and wakes between them.
# Usage: [HCIDEV=n] [GAP=s] perl btloop.pl [SECONDS] [WINDOW] [MAXLEN]
use strict;
use Socket;
use Time::HiRes qw(time);

my ($secs, $win, $maxlen, $dev) = (shift || 30, shift || 3, shift || 0, $ENV{HCIDEV} || 0);
$| = 1;
socket(my $s, 31, SOCK_RAW, 1) or die "socket: $!";		# PF_BLUETOOTH, BTPROTO_HCI
bind($s, pack("S S S", 31, $dev, 1)) or die "bind hci$dev user channel: $!";	# HCI_CHANNEL_USER
my $rin = ''; vec($rin, fileno($s), 1) = 1;

my @pending;	# packets cmd() read past while waiting for its reply
sub rd {	# one packet or undef after $t seconds
	my $t = shift;
	return shift @pending if @pending;
	return undef unless select(my $r = $rin, undef, undef, $t);
	sysread($s, my $buf, 4096) or die "read: $!";
	return $buf;
}
sub cmd {	# opcode, params -> Command Complete's return parameters
	my ($op, $p) = @_;
	syswrite($s, pack("C v C", 1, $op, length $p) . $p) or die "write: $!";
	my $end = time + 3;
	while (time < $end) {
		next unless select(my $r = $rin, undef, undef, 0.5);
		sysread($s, my $b, 4096) or die "read: $!";
		my ($type, $ev) = unpack("C C", $b);
		push(@pending, $b), next unless $type == 4 && ($ev == 0x0e || $ev == 0x0f);
		return substr($b, 6) if $ev == 0x0e && unpack("x4 v", $b) == $op;
		die sprintf("opcode 0x%04x status %d\n", $op, unpack("x3 C", $b))
			if $ev == 0x0f && unpack("x5 v", $b) == $op && unpack("x3 C", $b);
	}
	die sprintf("opcode 0x%04x: no reply\n", $op);
}

my ($st, $mtu, undef, $nacl) = unpack("C v C v", cmd(0x1005, ""));	# Read Buffer Size
die "read buffer size: status $st\n" if $st;
$maxlen ||= $mtu;
$win = $nacl - 1 if $win > $nacl - 1;
print "ACL MTU $mtu, $nacl buffers; packets up to $maxlen bytes, window $win, ${secs} s\n";

$st = unpack("C", cmd(0x1802, "\x01"));	# Write Loopback Mode: local
die "loopback: status $st\n" if $st;
my $h;
for (my $end = time + 2; time < $end && !defined $h;) {
	my $b = rd(0.5) // next;
	my ($type, $ev, undef, $est, $hd) = unpack("C C C C v", $b);
	$h = $hd if $type == 4 && $ev == 0x03 && !$est && unpack("x12 C", $b) == 1;	# ACL link
}
die "no loopback ACL connection\n" unless defined $h;

my $pool = join "", map { chr int rand 256 } 1 .. 70000;
my (%ev, @out, %c);
my ($seq, $next, $t0, $last) = (0, 0, time, time);
my $bytes = 0;
sub payload { my ($n, $len) = @_; pack("N", $n) . substr($pool, ($n * 7919) % 65536, $len - 4) }
while (time - $t0 < $secs || @out) {
	while (@out < $win && time - $t0 < $secs) {
		if ($ENV{GAP}) { select(undef, undef, undef, rand $ENV{GAP}); $last = time; }
		my $len = 4 + int rand($maxlen - 3);
		syswrite($s, pack("C v v", 2, $h | 0x2000, $len) . payload($seq, $len)) or die "write: $!";
		push @out, [$seq++, $len];
		$c{sent}++;
	}
	my $b = rd(0.2);
	if (!defined $b) {
		if (time - $last > 2) {	# nothing back for 2 s: the outstanding ones are lost
			printf "%7.2f s: timeout, %d outstanding (seq %d..)\n", time - $t0, scalar @out, $out[0][0];
			$c{timeout}++; $c{lost} += @out; @out = (); $last = time;
		}
		next;
	}
	my $type = unpack("C", $b);
	if ($type == 4) {
		my $e = unpack("x C", $b);
		$ev{sprintf "0x%02x", $e}++;
		printf "%7.2f s: event 0x%02x, %d bytes\n", time - $t0, $e, length($b) - 3	# no payload: BD addresses
			unless $e == 0x13;	# Number Of Completed Packets
		next;
	}
	next unless $type == 2;
	$last = time;
	my ($hf, $len) = unpack("x v v", $b);
	my $data = substr($b, 5);
	$c{rcvd}++;
	my $n = length($data) >= 4 ? unpack("N", $data) : -1;
	while (@out && $out[0][0] != $n && grep { $_->[0] == $n } @out) {	# earlier ones skipped: lost
		printf "%7.2f s: seq %d lost (got %d)\n", time - $t0, $out[0][0], $n;
		$c{lost}++; shift @out;
	}
	if (!@out || $out[0][0] != $n) {
		printf "%7.2f s: unexpected packet, %d bytes, header len %d, starts %s\n", time - $t0,
			length $data, $len, unpack("H*", substr($data, 0, 12));
		$c{unexpected}++;
		next;
	}
	my $exp = payload($n, $out[0][1]);
	if ($data ne $exp || $len != length $exp || ($hf & 0xfff) != $h) {
		my $i = 0; $i++ while $i < length $exp && substr($data, $i, 1) eq substr($exp, $i, 1);
		printf "%7.2f s: seq %d corrupt: %d of %d bytes, header len %d, first difference at %d\n",
			time - $t0, $n, length $data, length $exp, $len, $i;
		$c{corrupt}++;
	} else {
		$c{ok}++; $bytes += length $exp;
	}
	shift @out;
}
my $dt = time - $t0;
eval { cmd(0x1802, "\x00") };	# loopback off
printf "%.1f s: sent %d, ok %d, corrupt %d, lost %d, unexpected %d, timeouts %d; %.1f KB/s each way\n",
	$dt, $c{sent}, $c{ok}, $c{corrupt} // 0, $c{lost} // 0, $c{unexpected} // 0, $c{timeout} // 0,
	$bytes / $dt / 1000;
print "events: ", join(" ", map { "$_=$ev{$_}" } sort keys %ev), "\n";
