#!/bin/sh
# On a RAM-booted test kernel with camera-debug's omap3_isp parameters: one ispcap run with the given
# switches, then the frame rate, interrupt counters (nonzero bits) and the dividers chosen.
# Usage: camtest.sh CSI2_VP_DIV OCP_AUTOIDLE SBL_AUTOIDLE [ispcap args...]
P=/sys/module/omap3_isp/parameters
vp=$1 ocp=$2 sbl=$3; shift 3
z=0; i=1; while [ $i -lt 32 ]; do z="$z,0"; i=$((i + 1)); done
for f in irq_counts sbl_counts csi2_irq_counts csi2_phy_counts; do echo $z > $P/$f; done
echo $vp > $P/csi2_vp_div; echo $ocp > $P/ocp_autoidle; echo $sbl > $P/sbl_autoidle
t0=$(cut -d' ' -f1 /proc/uptime)
chroot /newroot /tmp/ispcap "${@:-150}" > /tmp/ispcap.out 2>&1 &
pid=$!
lim=$(( ${1:-150} / 20 + 10 ))
n=0; while kill -0 $pid 2>/dev/null && [ $n -lt $lim ]; do sleep 1; n=$((n + 1)); done
kill -0 $pid 2>/dev/null && { echo "ispcap still running after $lim s: killed"; kill $pid; sleep 2; }
t1=$(cut -d' ' -f1 /proc/uptime)
echo "== vp_div $vp ocp $ocp sbl $sbl, ${t0}-${t1} s"
grep -E 'fps|timeout|error|Error' /tmp/ispcap.out | tail -3
for f in irq_counts sbl_counts csi2_irq_counts csi2_phy_counts; do
	echo "$f: $(tr ',' '\n' < $P/$f | awk '$1 != 0 { printf "b%d=%s ", NR - 1, $1 }')"
done
dmesg | grep -v 'command line' | grep -E 'camera-debug|omap3isp|L3|Unable' | tail -4
