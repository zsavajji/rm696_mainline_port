#!/usr/bin/perl
# On the phone (Harmattan's perl, in the chroot): a minimal sensord client, to check a sensor's data
# path without an app: load the plugin and request a session over D-Bus, attach to sensord's socket,
# start, and hex-dump what arrives (frames are a u32 sample count, then the samples).
# Usage: perl sensortest.pl <sensor> <Interface> [seconds], e.g. compasssensor CompassSensor 5
use strict;
use Socket;

my ($sensor, $iface, $secs) = (@ARGV, 5);
die "usage: $0 sensor Interface [seconds]\n" unless $iface;
my $dbus = "dbus-send --system --print-reply --dest=com.nokia.SensorService";

sub call { my $r = `$dbus @_ 2>&1`; die "dbus @_: $r" if $?; $r }

call("/SensorManager local.SensorManager.loadPlugin string:$sensor") =~ /boolean true/
	or die "loadPlugin $sensor failed\n";
my ($session) = call("/SensorManager local.SensorManager.requestSensor string:$sensor int64:$$")
	=~ /int32 (-?\d+)/;
die "requestSensor $sensor: no session\n" unless defined $session && $session >= 0;
print "session $session\n";

socket(my $s, PF_UNIX, SOCK_STREAM, 0) or die "socket: $!";
connect($s, sockaddr_un("/tmp/sensord.sock")) or die "connect: $!";
syswrite($s, pack("l", $session)) == 4 or die "write: $!";
call("/SensorManager/$sensor local.$iface.start int32:$session");

my $end = time + $secs;
while (time < $end) {
	my $rin = ''; vec($rin, fileno($s), 1) = 1;
	next unless select($rin, undef, undef, 0.5);
	my $n = sysread($s, my $buf, 4096) or last;
	printf "%3d bytes: %s\n", $n, join(" ", unpack("(H8)*", $buf));
}
call("/SensorManager/$sensor local.$iface.stop int32:$session");
call("/SensorManager local.SensorManager.releaseSensor string:$sensor int32:$session int64:$$");
