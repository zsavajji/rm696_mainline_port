#!/bin/sh
# spawncpu.sh BENCH TINY: who spends the CPU while spawnbench runs one phase at a time (stock or the test
# kernel, as user): /proc/stat and every process's utime/stime ticks before and after each phase.
# Parse with tests/spawncpu.py. Phases: 0 fork+exit, 2 vfork+exec tinyexit, 3 fork+exec /bin/true.
B=${1:-/tmp/spawnbench}; T=${2:-/tmp/tinyexit}
snap() {
	echo "== $1"
	head -1 /proc/stat
	for d in /proc/[0-9]*; do read l < $d/stat 2>/dev/null && echo "$l"; done
}
for ph in "idle 0" "0 3000" "2 3000" "3 1500"; do
	set -- $ph
	snap "before $1"
	if [ $1 = idle ]; then sleep 3; else $B $T $2 $1; fi
	snap "after $1"
done
