#!/usr/bin/perl
# On the phone (chroot, root, FM already on: fm.pl KEEP=1): scan 87.5-108 MHz in 0.1 MHz steps by RSSI,
# print the strongest TOP, tune the best (or TUNE=MHz) and decode RDS for RDS_S seconds: PI, the station
# name (PS, groups 0A/0B) and the block counts. Leaves the radio tuned there.
use strict;
use Fcntl;
use Time::HiRes qw(time);

my ($top, $rds_s) = ($ENV{TOP} || 8, $ENV{RDS_S} // 15);
$| = 1;
sysopen(my $r, '/dev/radio0', O_RDONLY) or die "open /dev/radio0: $!";
sub tune { ioctl($r, 0x402c5639, my $b = pack('L L L x32', 0, 1, int($_[0] * 16000 + 0.5))) }
sub sig { my $b = pack('L x80', 0); ioctl($r, 0xc054561d, $b) or return; (unpack 'L Z32 L L L L L L l', $b)[8] }

my %s;
my $t = time;
for (my $f = 87.5; $f < 108.05; $f += 0.1) {
	my $k = sprintf '%.1f', $f;
	tune($k) and $s{$k} = sig();
}
my @best = sort { $s{$b} <=> $s{$a} } keys %s;
printf "scan: %d frequencies in %.1f s, RSSI min %d max %d\n", scalar keys %s, time - $t,
	$s{$best[-1]}, $s{$best[0]};
printf "  %s MHz: %d\n", $_, $s{$_} for @best[0 .. $top - 1];

my $f = $ENV{TUNE} || $best[0];
tune($f) or die "tune $f: $!";
printf "tuned %s MHz, RSSI %d\n", $f, sig();
my (%n, $errs, $pi, @ps, @grp);
my $end = time + $rds_s;
while (time < $end) {
	my $rin = ''; vec($rin, fileno($r), 1) = 1;
	select(my $o = $rin, undef, undef, 0.5) or next;
	defined(sysread($r, my $buf, 3 * 32)) or next;
	for (unpack '(a3)*', $buf) {
		my ($lsb, $msb, $st) = unpack 'C C C', $_;
		my ($id, $err) = ($st & 7, $st & 0x10);
		$n{$id}++; $errs++ if $st & 0x18;
		next if $err;
		my $v = $msb << 8 | $lsb;
		$id = 2 if $id == 3;			# C' as C
		$id = 3 if $id == 4;			# D
		@grp = () if $id == 0;
		$grp[$id] = $v if $id <= 3;
		$pi = $v if $id == 0;
		if ($id == 3 && defined $grp[1] && ($grp[1] >> 12) == 0) {	# group 0A/0B: PS segment
			my $seg = $grp[1] & 3;
			@ps[2 * $seg, 2 * $seg + 1] = map { $_ >= 32 && $_ < 127 ? chr : '?' } $v >> 8, $v & 0xff;
		}
	}
}
printf "RDS %d s: blocks %s, %d with errors; PI %s, PS \"%s\"\n", $rds_s,
	join(' ', map "$_:$n{$_}", sort keys %n) || 'none', $errs, defined $pi ? sprintf('%04X', $pi) : '-',
	join('', map { defined($_) ? $_ : '_' } @ps[0 .. 7]);
