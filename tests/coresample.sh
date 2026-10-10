#!/bin/sh
# What holds CORE ON: a sampler to run beside tests/coreoff1.sh during an unplugged run (2026-10-08,
# the 40 s CORE stall of boot 279). Every ${S:-2} s one line to /tmp/coresample.log: uptime, CORE's
# OFF/RET counts, C4-C7 usage, cm= the registers omap_sram_idle()'s CORE gate reads, then idle status:
# CM_FCLKEN1/3_CORE (a00, a08: any bit keeps CORE ON), ICLKEN1 (a10), IDLEST1/3 (a20, a28), CLKSTST (a4c;
# bits: tests/cmcore-bits.txt), CM_CLKSEL1_PLL (d40: DPLL3 M2 in bits 31-27, 1 = L3 OPP100, 2 = OPP50:
# erratum 1.85's gate wants OPP50), PRM_VP2_CONFIG (bit 0: SmartReflex 1.5 calibrating VDD2, also a
# gate); runtime-active ms of I2C1-3, the SSI port and UART2,
# the cawake, SSI PORT, I2C3 and bcm4751-gps interrupt counts and the GPS chip's enable. While CORE's
# counts haven't moved for 3 samples (a stall) it adds the runtime-active platform devices, the clocks
# enabled, the CPU latency limit and the L3 policy's state. Stops at /tmp/coresample.stop or after
# ${N:-450} samples. Needs /tmp/devmem-ro (build/devmem-ro). Start detached:
#   setsid sh /tmp/coresample.sh </dev/null >/dev/null 2>&1 &
D=/sys/kernel/debug/pm_debug P=/sys/bus/platform/devices
cnt() { grep "^core_pwrdm" $D/count | cut -d, -f2-3 | tr -d ' '; }
act() { cat $P/$1/power/runtime_active_time; }
irq() { awk -v n="$1" '$NF == n {print $2}' /proc/interrupts; }
cm() { /tmp/devmem-ro 0x48004a00 0x48004a08 0x48004a10 0x48004a20 0x48004a28 0x48004a4c 0x48004d40 \
	0x483072d0 | cut -d' ' -f2 | tr '\n' ' '; }
rm -f /tmp/coresample.stop; i=0; h1= h2= h3=
while [ ! -e /tmp/coresample.stop ] && [ $i -lt ${N:-450} ]; do
	c=$(cnt)
	echo "$(cut -d' ' -f1 /proc/uptime) core:$c C4-7=$(for s in 3 4 5 6; do cat /sys/devices/system/cpu/cpu0/cpuidle/state$s/usage; done | tr '\n' /) cm=$(cm)i2c=$(act 48070000.i2c)/$(act 48072000.i2c)/$(act 48060000.i2c) ssi=$(act 4805a000.ssi-port) u2=$(act 4806c000.serial) cawake=$(irq cawake) port=$(irq PORT) i2c3i=$(irq 48060000.i2c) gps=$(irq bcm4751-gps)/$(cat /sys/bus/i2c/devices/3-01fa/enable)" >> /tmp/coresample.log
	if [ "$c" = "$h3" ]; then
		echo "  stall: active=$(grep -l '^active' $P/*/power/runtime_status 2>/dev/null | cut -d/ -f6 | tr '\n' ,) lat=$(od -An -td4 -N4 /dev/cpu_dma_latency | tr -d ' ') l3=$(tr '\n' ' ' < /sys/kernel/debug/omap3_l3 | cut -c1-200)" >> /tmp/coresample.log
		echo "  clocks: $(awk '$1 ~ /_(fck|ick)$/ && $2 > 0 {printf "%s:%s ", $1, $2}' /sys/kernel/debug/clk/clk_summary)" >> /tmp/coresample.log
	fi
	h3=$h2 h2=$h1 h1=$c i=$((i + 1))
	sleep ${S:-2}
done
