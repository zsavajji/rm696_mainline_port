#!/usr/bin/perl
# tap.pl: one tap injected into the touchscreen's evdev node, as swipe.pl's strokes (multitouch
# protocol A; the driver's coordinates: the landscape framebuffer, 854x480).
#   tap.pl /dev/input/eventN X Y
use strict;
use Time::HiRes qw(usleep);
my ($dev, $x, $y) = @ARGV;
die "usage: tap.pl /dev/input/eventN X Y\n" unless $dev && defined $y;
open(my $f, '>', $dev) or die "$dev: $!\n";
sub ev { syswrite($f, pack('l l S S l', 0, 0, @_)) }
sub frame {
	ev(3, 0x39, 0); ev(3, 0x35, $x); ev(3, 0x36, $y); ev(3, 0x30, 8); ev(3, 0x3a, 40);
	ev(0, 2, 0);					# SYN_MT_REPORT
	ev(1, 0x14a, 1); ev(3, 0, $x); ev(3, 1, $y); ev(3, 0x18, 40);
	ev(0, 0, 0);					# SYN_REPORT
}
for (1 .. 5) { frame(); usleep(12000) }
ev(1, 0x14a, 0); ev(3, 0x18, 0); ev(0, 0, 0);	# lift-off: BTN_TOUCH 0 alone
