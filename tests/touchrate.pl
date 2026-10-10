#!/usr/bin/perl
# touchrate.pl EVDEV SECONDS: frames per touch from the input device: interval between SYN_REPORTs
# while touching, and how fast the first position change follows the touch-down
use Time::HiRes qw(time);
my ($dev, $secs) = @ARGV;
open(my $f, "<", $dev) or die "$dev: $!";
my $end = time + $secs;
my ($down, $tdown, $tlast, $x0, $y0, $moved, @iv, @firstmove, $touches, $x, $y);
my $rin = ''; vec($rin, fileno($f), 1) = 1;
while (time < $end) {
	next unless select(my $r = $rin, undef, undef, 0.2);
	sysread($f, my $ev, 16) == 16 or last;
	my ($s, $us, $type, $code, $val) = unpack("l l S S l", $ev);
	my $t = $s + $us / 1e6;
	if ($type == 1 && $code == 0x14a) {
		if ($val) { $down = 1; $tdown = $t; $touches++; undef $x0; undef $moved; undef $tlast }
		else { $down = 0 }
		next;
	}
	if ($type == 3 && $code == 0x35) { $x = $val }
	if ($type == 3 && $code == 0x36) { $y = $val }
	if ($type == 0 && $code == 0 && $down) {
		push @iv, ($t - $tlast) * 1000 if defined $tlast;
		$tlast = $t;
		if (!defined $x0) { ($x0, $y0) = ($x, $y) }
		elsif (!$moved && ($x != $x0 || $y != $y0)) { $moved = 1; push @firstmove, ($t - $tdown) * 1000 }
	}
}
@iv = sort { $a <=> $b } @iv;
my $n = @iv;
printf "%d touches, %d frames while touching: interval median %.1f ms (p10 %.1f, p90 %.1f) = %.0f Hz; first move %s ms after touch-down\n",
	$touches, $n + $touches, $n ? $iv[$n / 2] : 0, $n ? $iv[$n / 10] : 0, $n ? $iv[$n * 9 / 10] : 0, $n ? 1000 / $iv[$n / 2] : 0,
	@firstmove ? sprintf("%.0f (median of %d)", (sort { $a <=> $b } @firstmove)[@firstmove / 2], scalar @firstmove) : "-";
