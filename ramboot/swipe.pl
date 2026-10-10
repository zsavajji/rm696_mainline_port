#!/usr/bin/perl
# swipe.pl: touch strokes injected into the touchscreen's evdev node, as the N9's driver reports them
# (multitouch protocol A, kernel/atmel-mxt-protocol-a.patch), for repeatable frame-pacing tests: the
# input core hands written events to every reader, X's mtev included. Coordinates are the driver's
# (landscape framebuffer, 854x480); the portrait UI's vertical axis is the framebuffer's X.
#   swipe.pl /dev/input/eventN flick|page COUNT
#     flick: fast portrait-vertical flicks in the middle, alternating, 2 s apart (kinetic scrolling
#            runs on after the release, past the input boost's 1 s)
#     page:  portrait-horizontal swipes across the screen, alternating, 1.5 s apart (home views)
use strict;
use warnings;
use Time::HiRes qw(usleep);

my ($dev, $mode, $count) = @ARGV;
die "usage: swipe.pl /dev/input/eventN flick|page COUNT\n" unless $dev && $mode && $count;
open(my $f, '>', $dev) or die "$dev: $!\n";

# struct input_event on 32-bit ARM: timeval (the kernel stamps it), type, code, value
sub ev { syswrite($f, pack('l l S S l', 0, 0, @_)) }
sub frame {
	my ($x, $y, $down) = @_;
	ev(3, 0x39, 0); ev(3, 0x35, $x); ev(3, 0x36, $y); ev(3, 0x30, 8); ev(3, 0x3a, 40);
	ev(0, 2, 0);					# SYN_MT_REPORT
	ev(1, 0x14a, 1); ev(3, 0, $x); ev(3, 1, $y); ev(3, 0x18, 40);
	ev(0, 0, 0);					# SYN_REPORT
}
sub stroke {
	my ($x0, $y0, $x1, $y1, $steps, $us) = @_;
	for my $i (0 .. $steps) {
		frame(int($x0 + ($x1 - $x0) * $i / $steps), int($y0 + ($y1 - $y0) * $i / $steps));
		usleep($us);
	}
	frame($x1, $y1);				# lift-off as the driver: last position again,
	ev(1, 0x14a, 0); ev(3, 0x18, 0); ev(0, 0, 0);	# then BTN_TOUCH 0 alone
}

for my $n (1 .. $count) {
	my $dir = $n % 2 ? 1 : -1;
	if ($mode eq 'flick') {
		stroke(427 - 150 * $dir, 240, 427 + 150 * $dir, 240, 10, 10000);
		usleep(2000000);
	} else {
		stroke(427, 240 - 180 * $dir, 427, 240 + 180 * $dir, 15, 12000);
		usleep(1500000);
	}
}
