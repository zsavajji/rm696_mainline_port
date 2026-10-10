#!/usr/bin/perl
# Read-only dump of the TWL5031's power registers (I2C1, address 0x4b): PM_MASTER 0x36-0x58
# (transitions, SW events, script addresses; not 0x59/0x5a, the script RAM window) and
# PM_RECEIVER 0x5b-0xf1 (resource groups, types, remaps). One combined write+read transfer per
# register (I2C_RDWR), so BME's own reads of the TWL can't interleave. Writes nothing.
# Run as root on the test kernel: chroot /newroot perl /tmp/twl-pm-dump.pl
use strict;
open(my $fh, '+<', '/dev/i2c-1') or die "i2c-1: $!";
sub rd {
	my $w = chr(shift); my $r = "\0";
	my $msgs = pack('SSSx2p SSSx2p', 0x4b, 0, 1, $w, 0x4b, 1, 1, $r);
	ioctl($fh, 0x0707, pack('pL', $msgs, 2)) or die "I2C_RDWR: $!";	# I2C_RDWR
	return ord($r);
}
my @regs = (0x36 .. 0x58, 0x5b .. 0xf1);
my $n = 0;
for my $a (@regs) {
	printf("%02x=%02x%s", $a, rd($a), (++$n % 16) ? ' ' : "\n");
}
print "\n";
