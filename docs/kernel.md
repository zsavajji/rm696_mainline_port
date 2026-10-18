# The kernel

`linux_mainline_rm696`, branch `rm696`: **linux-stable v6.18.55** and about 280 commits on top, one
change each, with the reason in its message. RM-696 is the N9's type code. The port started on
v6.18.53; stable releases come in as merges of their tags, so `git log --no-merges v6.18.55..rm696`
is the whole port.

The aim is Nokia's 2.6.32 kernel's behaviour on a current kernel: Harmattan's closed userspace stays
exactly as it shipped, so where 6.18 differs from 2.6.32 at a device name, a sysfs path, an ioctl or a
timing Harmattan depends on, the kernel gives Harmattan what it expects. The sources for that were
Nokia's own kernel (as published for the N9), Nemo Mobile's 3.5 port of its drivers, and the PR1.3
root filesystem.

## Configuration

`omap2plus_defconfig` with `arch/arm/configs/rm696.config` on top: an N9-only, single-core OMAP3630
kernel, omapfb instead of omapdrm (Harmattan's X driver and the SGX driver use omapfb), stock's
128 Hz tick, and none of the hardening that Nokia's 2012 kernel didn't have either.
[Removed and switched off](./removed) lists each such choice, what it measured and how to undo it.

## What the commits do

| Area | Changes |
|---|---|
| Display | omapfb with Nokia's interfaces: the DSS notifier, `update_mode`, landscape updates split in two halves timed from the panel's TE, DSI ULPS when idle, stock's framebuffer geometry and video memory, NOLO's logo taken over, the panel's power controls for mce, TV-out over VENC |
| GPU | `fbdev` exports and hooks for the out-of-tree SGX driver (its own repository, `pvr_sgx_rm696`), the SGX held out of smart idle |
| Power | CORE/L3 frequency scaling (Linux 4.1's DPLL3 code, back) with a policy as Nokia's, VDD1/VDD2 through the voltage processor, SmartReflex class 1.5, Nokia's OFF-mode policy and TWL5031 sleep scripts, IO pad wakeups, OMAP3630 errata as stock, the N9's C-state latencies, the oscillator's start-up time, power-off as stock |
| DSP | the TI DSP bridge (tidspbridge, removed from mainline after 3.16) brought back and fixed for Harmattan's gst-dsp: video decoding and the cameras' DSP stage |
| Cameras | the OMAP3 ISP with Harmattan's media and V4L2 interfaces, Nokia's smiapp, AD58xx lens and AS3645A flash drivers |
| Audio | Nokia's `dfl61` machine driver (two cards as stock), the TLV320DAC33's low-power FIFO mode, McBSP power levels, the AV jack's buttons, ECI accessories and TV-out switch |
| Radios | WLAN on SDIO with Nokia's NVS push, `hci_nokia` for the TI1273 at 3.69 Mbaud, Nokia's WL1273 FM drivers, Nokia's PN544 NFC driver, the modem's SSI/HSI and `cmt_speech` fixes |
| Sensors and input | Nokia's AK8975 compass, BCM4751 GPS, APDS990x light/proximity and vibra drivers, the maXTouch with Nokia's configuration, wake gesture and protocol A, the LP5521 LED |
| Harmattan's interfaces | Aegis (below), `/dev/iphb`, the phonet group, `/proc/interrupts` in 2.6.32's form for csd, GPIO numbering, I2C and gadget names, watchdog device names, zram as `ramzswap`, the OneNAND writable as stock (CAL itself stays locked under any unsigned kernel, see [Power](./power#cal-and-onenand)), many sysfs paths |
| Speed | single-CPU scheduler paths, cheaper fork and mmap, the Cortex-A8 branch predictor flush only with hardening, fewer wakeups for audio and the DSP's mailbox |

### Mainline bugs found on the way

Fixed in the tree, each in its own commit (`git log --grep` finds them by subject):

- `clk: ti: mux: no latch bit for composite muxes`: every parent change of a TI composite mux toggled
  bit 0 of its register; on the N9 the SGX lost its clock when DPLL4 stopped (since Linux 4.17).
- `wifi: wlcore: fix runtime PM leaks in firmware restarts` and `wifi: wlcore: don't leak runtime PM
  when setting TX power fails`: the WLAN chip never entered its low-power state (the N9 now runs
  Nokia's driver instead, see [Power](./power#wlan-power-save)).
- `usb: musb: don't restore a context the controller kept`: the USB network dead after a replug.
- `usb: musb: gadget: don't flush the RX FIFO when queueing a request`: mass-storage writes stalled.
- `ARM: OMAP3: hwmod: don't wait for the I2C's RESETDONE in the hwmod`: after every CORE OFF the
  first access to each I2C bus spun 14 ms with interrupts off, waiting for a bit the I2C sets only
  once enabled ([Power](./power#i2c-after-core-off)).
- `serial: 8250: drop the TX runtime PM reference at shutdown` and `serial: 8250_omap: raise RTS after
  the EFR write when autoRTS is on`: Bluetooth's UART stuck awake, and its first byte after a wakeup
  misread at 3.69 Mbaud.
- `HSI: omap_ssi_port: don't write the divisor of a suspended port` and `HSI: omap_ssi_port: acknowledge
  the status a context loss leaves`: L3 errors and garbage words on the modem link.
- `netlink: refuse a dump chunk only when the receive queue is already full`: Harmattan's modem daemons
  spinning after a USB replug.
- `phonet: pep: pull the header before parsing a connect request's sub-blocks`: `accept()` dropped a pipe
  connect request that carried sub-blocks, so mobile data's pipe never came up
  ([Modem](./modem#what-harmattan-needs-from-the-kernel)).
- `wifi: mac80211: ignore a -128 dBm country element power limit`: some access points capped the
  transmit power at 0 dBm.
- `i2c: omap: don't touch a suspended controller from the interrupt thread`.
- `usb: gadget: u_ether: messages on a detached gadget`: an oops at a cable replug.
- `phy: ti: phy-twl4030-usb: no VBUS_OFF to musb for a cable it never heard of`: after a wall charger
  was unplugged, CORE never reached retention again until the next cable.
- `ARM: OMAP3: PM: restore SDRC_POWER after OFF on the HS 3630 too`: on HS chips the ROM leaves the SDRAM
  in self-refresh-at-every-pause after a CORE OFF wake-up and the kernel put the normal setting back on the
  3430 only: from the first CORE OFF on, RAM accesses were about 3x slower (typing lagged). See
  [Performance](./performance).
- `wifi: wl12xx: 100 ms dynamic power save timeout, as stock`, and the panel's `no 100 ms TE wait` and
  `skip the first TEs after TEAR_ON`: standby power and redraw latency as stock.

## Aegis

Harmattan's security framework, Aegis, is a Nokia kernel module set (credentials, resource tokens, the
validator that checks binaries against signed hash lists). It is here ported to 6.18, and Harmattan's
userspace finds the interfaces it expects. It runs in **open mode**
only (`aegis.mode=open` on the command line): it logs what it would refuse and refuses nothing, and
loads unsigned modules such as the SGX driver. As in stock's open mode, root keeps its capabilities in
processes started under an Aegis policy (`devel-su`, root daemons). An enforcing (closed) mode isn't supported.

## Licence

GPL-2.0, as Linux (`COPYING`). Nokia's drivers, Aegis and the DSP bridge are GPL-2.0 as well.
