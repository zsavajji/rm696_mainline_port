#!/usr/bin/perl
# On the phone (Harmattan's perl, in the chroot, root; a headset plugged in: it is the antenna): the
# WL1273 FM radio end to end, as fmrxd (the community apps' daemon) and Nokia's testserver drive it.
# Each step logs ok or FAIL and goes on, so one run answers as much as it can:
#  1. HCI=1: hci0 up and fmrxd's "muxer" command (0xfc00 f3 88 01 02), first as fmrxd does;
#     HCI=2: the same, then hci0 down after 1 s (fmrxd when Bluetooth was off); HCI=3: up, no command
#  2. "Mode Switch" Rx on hw:dfl61wl1273: powers the FM part up, uploads radio-wl1273-fw.bin
#  3. "Codec Mode" FmRx, "Audio Switch" Digital
#  4. /dev/radio0: QUERYCAP, unmute (testserver), tune each of FREQS (MHz) and read the RSSI
#     (.signal, the chip's signed value), then SEEKS hardware seeks upward
#  5. RDS: read() for RDS_S seconds, 3-byte blocks counted by block id and error bits
#  6. 3 s capture from hw:dfl61wl1273, 48 kHz stereo (fmrxd's), RMS per channel (0 = silence)
#  7. power off as fmrxd: "Audio Switch" Analog, "Codec Mode" Bt, "Mode Switch" Off (KEEP=1: stay on,
#     tuned to the last frequency, to listen: HANDOFF-FM.md)
# Before and after: the wl1273-fm interrupt count and the kernel's wl1273 lines.
# Usage: [HCI=1] [FREQS="87.6 104.8"] [SEEKS=3] [RDS_S=10] [KEEP=1] perl fm.pl
use strict;
use Fcntl;
use Time::HiRes qw(time sleep);

my @freqs = split ' ', ($ENV{FREQS} || '87.6 95.0 104.8');
my ($seeks, $rds_s) = ($ENV{SEEKS} // 3, $ENV{RDS_S} // 10);
my $card = 'dfl61wl1273';
$| = 1;
sub step { printf "%-5s %s\n", $_[0] ? 'ok' : 'FAIL', $_[1]; $_[0] }
sub mix { my $o = `amixer -c $card cset name='$_[0]' '$_[1]' 2>&1`; step(!$?, "$_[0] = $_[1]" . ($? ? ": $o" : '')) }
sub irqs { my ($l) = grep /wl1273/, `cat /proc/interrupts`; $l =~ /^\s*\d+:\s+(\d+)/ ? $1 : 'none' }
sub klog { print "  kernel: $_" for grep /wl1273|radio/i, grep !/command line/, `dmesg | tail -40` }

print "wl1273-fm interrupts before: ", irqs(), "\n";
print "cards: ", `cat /proc/asound/cards` =~ /^\s*(\d+) \[$card/m ? "$card is card $1 (fmrxd uses hw:2)\n" : "no $card\n";

if ($ENV{HCI}) {	# first, as fmrxd's radio_start()
	step(!system('hciconfig hci0 up'), 'hci0 up');
	step(!system('hcitool cmd 0x3f 0x000 0xf3 0x88 0x01 0x02 >/dev/null'), 'HCI 0xfc00 f3 88 01 02')
		unless $ENV{HCI} == 3;
	if ($ENV{HCI} == 2) {	# fmrxd when Bluetooth was off: down again 1 s later
		sleep 1;
		step(!system('hciconfig hci0 down'), 'hci0 down again');
	}
}
my $t = time;
mix('Mode Switch', 'Rx');
printf "      power-up took %.2f s\n", time - $t;
mix('Codec Mode', 'FmRx');
mix('Audio Switch', 'Digital');

if (sysopen(my $r, '/dev/radio0', O_RDONLY)) {
	my $cap = "\0" x 104;
	if (step(ioctl($r, 0x80685600, $cap), 'VIDIOC_QUERYCAP')) {	# _IOR('V', 0, 104)
		my ($drv, $name, $bus, $ver, $caps, $dcaps) = unpack 'Z16 Z32 Z32 L L L', $cap;
		printf "      %s, \"%s\", caps 0x%08x (TUNER %s)\n", $drv, $name, $caps, $caps & 0x10000 ? 'yes' : 'NO';
	}
	step(ioctl($r, 0xc008561c, my $c = pack('L l', 0x00980909, 0)), 'unmute (VIDIOC_S_CTRL)');
	my $tuner = sub {	# VIDIOC_G_TUNER, _IOWR('V', 29, 84)
		my $b = pack('L x80', 0);
		ioctl($r, 0xc054561d, $b) or return "G_TUNER: $!";
		my (undef, undef, $type, $tcap, $lo, $hi, $sub, undef, $sig) = unpack 'L Z32 L L L L L L l', $b;
		sprintf 'signal %d, %s%s, range %.2f-%.2f MHz', $sig, $sub & 2 ? 'stereo' : 'mono?',
			$sub & 0x10 ? ', RDS' : '', $lo / 16000, $hi / 16000;
	};
	my $freq = sub {	# VIDIOC_G_FREQUENCY, _IOWR('V', 56, 44)
		my $b = pack('L L L x32', 0, 1, 0);
		ioctl($r, 0xc02c5638, $b) ? sprintf('%.2f MHz', (unpack 'L L L', $b)[2] / 16000) : "G_FREQUENCY: $!";
	};
	for my $f (@freqs) {	# VIDIOC_S_FREQUENCY, _IOW('V', 57, 44): units of 62.5 Hz
		$t = time;
		my $ok = ioctl($r, 0x402c5639, my $b = pack('L L L x32', 0, 1, int($f * 16000 + 0.5)));
		step($ok, sprintf('tune %s MHz (%.2f s): %s', $f, time - $t, $ok ? $tuner->() . ', at ' . $freq->() : $!));
	}
	for (1 .. $seeks) {	# VIDIOC_S_HW_FREQ_SEEK, _IOW('V', 82, 48): up, wrap around
		$t = time;
		my $ok = ioctl($r, 0x40305652, my $b = pack('L L L L x32', 0, 1, 1, 1));
		step($ok, sprintf('seek up (%.2f s): %s', time - $t, $ok ? $freq->() . ', ' . $tuner->() : $!));
	}
	my (%blocks, $errs, $n, $why);
	my $end = time + $rds_s;
	while (time < $end) {
		my $rin = ''; vec($rin, fileno($r), 1) = 1;
		select(my $rout = $rin, undef, undef, 0.5) or next;
		my $got = sysread($r, my $buf, 3 * 32);
		if (!defined $got) { $why = $!; sleep 0.5; next }
		for (unpack '(a3)*', $buf) {
			my $st = ord substr($_, 2);
			$blocks{$st & 7}++; $errs++ if $st & 0x18; $n++;
		}
	}
	step($n, sprintf 'RDS in %d s: %d blocks (by id: %s), %d with errors%s', $rds_s, $n,
		join(' ', map "$_:$blocks{$_}", sort keys %blocks) || '-', $errs, $why ? ", last error: $why" : '');
	close $r;
} else {
	step(0, "open /dev/radio0: $!");
}

my $o = `arecord -D hw:$card -f S16_LE -r 48000 -c 2 -d 3 -t raw /tmp/fm.raw 2>&1`;
if (step(!$? && -s '/tmp/fm.raw', 'capture 3 s at 48 kHz stereo' . ($? ? ": $o" : ''))) {
	open my $fh, '<', '/tmp/fm.raw'; binmode $fh; local $/; my @s = unpack 's<*', <$fh>;
	my @sum = (0, 0); $sum[$_ % 2] += $s[$_] ** 2 for 0 .. $#s;
	printf "      %d frames, RMS left %.0f, right %.0f\n", @s / 2, map sqrt($_ / (@s / 2 || 1)), @sum;
}
unlink '/tmp/fm.raw';

unless ($ENV{KEEP}) {
	mix('Audio Switch', 'Analog');
	mix('Codec Mode', 'Bt');
	mix('Mode Switch', 'Off');
	system('hciconfig hci0 down') if $ENV{HCI} && $ENV{HCI} != 2;
}
print "wl1273-fm interrupts after: ", irqs(), "\n";
klog();
