#!/usr/bin/perl
# bb5-test.pl: harmless calls into the N9's real secure environment through /dev/omap_sec (Nokia's
# omap_sec + omap_hs, kernel/omap3-sec-bb5.patch): a hardware random number, Nokia's ROT13 test PA (a
# signed protected application loaded and run in the secure world) and the PA image versions. Nothing
# here reads an identifier or touches secure storage. Run in Harmattan's root: chroot /newroot perl ...
use strict;
use warnings;

use constant IOCTL_SET_CMD => 0x4004b500;	# _IOW(0xB5, 0, u32), sec.h
use constant { CMD_RANDOM1 => 6, CMD_VERSIONS_GET => 7, CMD_PA_ROT13 => 0x100 };

# One command: the code by ioctl, then its argument length and data; the result is the secure ROM's
# and the PA's return values and the command's output.
sub sec_cmd {
	my ($cmd, $data) = @_;
	open(my $f, '+<', '/dev/omap_sec') or die "open /dev/omap_sec: $!\n";
	ioctl($f, IOCTL_SET_CMD, $cmd + 0) or die "ioctl: $!\n";
	defined syswrite($f, pack('L', length $data) . $data) or die sprintf("command %#x: %s\n", $cmd, $!);
	defined sysread($f, my $out, 65536) or die "read: $!\n";
	close $f;
	my ($rom_rv, $pa_rv) = unpack('LL', $out);
	return ($rom_rv, $pa_rv, substr($out, 8));
}

my $fail = 0;
sub check {
	my ($ok, $what) = @_;
	print(($ok ? "ok   " : "FAIL ") . "$what\n");
	$fail++ unless $ok;
}

my ($rv, undef, $r1) = sec_cmd(CMD_RANDOM1, pack('l', 16));
my (undef, undef, $r2) = sec_cmd(CMD_RANDOM1, pack('l', 16));
check($rv == 0 && length $r1 == 16 && $r1 ne $r2,
	sprintf('random (secure ROM RNG): rom_rv %#x, %s / %s', $rv, unpack('H*', $r1), unpack('H*', $r2 // '')));

my $text = 'Hello from Linux 6.18, real BB5';
(my $want = $text) =~ tr/A-Za-z/N-ZA-Mn-za-m/;
my ($rom, $pa, $got) = sec_cmd(CMD_PA_ROT13, pack('L', length $text) . $text);
check($rom == 0 && $pa == 0 && $got eq $want,
	sprintf('PA_ROT13 (signed PA in the secure world): rom_rv %#x pa_rv %#x "%s"', $rom, $pa, $got));

($rv, undef, my $v) = sec_cmd(CMD_VERSIONS_GET, '');
my ($pa_ver, $fmt_ver) = unpack('LL', $v . "\0" x 8);
check($rv == 0 && length $v == 8, "PA image version $pa_ver, format version $fmt_ver");

exit($fail ? 1 : 0);
