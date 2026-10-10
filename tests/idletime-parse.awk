# LC_ALL=C awk -f idletime-parse.awk TRACE: mean duration of each *_in/*_out pair (us) and the pair count
{
	ts = ""
	for (i = 1; i <= NF; i++)
		if ($i ~ /^[0-9]+\.[0-9]+:$/) { ts = $i; sub(/:/, "", ts); ev = $(i + 1); break }
	if (ts == "") next
	sub(/:$/, "", ev)
	t = ts + 0
	if (ev ~ /_in$/) { name = ev; sub(/_in$/, "", name); start[name] = t }
	else if (ev ~ /_out$/) {
		name = ev; sub(/_out$/, "", name)
		if (start[name]) {
			d = (t - start[name]) * 1e6
			if (d >= 0 && d < 5000) { sum[name] += d; n[name]++ }
			start[name] = 0
		}
	}
}
END {
	for (k in n) printf "%-28s n=%5d  mean %5.1f us\n", k, n[k], sum[k] / n[k]
}
