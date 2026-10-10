#!/usr/bin/perl
# On the phone (Harmattan's perl, in the chroot; root; bluetoothd stopped or paused): power hci0 up,
# queue COMMANDS harmless HCI commands (Read BD_ADDR) and power it down at once, ROUNDS times: the
# power-off then races commands still queued (sent after the driver's shutdown put the chip in reset).
# Prints how long each power-off (HCIDEVDOWN) took: 30 s = the tty close waiting for bytes CTS holds.
# Usage: perl bt-downrace.pl [ROUNDS] [COMMANDS]
use strict;
use Socket;
use Time::HiRes qw(time sleep);

my ($rounds, $cmds) = (shift || 10, shift || 20);
$| = 1;
socket(my $s, 31, SOCK_RAW, 1) or die "socket: $!";		# PF_BLUETOOTH, BTPROTO_HCI
bind($s, pack("S S S", 31, 0, 0)) or die "bind hci0: $!";	# raw channel
my ($HCIDEVUP, $HCIDEVDOWN) = (0x400448c9, 0x400448ca);
my $slow = 0;
for my $r (1 .. $rounds) {
	ioctl($s, $HCIDEVUP, 0) or $!{EALREADY} or die "up: $!";
	sleep 1;
	syswrite($s, pack("C v C", 1, 0x1009, 0)) for 1 .. $cmds;	# HCI_Read_BD_ADDR
	my $t = time;
	ioctl($s, $HCIDEVDOWN, 0) or die "down: $!";
	my $d = time - $t;
	$slow++ if $d > 5;
	printf "round %d: down %.2f s\n", $r, $d;
}
print "$rounds rounds, $slow slow power-offs\n";
