#!/usr/bin/perl
# On the phone (Harmattan's perl, in the chroot; root): a minimal btmon. The kernel's HCI monitor
# channel for SECONDS: commands, events (connection, pairing and security ones decoded) and ACL
# traffic with L2CAP signalling, RFCOMM frame types and OBEX opcodes / response codes (0xa0 success, 0x90
# continue, 0xc0-0xd5 errors) decoded. No BD addresses or payload printed.
# Usage: perl btmon.pl [SECONDS]
use strict;
use Socket;
use Time::HiRes qw(time);

my $secs = shift || 20;
$| = 1;
socket(my $s, 31, SOCK_RAW, 1) or die "socket: $!";	# PF_BLUETOOTH, BTPROTO_HCI
bind($s, pack("S S S", 31, 0xffff, 2)) or die "bind: $!";	# HCI_DEV_NONE, HCI_CHANNEL_MONITOR
my %op = (0 => "new-index", 1 => "del-index", 2 => "cmd", 3 => "evt", 4 => "acl>", 5 => "acl<",
	6 => "sco>", 7 => "sco<", 8 => "open-index", 9 => "close-index", 10 => "index-info",
	11 => "vendor-diag", 12 => "system-note", 13 => "user-logging");
my %ev = (0x03 => "conn-complete", 0x04 => "conn-request", 0x05 => "disconn-complete",
	0x06 => "auth-complete", 0x08 => "encrypt-change", 0x16 => "pin-request", 0x17 => "linkkey-request",
	0x18 => "linkkey-notify", 0x31 => "iocap-request", 0x32 => "iocap-response",
	0x33 => "user-confirm-request", 0x36 => "ssp-complete", 0x14 => "mode-change", 0x12 => "role-change");
my %sig = (1 => "cmd-reject", 2 => "conn-req", 3 => "conn-rsp", 4 => "conf-req", 5 => "conf-rsp",
	6 => "disconn-req", 7 => "disconn-rsp", 10 => "info-req", 11 => "info-rsp");
my %rf = (0x2f => "SABM", 0x63 => "UA", 0x0f => "DM", 0x43 => "DISC", 0xef => "UIH");
my ($t0, $end, %count, %obex) = (time, time + $secs);
my $rin = ''; vec($rin, fileno($s), 1) = 1;
while (time < $end) {
	next unless select(my $r = $rin, undef, undef, 0.5);
	my $n = sysread($s, my $buf, 2048) or last;
	my ($opc, $idx, $len) = unpack("S S S", $buf);
	my $d = substr($buf, 6);
	my $name = $op{$opc} // "op$opc";
	$count{$name}++;
	my $info = "";
	if ($opc == 2) {
		my ($code, $plen) = unpack("v C", $d);
		$info = sprintf("ogf 0x%02x ocf 0x%03x plen %d", $code >> 10, $code & 0x3ff, $plen);
	} elsif ($opc == 3) {
		my ($e, $plen) = unpack("C C", $d);
		$info = sprintf("event 0x%02x %s plen %d", $e, $ev{$e} // "", $plen);
		$info .= sprintf(" (opcode 0x%04x status %d)", unpack("x3 v C", $d)) if $e == 0x0e;
		$info .= sprintf(" (status %d)", unpack("x2 C", $d)) if $e == 0x01 || $e == 0x0f || $e == 0x06 || $e == 0x36;
		$info .= sprintf(" (status %d handle %d)", unpack("x2 C v", $d)) if $e == 0x03;
		$info .= sprintf(" (status %d handle %d reason 0x%02x)", unpack("x2 C v C", $d)) if $e == 0x05;
		$info .= sprintf(" (status %d handle %d on %d)", unpack("x2 C v C", $d)) if $e == 0x08;
		$info .= sprintf(" (link type %d)", unpack("x11 C", $d)) if $e == 0x04;
		$info .= sprintf(" (%d responses)", unpack("x2 C", $d)) if $e == 0x02 || $e == 0x22 || $e == 0x2f;
	} elsif ($opc == 4 || $opc == 5) {
		my ($hf, $dl, $ll, $cid) = unpack("v v v v", $d);
		$info = sprintf("%d bytes h=%d", $len, $hf & 0xfff);
		if ((($hf >> 12) & 3) != 1 && length($d) >= 9) {	# a start fragment: L2CAP header
			my $p = substr($d, 8);
			$info .= sprintf(" cid 0x%04x", $cid);
			if ($cid == 1) {
				my ($code, $id) = unpack("C C", $p);
				$info .= " " . ($sig{$code} // sprintf("sig 0x%02x", $code));
				$info .= sprintf(" psm 0x%04x scid 0x%04x", unpack("x4 v v", $p)) if $code == 2;
				$info .= sprintf(" dcid 0x%04x scid 0x%04x result %d status %d", unpack("x4 v v v v", $p)) if $code == 3;
				$info .= sprintf(" reason %d", unpack("x4 v", $p)) if $code == 1;
			} elsif ($cid >= 0x40 && length($p) >= 2) {	# a dynamic channel: as RFCOMM
				my ($a, $c) = unpack("C C", $p);
				my $t = $rf{$c & 0xef} // sprintf("ctrl 0x%02x", $c);
				$info .= sprintf(" rfcomm dlci %d %s%s", $a >> 2, $t, $c & 0x10 ? " P/F" : "");
				$info .= sprintf(" mux 0x%02x", unpack("x3 C", $p)) if ($a >> 2) == 0 && $t eq "UIH" && length($p) >= 4;
				if (($a >> 2) && $t eq "UIH" && length($p) >= 3) {	# OBEX: each packet's opcode / response code
					my ($l, $o) = (unpack("x2 C", $p), 3);
					($l, $o) = (unpack("x2 v", $p), 4) unless $l & 1;	# 2-byte length (EA bit clear)
					$l >>= 1; $o++ if $c & 0x10;	# credits byte
					my $k = "$opc/" . ($a >> 2);
					if (($obex{$k} // 0) <= 0 && length($p) >= $o + 3) {
						my ($code, $olen) = unpack("x$o C n", $p);
						$info .= sprintf(" obex 0x%02x len %d", $code, $olen);
						$obex{$k} = $olen;
					}
					$obex{$k} -= $l;
				}
			}
		}
	} elsif ($opc == 12 || $opc == 13) {
		($info = $d) =~ s/[^[:print:]]//g;
	}
	printf "%8.3f hci%d %-11s %s\n", time - $t0, $idx == 0xffff ? -1 : $idx, $name, $info;
}
print "counts: ", join(" ", map { "$_=$count{$_}" } sort keys %count), "\n";
