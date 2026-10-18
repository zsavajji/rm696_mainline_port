# Power

The kernel runs the N9's power management as Nokia's 2.6.32 did: CPU and CORE/L3 frequency and voltage
scaling with SmartReflex class 1.5, and CORE retention and OFF in idle under Nokia's OFF-mode policy,
with Harmattan's own `pmconfig`, BME and DSME in charge as on stock. This page lists each part, what
was measured, where it differs from stock, and how to measure it yourself.

## Harmattan's pmconfig

At boot `/sbin/preinit` runs `/sbin/read_cfg.awk` on `/etc/pmconfig`, which writes each line to a
kernel file. Stock PR1.3's file and where each line lands here:

| pmconfig line | Kernel file | Effect on 6.18 |
|---|---|---|
| `disable_core_off 0` | `pm_debug/disable_core_off` | CORE OFF allowed (1 stops at retention) |
| `enable_off_mode 1` | `pm_debug/enable_off_mode` | OFF mode on, from boot |
| `sleep_while_idle 1`, `voltage_off_while_idle 1` | `pm_debug/...` | accepted; 6.18 behaves as if both were 1 |
| `sr_vdd1_autocomp 1`, `sr_vdd2_autocomp 1` | `/sys/power/sr_vdd*_autocomp` | SmartReflex class 1.5 on both VDDs |
| `clocks_off_while_idle 1` | (commented out in `read_cfg.awk`) | none, as on stock |
| `scaling_governor ondemand`, `scaling_min_freq 300000`, `scaling_max_freq 1000000` | cpu0's cpufreq | ondemand, 300 MHz to 1 GHz |
| `sleep_ind 1` | (no line in `read_cfg.awk`) | none |

`pm_debug` is `/sys/kernel/debug/pm_debug`. Mainline had none of Nokia's knobs, and awk stopped at the
first write that failed, so nothing after it applied, SmartReflex included (`6b5257b59` adds them).

Until `0a14c7129` an N9-only `off_mode_armed = 0` held pmconfig's `enable_off_mode 1` back unless a
test session armed it: the release image ran 5 hours with CORE never OFF and MPU OFF never entered
(cpuidle C4, C6 and C7 usage 0). OFF mode is now armed at boot, as on Nokia's kernel.
`pm_debug/off_mode_armed` stays as a test switch: write 0 to hold the request back, 1 to release it.

## Idle states

| State | MPU | CORE | Exit latency (N9) | Target residency (N9) | Mainline's generic table |
|---|---|---|---|---|---|
| C1 | ON | ON | 102 us | 101 us | 4 / 5 us |
| C2 | ON, clock domain idle | ON | 146 us | 183 us | 20 / 30 us |
| C3 | retention | ON | 252 us | 29.2 ms | 100 / 300 us |
| C4 | OFF | ON | 2.3 ms | 42.6 ms | 3.3 / 4 ms |
| C5 | retention | retention | 5.6 ms | 56.1 ms | 10 / 12 ms |
| C6 | OFF | retention | 7.7 ms | 77.6 ms | 11.5 / 15 ms |
| C7 | OFF | OFF | 22.3 ms | 99.1 ms | 40 / 300 ms |

The N9 column is Nokia's own measurement (`board-rm696.c`, sleep plus wake latency), applied for
`nokia,omap3-n9` by `bbd32bffc`; C7 is stock's C7 (`9066b7305`; stock's C8, 158 ms, adds what this
kernel's C7 does anyway, OFF with the secure RAM save, and with it most standby idles stayed in
retention). With mainline's table the display's 6 ms latency limit refused C5, and the
governor took MPU retention for idles of 300 us, where Nokia asked for 29 ms.

Two latency limits apply, both as stock: 6 ms while the display is on and not in its low-power standby
mode (the panel's `idle_latency_us` in sysfs), and 6 ms for 1 s after any key or touch (the input
boost, below). So C5 runs with the screen on; C6 and C7 only with the display off.

In standby the state is picked as stock's cpuidle did (`23d3a1489`, Nokia's `cpuidle_chip_is_idle()`):
with the tick stopped, no functional clock running in CORE or PER (the UARTs aside) and CORE OFF
allowed, the deepest state that the next timer and the latency limit allow, instead of the menu
governor's guess, which took retention or less for most idles long enough for OFF. Switch:
`/sys/module/cpuidle34xx/parameters/chip_idle_deepest` (default Y).

Beyond the table, `omap_sram_idle()` keeps CORE ON for an idle when a CORE functional clock runs, when
L3 is held high and can't be lowered for this idle (below), or while SmartReflex calibrates VDD2. With
the camera domain on, only C1 is used. Nokia's policy (`fcc18ed79`) adds: PER OFF only with CORE OFF,
CORE OFF only with CAM, DSS, IVA2, SGX and USBHOST off (`346db0a2d` counts DSS and USBHOST as going OFF
with the MPU), the IVA2 left to the DSP bridge.

## CORE retention and OFF

### What kept CORE on

CORE retention needs every CORE clock idle. Each of these held it on (in mainline 6.18 or in an earlier
state of this port) and is fixed, mostly as stock did it:

| Commit | Blocker |
|---|---|
| `35a7fec2d` | WDT2 (DSME's watchdog) in no-idle for as long as it ran; force idle as stock's driver set it |
| `68b9826ec` | I2C's 1 s runtime-PM autosuspend; 0 as stock (idle after each transfer) |
| `12e998bcd` | the bandgap's clock held for good; now only around a conversion |
| `0790e6776` | the DSI PLL's input clock leaked one enable per display on/off |
| `434fe6b03` | the unused SHA1/MD5 accelerator's hwmod kept its clock on |
| `e1792b9bf` | the ISP's IOMMU active from probe, holding the camera domain and the MPU in C1 |
| `a7b61bb36` | this port's GPT10 clocksource (a CORE timer), reverted: the 32 kHz counter, as stock (cost: [Performance](./performance#scheduler-and-context-switches)) |
| `4d1e42064` | DPLL3 kept locked; erratum 1.85 workaround 2 as stock: DPLL3 in automatic mode around CORE idle only |
| `1c87ecc8b` | after a wall-charger unplug musb ran with the PHY powered down (below) |

UART1 and UART4 (not wired on the N9) are disabled in the device tree; Bluetooth's UART2 idles as on
stock ([Bluetooth](./bluetooth)).

### What OFF needs

All as Nokia's kernel did, except `58fde0d17` and `75eaae875`, which fix bugs (the latter's is in
Nokia's kernel too):

| Commit | What |
|---|---|
| `c2f638ca4`, `4ea7a477f` | the HS secure RAM (48 KiB) saved through the ROM at every CORE OFF entry; a failed save sends that entry to retention instead |
| `5383469c6`, `a5ced2f6f` | L2 auxiliary control saved through the PPA; erratum 1.107 at boot |
| `9e65783c7` | the scratchpad saved again after every DPLL1 and DPLL3 change (the ROM relocks both from it) |
| `dd5510056`, `3f1b231ce` | Nokia's TWL5031 sleep and wake scripts and resource configuration, decoded from stock's binary; the regulators no longer rewrite the sleep remaps |
| `72d64f25f`, `be67433c1` | the IO daisy chain armed around CORE RET/OFF; the wake bit on every GPIO interrupt's pad and sys_nirq |
| `d5525319a` | erratum 1.45 around PER OFF: GPIO outputs held by their pulls |
| `df1eb9813` | the mailbox's idle mode and interrupt enables kept across OFF |
| `aed6f173d` | every pad as stock runs it |
| `58fde0d17` | the modem port's status after a context loss acknowledged (one garbage word per OFF wake before) |
| `75eaae875` | SDRC_POWER restored after OFF on the 3630 too (below) |
| `e9943aa01` | reboot with the global software reset: mainline's DPLL3 warm reset runs the TWL's sleep script, which with VDD1 and VDD2 remapped OFF left the phone dead until a battery pull |

**SDRC_POWER.** On HS chips the ROM restores SDRC_POWER from the scratchpad at every CORE OFF wake-up,
with self-refresh after an idle count of 1 (erratum i443). `omap_sram_idle()` put the normal value
(0x9) back only on the 3430, so after the first CORE OFF the SDRAM dropped into self-refresh at every
pause for the rest of the boot (0x129): random SDRAM loads about 3x slower, typing lagged. Nokia's
2.6.32 has the same gate; whether stock was affected was not measured. With the fix, after 812 CORE
OFF entries SDRC_POWER still reads 0x9 and random loads over 8 MB take ~240 ns (~700 ns in the slow
mode). More numbers in [Performance](./performance#the-memory-path).

### Measured

Unplugged, display off and locked (the 6.18 runs with Bluetooth off and WLAN down; stock on a normal
boot):

| Kernel | CORE OFF | CORE retention |
|---|---|---|
| stock 2.6.32 | 1322 entries, 188 of 346 s in OFF | 94 |
| 6.18, OFF not armed | 0 | ~130 a minute, 263 of 266 s in retention |
| 6.18, OFF armed, CPU and L3 at fixed clocks | 175 in 180 s (93% of C7 picks reached OFF) | |
| 6.18, OFF armed, DVFS live | 150 in 300 s (59% of C7 picks) | |
| 6.18, OFF armed, the modem talking every minute | ~700 in 10 min | |

The release image (kernel `592e0d149`, OFF armed at boot) gave 334 CORE OFF and 986
retention entries in 14 minutes of unplugged standby.

Clean wakes from OFF by the RTC alarm, keys and Bluetooth; 0 secure RAM save failures in hundreds of
saves. Bluetooth on changes nothing ([Bluetooth](./bluetooth)).

With the screen on and still and WLAN associated, CORE now retains as on stock: 208 retentions in 90 s
(0 before `ff7ed3abd`/`e16a0248f`, below).

Battery drain: with CORE stuck ON overnight (the charger bug below) the drain was about 25-70 mA.
Standby on a 5 GHz access point, WLAN associated, screen off: 18 mA with Nokia's WLAN driver
([WLAN power save](#wlan-power-save)), CORE OFF 25% of the time; with the I2C fix below, CORE OFF
41% and 13-15 mA. The standby clock adds about 9 mA while it shows: the panel draws it by itself in
its low-power mode (`lpm` in the panel's sysfs, in `tests/powerlog.sh`), with nothing on the SoC side
changing; stock's 6-8 and 11-16 mA phases on the same access point are the same two states.
The TWL5031 charger driver's wall-charger poll no longer wakes the CPU (`b47966392`). With stock's
idle choice (`23d3a1489`, [Idle states](#idle-states)) a night of 11 hours with the standby clock on:
15.5 mA (median 11), CORE OFF 64% (23-24 mA and 41% before it, stock 11-16 mA in that state).

### I2C after CORE OFF

`9e69d67db`: the first access to each I2C bus after every CORE OFF took 14 ms with interrupts off
(BME's and DSME's, a few times a second in standby). After OFF the I2C comes back reset, and it sets
RESETDONE only once its enable bit is set; the hwmod waited for RESETDONE before the driver could set
it, for its whole 10 ms timeout (`_enable_sysc()`, 152 of 649 enables in 2 minutes, kprobe timings).
The driver waits for it itself, with the enable bit set, when it resets the controller; the hwmod no
longer does. The I2C's wake-up path now takes under 0.4 ms.

### Not done

- Stock's retention voltage setting (0.8375 V) and its watchdog guard around OFF are not ported.
- With WLAN associated, about 29 wake-ups a second remain in standby (stock's are fewer), and the
  idle governor picks retention for many idles long enough for OFF.
- Once, CORE stayed ON for ~40 s with nothing found holding it; `tests/coresample.sh` names the holder
  if it happens again.

## The oscillator start-up time

In CORE retention and OFF the PRCM releases the system oscillator (sys_clkreq) and waits
`PRM_CLKSETUP` for it on wake-up. Mainline's default is 10 ms (328 cycles of 32 kHz); Nokia's board
files set 113 cycles (3.45 ms) and a matching `VOLTSETUP2`. `8167154ce` does the same for the N9 and
N950. Wake latencies measured with `tests/wakelat.c` (`tests/oscsetup.sh`):

| Wake from | 328 cycles (mainline) | 113 cycles (stock, now) |
|---|---|---|
| CORE retention (C5) | 11.2-11.4 ms | 4.6-4.8 ms |
| MPU OFF + CORE retention (C6) | 11.8-12.5 ms | 5.3-5.9 ms |
| CORE OFF (C7) | 23.3-23.4 ms | 16.8 ms |

Every retention wake pays it, whether OFF is armed or not. With 113 the wakes fit Nokia's C-state
table. Not checked: the cold, a long soak, an N950.

## CPU frequency and voltage

| OPP | VDD1 nominal | VDD1 with SmartReflex (this phone) |
|---|---|---|
| 300 MHz | 1.0125 V | 0.875 V |
| 600 MHz | 1.200 V | 0.975 V |
| 800 MHz | 1.325 V | 1.0875 V |
| 1 GHz | 1.375 V (ABB in forward body bias) | 1.1625 V |

- `cpufreq-dt` with omap36xx's OPPs; mainline's 1 GHz is turbo-only for DM37x speed-binned chips,
  stock ran every N9 at 1 GHz, so the N9's device tree makes it a normal OPP.
- VDD1 and VDD2 are set through the voltage processor (`d988b6aae`): with the TWL in SmartReflex mode
  their VSEL registers are ignored, so mainline's regulator writes did nothing.
- The governor is pmconfig's `ondemand`; the kernel leaves its tunables at mainline's defaults
  (`/sys/devices/system/cpu/cpufreq/ondemand/`). An A/B of `up_threshold` 80 against 60 showed no
  gain ([Performance](./performance#the-cpu-governor)).
- **Input boost** (`86ae9abe1`), as stock's PM optimizer: after a key or touch the CPU runs at its
  maximum with a 6 ms idle latency limit for 1 s (`/sys/module/cpufreq_input_boost/parameters/`
  `boost_ms`, `latency_us`). Devices without keys (the accelerometer) don't trigger it.
- **GPU floor**: while the SGX is busy the CPU stays at or above 800 MHz
  (`/sys/module/pvrsrvkm/parameters/cpu_min_khz`, 0 = off). Stock had none.
- **Overclock, off by default**: boost OPPs at 1.1 GHz (1.3875 V) and 1.2 GHz (1.4 V), enabled with
  `echo 1 > /sys/devices/system/cpu/cpufreq/boost`. SmartReflex stays off at both (no eFuse target for
  those voltages). Chips differ; the N9 community's daily ceiling was 1.2 GHz. The thermal zone still
  throttles; the CPU temperature is read every 5 s (stock read none).

## CORE/L3 frequency scaling

`43e535b97` brings back Linux 4.1's DPLL3 M2 switch: CORE 390.4 or 195.2 MHz, L3 and the SDRAM
controller 195.2 (OPP100) or 97.6 MHz (OPP50), run from SRAM with the SDRAM in self-refresh and its
refresh rate reprogrammed. VDD2 follows: 1.2 or 1.0 V nominal, 0.95 or 0.8375 V with SmartReflex.

The policy is Nokia's: L3 at OPP50 unless something holds it high. Raised at once, lowered 100 ms after
the last hold went (`/sys/module/clkt34xx_dpll3m2/parameters/l3_lower_delay_ms`).

| Holder | When |
|---|---|
| `cpu` | the CPU above `scaling_min_freq` |
| `sgx` | from before the GPU gets its clock (CORE/2) until after it lost it |
| `dss` | the display on and not in its low-power standby mode; in standby, each clock update |
| `usb` | a USB cable in (released within 2 s of an unplug) |
| `isp` | the camera streaming |

Stock also held L3 for WLAN while associated and out of power save; that hold is dropped
(`0f5c6b8a0`): the firmware's dynamic power save hides it from the host, and real traffic loads the
CPU, whose rule holds L3.

The lowering delay, measured in settled standby: 1000 ms kept L3 at OPP50 39% of the time (39 switches
a minute), 500 ms 61% (43), 250 ms 66% (49), 100 ms 77% (53), 0 ms (stock) 79% (60).

**In idle** (`ff7ed3abd`, `e16a0248f`), as Nokia's kernel: with L3 held at OPP100, CORE retention
lowers DPLL3's M2 to OPP50's rate inside the idle path (VDD2 untouched) and restores it after the
wake-up, so the display's and the CPU's holds no longer keep CORE out of retention. Not while the
SGX, ISP or USB hold L3, the DSP is clocked or the display controller is fetching a frame. Retention
only: an OFF pick with L3 high becomes retention.

`/sys/kernel/debug/omap3_l3` shows time at each level, switches, the idle lowerings and each holder's
count. Writing `low`, `high` or `auto` pins the level for tests; `-usb` (or `-cpu`, `-wlan`) stops
counting that holder, `+usb` counts it again.

## SmartReflex

Class 1.5, as Nokia's kernel (`271ae6cb6`, `b511623ca`, `5857f2ef3`): after a change to an OPP without
a calibrated voltage, SmartReflex and the voltage processor run until the voltage settles; that
voltage becomes the OPP's and SmartReflex stops. The OPP then runs at it, and is recalibrated after
24 h from 50 mV above. A VDD calibrating keeps its domains out of retention for that time (as stock).
Mainline's class 3, which runs all the time and had to be stopped and restarted around every idle
entry, is not built.

Calibrated on this phone: VDD1 above; VDD2 0.8375 V at L3 OPP50 and 0.95 V at OPP100.
`/sys/kernel/debug/sr_calib` lists each OPP's nominal, starting and calibrated voltage. Writing 0 to
`/sys/power/sr_vdd*_autocomp` drops the calibrations, as on stock.

Nokia's class 1.5 sampled the voltage on SmartReflex's MCUBOUNDS interrupt, which never reached the
CPU, so stock always took the voltage processor's value at its second check; the port reads that value
at the same checks (settled when two agree, else the highest after five).

## Charging and charger detection

As Nokia's `twl5031-bcc` (`a2b07927d`, `e084ac271`): on VBUS, with the PHY powered down, data contact
detection, then the TWL5031's charger state machine, then D+'s line state. The gadget connects only
after a successful data contact and never to a wall charger. The `usb` power supply reports:

| Found | `POWER_SUPPLY_TYPE` | `CURRENT_NOW` | Harmattan |
|---|---|---|---|
| a host port | `USB` | 100 mA, then the configuration's (500) | BME charges at that current; usb_moded offers its USB modes |
| a charging host port | `USB_CDP` | 500 mA, 900 once enumerated | as above |
| a wall charger | `USB_DCP` | | BME charges as from a wall charger; no USB mode |

The gadget configurations declare 500 mA, as stock's.

- `da752d39b`: BME's uevent socket (`SO_RCVBUF` 600) holds about one uevent on 6.18, and the PHY's own
  uevents came first at an unplug, so BME missed the supply going away and showed "wrong charger".
  Each change is now announced again 200 ms later.
- `1c87ecc8b`: the detection never tells musb of a wall charger (or of a cable whose data contact
  failed), but the unplug still sent musb VBUS_OFF. musb then ran and idled with the PHY powered
  down, and CORE never reached retention again: about 15 hours overnight. VBUS_OFF now goes only for
  a cable musb was told of, as stock. Checked on the phone: CORE kept retaining through 18 minutes on
  a wall charger, and after the unplug it kept going (126 OFF and 417 retention entries in the 5
  minutes watched, ~79 retentions a minute) with musb runtime-suspended across the unplug.

## The battery (BME)

Nokia's closed battery daemon, BME, runs as on stock. It drives the bq24153 charger itself over
`/dev/i2c-1`, reads the battery through Nokia's `/dev/twl4030-adc` (ported onto mainline's MADC driver)
and reads the `usb` and `vac` power supplies at their uevents. Mainline's TWL4030 charger node is
disabled.
`bmestat` (in Harmattan) prints the charger type, charge state, level, remaining capacity and battery
current.

Known fragility: BME's small uevent socket. Once BME was seen spinning in kernel time after its socket
overran (`Drops` for its pid in `/proc/net/netlink`); `initctl restart bme` recovers it.

## Power-off and charging while off

Stock's power-off is back (`e0e5aff12`: DEVOFF in all three processor groups, the start-on events
left alone, so a charger starts ACT_DEAD and an alarm can power the phone on, as on stock). Not yet
tried on a phone ([Status](./status)).

## WLAN power save

The WLAN chip runs Nokia's own driver and firmware, as on stock (`drivers/net/wireless/ti/wl1271`:
Nokia's wl12xx ported to 6.18, with stock's firmware 6.1.1.39.339 from Harmattan's `/lib/firmware`).
Mainline's wlcore with linux-firmware's 6.3.10 never got the chip into power save on 5 GHz: standby
drew 119 mA on a 5 GHz channel where stock draws 9.7 mA (same channel, same spot; the firmware's
`ps_enter` counter stayed 0), and its 6.5.7 multi-role firmware doesn't run on this chip.

- Nokia's driver expects mac80211 to report the association together with the BSSID, as 2.6.3x did;
  6.18 reports the BSSID at authentication and the association alone, and without its join the driver
  never counted itself associated, so it never entered power save (`50ad704e2`). With that, standby on
  the same 5 GHz channel: 18 mA over 3 hours, CORE OFF 25% of the time, 0.9 WLAN interrupts a second.
- The chip goes to ELP 5 ms after the last access (the driver's `ELP_ENTRY_DELAY`), and the WLAN slot's
  SD host turns its clocks off 10 ms after the last transfer, as stock's kernel (`6878fd12c`).
- Stock's sysfs knobs are back where `wlancond` looks for them (`/sys/devices/platform/wl1271`:
  `scan_size`, `scan_delay`, `bt_coex_state`, `allow_adhoc`, `hw_pg_ver`), and `wl1271-cal` pushes the
  CAL calibration through nl80211 testmode, as on stock. `wlan0`'s address comes from the chip's fuse,
  as it did with wlcore.

## Other drivers' idle

- The display enters DSI ULPS 500 ms after the last update, as stock; the standby screen runs in the
  panel's low-power mode ([Display](./display)).
- The DAC33's low-power FIFO mode runs for long-buffer playback ([Audio](./audio)).
- McBSP wakeups no longer wake the CPU (`3a5439de6`): mainline grouped McBSP2/3/4 with the MPU.
- The SGX powers down 1 ms after it idles, as Nokia's driver.
- The R&D sleep indicator lights are off at boot, as stock (`0342d26bd`).

## CAL and OneNAND

CAL, the OneNAND's `config` partition, is where libcal keeps BME's, DSME's and the secure storage's
data. `395b6b051` writes it as Nokia's kernel did: NOLO's block locks kept, each page programmed on its
own (no cache program, no write verify), no OTP.

When NOLO boots a kernel without Nokia's signature, which includes stock's own open-mode kernel, CAL
(blocks 4-12) is locked tight. CAL writes from BME, mce and DSME then fail with `onenand_wait: controller
error = 0x0400` and `write failed -5`, exactly as on stock in open mode, and nothing is written. The
frequent `correctable ECC error = 0x5555` messages are stable correctable bit flips on CAL pages, also
seen on stock.

## Measuring

Mount debugfs first (`mount -t debugfs none /sys/kernel/debug`). Unplug USB: a cable holds L3 and
musb's clock. Wait for the end of Harmattan's start-up (3-4 minutes).

| Where | What |
|---|---|
| `pm_debug/count` | per power domain: current state, then OFF, RET, INA counts (`core_pwrdm`, `mpu_pwrdm`, `per_pwrdm`, ...) |
| `pm_debug/time` | per power domain: nanoseconds in each state |
| `pm_debug/secure_ram_saves`, `secure_ram_save_fails` | CORE OFF entries that saved the secure RAM |
| `/sys/devices/system/cpu/cpu0/cpuidle/state0..6/` | C1-C7 `usage` and `time` |
| `/sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state` | time per CPU frequency (10 ms units) |
| `/sys/kernel/debug/omap3_l3` | L3 levels, switches and holders |
| `/proc/interrupts` | `pm_wkup` counts PRCM wake-ups |
| `/sys/class/leds/debug::sleep/brightness` | write 1: the sleep indicator lights show sys_clkreq, dark while the SoC sleeps |

In `pm_debug/count`, only domains walked at that idle are counted: the device domains (DSS, CAM, SGX,
IVA2, USBHOST) count at CORE idles; `pm_debug/count_all_domains` 1 walks every domain at every idle.

Scripts in `tests/`, run as root from the [rescue SSH](./rescue) shell (Harmattan at `/newroot`):

- **`powerlog.sh`**: a battery day log, one line a minute to `/tmp/powerlog.txt`: CORE seconds in
  ON/RET/OFF and entries, MPU OFF entries, C5-C7 picks, wake-up/timer/MMC/WLAN/I2C interrupts, WLAN
  state and packets, the WLAN chip's awake and asleep seconds, backlight, USB, battery voltage, BME's
  level, capacity and current, and seconds at 600/800/1000 MHz; the top CPU users every 10 minutes.
  The counters are cumulative: subtract two lines for a period. Start with
  `setsid sh /tmp/powerlog.sh </dev/null >/dev/null 2>&1 &`, stop with `touch /tmp/powerlog.stop`.
- **`coreidle.sh`**: CORE idle against the USB cable, a line every `S` seconds (5) for `N` lines (360):
  VBUS, CORE and USBHOST counts, the OTG, musb and PHY runtime PM state, CORE's clock enables and
  idle status, the L3 holders. Its register column needs a multi-address `/dev/mem` reader at
  `/tmp/devmem-ro`.
- **`wakelat.c`** and **`oscsetup.sh`**: wake-up lateness per idle state; **`coresample.sh`**: what
  holds CORE ON, every 2 s; **`screenon-core.sh`**: CORE retention with the screen on and WLAN
  associated; **`idlestates.sh`**: entries and residency per state over a minute;
  **`twl-pm-dump.pl`**: a read-only dump of the TWL5031's power registers and scripts.
