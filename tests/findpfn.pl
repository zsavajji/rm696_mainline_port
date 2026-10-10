# tests/findpfn.pl, on the test kernel: chroot /newroot perl /tmp/findpfn.pl PFN_HEX (PFN from tracefs page_isolation/test_pages_isolated fin_pfn)
# perl findpfn.pl PFN_HEX: which processes map that physical page (reads /proc/PID/maps + pagemap as root)
my $want = hex($ARGV[0]);
opendir(my $d, "/proc") or die;
for my $pid (grep { /^\d+$/ } readdir $d) {
	open(my $m, "<", "/proc/$pid/maps") or next;
	open(my $pm, "<:raw", "/proc/$pid/pagemap") or next;
	my $comm = do { local $/; open(my $c, "<", "/proc/$pid/comm"); <$c> }; chomp $comm;
	while (<$m>) {
		my ($s, $e, $rest) = /^([0-9a-f]+)-([0-9a-f]+)\s+(.*)$/ or next;
		for (my $a = hex($s); $a < hex($e); $a += 4096) {
			seek($pm, ($a / 4096) * 8, 0); read($pm, my $buf, 8) == 8 or last;
			my ($lo, $hi) = unpack("VV", $buf);
			next unless $hi & 0x80000000;            # present
			my $pfn = $lo | (($hi & 0x7fffff) << 32);
			print "$pid $comm ", sprintf("%x", $a), " $rest\n" if $pfn == $want;
		}
	}
}
