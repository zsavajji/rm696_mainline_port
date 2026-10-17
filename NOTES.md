# Development notes

The project's working record: every change, test and finding, in order. For installing and building,
see the documentation at https://zsavajji.github.io/rm696_mainline_port/ and `README.md`.

Goal: a modern kernel on the real Nokia N9 that still runs Harmattan's GPU stack. Harmattan's GL
libraries are closed blobs (SGX DDK **1.4.14.2514**, `*_r125.so`, `libsrv_um`), so the kernel side must
keep their interface exactly. This builds that kernel side for Linux 6.18.53 (the version n9-qemu's
Aegis port targets).

Status (2026-09-30): **runs on the real N9.** RAM-booted 6.18 (below): `pvrsrvkm` powers the SGX and
reads revision 1.2.5, and Harmattan's closed `pvrsrvinit_r125` initializes it through this driver. The
DDK version and build options match (it logs no mismatch), the microkernel runs (the SGX interrupt
fires), and the SGX idles into runtime suspend. **The GPU executes work:** through Harmattan's libpvr2d
(`tests/pvr2d-test.c`), a GPU fill and a GPU copy are right on every pixel, and GPU-drawn colour bars
land in the framebuffer. **The N9 panel works:** omapfb drives it over DSI (it answers with stock's ID,
fe.91.96), and the GPU-drawn bars show on the phone's own screen. **3D works:** Harmattan's own Xorg
runs on it with Nokia's X driver (DRI2 over pvr2d, `fb0` 856×1536 RGB565 as stock), and
`tests/gles2-test.c` renders a GLES2 triangle through Harmattan's EGL (`EGL 1.4 build 1.4.14.2514
Nokia`, `PowerVR SGX 530`, `OpenGL ES 2.0`), with the pixels read back right.


Status (2026-10-08, rm696 cf6e32591): stock Harmattan runs day to day on 6.18 (RAM boot, read-only):
display, GPU, video, both cameras, audio and the headset button, WLAN, Bluetooth (OBEX transfers,
~225 KB/s UART), FM radio, NFC (`docs/nfc.md`), modem at the ISI level and its call-audio link
(tested up to a call's start without a SIM, `docs/audio.md`), sensors, charging; CORE retains in
standby and reaches OFF, with Bluetooth on too since 2026-10-08 (`docs/power.md`,
`docs/bluetooth.md`). State and next
steps: `RELEASE.md`; what isn't ported or finished yet: `UNPORTED.md`.

What the kernel leaves out or switches off (against mainline and stock), why, what it measured
and how to put each back: `REMOVED.md`.

## Build

    kernel/build.sh      # in n9-qemu's local build VM by default (../n9-qemu/kernel/buildvm.sh starts it)

The kernel is `../linux_mainline_rm696` (branch `rm696`): Linux 6.18.55 (linux-stable, shallow) and
this project's changes as commits, Aegis and `arch/arm/configs/rm696.config` included; `build.sh`
builds what is committed there (it warns about uncommitted changes) and builds the SGX driver
(`../pvr_sgx_rm696`, its own repository since 2026-10-10) against it.

Output in `build/`: `zImage-n9` (the RAM-boot test kernel, N9 device tree appended), `pvrsrvkm.ko`,
`omaplfb.ko`, and `ramboot-key` (made on the first build, the test image's root login). `BOX=` builds
elsewhere (see `kernel/build.sh`).

Nokia's firmware is not in the repository: `FIRMWARE.md` lists what the build and the phone need
and where it comes from.

0xFFFF (NOLO's USB protocol, for the RAM boot) builds on macOS with Homebrew's libusb-compat:

    brew install libusb-compat
    git clone https://github.com/pali/0xFFFF && cd 0xFFFF
    # it refuses libusb-1.0 wrappers (slow device listing on Linux); on macOS it polls ~18 times a second
    perl -0pi -e 's/\tif \( dlsym\(RTLD_DEFAULT, "libusb_init"\) \)\n\t\tERROR_RETURN\([^\n]*\n//' src/usb-device.c
    # and ignores the boot ROM (cold flash mode, 0421:0106): claiming it sometimes fails and stalls the
    # RAM boot; left alone, the ROM starts NOLO by itself
    sed -i '' '/0x0421, 0x0106,  0,  0, FLASH_COLD/d' src/usb-device.c
    CPPFLAGS="-I/opt/homebrew/include -D_DARWIN_C_SOURCE" LDFLAGS="-L/opt/homebrew/lib" make   # -> src/0xFFFF

## Layout

The kernel rows are commits in `../linux_mainline_rm696` since 2026-10-02, named by the patch files
they were (each commit message names its file; the files are kept in `build/kernel-patches-2026-10-02/`).
The table runs to 2026-10-05; later commits are listed in their sections below (cameras, small
interfaces, idle and OFF mode, Bluetooth, FM radio, ECI, NFC, CORE OFF).

| Path | What |
|---|---|
| `../pvr_sgx_rm696` | the SGX driver, its own repository since 2026-10-10 (was `pvr/` here): `pvrsrvkm.ko` (services, SGX) and `omaplfb.ko` (display class on `/dev/fb0`) |
| `arch/arm/configs/rm696.config` (was `kernel/n9.config`) | on top of `omap2plus_defconfig`: omapfb instead of omapdrm (Harmattan's X and omaplfb use omapfb) |
| `omapfb-notify.patch` | Nokia's DSS notifier, which the driver's flip events wait on |
| `fbdev-export-registered-fb.patch` | re-exports `registered_fb` for omaplfb |
| `n9-display.patch` | the N9's display in `omap3-n9.dts`: the N950's DSI node with the N9's lanes and panel (`nokia,pyrenees`) |
| `omapfb-panel-dsi-cm.patch` | omapfb's DSI command-mode panel driver: frame size, visible area (back porches) and rotation (DCS address mode) from the DT, not Taal's fixed 864×480; `rotate`/`mirror` report it |
| `omapfb-display-update-mode.patch` | Nokia's per-display `update_mode` sysfs attribute (Harmattan's X driver reads it) |
| `omapfb-overlay-detach.patch` | overlays detach from a manual-update display when no update is running, as Nokia's omapdss allowed |
| `fbdev-zero-mode.patch` | the fbdev core passes a 0×0 mode to the driver (omapfb's empty overlay framebuffers) |
| `n9-harmattan.patch` | Harmattan on the N9 dts: stock I2C/GPIO numbering (aliases), no power-off, TWL4030 charger node off, the touchscreen |
| `gpio-omap-legacy-base.patch` | GPIO bank N numbered from N × 32 (its `gpioN` alias), as legacy kernels, for sysfs GPIO users (BME) |
| `omapfb-panel-split-update.patch` | landscape updates in two halves timed from TE, as stock for the SMD Pyrenees: DSI region updates, clipped overlays, one frame per split, calibration in sysfs |
| `omapfb-panel-stock-power.patch` | stock's display power controls for mce: DCS backlight as `display0`, Pyrenees `lpm` (standby screen), `dimming`, `hbm` |
| `omapfb-panel-update-pacing.patch` | frame pacing: `update_stats` (frames by TE periods, request phase), a first half started up to 2 ms after TE (`split_late_us`), stock's 6 ms idle limit while the display is on (`idle_latency_us`) |
| `cpufreq-input-boost.patch` | a CPU boost on key/touch input (max frequency, shallow idle, 1 s), as stock's PM optimizer |
| `twl5031-bcc.patch` | the TWL5031 charger's presence as the "usb"/"vac" power supplies BME reads; read-only |
| `sound-dfl61.patch` | audio as stock: Nokia's two cards (`dfl61-twl4030` on McBSP3, `dfl61-dac33` + TPA6140A2 on McBSP2) as a DT machine driver, `sound/soc/ti/dfl61.c`, and `omap3-n9-audio.dtsi` |
| `vibra-apds-n9.patch` | Nokia's vibra (SPI) and APDS990x (`/dev/apds990x0`) drivers on 6.18, `omap3-n9-nokia.dtsi` (also the LP5521 notification LED) |
| `leds-lp5521-cp-off.patch` | LP5521 without its charge pump drives R from the battery: the N9's white LED, as stock |
| `iphb.patch` | Nokia's IP heartbeat (`/dev/iphb`, DSME): TCP keepalives held until its heartbeat |
| `phonet-gid.patch` | Phonet access for the `phonet` group too (Nokia's `phonet_gid`), for Harmattan's sscd/csd |
| `bt-bluez4-security.patch` | `BT_SECURITY` with the level alone (BlueZ 4's form), as before 6.9 |
| `bt-nokia-ti1273.patch` | `hci_nokia`: stock's TI1273 firmware by chip version; the LE firmware's broken LE states skipped |
| `vdd-vp-scaling.patch` | VDD1/VDD2 through OMAP's voltage processor (the TWL ignores VSEL in SmartReflex mode), so cpufreq's voltages apply |
| `wl12xx-n9-sdio.patch` | the N9's WLAN on MMC3 (SDIO) in the dts |
| `onenand-read-only.patch` | OneNAND read-only in the driver: no writes, erases, OTP writes or locks |
| `omap-wdt-nowayout-shutdown.patch` | with NOWAYOUT, the OMAP watchdog keeps running through a halt |
| `atmel-mxt-n9-config.patch` | the touch configuration stock's `mxt_configure.sh` applies for this panel (`RM-696_Pyrenees_SMD_ES40_V1_6`), written to the chip's RAM at probe |
| `atmel-mxt-protocol-a.patch` | the maXTouch's T9 contacts in multitouch protocol A, for X's `mtev` |
| `atmel-mxt-wake-gesture.patch` | Nokia's `wait_for_gesture` (double tap to wake, `MSC_GESTURE`), `disable_ts`, `calibrate`; stock's input name |
| `i2c-adapter-class.patch` | `/sys/class/i2c-adapter` (I2C_COMPAT, gone in 6.x), mce's path to the touchscreen |
| `evdev-noop-llseek.patch` | input devices seekable as a no-op, as 2.6.32: mce seeks them after each event |
| `omap3-sec-bb5.patch` | Nokia's OMAP3 HS secure-environment driver (`/dev/omap_sec`: `omap_sec`, `omap_hs`), built in as stock |
| `n9-gps-compass.patch` | Nokia's AK8975 (`/dev/ak89750`, sensord's compass) and BCM4751 GPS (`/dev/bcm4751-gps`, sysfs at `3-01fa` for nped) drivers on 6.18; 10-bit I2C clients named as 2.6.32 did |
| `usb-moded-compat.patch` | Nokia's USB gadget names and 2.6.32 sysfs paths for usb_moded: `g_file_storage`, `musb_hdrc/gadget/{gadget-lunN,softconnect}` |
| `usb-musb-rx-early-packet.patch` | musb gadget: an OUT packet that arrives before its request is read (from a work), not flushed; mainline's flush (3fc137386c46) dropped mass storage commands |
| commit "usb: musb: gadget: don't flush the RX FIFO when queueing a request" | mainline bug (3fc137386c46): queueing an OUT request flushed the FIFO, and a packet arriving during the flush came out with length 0: USB mass storage writes from the Mac stalled (a command block lost, the host resetting the device every 30 s). Now the FIFO is left alone, as before 3fc137386c46 and as Nokia's kernel ("USB mass storage writes") |
| `8250-omap-auto-rts.patch` | automatic RTS kept when flow control is set after RTS is raised (hci_nokia's order): the BT UART's receive flow control |
| `bt-nokia-uart-rx.patch` | BT receive: a frame left incomplete for 500 ms dropped (no more swallowed replies), a stray byte between packets dropped alone; temporary `rx_dump` |
| `omapfb-panel-update-ulps.patch` | DSI ULPS 500 ms after the last update, as stock: DSS idles while the picture is still |
| `twl4030-madc-chardev.patch` | Nokia's `/dev/twl4030-adc` (raw read, set-up conversions read after `poll()`) on mainline's MADC, for BME; without mainline's carkit MADC routing |
| `aegis/*.patch` | changes to n9-qemu's Aegis port: the open-time file check after the open (`file_post_open`: a 6.x file can't be read at `file_open`); hashlists for files on an overlay (a layer's `st_dev`); open mode logs and denies nothing (loader failure, enforcement, module whitelist) and reports nothing to userspace (MALF) |
| `overlayfs-aegis-pseudo-dev.patch` | overlayfs: whether a `st_dev` is one of an overlay's layer pseudo devices, for Aegis's hashlists |
| `sgx-sysc-no-smart-idle.patch` | the SGX module without smart idle/standby while powered: after standby it wedged mid-reset (an external abort, a panic) |
| `omapfb-takeover.patch` | NOLO's display taken over as stock (`omapdss.def_disp_enabled`): GPIO bank 3 not reset, and while the panel is still on, no panel reset and no first frame; otherwise a full power on |
| `pstore-ramoops-n9.patch` | 1 MiB of RAM for pstore/ramoops: a panic's log survives the warm reset into the next test boot (the init copies it to `MyDocs/.ramboot`) |
| `ti-composite-mux-latch.patch` | the standby crash's fix: TI composite muxes got latch bit 0 (kzalloc) instead of none, so every parent change set and cleared bit 0 of the register: `sgx_fck` on `core_d2_ck` (5) got 192M (4) and lost its clock when DPLL4 stopped. Upstream bug since ee2fc3c5ca8d (4.17), still in mainline |
| `omap3-core-dvfs.patch` | CORE/L3 scaling, the mechanism: Linux 4.1's SRAM routine changes DPLL3 M2 with the SDRAM in self-refresh, SDRC timings from `sdram-nokia.c`, VDD2 follows (1.0 V at OPP50, 1.2 V at OPP100) |
| commit "ARM: OMAP3: L3 scaling policy for the Nokia N9" | L3 at OPP50 unless held: the CPU above `scaling_min_freq`, or `omap3_l3_hold()` (the SGX while it's clocked: `pvr/sysutils.c`); raised at once, lowered after 1 s; debugfs `omap3_l3` (level, time at each level, holds; `low`/`high`/`auto` for tests) |
| commit "HSI: omap_ssi_port: don't write the divisor of a suspended port" | mainline bug: each L3 change wrote the SSI port's TX divisor with its clocks off, an L3 "In-band Error" |
| commit "ARM: OMAP3: L3 policy: holds by user, counted from boot" | `omap3_l3_hold(who)`: the CPU, SGX, display, USB, WLAN; debugfs `omap3_l3` shows each one's holds, `-usb`/`+usb` stops/resumes counting one (not `sgx` or `dss`); holds taken before the policy's late initcall (display, USB) count |
| commit "fbdev: omapfb: panel-dsi-cm: hold OMAP3 L3 for the display" | L3 high while the DSS runs (its 172.8 MHz clock is too fast for VDD2 OPP50, stock's comment) and while the panel is on outside its standby screen; sysfs `l3_lpm_hold` 1 holds it in the standby screen too, as stock (the fallback) |
| commit "usb: musb: omap2430: hold OMAP3 L3 while the controller is on" | as stock's `rm696_usb_set_pm_limits` (cable plugged in) |
| commit "wifi: wlcore: hold OMAP3 L3 while the chip is awake" | as stock's `WL12XX_PERF_HIGH_THROUGHPUT`; mainline's power save is the firmware's, so the closest is the chip out of ELP |
| commit "ARM: OMAP3: L3 policy: lowering delay as a parameter" | `/sys/module/clkt34xx_dpll3m2/parameters/l3_lower_delay_ms` (1000) |
| commit "wifi: wlcore: fix runtime PM leaks in firmware restarts" | mainline bug: the firmware switch in `wl1271_op_add_interface()` and `wl12xx_read_fwlog_panic()` kept a runtime PM reference |
| commit "wifi: wlcore: don't leak runtime PM when setting TX power fails" | mainline bug: wlancond sets the TX power before association, mac80211 passes INT_MIN, wlcore refused it and skipped its put (and the other changes): the chip never entered ELP after the first WLAN bring-up |
| commit "wifi: mac80211: ignore a -128 dBm country element power limit" | an AP listing every channel at 0x80 limited the TX power to 0 dBm (wlcore never applied it, see "CORE/L3 scaling") |
| commit "usb: musb: don't restore a context the controller kept" | mainline bug: after a USB replug, the core's runtime resume (200 ms after the glue's) wrote the unplug-time endpoint registers over the ones the host had just configured; macOS never got the ECM link notification (link down until reboot) |
| commit "sched/fair: no load tracking or group-share division on one CPU" | 6.17 made SMP unconditional in the scheduler: a UP kernel ran SMP load tracking (PELT) and a 64-bit division per cgroup level on every enqueue, dequeue and pick; back to the pre-6.17 UP paths (-1 us a switch; "Context switch cost") |
| commit "ARM: Cortex-A8: BTB flush on mm switch only with branch predictor hardening" | every A8 mm switch flushed the branch predictor (the N9's firmware sets ACTLR.IBE, so it's real: 576 cycles plus a cold predictor afterwards); now only with `HARDEN_BRANCH_PREDICTOR`, as stock had none. Process switch -4 us. Risk and how to undo: "Context switch cost" |
| commit "ARM: OMAP3: PM: don't wake the MPU for McBSP wakeups" | mainline routes McBSP2/3/4 wakeups to the MPU (PM_MPUGRPSEL_PER); during audio every McBSP3 FIFO request woke the MPU with a PRCM interrupt (~210/s, 10+ slow PRM reads each); Nokia's kernel grouped only GPIO2-6 and UART3 with the MPU. Video: PRCM interrupts 9668 -> 3106 in 20 s, busy 54-55% -> 52.1%, pulseaudio 204 -> 124 ticks |
| commits "mailbox: omap: flush, and no TX interrupt per message for clients that flush", "staging: tidspbridge: send mailbox messages without a TX interrupt" | every message to the DSP (two with its DSPWAKEUP) took a TX interrupt and a run of the mailbox thread; now written straight into the FIFO as Nokia's mailbox did (`.flush`, `knows_txdone`), a full FIFO still uses the interrupt. Video: mailbox interrupts 5240 -> 2040-2055 in 20 s (stock 2052), busy 52.1% -> 50.0%; audio checked by ear |
| commit "staging: tidspbridge: clock WDT3 before the DSP starts" | every DSP start logged an L3 "In-band Error seen by IVA_SS at address 0" with a stack dump: the DSP firmware touches WDT3 as soon as it runs and the bridge clocked WDT3 only after the start (Omar Ramirez Luna's 2011 finding, [linux-omap](https://www.spinics.net/lists/linux-omap/msg61246.html)). Stock 2.6.32 has no L3 error handler, so it never showed. 0 in 18 starts after (boots 157-158), 50 of 59 before ("DSP open points closed") |
| commit "ARM: dts: omap3-n9: read the CPU temperature every 5 s" | each read of the OMAP3630 bandgap (mainline: unreliable) busy-waits for its conversion, up to 2.5 ms on the timeouts it logs a few times a boot; stock read no CPU sensor. Above the passive trip the zone still polls every 250 ms |
| commit "ARM: a 128 Hz tick option; the N9 at 128 Hz, as stock" | stock's tick, a whole 256 cycles of the 32 kHz system timer: video timer interrupts 5832-6466 -> 4220-4280 in 20 s (stock 3576). To undo: `CONFIG_HZ_250=y` in rm696.config |
| commit "sched/fair: no runtime update at levels with one entity when picking" | `pick_task_fair()` updated the current entity at every cgroup level; alone on its level it is the pick anyway and its runtime is accounted at the next update there. Thread switch -0.6 us |
| commits "ARM: dts: omap3: timer10 as a ti-sysc module, without its hwmod data", "clocksource/drivers/timer-ti-dm-systimer: a board-chosen clocksource next to the 32k counter", "ARM: dts: omap3-n9: GPT10 on the system clock as clocksource and sched_clock" | the 32 kHz counter is on the wakeup L4 (~780 ns a read at 1 GHz; a CORE timer ~250 ns), read on every switch and wakeup; GPT10 (CORE) on the 19.2 MHz system clock: 52 ns resolution, clock_gettime 1.15 -> 0.78 us, yield 1.60 -> 1.25, process switch ~-1 us. **Reverted** 2026-10-06 (a7b61bb36, my choice): GPT10's running clock kept CORE out of retention and OFF, so the clocksource is the 32 kHz counter again (`REMOVED.md`, "Tried and not kept") |
| commit "ARM: mm: sync the I-cache once per change of a page, not per mapping" | the whole I-cache was invalidated for every executable PTE (up to 16 per fault with fault-around); now once per change of the page's contents (PG_icache_clean = PG_arch_2, cleared by flush_dcache_folio(), any DMA into the page, and on free), as arm64. 300 busybox spawns 1.82 -> 1.65 s; no crashes over 5 rounds of drop_caches + re-exec |
| commits "ARM: OMAP2+: voltage: run an OPP at its calibrated voltage", "ARM: OMAP3: PM: don't stop SmartReflex for every idle entry", "ARM: OMAP3: SmartReflex class 1.5, as Nokia's N9 kernel" | SmartReflex as stock: each OPP's voltage calibrated once (again after 24 h), SR off in between, class 3 and its per-idle stop gone ("SmartReflex class 1.5") |
| commits "staging: tidspbridge: send nothing to a DSP that can't take it, as Nokia's", "mailbox: a queue of 64 messages, as Nokia's OMAP mailbox" | no messages to a crashed DSP, and stock's queue depth |
| commit "staging: tidspbridge: unload a node's library when its create fails, as Nokia's" | a node whose create failed without a node environment (a DSP crash or watchdog overflow during it) kept its library loaded in the code manager's DBLL target, which outlives DSP reloads: after the reload that library wasn't loaded again and the next one went over it, and every later node start faulted until reboot. Nokia's `node_create()` unloads it ("DSP crash recovery") |
| commits "genirq: an interrupt's /proc/interrupts line in Linux 2.6.32's form", "HSI: nokia-modem: name the reset interrupt cmt_rst_ind, as Nokia's kernel" | Harmattan's csd reads the modem reset count from `/proc/interrupts` as `"%*d: %u%*[ ]GPIO%*[ ]cmt_rst_ind%c"`: the reset interrupt has Nokia's name and that one line 2.6.32's columns (`GPIO`, no hwirq or trigger); every other line unchanged |
| commit "ARM: rm696.config: DISPC core clock at least 4x the pixel clock, as stock" | `CONFIG_FB_OMAP2_DSS_MIN_FCK_PER_PCK=4`: the DISPC at 147.84 MHz and the pixel clock at 36.96 MHz (was 49.28, 3x), as stock's fixed 4x (`board-rm696-video.c`); the video plane's scaler needs 4x to downscale 4x, which Xv does for a portrait 1080x720 clip (270 columns): every set-up was refused, the video black ("Video: my clips") |
| `serdev-ignore-errors.patch` | serdev ports ignore breaks (IGNBRK), so a line break doesn't reach H4 framing as a zero byte. Added when the BT chip seemed to hold its TX low while asleep; boot 39 showed it doesn't (the "zeros" were EIR padding: "Bluetooth" below) |
| `ramboot/harmattan.patch` | Harmattan's boot jobs for the test kernel (applied at boot, in RAM) |
| `tests/` | `pvr2d-test.c` (the SGX through Harmattan's libpvr2d), `gles2-test.c` (GLES2 through Harmattan's EGL on X), `build.sh` (Harmattan binaries with n9-qemu's sysroot) |
| `ramboot/save-logs.sh N` | before a reset: the boot's dmesg and syslog as `build/ramboot-*-N.txt`, identifiers removed (and checked) |
| `ramboot/mydocs-rw.sh [SECONDS]` | on a test boot: MyDocs exported read-write over USB mass storage (unmounted on the phone meanwhile), back read-only for Harmattan with SSH after unplug or SECONDS (macOS's eject doesn't reach the gadget). Writes the eMMC: only on my ask |
| `tests/msc-ramdisk.sh [SECONDS [MB]]` | on a test boot: a FAT image in RAM exported read-write over USB mass storage with musb's tracepoints on (`/tmp/msc-trace.txt`); nothing reaches the eMMC |
| `ramboot/unlock.sh` | after a test boot reaches the UI: root may talk to mce, display held on, unlocked |
| `tests/tone.sh` | a quiet 4 s test tone through PulseAudio, and where it went (PCMs, headphone DAPM path, TPA registers) |
| `tests/sensortest.pl` | a sensord client (perl, on the phone) that dumps a sensor's samples |
| `tests/touchrate.pl` | on the phone: the touchscreen's report rate while touching and the delay to the first movement |
| `tests/btmon.pl` | on the phone: a minimal btmon (the kernel's HCI monitor channel), addresses masked |
| `tests/btloop.pl` | on the phone: sustained Bluetooth receive test without a second device (HCI user channel, controller in local loopback, every echoed ACL packet checked) |
| `tests/voicepath.sh` | the call-audio hardware without a call: earpiece path and the digital mics |
| `tests/kprof.c` | `build/kprof SECONDS HZ` on the phone: a system-wide sampling profiler (kernel symbols, user time by process) |
| `tests/gst-test.c` | a GStreamer 0.10 pipeline on Harmattan (it has no gst-launch): errors, time to EOS, buffers through `out` and into every fakesink |
| `tests/ioctl-log.c` | `build/ioctl-log.so`, LD_PRELOAD: the DSP bridge's ioctls of a process (args, messages, return, per-command time with `IOCTL_LOG=sum`; as root the DRAM view of flushed/invalidated/handed-off buffers); runs on stock as user |
| `tests/kbench.c` | kernel basics, stock vs ours: syscall, clock_gettime (the 32k counter), sched_yield, pipe, thread and process switch, page fault, memset/memcpy; prints its cgroup |
| `tests/compare.sh` | the same measurements on stock (as user) and on the test kernel: kbench x3, tlbbench, 20 s of video (busy share from the idle time, per-process ticks, context switches, interrupts, CPU frequencies) |
| `tests/pinned.sh`, `tests/schedfeat.sh` | on the test kernel, CPU pinned at 1 GHz: swprof and kbench x3; swprof plus the `sched_prof` sections under each scheduler feature setting (perf-schedprof kernels) |
| `tests/swprof.c` | the thread/process ping-pong; `NOPERF=1` runs it without perf events (they reprogram the cycle counter at every switch) and prints the time per switch |
| `tests/devmem.c` | `devmem ADDR [8\|16\|32 [VALUE]]`, and `devmem ADDR dump LEN` (raw bytes; mmap, so no-map memory like the DSP pool works) |
| `tests/dsp/` | DSP debugging: reference decodes and encodes on stock and ours (`dspref.sh`), DSP restarts (`dsprestart.c`), kprobe timing, DOF symbol/section tools for disassembling the DSP image (`tests/dsp/README.md`) |
| `ramboot/butter.sh`, `swipe.pl` | frame pacing A/B on the phone: injected flicks or page swipes under each setting, the panel's frame-interval histogram, CPU frequency time, deep idle |
| `ramboot/bb5-test.sh`, `bb5-test.pl` | loads the secure-environment driver on the RAM-booted phone and makes harmless secure calls |
| `ramboot/init` | the test kernel's initramfs init: watchdog session, USB networking, dropbear, then Harmattan on read-only disks with RAM overlays. Its loops fork nothing in steady state (2026-10-05: `read -t` on a FIFO instead of sleep, builtins instead of grep/cat/ip; the session's age checked once a minute; MyDocs log every 30 s): ~4 forks a second had doubled ohmd's work. It also points the kernel's firmware loader at `/newroot/lib/firmware` (the loader reads from the initramfs, not the chroot): without it hci0 never powered up and, depending on boot timing, conndlgs looped on bluetoothd for minutes after INIT_DONE |
| `check-abi.py` (in `pvr_sgx_rm696`) | checks the ioctl dispatch against Harmattan's binary module |

## Source

The SGX driver and `check-abi.py` live in their own repository, `pvr_sgx_rm696`, since 2026-10-10 (before,
`pvr/` and `check-abi.py` here). Its README has where the driver comes from (Nokia's N900 driver as
Maemo Leste forward-ported it to 5.0), every change for 6.18, and what `check-abi.py` shows.

## RAM-boot test

`zImage-n9` boots from RAM, with nothing flashed and nothing written to the phone's OneNAND or eMMC. Any
reset or reboot brings back stock Harmattan.

1. On the Mac: System Settings → Privacy & Security → "Allow accessories to connect" → **Automatically
   When Unlocked**. NOLO appears on USB with a new identity for only a few seconds, and a prompt would
   miss that window.
2. `build/0xFFFF -m kernel:build/zImage-n9 -l -b`. It waits for NOLO. `ramboot/arm.sh` does it in its
   own window, from a copy of the build. A phone up in one of stock's USB modes (mass storage) makes
   0xFFFF give up ("No device detected"), and a 0xFFFF started after that doesn't see NOLO on this Mac:
   `arm.sh` then waits for NOLO's USB device itself and starts 0xFFFF on it.
3. Reboot the phone into NOLO with USB connected: from stock only I can (`devel-su` with my
   root password, then `reboot`; the test phone's power button is broken); from a test kernel, the
   guarded SysRq-B.
4. About 15–30 s later the Mac's `en8` comes back up. The gadget uses the SDK mode's USB ids and MACs, so
   the Mac reuses `en8` and its static 192.168.2.14. Then `ssh -i build/ramboot-key -o UserKnownHostsFile=/dev/null root@192.168.2.15`.
5. By default the image then boots Harmattan (below). For the driver tests instead, first create
   `MyDocs/.ramboot/shell` from stock Harmattan; the image then stays in its own shell.
   `insmod /lib/modules/sgx/pvrsrvkm.ko`; `/proc/pvr/version` should match the stock phone's
   (`1.4.14.2514 (release)`, `SGX revision = 1.2.5`). Then Harmattan's `/usr/sbin/pvrsrvinit` in a chroot of
   `/harmattan`, then `reboot -f`.

Since the power button is broken, a stuck test kernel would sit there until the battery died, so it
can't be allowed to get stuck:
- Once started, nothing can stop the watchdogs (`CONFIG_WATCHDOG_NOWAYOUT`). The OMAP one starts when its
  driver probes (`omap_wdt.early_enable=1`); until init opens it, the kernel feeds it for at most 120 s.
  The TWL5031's (armed by NOLO, can't be stopped) is left alone until init loads its driver.
- In init, a single process feeds both, until 10 minutes after the last `touch /tmp/stay`, then runs
  `reboot -f`. If that process dies or the reboot hangs, the watchdogs reset the phone.
- A panic reboots after 10 s.

Run on 2026-09-30:
- NOLO 2.3.6 RAM-boots the unsigned 7.4 MB image. 0xFFFF on macOS needs its libusb-1.0 guard removed
  (see Build). About 1 in 2 times the first USB claim fails with "Device not configured" and it retries
  on its own.
- USB networking and ssh in about 25 s.
  - The OMAP3630 has no cycle counter for jitter entropy and the N9's RNG is off, so the image carries an
    `rng-seed` in its device tree. Without one, dropbear blocked in `getrandom()` for minutes.
  - The eMMC is `mmcblk1` on this kernel.
- The first `pvrsrvkm` crashed in `dma_map_page(NULL, …)`: the DDK's cache invalidation now passes the
  SGX device. That oops made `omap2plus_defconfig`'s mtdoops try to write NOLO's OneNAND "log" partition.
  The block lock refused it. mtdoops is now off, and OneNAND is read-only in the driver (below).
- `/usr/sbin/pvrsrvinit` is a shell script without `#!` (upstart runs it with sh). It execs
  `pvrsrvinit_r125`, the revision it greps from `/proc/pvr/version`.
- The session's 10-minute reboot and SysRq-B (`echo b > /proc/sysrq-trigger`) both returned the phone
  to stock Harmattan.
- With a `simple-framebuffer` as `/dev/fb0`, `omaplfb` registers the display class, and `pvr2d-test`
  passes: the fill and the copy of 256×256 ARGB8888 buffers are right on every pixel (no cache
  invalidate needed), and 5 bars land in `/dev/fb0`. There are 10 SGX interrupts and no kernel messages.
  PVR2D's fill colour is ARGB8888 whatever the target format, and the GPU converts it exactly.
- The N9 panel (`kernel/n9-display.patch`: postmarketOS's 2017 N9 DT, which was tested on hardware)
  - It answers over DSI on the first try (`panel revision fe.91.96`, as stock).
  - omapfb makes it `fb0`: 480×864, 32 bpp. The tearing-effect interrupt ticks at 60 Hz.
  - Frames reach the panel only in omapfb's auto-update mode (`update_mode` 1; its `auto_update`
    parameter left it manual). `ramboot/init` sets it.
  - Then `pvr2d-test`'s bars show on the screen: red, green, blue, white, black.
  - The regulator core turns off `vmmc2`, which the N950 DT gives the panel, 30 s after boot, and the
    panel doesn't notice. On stock it's on with one user, maybe the touchscreen.
- Landscape (DT `rotation = <90>` → DCS address mode 0x60, stock's `rotate` 1): `fb0` is 854×480,
  stock's geometry. The bars and two corner markers show the right way up.
- Harmattan's X (`/usr/bin/Xorg` as stock's `/etc/init/xomap.conf` starts it) in the chroot:
  - Nokia's `security` module needs Aegis to resolve the token
    `xserver-security-policy::record-input` and ends X without it. That's more evidence for step 3's
    Aegis. For tests, `security.conf` gets `policy.conf`'s content, bind-mounted.
  - Nokia's X driver (`fbdev_drv.so`) then needs stock's display sysfs:
    - a display named `lcd` (the DT label);
    - readable `rotate` and `mirror`, and `update_mode`;
    - and a display named `tv` (TV-out).

    Faked in the chroot, it got as far as each of those. The kernel now has them for real
    (`kernel/n9-display.patch`, `omapfb-*.patch`), along with three more things it needed:
    - The `timings` must be the panel's unrotated frame, because X applies `rotate` itself.
    - Overlays must detach from a manual-update display with no update running
      (`omapfb-overlay-detach.patch`; mainline refused: "need an update to change the manager").
    - A 0×0 mode must pass `FBIOPUT_VSCREENINFO` for the empty Xv overlay framebuffers
      (`fbdev-zero-mode.patch`).

    Also `omap2fb.vram=0:3M` (omapfb's module is `omap2fb`, so `omapfb.*` parameters do nothing).
  - Then X runs: `[DRI2] Setup complete`, `DRI driver: pvr2d`. `gles2-test` passes when the X window
    uses the EGL config's visual (32-bit, `0x4b`).
- Nokia's display code, as reference: [harmattan/kernel-plus-harmattan](https://github.com/harmattan/kernel-plus-harmattan)
  (`drivers/video/omap2`, `arch/arm/mach-omap2/board-rm696-video.c`).
  - The N9's panel is `pyrenees` on `panel-nokia-dsi`, `rotate` 1, 854 rows at offset 0.
  - The DSI lanes match the DT's.
  - omapfb is RGB565, 856×1536 virtual (3 × 512 lines).
- Logs: `build/ramboot-dmesg-{1,2,3,4}.txt` (the first with the oops, the fourth the panel); on the phone,
  `MyDocs/.ramboot/dmesg.txt` from the last boot.

## Harmattan boot (step 3)

(Written on 2026-09-30 before the first run; the runs follow below.) After the RAM-boot setup above, `ramboot/init` boots stock Harmattan PR1.3 on
this kernel, read-only for testing: every write goes to RAM.

- Disks:
  - The eMMC rootfs (`mmcblk1p2`) and `/home` (`p3`) are read-only block devices
    (`blockdev --setro`, checked with `--getro` before Harmattan may start; otherwise it stays in the
    shell). They are the lowers of two overlays with a tmpfs upper (256 MB): `/newroot` and
    `/newroot/home`.
  - On this kernel the eMMC is `mmcblk1`, so Harmattan's `/dev/mmcblk0p*` names don't resolve.
    `mount-home` finds no devices (`/home` is already the overlay) and `sfdisk --id` finds no
    `mmcblk0` to fix.
  - MyDocs (`p1`, FAT): the init mounts it read-only with stock's options at `/mydocs`, and Harmattan
    gets a read-only bind at `/home/user/MyDocs` (music, photos). The kernel log goes to
    `MyDocs/.ramboot/dmesg.txt` every 10 s through a moment's remount read-write of `/mydocs` only;
    Harmattan's bind stays read-only even then. `mount-home` is patched to skip MyDocs when it's
    already mounted (it would cover it with its read-only tmpfs). SysRq-B only while `/mydocs` is
    `ro`.
  - OneNAND is read-only in the driver (`onenand-read-only.patch`: no `MTD_WRITEABLE`, no OTP writes or
    locks). CAL is readable for libcal.
- Aegis: the kernel runs Harmattan's own `/usr/sbin/validator-init` at the first exec from the new
  root, authorized by NOLO's `vhash=` (that binary's SHA1). It loads the reference hashes through the
  real BB5 (Nokia's secure driver, built in; "Secure world / BB5").
  - `aegis.mode=open` (CONFIG_CMDLINE) does what kernel-plus-harmattan's "aegis hack" does in effect:
    a failing loader disables the validator instead of panicking; validator-init's enforcement
    (`enforce 0x7`) and module whitelist are logged, not applied; verification failures go to dmesg
    only, not to Harmattan, which would enter MALF ("malfunction": `/var/malf`, reboot) over the files
    this image changes (`preinit`, `getbootstate`, jobs in `harmattan.patch`).
  - Harmattan's `/proc/sysrq-trigger` is `/dev/null`: validator-init's malfunction path resets with
    'b', unsynced, while MyDocs may be rw. The initramfs's own stays for the session's SysRq-B.
- Boot jobs (`ramboot/harmattan.patch`, applied at boot through the overlay by Alpine's GNU patch):
  - `preinit` skips its rootfs check (it would `e2fsck` a missing `mmcblk0p2`, then `reboot -f`);
  - no boot watchdog (the groups start as stock, once `stserver-normal` runs: "Modem" below);
  - no DSP, audio or modem daemons yet;
  - `|| true` on the group starts, since upstart runs scripts with `sh -e`.
- `/lib/modules/<release>` holds only `pvrsrvkm` and `omaplfb`, with a hand-written `modules.dep`
  (module-init-tools 3.4). So udev loads no mainline driver behind Harmattan's back.
- Hand-off: `exec chroot /newroot /sbin/preinit`, not `switch_root`, so the initramfs stays. The
  session, the MyDocs log and dropbear keep running, and ssh `root@192.168.2.15` still lands in the
  initramfs (`chroot /newroot` for Harmattan). PID 1's `chroot()` moves the root the kernel's helpers
  run in, so `validator-init` and `modprobe` resolve in Harmattan.
- The fail-safes, extended:
  - The kernel can't power off: `ti,use_poweroff` is gone from the dts. A power-off (DSME's shutdown,
    `check_wipe`'s SysRq-O) halts instead, after device shutdown. `omap_wdt` now keeps running through
    that when NOWAYOUT (`omap-wdt-nowayout-shutdown.patch`), and the TWL watchdog has no shutdown
    hook. Both reset the halted phone into stock.
  - DSME's `/sbin/dsme` can't open the watchdogs the session holds, and says "no WD's opened; WD
    kicking disabled". The session stays the only feeder.
  - The mainline TWL4030 charger (BCI) node is disabled. The TWL5031's charger is different, and BME
    drives it over `/dev/i2c-1` as on stock.
- Numbering as stock: I2C buses 1–3 and GPIO banks from 0 (dts aliases, `gpio-omap-legacy-base.patch`),
  for BME's `/dev/i2c-1` and `gpio162`.
- The touchscreen is in: the dts node and `atmel-mxt-protocol-a.patch`.
- Jobs with Nokia's `reboot` stanza (mce, bme, dbus, hal, X, most of the xsession daemons...) reboot
  the phone when they exceed their respawn limit. On the test boots, `ramboot/init` removes the
  stanza in the overlay, so a failing part stays failed and can be inspected; the session reboots.
- `ramboot/console.sh` (on the Mac) follows the test kernel's log over ssh, reconnecting across
  reboots, without the lines carrying the IMEI and serial.

First run, 2026-09-30 (`build/ramboot-dmesg-6.txt`):
- Everything up to Harmattan's userspace worked:
  - the kernel ran the emulator's `validator-init` ("vhash code matched", "Aegis: enabled"), and the
    validator only logged the patched `preinit`'s hash;
  - upstart, udev, D-Bus, HAL, gconf, ohmd, aegisfs, and Xorg with the SGX modules loaded;
  - the touchscreen probed as 853×479, stock's landscape frame;
  - DSME's watchdog part found the watchdogs busy and disabled its kicking, as expected.
- Then DSME exited, mce couldn't reach it, and mce's `reboot` stanza rebooted the phone. That shutdown
  hung, and the phone stayed up.
- The root cause was libcal: `open(/dev/mtd1): Permission denied` for BME, DSME's power-on timer and
  sysinfod. mtdchar refuses read-write opens of a non-writeable MTD, which the first
  `onenand-read-only.patch` made. It now keeps the MTD writeable and removes the operations that
  change the flash instead.
- BME also needs Nokia's `/dev/twl4030-adc`. Its `twl5030.so` plugin uses all of the character
  device: raw read, set-up and abort conversion (`0x6000`–`0x6002`), then `poll()` and `read()`.
  Mainline's `twl4030-madc` is IIO only, so this is the next port (from Nokia's
  `drivers/mfd/twl4030-madc.c`).
- Without `/dev/omap_sec`, the phone's `libbb5` fails too (secure-clean, aegisfs signatures). The image
  uses the SDK emulator's, as n9-qemu does.

Second run (`build/ramboot-dmesg-7.txt`, with Harmattan's syslog):
- libcal reads CAL (DSME's power-on timer only reports its refused write), no more `bb5_open`
  failures, and DSME runs.
- The boot now waits in `group-dsme`'s `start bme`. BME's job is `expect stop`, and BME raises
  SIGSTOP only once the battery is fine. Without `/dev/twl4030-adc` it reads 37 mV, logs "Battery level
  low for boot (37 < 3475) and no charger", and retries every 5 s.
- Next: `twl4030-madc-chardev.patch` (the character device on mainline's MADC; `CONFIG_IIO=y`, which
  `TWL4030_MADC=y` needs). "no charger" also wants the `usb`/`vac` power supplies of Nokia's
  `twl5031-bcc`.
- The stock numbering works: GPIO banks at 0–191 (BME exported `gpio162`) and `/dev/i2c-1..3`.
- Charging: `twl5031-bcc.patch` reports the "usb"/"vac" power supplies BME reads (present, 500 mA),
  from the BCC status polled every 2 s, and never writes the charger. Built, not yet run. Later:
  Nokia's charger-type detection (data contact detection and the BCC's state machine). It drives
  the USB PHY's data lines, so it has to run before the USB gadget is up. Until then a wall charger
  counts as a 500 mA host port.

Third and fourth runs:
- With `/dev/twl4030-adc`, BME reads the battery (4111 mV, "Battery level OK for boot") and the boot
  goes on through X to the whole session: mcompositor, sysuid, meegotouchhome, applauncherd,
  devicelockd, the input method server. The screen showed the boot spinner.
- mce then failed in `scan_inputdevices()`: there was no `/dev/input`, because omap2plus builds evdev as a
  module. Now built in, with the TWL keypad (volume keys), the power button, uinput and the
  accelerometer (lis3lv02d, for sensord's orientation).
- **Fourth run: Harmattan's home screen on the N9 with Linux 6.18** (`build/fb0-harmattan-home.png`,
  from `/dev/fb0`): the app grid, status bar with clock and battery. Input devices: TWL4030 Keypad,
  twl4030_pwrbutton, Atmel maXTouch Touchscreen, ST LIS3LV02DL Accelerometer.
- Still failing, not blocking: usb_moded (GLib assertions), `cherryui` (segfault after "Cherry state
  file's content is invalid"), pvrsrv-watch, mxt-configure (Nokia's touch-driver sysfs),
  extra-modules, timeconfig, select-usb-module, sysconfig-middle; DSME has no `/dev/iphb`.
- Touch works (protocol A into X's `mtev`). Swipes start from one portrait edge only: the chip runs its
  NVM (factory) configuration, while Nokia's driver wrote the N9's (`rm-696_pyrenees_smd_v1_6`) into
  its RAM at every boot and reset, only backing it up to NVM as error recovery. On the
  portrait left/right axis (T9 Y): clipping 1/1 vs 5/10, edge correction `0x98`/100 vs `0x9a`/85.
  `atmel-mxt-n9-config.patch` writes Nokia's objects to RAM at probe, never to NVM.
- The display locks after inactivity, and double-tap-to-wake needs Nokia's touch driver's gesture
  mode (`wait_for_gesture`). For tests: mce's display on (`req_display_state_on`), the tklock off
  (`req_tklock_mode_change`, which needs the Aegis token `mce::TKLockControl`; root may call it
  through a D-Bus policy file put in the RAM overlay), and blanking off
  (gconf `/system/osso/dsm/display/inhibit_blank_mode` 3).
- A garbage band about 10 rows tall at the bottom of the panel: its frame has 864 rows, and Nokia's
  driver shows only 854 (DCS `0x30` partial area 0–853, then `0x12` partial mode). Mainline never
  enters partial mode, so the 10 rows we never write were visible. `omapfb-panel-dsi-cm.patch` now
  does the same when the DT panel-timing has porches.
- Diagonal tearing, fixed as stock does it (`omapfb-panel-split-update.patch`): in landscape (`0x60`,
  MV|MX) an update is written across the panel's columns while it scans rows, so a whole frame always
  crosses the scan, even with TE (`tear_elim` 1). Each update now goes in two halves:
  - DSI `update_region()` sends columns `[x, x + w)`. The apply layer's region start programs each
    overlay clipped to them, as Nokia's "partial planes" did (unscaled overlays only; Xv video will
    need scaled cuts).
  - Both halves show one frame. The first latches the overlays and keeps a copy for the second, and
    the manager counts as updating until the second is out. So a flip (pan) made meanwhile waits,
    and the SGX's flip notifications come once the frame is done, as with Nokia's
    `omap_dss_lock_cache()`.
  - The N9's panel is the SMD Pyrenees (id `fe`), for which stock reverses the scheme. TE moves to
    mid-scan (`SET_TEAR_SCANLINE` 432 of 864 rows), the left half goes at TE, and the right half
    from a timer.
  - Stock timed the right half for 46 fps (the panel slows in ACL). At 60 Hz it then ends just past
    the next TE, and updates run at 30 fps. The timer is now 52% of the measured TE period: 8.7 ms
    at 60 Hz was tear-free and near-stock smooth on the phone.
  - What went wrong on the way, measured with sysfs `split_timing`: halves at 6.1 ms each on a
    16.66 ms TE period. The non-reversed scheme tore in the second half (the TE isn't where it
    assumes), and the right half first tore in both. Asking the DT for stock's 42.72 MHz pixel clock
    broke the display: mainline's DSI calculation adds 1.5× on top and ran out of its 300 MHz.
  - Calibration in sysfs on the panel device: `split_reverse`, `split_right_first` and
    `split_mid_us` (µs from TE to the timer's half; 0 = the default).
- Top-edge swipe (fixed 2026-10-01): mcompositor's swipe extension starts a swipe from an X button
  press inside a thin input window along the edge, so the touch-down must land within a few pixels.
  The first config patch used Nokia's kernel `cfg.h` (`RM-696_Pyrenees_SMD_V1_6`), but stock applies
  its config from userspace (`mxt_configure.sh`, `/usr/share/mxt-config/configs/id_to_file_map.txt`)
  by panel revision. This panel (`fe.91.96`) gets `RM-696_Pyrenees_SMD_ES40_V1_6.bin`: T9 MOVHYSTI 4
  (was 8), XLOCLIP 6 (0) and edge correction `0xd4`/55 (`0x94`/50), plus T8/T22/T24/T25/T28. With
  the old one, top-edge touch-downs reported 15–16 px in (a press, not a swipe); with ES40, 2–6 px.
  The `.bin` format is a 10-byte header, then per object `[type][size-1][data]`.
  `ramboot/touch.sh` shows the touch frames live.
- Touch sampling (2026-10-01, me: "a small touch precedes every swipe"): T7 is the file's
  `ff ff`, free-run, as stock's driver wrote it (its config area starts at T7; nothing in Harmattan
  sets the acquisition intervals). The first config patch had kept the driver's 20/7 ms: an idle
  scan every 20 ms before a touch is even seen. Measured on my swipes (`touchrate.pl`, a
  live T7 write): 20/7 ms 128 Hz, first movement 37 ms after touch-down; free-run 185 Hz, 26 ms;
  me: "a bit better". Stock's driver also capped reports at one per 7 ms after a touch's
  first 25 ms (`rlimit_min_interval_us`, `rlimit_bypass_us`); not ported (more samples were wanted,
  and nothing in Harmattan sets them).
- The lift-off sequence also follows Nokia's driver: the released contact once more at its last
  position, then `BTN_TOUCH 0` alone, never an empty `SYN_MT_REPORT`.

## Performance (tested 2026-10-01)

Stock's kernel (`rm581_defconfig`, `board-rm680.c`) set the N9 up for responsiveness; the test kernel
didn't. It now follows stock:
- **CPU frequency**:
  - `CPUFREQ_DT` was a module we don't ship, so the CPU stayed at NOLO's clock. Now it's built in,
    with omap36xx's OPPs (300/600/800 MHz, 1 GHz with the ABB in FBB) on the N9's VDD1 (`vcc`,
    0.6–1.45 V).
  - Mainline makes OPP1G turbo-only, and only for chips with the DM37x speed-bin fuse. Stock runs
    every N9 at 1 GHz, so the N9's dts makes it a normal OPP.
  - **VDD1 follows the OPP through the voltage processor** (`vdd-vp-scaling.patch`). twl-core puts
    the TWL in SmartReflex mode, where VDD1/VDD2 ignore their VSEL register and take the voltage from
    OMAP's VP over the SmartReflex I2C; mainline's TWL regulator still wrote VSEL and reported success,
    so the first test ran 1 GHz at NOLO's 1.2 V. The regulator now scales through `voltdm_scale()`
    (VP force update, which also keeps the VC's "on" voltage for idle exits) and fails until the VP is
    up (late init), so cpufreq can't raise the clock on an unchanged voltage. Measured: 300/600/800/
    1000 MHz at 1.0125/1.2/1.325/1.375 V, as TI's table. Nokia's kernel did the same (VP, limits
    0.85–1.45 V); mainline's VP limits (0.85–1.425 V) already cover OPP1G and the 1.4 V overclock,
    which gets its own voltage-table entry.
  - The governor is stock's `ondemand`, as Harmattan's `pmconfig` asks, with my own
    `apps/ondemand-tune` on top (50 ms sampling, 80% threshold; stock's 300 ms sampling is slow).
    `schedutil`, used until 2026-10-03, kept the CPU at 1 GHz for 20 s of each idle minute (5.8%
    load), so L3 stayed high; `ondemand` with that tune: 9 s, and L3 low 24 s instead of ~5.
- **Input boost** (`cpufreq-input-boost.patch`), as stock's PM optimizer: after any key or touch,
  the CPU runs at its maximum and stays out of deep idle (≤ 6 ms exit latency) for 1 s. It skips ABS
  devices that aren't touch devices: the accelerometer has click buttons too and streams events while
  Harmattan's sensord polls it, which kept the boost (and the CPU at its maximum) on for good in the
  first test.
- **Scheduling**: full preemption and HZ 250 (stock: `PREEMPT`, HZ 128); HZ 128 too since 2026-10-05
  (rm696 281cc3d23, "Context switch cost").
- **Memory**:
  - `MEMCG_V1` for Harmattan's `/syspart` cgroups (app partitions, memory limits, freezer).
  - Swap on zram at stock's sizes (stock used ramzswap, zram's predecessor).
  - `vm.compaction_proactiveness=0`: since 5.9, proactive compaction kept an idle OMAP3 out of OFF
    mode (Maemo Leste on the N900).
- **RTC**: the TWL RTC is built in, so Harmattan gets its time from `/dev/rtc0` instead of 1970.
- **Display**: the split update's second-half work is on the high-priority workqueue, so a busy
  CPU doesn't push it past its TE.
- **Overclock, off by default**: boost OPPs at 1.1 GHz / 1.375 V and 1.2 GHz / 1.40 V (ABB in FBB),
  enabled with `echo 1 > /sys/devices/system/cpu/cpufreq/boost`. The N9 community (talk.maemo.org)
  overclocked to 1.2–1.3 GHz and held 1.2 GHz as the daily ceiling; chips differ a lot. The input
  boost follows the current maximum, and the thermal zone still throttles.
- The SGX powers down after 1 ms idle (`SYS_SGX_ACTIVE_POWER_LATENCY_MS`), as Nokia's driver did.
- `ramboot/check.sh` (on the Mac) reports it all on a test boot: cpufreq, clocks, VDD1, swap,
  syspart, time, charger, panel timing, input devices, errors.
- **Idle power** (2026-10-01 night). With the display off the CPU only ever reached C3 (MPU
  retention, CORE on); `pm_debug/count` showed `core_pwrdm` never out of ON since boot. Causes:
  - every UART runtime-active: 8250_omap leaves a UART without a serdev child at autosuspend -1
    (never). UART1 and UART4 aren't connected on the N9 (stock set up only UART2, Bluetooth, and
    UART3, the debug console): disabled in `omap3-n9-nokia.dtsi`; UART3 gets 3 s (the init), as
    stock's omap-serial idled it. UART2 (Bluetooth): above, and its 921600-baud latency request
    (555 µs) keeps C4+ out while it's active;
  - DSI never entered ULPS (`ulps_timeout` 0): stock's board file set 500 ms
    (`board-rm696-video.c`), now the driver's default (`omapfb-panel-update-ulps.patch`); with it
    DSS/DISPC/DSI runtime-suspend while the picture is still, and frame pacing is unchanged;
  - USB connected (musb, the TWL USB PHY and its I2C): expected, the cable;
  - in the first seconds after display off, sensord polls the compass at 10 Hz for Maps (`fenix
    -prestart`, applauncherd's prestarted Maps holds a compass session); it stops by itself (0
    transfers 90 s after display off).
  Boot 30, display off, USB connected: PER reaches RET (65 times), CORE still ON (USB, UART2).
  Harmattan's `/etc/pmconfig` also turned on SmartReflex (`sr_vdd1/2_autocomp 1`) and OFF mode
  through 2.6.32 paths; here SmartReflex Class3 is loaded with `autocomp` 0 (debugfs) and OFF mode
  needs the secure RAM save (BB5). (Since: SmartReflex on through pmconfig from 2026-10-04, class 1.5
  as stock from 10-05; CORE retention and CORE OFF from 10-07: "CORE retention found", "CORE OFF".) The init logs `MyDocs/.ramboot/power.txt` every minute (battery
  voltage from MADC channel 12, USB power, C5+ entries and time, CORE's RET count), for a battery
  test with USB unplugged.
- What's left of the late frames isn't the kernel (boot 28, injected flicks): 92-96% of frames on
  time, run to run; the CPU pinned at 1 GHz did no better (it runs there 84% of a flick test
  anyway). The SGX stays powered through an animation (a resume takes ~0.1 ms; 34 in two flicks,
  between them). `tests/kprof.c` (a perf_event sampling profiler, `build/kprof`): CPU 47% idle
  during flicks, the home screen 29%, X 3%, the kernel 18% spread thin (poll/select, scheduling,
  syscalls; the SGX's busy-wait 0.1%). So the home screen's drawing on the GPU, at stock's clocks
  (SGX and L3 195.2 MHz: NOLO's DPLL3 at 390.4 MHz). The eMMC runs 4-bit at 52 MHz: the board's
  wiring (the eMMC's dat4-7 pads carry MMC3 to the WLAN, stock's mux too; stock's `.wires = 8`
  can't have applied).

WLAN (tested 2026-10-01: scan, WPA2-PSK through Nokia's eapd, DHCP, internet):
- The N9's WL1271 is on MMC3 (SDIO), which the upstream dts leaves disabled. `wl12xx-n9-sdio.patch`
  adds its pins (mode 3 of `mcspi1_cs1/cs2` and the eMMC's unused dat4–7), `vwlan_fixed`, IRQ GPIO 42
  and the 38.4 MHz reference clock. `vwlan_fixed` gets 1.8 V (Nokia's VSDIO): without a voltage
  omap_hsmmc can't compute the card's OCR and drops it ("Failed to initialize a non-removable card").
- `cfg80211`/`mac80211` are built in. `wlcore`, `wl12xx` and `wlcore_sdio` ship as modules for
  Harmattan's `wl1271-cal` job.
- The job first writes CAL's `wlan-nvs-t1` (`tests/wlan-nvs.c`, via libcal) to
  `ti-connectivity/wl127x-nvs.bin` (wlcore names it per chip family, `wlcore/sdio.c`). Mainline wlcore
  loads it at probe, where Nokia's took an nl80211 testmode push.
- Firmware: linux-firmware's `wl127x-fw-5-sr.bin` (until 2026-10-17: now Nokia's driver with stock's
  firmware, see "WLAN: Nokia's driver and stock's firmware").
- Harmattan's own stack runs unchanged on mainline nl80211: `wlancond` (association; its "Error in
  netlink message length" and "set channel ret=-16" are harmless), `eapd` (the 4-way handshake over
  a packet socket, keys through nl80211), `icd2` and its `udhcpc`.
- `icd2`'s job modprobes `xt_IDLETIMER` and won't start without it: legacy iptables (filter table)
  is built in and `xt_IDLETIMER` ships as a module; `wlancond` gets NFLOG. Nokia's `condition` match
  (`/etc/network/wlan_iptables.sh`, a throughput estimator) never went upstream: ported 2026-10-06
  (rm696 9ad462fb4, "Small interfaces Harmattan reads").
- Latency to the AP is ~130 ms average with power save on, to compare with stock.

Audio (tested 2026-10-01: speaker playback through Harmattan's PulseAudio):
- Harmattan's PulseAudio opens Nokia's cards by name, `hw:dfl61twl4030` and `hw:dfl61dac33`, and
  `system.pa` is `.fail` until both load. `sound-dfl61.patch` ports Nokia's two machine drivers
  (`dfl61-twl4030.c`, `dfl61-tlv320dac33.c`, audio config 4) to one DT driver, `sound/soc/ti/dfl61.c`,
  on mainline's twl4030, tlv320dac33 and tpa6130a2 codecs, whose control names match the profile
  sets (`/usr/share/pulseaudio/alsa-mixer`). McBSP3 is the TWL5031's I2S (speaker amp on TWL GPIO 7),
  and McBSP2 the DAC33's, into the TPA6140A2 (`sound-name-prefix`). NOLO leaves the McBSP pads set.
  The BT/FM card (`dfl61wl1273`) is optional in `system.pa` and left out.
- Mainline's tpa6130a2 matched `ti,tpa6140a2` without its model, which gave a TPA6140A2 the 6130's
  volume control; the patch adds it. `CONFIG_SOUND` must be `y` too, or ALSA stays a module.
- Harmattan side (`ramboot/harmattan.patch`): `group-hal` starts PulseAudio again, and its pre-start
  uses mainline's McBSP (`68000000.ocp/4902x000.mcbsp`, threshold mode) and ASoC (`pmdown_time`
  under the DAI links) sysfs. It no longer fails on the missing modem's `/dev/cmt_speech`. Nokia's
  own DAC33 "Mode 7 Low Power" isn't in mainline, so the DAC33 runs in bypass.
- Headphones: the card has Nokia's jack, "dfl61-twl4030 Jack" (ohmd's accessories plugin finds it
  by " Jack" and follows its switches), fed by AvPlugDet (TWL GPIO 0, high when plugged) and
  reporting `SND_JACK_HEADPHONE` alone, as Nokia's twl5031-aci did for headphones. Its
  `SND_JACK_MECHANICAL` alone meant "unknown accessory": with it set too, ohmd ruled the plug
  incompatible and kept the speaker (found by injecting switch events into the jack's evdev node,
  which reach ohmd as a real plug; `/etc/debug.d/ohmd` gives ohmd's decision log). TVOUT_EN
  (GPIO 40) is hogged low (the jack in audio mode).
- The plug is classified as Nokia's twl5031-aci did (`dfl61_jack_detect()`: the TWL5031's
  accessory comparators, the mic line through MADC ADCIN10): wrong pinout (the headphone amp pulls
  the mic contact down), headphones (< 40 mV), video cable (< 500 mV), open cable, basic headset,
  carkit, unknown. The buttons (a basic headset's, Nokia's ECI remotes): "The jack's buttons and ECI
  accessories" (rm696 24b20f193). First
  real plugs (boot 27, me): Apple EarPods (CTIA) "wrong pinout" (609 mV, 54 with the amp),
  so the speaker stays, as stock's logic does (not checked on stock); plain TRS headphones
  "headphones" at 24 mV. But later plugs of the same EarPods read "video cable" (52-54 mV), and the
  TRS headphones played nothing: the measurement forced the TPA6140A2's PGAs on and handed them
  back with `snd_soc_dapm_enable_pin()`, which keeps a widget forced. The amp stayed on for later
  measurements (no wrong-pinout drop left, ~52 mV read as a video cable), and DAPM never
  re-evaluated what follows a widget whose power never changes: the TPA's mute widgets (mainline
  models mute as inverted PGAs) and the Headphone endpoint stayed off during playback (register 2
  0xe8, muted) and on when idle. Toggling the Headphone pin during playback unmuted it (I
  heard the test tone). Fixed: widgets go back to DAPM by disable then enable; the amp is off
  before the first measurement, as Nokia's `dfl61_request_hp_enable(0)`; and, as Nokia's
  `aci_work`, passes repeat until two in a row agree (200 ms after headphones, video cable and
  unknown results), "unknown" after 24. Tested (boot 28, me plugging): TRS headphones
  "headphones" (24 mV) at boot and on replug, the test tone heard with nothing done by hand
  (`tests/tone.sh`: dac33 PCM running, the TPA unmuted, volume 20); the EarPods "wrong pinout"
  (613 mV, 52-54 with the amp) on every plug, the speaker kept.
- Call audio (2026-10-01 night): PulseAudio holds `/dev/cmt_speech` open (`module-meego-cmtspeech`);
  every control its call paths use exists on the TWL card (earpiece, internal digital mics,
  headset-call). `tests/voicepath.sh` sets them as PulseAudio's earpiece and mic paths do, plays to
  the earpiece (DAPM: DAC Left2, Earpiece Mixer, PGA, Earpiece on) and records the digital mics
  (Digimic0, Mic Bias 1: room noise after ~0.75 s of high-pass settling, a sound in the room seen).
  A real call needs a SIM. BT SCO: see Bluetooth. FM radio: since 2026-10-07 ("FM radio" below). The
  path to the modem without a SIM: since 2026-10-08 ("Call audio without a SIM" below).

Haptics, light/proximity (2026-10-01, `vibra-apds-n9.patch`, `omap3-n9-nokia.dtsi`):
- The vibra is Nokia's `vibra_spi` ported: its amplifier takes the waveform as a bit stream on
  McSPI2's data line (only `mcspi2_simo` is in SPI mode; the clock/CS pads are other GPIOs), power
  on GPIO 182. An FF input device "SPI vibrator" (udev: `/dev/input/vibra`) with custom periodic
  effects; Immersion's `immvibed` drives it for `libimmvibe`/meegofeedbackd.
- The APDS990x is Nokia's later driver over mainline's (which lacks `/dev/apds990x0`, the packed
  result sensord reads for ALS and proximity), with the N9's production calibration as DT match data
  (`nokia,n9-apds990x`), IRQ GPIO 83 (level low), Vdd from VAUX1.

Compass and GPS (2026-10-01, `n9-gps-compass.patch`, nodes in `omap3-n9-nokia.dtsi`; Nokia's
`drivers/misc/ak8975.c` and `bcm4751-gps.c` with `board-rm696-peripherals.c`'s data):
- The AK8975 (I2C3 0x0f) as Nokia's misc device: `/dev/ak89750`, each `read()` one measurement as
  `{s16 x, y, z; u16 valid}` with the board's axes (x = Z, y = -X, z = -Y), sysfs `selftest`,
  `memory`, `range`, `chip_id`; AVdd VAUX1, DVdd VIO. omap3-n9.dts's own `ak8975@f` (mainline's IIO
  driver, a module here) is included after `omap3-n9-nokia.dtsi` and its `compatible` would win:
  disabled, and Nokia's driver gets its own `magnetometer@f`. Stock's `id_table[2]` read past its
  table; fixed. Tested (boot 27): selftest OK (1, 1, -512), steady readings; sensord's
  magnetometer and compass sessions deliver data (heading in degrees, calibration level 0 until
  the phone is moved in a figure 8).
- The BCM4751 (I2C3, 10-bit address 0x1fa) as Nokia's raw interface for nped:
  `/dev/bcm4751-gps` (reads and writes of up to 64 bytes, `I2C_SLAVE`/`I2C_TENBIT` ioctls: nped sets
  10-bit mode and the address itself), sysfs `enable` (NSHUTDOWN, GPIO 94), `wakeup` (GPIO 91),
  `hostreq` (GPIO 95, rising-edge IRQ, `sysfs_notify` to pollers); Vbat and Vddio from VIO, as stock.
  Stock registered it as a 7-bit client at 0x1fa (2.6.32 didn't check), and nped's job sets the
  group on `/sys/bus/i2c/devices/3-01fa/*`; 6.x names 10-bit clients `3-a1fa`, so `i2c_dev_set_name()`
  names a 10-bit client above 0x7f as 2.6.32 did (no clash with 7-bit names is possible). NOLO
  leaves the three pads in GPIO mode. Tested (boot 27): nped powers the chip, writes framed packets
  (`f0 a5 93 … f0 f1`) and reads its replies, then powers it down when idle; the first write after
  power-up NACKs ("i2c_write: Remote I/O error"), as it does on stock (same syslog line). I
  confirmed GPS works.
- `tests/sensortest.pl`: a sensord client in perl (D-Bus `com.nokia.SensorService`, then
  `/tmp/sensord.sock`) that hex-dumps a sensor's samples, for checks without an app. Tested with it
  (boot 27): magnetometer, compass, ALS (~750 lux) and proximity (near/far as a hand covers it).

Bluetooth (2026-10-01, `bt-nokia-ti1273.patch`): mainline's `hci_nokia` on the DT's UART2 node.
The lessons in short: [docs/bluetooth.md](docs/bluetooth.md).
- Firmware by chip version as Nokia's `hci_h4p` (0xd1/0xf1: `ti1273_le.bin`, this N9's; 0xe1:
  `_prele`; else plain): with the plain one the chip never answers the HCI reset.
- The LE firmware answers LE Read Supported States with 4 of 8 bytes, which failed the whole init:
  `HCI_QUIRK_BROKEN_LE_STATES` for it, and hci_sync skips that command under the quirk.
- BlueZ 4 passes `BT_SECURITY` as the level alone; since 6.9 the kernel wanted the whole struct
  (EINVAL, so no DUN/RFCOMM servers): `bt-bluez4-security.patch` takes the short form again.
- After the firmware the chip runs at 921600 (TI's 0xff36, as hci_ll), not 3.69 Mbaud. (3.69 Mbaud again
  by default since rm696 1e10a8a2b, 2026-10-07: "Bluetooth and UART2 idle", throughput.)
- Received bursts lost bytes ("Frame reassembly failed", -84/-90), and with H4's no-resync framing
  one lost byte loses the events after it (inquiries never complete; `tests/btmon.pl` on the HCI
  monitor channel showed Inquiry sent, no Inquiry Complete). Two causes (2026-10-01 night):
  - 8250_omap never enabled automatic RTS for it: `set_termios()` resets EFR and sets only
    auto-CTS, and `set_mctrl()` adds auto-RTS only if RTS is raised after flow control is on;
    hci_nokia raises RTS first. `8250-omap-auto-rts.patch` keeps auto-RTS in `set_termios()` when
    RTS is up. With it the chip answers (Command Status), but bursts still failed:
  - UART2's runtime PM: on the chip's host-wakeup hci_nokia only queued a resume
    (`pm_runtime_get()`), and the chip sent into a UART still suspended. With UART2 pinned on
    (`power/control` = on), an inquiry completed (Command Status, Inquiry Complete 10.24 s later)
    with no reassembly errors; with runtime PM, it failed again. `bt-nokia-wakeup-sync.patch`
    resumes it synchronously in the (threaded) wake IRQ: built, not yet run.
  - 2026-10-02 (boots 31-36): the sync resume changed nothing (UART2 is runtime-active throughout
    anyway). `rx_dump` (a temporary module parameter: every received chunk in the kernel log)
    showed what fails: commands and events while the chip is awake arrive whole; while it sleeps
    the chip holds its TX low, and through RX DMA the zeros reached H4 as data (a 3930-byte "ACL
    packet", -90, events lost behind it); and the first event after it wakes loses its first bytes
    (Inquiry Complete `04 01 01 00` arrived as `01 00`). Built and tried: Nokia's wake handshake
    (RTS raised after host-wakeup, dropped before sleep, as hci_h4p's enable/disable_rx), a stray
    byte between packets dropped alone (as hci_h4p), UART2 without DMA (`/delete-property/ dmas`),
    serdev ports with IGNBRK (IGNPAR too dropped more). Inquiries still don't complete, and one
    `hciconfig up` failed with EIO. Next: hold the chip awake (BT wakeup line high) to confirm the
    loss is only at wake-up; compare hci_h4p's negotiation (sleep mode bits in the NEG packet) and
    its UART set-up (TLR/TCR, no-idle while awake) with hci_nokia's.
  - bluetoothd cancels a raw `hcitool inq` while it sets the adapter up (Inquiry Cancel right after
    `hciconfig up`): wait ~10 s, or power it through bluetoothd (`SetProperty Powered`).
  - Boots 37-38: with UART2 pinned (`power/control` = on) an inquiry found 6 devices, so
    `bt-nokia-wakeup-sync.patch` also held UART2 while hci0 was up. Boot 39: still failing. What
    it was (boot 39, kprobes on `serial8250_read_char`/`uart_insert_char`, the wake IRQ and
    `nokia_recv`; Nokia's hci_h4p from Pavel Machek's
    [staging submission](https://lkml.rescloud.iu.edu/1401.2/00845.html) for comparison):
    - The "zeros" were never line noise: Extended Inquiry Result (`04 2f ff`, 255 bytes) carries
      240 bytes of zero-padded EIR. What got lost was each such event's first two bytes, so the
      rest read as junk and its body (`02 3c 04 08 …`) as an ACL header. Only one break in the
      whole session: the chip doesn't hold its TX low asleep.
    - The two bytes were lost by the wake handshake itself: when the chip wakes on its own
      (inquiry results, Inquiry Complete) and finds RTS low, its first two bytes never reach the
      wire (no UART interrupt, no line error; `04 01 01 00` arrived as `01 00`, 150 µs after
      the threaded wake handler). hci_h4p does the same handshake but from the hard IRQ, within
      µs. With RTS forced up (MCR via `/dev/mem`), Inquiry Complete arrived whole, 60 µs after
      host-wakeup. UART2 itself is clocked and never idles (SYSC no-idle, fclk on).
      (2026-10-07: more likely the resume's flow-control termios change clearing the receive FIFO
      right after RTS went up; the chip waits for RTS: "Bluetooth and UART2 idle".)
    - A frame begun on such a byte swallowed every later frame until its length was met: command
      replies (tx timeouts: they arrived whole at `nokia_recv`), and across `hciconfig down/up`
      (hci_nokia keeps its parser state), so the next set-up failed (EIO, ETIMEDOUT): the
      "wedged chip". A driver unbind/bind cleared it.
    - Fix, `bt-nokia-uart-rx.patch` (replaces `bt-nokia-wakeup-sync.patch`, kept as
      `build/bt-nokia-wakeup-sync.patch.old`): mainline's wake handler again (no UART hold), and
      RTS stays up: mainline lowers it too, in the serdev device's runtime suspend (raised again by
      an async resume after host-wakeup, slower still), so its runtime suspend no longer touches
      flow control. A frame still incomplete 500 ms after its last bytes is dropped, the
      stray-byte drop kept; `rx_dump` and the failure dump stay for now (temporary).
    - Boot 40 (the first two, without the RTS change): four `hciconfig up` in a row all set up
      (the parser fix); inquiries still hung until the serdev device's runtime PM was pinned on
      (`/sys/bus/serial/devices/serial0-0/power/control` = on, RTS up): then 4 of 4 fresh
      inquiries completed in 10 s (1 device found on 2), no new receive errors, the chip still
      sleeping between (host-wakeup IRQs counting). Boot 41 (build #82, with the RTS change and the
      BT-off close below): 3 power-on/inquiry/power-off cycles, each power-on 0.7 s (firmware
      included), each inquiry complete in 10 s with 4 devices found; 0 receive errors, no
      reassembly failures, no command timeouts.
  - UART2 idle with Bluetooth off (same patch): hci_nokia sets `HCI_QUIRK_NON_PERSISTENT_SETUP`,
    so hci_serdev closes the port at power-off ("holding port open may drain the battery") and
    the set-up (reset, negotiation, firmware) runs at each power-on, as stock's hci_h4p did; a
    `shutdown` hook holds the chip in reset (and the BT wakeup line low) while off. Its runtime
    PM callbacks no longer touch the port (`ttyport_close()` leaves a stale tty: a wake IRQ on a
    closed port would have used it). With Bluetooth on, UART2 stays up: the chip needs RTS up at
    once when it wakes, which stock got from the hard IRQ. Tested (boot 41): with Bluetooth off,
    UART2, its port device and the serdev controller are runtime-suspended and the chip is in
    reset (GPIO 26); after each power-off in the cycles above, suspended again. Whether CORE now
    reaches RET is for an unplugged test (USB keeps it on).
  - Why UART2 never idles, BT on or off (boot 39, `rpm` tracepoints): hci_serdev opens the serdev
    port at registration and keeps it open (it closes only for `HCI_QUIRK_NON_PERSISTENT_SETUP`
    drivers, "holding port open may drain the battery"); `serdev_device_open()` holds the serdev
    controller runtime-active, which keeps its parents active: the serial core's port device
    (`4806c000.serial:0.0`, child-1), its controller (`:0`), and the UART (usage 0, child-1). The
    BT serdev device itself is suspended. Fixed for Bluetooth off (below).
  A stuck inquiry blocks the next one (the kernel waits for HCI_INQUIRY to clear): Inquiry Cancel
  (`hcitool cmd 0x01 0x0002`) or `hciconfig hci0 down; up` resets it.
- Bluetooth SCO (headset calls) as stock: over PCM, not HCI. Harmattan's PulseAudio opens
  `hw:dfl61wl1273` (8 kHz mono, `sink.hw1`/`source.hw1`, `module-bluetooth-discover sco_sink=...`).
  The chip's PCM is on McBSP4, which NOLO muxes on the GPMC nCS4-7 pads (mode 2: clkx, dr, dx, fsx;
  the mcbsp4 pads carry the modem's SSI in mode 1). Nokia's firmware sets the PCM up itself (TI's
  Write CODEC Config 0xFD06: master, 128 kHz bit clock, 8 kHz frames, one 16-bit slot a clock
  after the frame sync, i.e. DSP_A). `sound-dfl61.patch` adds the third card "dfl61-wl1273"
  (McBSP4 and mainline's generic `bt-sco` codec; stock's WL1273 codec also had FM modes, not
  ported). On boot 30 it failed: "Missing dma channel for stream: 1": McSPI1-4 held 18 of the
  sDMA's 32 logical channels (a pair per chip select, at probe). McSPI1/3/4 are unused on the N9
  (stock: vibra on McSPI2, McSPI4 only for an SPI WLAN): disabled in `omap3-n9-nokia.dtsi`. Built,
  not yet run then. Since the FM port (2026-10-07, rm696 ffb5dcc35) the card runs on Nokia's WL1273
  codec instead of `bt-sco`, BT mode by default: PulseAudio's `sink.hw1` streams to it at 8 kHz ("FM
  radio" below); a call through a Bluetooth headset not tried.
- Stock's TI1273 firmware (`ti1273*.bin`, Nokia's, not in linux-firmware) is needed twice: the
  initramfs carries it under `/lib/firmware/nokia/` (`kernel/build.sh` copies it from Harmattan's
  PR1.3 rootfs on the Mac) for the power-on at registration (~2.8 s, before any root is mounted), and
  the init links it under Harmattan's `/lib/firmware/nokia/` for bluetoothd's power-ons (PID 1's
  chroot moves the firmware loader's root too: `kernel_read_file_from_path_initns` reads in
  init_task's root, which PID 1 shares). Until 2026-10-05 only the links existed: the first power-on
  failed and kept the adapter in setup (`HCI_SETUP`) for the whole boot. Boot 162 (rm696 470c55a0a):
  the first power-on succeeds (93 commands, 0 errors) and the user channel opens on hci0 without a
  re-probe; that image lacked the links, and bluetoothd's power-on at 63 s failed (firmware -2)
  until they were made by hand. Boot 163 (`zImage-n9-470c55a`, the init with the links): all three
  pass: the firmware in both places and 0 failed loads (bluetoothd's power cycle: 194 commands, 0
  errors); `hciconfig hci0 up` from Harmattan UP RUNNING, 0 errors; the user channel 1557 of 1557
  echoes, 0 corrupt or lost in 20 s. The user channel needs hci0 down while bluetoothd is stopped:
  bluetoothd powers it up again within seconds of a `hciconfig hci0 down`, and an up adapter refuses
  the bind (EBUSY, the same error as a stuck `HCI_SETUP`). The chip has its own Nokia BD address.
- Sustained traffic (2026-10-05, boot of rm696 7546a2e33): the "RX loss under sustained traffic" of
  2026-10-01 was the wake handshake and the swallowing parser above, fixed on 2026-10-02 but tested
  only with inquiries until now. `tests/btloop.pl` (HCI user channel, the controller in local
  loopback, random-size ACL packets up to the 1021-byte MTU, three in flight, each echo checked byte
  for byte): 60 s idle, 60 s beside two CPU hogs (load 2.95) and 60 s beside a raw eMMC read, plus a
  10 s first run: 15136 packets, 7.9 MB received at ~40 KB/s each way, 0 lost, 0 corrupt, no UART
  overrun/framing/parity counts, 0 receive errors in hci_nokia, nothing in the kernel log. Over the
  radio, against the Mac (paged by address, no pairing): 20 of 20 remote name requests answered
  identically with the chip waking the host 122 times (the path that lost the first two bytes), and
  14 SDP browses with byte-identical results (the first after the Mac had reset an L2CAP link failed
  to connect, no receive error); 6 inquiries each completed in 10.27-10.29 s. Not covered: real
  profiles (A2DP, OBEX, PAN), which need a paired device and me. Seen on the way: the boot-time
  power-on (no firmware yet) leaves `HCI_SETUP` set for the whole boot, so the user channel is
  refused until the driver is re-probed (`docs/bluetooth.md`); BlueZ 4 doesn't use mgmt, so nothing else
  is known to depend on it. Since then the firmware is in the initramfs (above).

USB modes (2026-10-01 night, `usb-moded-compat.patch`, `ramboot/init`):
- Harmattan's usb_moded (2011) `modprobe`s Nokia's gadgets and writes 2.6.32 sysfs: mass storage
  is `g_file_storage luns=1 stall=0 removable=1`, then MyDocs (`/dev/mmcblk0p1`) into
  `/sys/devices/platform/musb_hdrc/gadget/gadget-lun0/file` (and `nofua`); Ovi Suite is `g_nokia
  use_mtp=1 connect=0`, then `gadget/softconnect`; SDK mode ("windows_network") is `g_ether`, then
  `ifdown usb0; ifup usb0`; charging only keeps `g_file_storage` loaded with no medium (seen
  2026-10-02: the Mac's volume goes away, the module stays). Its setting is
  `/Meego/System/UsbMode` (gconf; this phone's default turned out to be mass storage; since set to
  SDK, me, 2026-10-08: the release keeps every mode as stock).
- The patch: mass storage as the module name `g_file_storage` (mainline's `g_mass_storage`), a
  `gadget-lunN` link next to each LUN device, and musb's `/sys/devices/platform/musb_hdrc` (link to
  the controller), `gadget` (link to `gadget.0`) and `gadget/softconnect` (connect/disconnect).
  `g_file_storage` and `g_nokia` ship as modules (libcomposite and the functions are built in).
- The test image (init): `modprobe.d/ramboot-usb.conf` routes the three through
  `/usr/sbin/ramboot-usb`. SDK mode is the RAM boot's own ECM gadget (stock's ids and MACs; a real
  `g_ether` would get `usb1`, the gadget's ECM function keeps `usb0`). Mass storage (exported
  read-only: `options g_file_storage ro=1`) and Ovi Suite take the port only if
  `MyDocs/.ramboot/usb-modes` exists (or `/tmp/.ramboot-usb-modes` for a test); then the init keeps
  the session alive while one is loaded. Without that, the first boot with this (boot 29) loaded
  mass storage at boot (the phone's setting), ssh went away, and the session rebooted it.
  Whenever no such gadget is loaded the init binds the SSH gadget again (every 3 s).
- Tested (boot 30): the compat paths exist; usb_moded's boot-time mode no longer takes the port.
- 2026-10-02: the eMMC was `mmcblk1` on 6.18 (omap3.dtsi's mmc aliases), so usb_moded exported and
  remounted `/dev/mmcblk0p1`, which didn't exist: an empty LUN, and Harmattan's MyDocs gone after
  the switch (I saw both; csd/sscd also spun at 50% each then, not seen again). The eMMC is
  `mmc0` now (`omap3-n9-nokia.dtsi` aliases: mmcblk0, as stock). usb_moded then exports MyDocs
  read-only (`lun0: open backing file: /dev/mmcblk0p1`) and the Mac sees a read-only 9.45 GB disk
  ("File-Stor Gadget"), but it doesn't mount: after one failed command (no medium yet) every
  transfer stalls until the Mac's bulk reset, every ~30 s; the same with musb in PIO
  (`musb_hdrc.use_dma=0`), so not its DMA. Stock's export mounts on this Mac (user).
- Cause (boot 38, musb register trace): the Mac sends the next command (CBW) as soon as it has the
  last status; it lands while f_mass_storage has no OUT request queued, the RX interrupt finds none
  and leaves it in the FIFO, and the request queued a moment later finds RXCSR `0003` and flushes
  it (`0057`): mainline 3fc137386c46 (CVE-2024-56687) replaced `rxstate()` in `musb_ep_restart()`
  by a FIFO flush, as `usb_ep_queue()` must not complete a request, accepting "one or two packets
  dropped" (fine for Ethernet, not for a command protocol). The phone then waits for a command the
  Mac thinks it sent: bulk reset after 10 s, again and again.
  [lkml v2](https://lkml.iu.edu/hypermail/linux/kernel/2411.1/02225.html)
- Fix, `usb-musb-rx-early-packet.patch`: with RXPKTRDY already set, `musb_ep_restart()` leaves the
  packet and schedules a work that runs the normal RX path (`musb_g_rx()`), so it's read into the
  request and completed outside `usb_ep_queue()`; otherwise the flush as mainline.
- Tested (boot 39, DMA on): `modprobe g_file_storage … file=/dev/mmcblk0p1` by hand and
  usb_moded's `set_mode mass_storage`: the Mac mounts `/Volumes/Nokia` (read-only) within 5 s,
  80 s without a reset or an invalid CBW, unmounts on the switch back, and Harmattan's MyDocs is
  mounted (ro) again after it. Ovi Suite (MTP) not tried.
  The test image keeps MyDocs read-only whoever mounts it: `ro` in the overlay's fstab (usb_moded
  remounts from it when it leaves mass storage: rw, a second writer next to the log writer's), and
  the init re-binds it read-only if it's missing.
  To try a mode by hand: `touch /tmp/.ramboot-usb-modes` in Harmattan, D-Bus `set_mode` (root needs
  `ramboot/unlock.sh`'s policy), with a timed `rmmod g_file_storage` from the init side to get ssh
  back (the init then binds the SSH gadget and sets usb0 up again).

Modem (2026-10-01, working at the ISI level; no SIM in the test phone, so no calls tried):
- Mainline's N9 DT and drivers: OMAP SSI on port 1, `ssi_protocol` (McSAAB, `phonet0`), `cmt_speech`
  (`/dev/cmt_speech`, PulseAudio's call audio), `nokia-modem` with `nokia_modem.pm=0`: NOLO leaves
  the modem powered (`cmt_en` high) and stock's kernel never drove its GPIOs (pm=1 drives them low).
  The wake-line test passes; `group-hal` starts `csd`, `sscd` and (since 2026-10-05) `infoserver`
  again.
- Phonet: mainline lets only CAP_SYS_ADMIN create Phonet sockets and bind resources; Nokia's kernel
  also allowed a group (`phonet_gid`, Harmattan's `/etc/modprobe.d`: 30012), and sscd/csd run
  without the capability. `phonet-gid.patch` restores it (`phonet.phonet_gid=30012` in CONFIG_CMDLINE).
- Result, as stock: csd "Phonet up", SIM `SIM_NO_SIM`; sscd modem power on, Phonet on, RF inactive,
  `ModemState=Tablet SimState=Missing`, `SystemReady`. sscd logs the IMEI to syslog: filter it.
- The modem's `COMM_SERVICE_NOT_AUTHENTICATED_RESP` (`59 f0 17 02`, once every test boot through 158,
  never on stock) came from the test image, not from BB5 or the kernel (2026-10-05, boot 159). sscd's
  self-test module asks resource 0x59 for the self-test results (`ST_RESULTS_GET_REQ`, `59 02 04 00`:
  sscd uses the resource as the transaction id), then `PN_SELFTEST` (0x35). On stock, Nokia's self-test
  server `stserver -z` (job `stserver-normal`, which the boot groups wait for) binds both resources
  (`SIOCPNADDRESOURCE`) and Phonet delivers the query to it locally (resource routing in
  `net/phonet/af_phonet.c`, as in 2.6.32) and forwards to the modem's 0x35. `harmattan.patch` had
  disabled it (and `infoserver`), so the query reached the modem's firewall. Both run as stock again: no
  refusal; the same query sent by hand is answered by stserver on the APE (`59 03 00 00`,
  `ST_RESULTS_GET_RESP`); sscd reaches `SystemReady` as before; stserver's job then ends with status 0
  (sscd has an `ST_SERVER_SHUTDOWN_REQ`; not traced); no new job failures. `infoserver` (Nokia's
  testserver framework, its proxies in
  `/usr/lib/testserver/modules/proxies`) binds 0x08 (`PN_SECURITY`), 0x17, 0x1B (`PN_PHONE_INFO`), 0x53,
  0x62 (`PN_EPOC_INFO`) and 0x6F on the APE as on stock, so those requests go through it again; csd logs
  the same as before. Their write paths run only on production-test requests (reboot, sysfs, CAL, an OTP
  lock), except stserver's ALS calibration at start, which may write CAL: the OneNAND driver refuses
  CAL writes on this kernel. `format_device` (`dd` over a disk's first sector, then `mkfs`) is in both
  binaries, but nothing in this pipeline calls it (the `handlers` modules are local-test-mode
  `testserver`'s).
- csd's GPRS plugin (`libcsd-gprs.so`) reads the modem's reset count from the reset indication's line in
  `/proc/interrupts` (its log: "CMT reset cycle %u, storing data counters"), parsed as
  `"%*d: %u%*[ ]GPIO%*[ ]cmt_rst_ind%c"`; it is the only reader of that file in Harmattan. With mainline's
  name (`modem_rst_ind`) and 6.x's columns (chip `49050000.gpio`-style, hwirq, `Edge`) every test boot
  logged "could not read CMT reset count"; stock never does (the stock sessions in the saved syslogs). Commits
  58bbb08e1 and 470c55a0a on rm696: `irq_set_proc_chip_label()` prints one interrupt's line as
  2.6.32 did (`185:          3       GPIO  cmt_rst_ind`), and nokia-modem requests the interrupt as
  `cmt_rst_ind` with the label `GPIO`; every other line keeps 6.x's columns. csd's format checked against
  the new, the old and stock's line on the Mac; tested on boots 162 and 163 (rm696 470c55a0a,
  `build/zImage-n9-470c55a`): `181:          0       GPIO  cmt_rst_ind`, csd logs no error.

Secure world / BB5 (2026-10-01): Harmattan's real `libbb5` (and `bb5-init`, Aegis) needs Nokia's
`/dev/omap_sec`. `omap3-sec-bb5.patch` ports Nokia's whole driver, all GPL in their published tree
(github harmattan/kernel-plus-harmattan): `plat-omap/sec.c` (the character device, PA firmware
loading), `plat-omap/pa.c` (PA command marshalling from `omap3_pafmt_*.bin`), `mach-omap2/hs.c` (the
`sec_operations` and secure RPC callback), `mach-omap2/sec_hal.c` + `sec_hal_entry.S` (the `smc #1`
entry, r12 = service, r6 = 0xff: the convention of mainline's `omap_smc3`). Checked against stock's
kernel (OneNAND `kernel` partition, read-only, symbols from its kallsyms): same code. Into
`mach-omap2`, as modules `omap_sec.ko` (`kci=`, NOLO passes stock `omap_sec.kci=958`) and
`omap_hs.ko` (its init resizes the secure RAM to 48 KiB and registers the RPC handler, as stock),
built in (`CONFIG_OMAP3_SEC=y`) with Harmattan's own `libbb5` and `validator-init`, as stock
(2026-10-02, boots 42-51; the first try, 2026-10-01, stopped at a black screen). What it took:
- validator-init keys the hashes by `st_dev`; on the overlay root, files report a layer's pseudo device
  with no superblock ("Cannot find superblock"): `overlayfs-aegis-pseudo-dev.patch` and
  `aegis/overlay-pseudo-dev.patch` attach them to the overlay.
- validator-init asks for enforcement; the changed `preinit` was then denied and PID 1 died (panic,
  `sw_rst` 10 s later): open mode logs it instead (`aegis/open-mode-no-panic.patch`).
- Every open-time check read nothing (-EINVAL: a 6.x file isn't readable at `file_open`), so every
  file "failed" and Harmattan entered MALF ("SECURITY sh /sbin/waitfordsme"): `aegis/file-post-open.patch`.
- aegisfs (Aegis's encrypted storage: `/home/user/private`, `/etc/ssl/certs`, ...) mounts through FUSE,
  which stock has built in: `CONFIG_FUSE_FS=y`. On the emulator's BB5 it never got that far (its
  signed config didn't verify).
- The module whitelist refused our modules (`pvrsrvkm`: no X, the black screen): open mode loads them.
Result (boot 51): the home screen; sscd stays up (`SystemReady`); secure-clean opens libbb5 and can't
read the wipe state (EAGAIN), as on stock; aegisfs mounts 11 filesystems; Aegis failures only for the
files this image changes. The modem's `COMM_SERVICE_NOT_AUTHENTICATED` (0x59) wasn't BB5: the test
image had disabled stock's self-test server ("Modem", 2026-10-05). How it went: `docs/modem.md`.
What changed for 6.18:
- The secure side reads its argument block from physical memory. Nokia passed the variadic arguments
  on the stack; 6.18's stacks are vmapped and a module's data isn't in the linear map either, so the
  block is kmalloc'd (`sec_hal_init`). Every other buffer the secure side gets is kmalloc'd already.
- The RPC handler's allocations are GFP_ATOMIC (they run inside a secure call, interrupts off).
- `omap_hs` can't be unloaded: the secure side keeps the RPC handler's address.
- SHA-1 of Aegis credentials from the crypto library (`CRYPTO_SHA1` is a module, not shipped);
  `in_egroup_p` takes a kgid; `kernel_read`, `strscpy`, `__poll_t`, no `no_llseek`.
- Our kernel's PAGE_OFFSET is 0xc0000000, stock's 0xb0000000. No PA takes a virtual pointer
  (`omap3_pafmt_958.bin`: 51 commands, only physical ones), so that doesn't reach the secure side.
- Mainline saves the secure RAM context once at boot, for OFF mode, into 0x803f bytes; stock reserved
  0xc040 for the 48 KiB secure RAM and re-saved it when a secure call dirtied it. The N9's DT has no
  `ti,twl4030-power-idle`, so OFF mode is off and the save is never restored or repeated. Enabling OFF
  mode would need stock's buffer and re-save first. (Done since: the 0xC040 save at every CORE OFF entry,
  c2f638ca4, and a positive save status counted as saved, 4ea7a477f; CORE OFF works, "CORE OFF".)
- Persistent secure storage goes through `bb5-init`/`libcal` to CAL on OneNAND, which this kernel
  can't write: nothing reaches the phone's flash.
Test: `ramboot/bb5-test.sh` runs `ramboot/bb5-test.pl` (a hardware random
number, Nokia's `PA_ROT13` test PA, the PA image versions). Tested on the phone (2026-10-01, two
boots): `omap_hs` initializes (secure RAM resize, RPC handler), the secure ROM RNG returns random
bytes, and the secure world loads, verifies and runs the signed `PA_ROT13`, returning the right text;
no driver warnings, Harmattan unaffected. Probe before the port: mainline's N900 ROM
RNG (PPA service 29) works on the N9 under this kernel. Built in, the same results (boot 50).

## Standby crash, NOLO's logo (2026-10-02)

Once the real BB5 ran, every test session rebooted by itself after 3-8 minutes, on standby (the low
power mode clock) or on waking from it; the reboot was `sw_rst`, with nothing in syslog (I say
standby reboots happened before BB5 too). pstore/ramoops (`pstore-ramoops-n9.patch`) caught it, the
same each time (boots 58, 60-62, FSR 0x1008: a precise external abort, AXI slave error):
`pvrsrvkm` re-initialising the SGX after it powered off (`SGXInitialise` → `SGXReset` →
`SGXResetInvalDC`) does its first *read* of an SGX core register (`EUR_CR_BIF_MEM_REQ_STAT`; the
reset's writes before it are posted) and the interconnect answers with an error, which Harmattan's
`panic_on_oops=1` turns into a panic. It happens when the GPU powers up with the display off (the
fatal one in boot 62 came 8.9 s after the previous; Xorg's 0.5 s updates had stopped); a reproducer
(display off, `pvr2d-test` every 3 s) crashes in under a minute. Ruled out first:
- the secure world: kprobes on its entry points saw no call before the panic, and 8000 secure calls
  with the GPU busy didn't crash it;
- power-up timing: build #103 (boots 60-62) waited for `PM_PWSTST_SGX` ON and `CM_CLKSTST_SGX`
  active before touching the SGX and never had to wait;
- smart idle: `sgx-sysc-no-smart-idle.patch` (no idle/standby while powered) survived 10 forced
  cycles but crashed after 19 minutes; reverted;
- pvr's cpufreq hook (the 5.0 port's, replaced by Nokia's `sgx_fck` clock notifier): still crashes;
- CORE idle errata (DM3730 SPRZ319F 1.85, DPLL3 releasing the SDRC early; 1.90, DPLL3 bypass
  ignoring the SGX clock): mainline leaves DPLL3 in automatic mode where stock keeps it locked
  outside CORE retention (`program_vdd2_opp_dll_wa`), but here CORE never leaves ON
  (`core_pwrdm OFF:0,RET:0,INA:0`; `core_l4_clkdm` holds 23 clocks), so DPLL3 never stops;
- SmartReflex: Harmattan's `/sbin/read_cfg.awk` enables it through stock's `/sys/power/sr_vdd*_autocomp`,
  which mainline doesn't have (its knob is debugfs `smartreflex/*/autocomp`, read 0 live); the same
  script's `pm_debug/enable_off_mode` reads 0 too.

`sgx-abort-diag.patch` (temporary) catches the abort when it's a `readl()` in `pvrsrvkm`: it logs the
SGX/CORE power and clock registers, DPLL3, the VDD1/VDD2 voltage processors, the SGX wrapper's
`OCP_DEBUG_STATUS` and the time since the last cpufreq change, then lets the read return 0 so the
phone stays up; `omap_l3_smx` then logs the decoded interconnect error (its BUG on a timeout is a
comment for now). Boot 65 (`build/ramboot-dmesg-65.txt`) survived the first fault and showed the
cause: **the SGX had no functional clock**. `CM_CLKSEL_SGX` held 4 (`omap_192m_alwon_fck`, from
DPLL4's M2) while the clock framework had `sgx_fck` on `core_d2_ck` (5, CORE/2, what pvr asks for and
stock uses), so enabling the GPU held DPLL3 only; with the display off nothing else needed DPLL4's
96/192 MHz output, the framework stopped DPLL4 (`CM_CLKEN_PLL` EN_PERIPH 1, `PWRDN_96M` set) and the
SGX read got "In-band Error" (SLVERR). With the display on, DPLL4 mostly ran for other users and the
GPU ran at 96-192 MHz instead of 195. Writing 5 by hand stuck, also across an SGX power-domain OFF/ON,
and the framework never writes 4 (no CM context restore without CORE OFF; no clock save/restore on
OMAP3), so something else sets the register's reset value: the diag patch now logs every change of it
(10 ms poll) and puts back the framework's value, to find what. Not SmartReflex (off, checked live),
not cpufreq (1 GHz for 79 s before the fault), not CORE idle.

Boot 66 timed it: 0 → 4 at 16.58 s, when pvr's `clk_set_rate` moved `sgx_fck` to `core_d2_ck`; a test
module setting each parent by hand showed index 0 → 0, 1 → 0, 2 → 2, 5 → 4: bit 0 always cleared. The
TI composite mux's `latch` was 0 (kzalloc) instead of -EINVAL, so `ti_clk_latch()` set and cleared bit 0
after every parent change; an upstream bug since ee2fc3c5ca8d (4.17), still in mainline. **Fixed** by
`ti-composite-mux-latch.patch` (boot 67: the framework writes 5 itself and nothing changes it after;
235 GPU tests with the display off over 16 minutes, no failure and no abort, where the first one used
to crash). `sgx-abort-diag.patch` is retired (`build/kernel-patches-2026-10-02/`). It also stopped the GPT10/11 muxes from flipping `CM_CLKSEL_CORE`'s L3 divider bit. With the
display on, the GPU had been running at 96-192 MHz from DPLL4 rather than 195 MHz from CORE.

NOLO's logo (`omapfb-takeover.patch`, stock's `def_disp_enabled`, which NOLO passes): stock keeps it
until Harmattan's boot image. Here the takeover holds the reset line (GPIO bank 3 no longer reset at
boot) and sends no frame, but the panel was found reset anyway (power mode 08, brightness 0 at 3.55 s;
an earlier "still lit at 2.5 s" was NOLO's own fade-in, never measured): not the reset line, not the
DSI's ULPS exit (tried both ways). The driver then did a full power on, so the screen was black from
there until `preinit` drew `booting.png` (~10 s).

**Fixed** (2026-10-05 night, boots 165-180, branch `logo-fix`; merged into rm696 2026-10-06, ea07646b6),
found with a raw DSI probe of the panel from a core_initcall, run every 100 ms on NOLO's still-configured
DSI (DCS 0x54 reads 0x24 with NOLO's settings, 0x00 after a reset): alive at 3.347 s, reset at 3.466 s,
the panel driver's probe.
- 147cff13e: mainline `dsicm_probe()` pulsed the panel reset unconditionally (the takeover only skipped
  it in power on); stock skipped the first init.
- 679e31b7c: NOLO's ULPS left by hand at the first DSI enable while the display is taken over.
- a2e408b6a: an RGB565 framebuffer, as stock (at 32 bpp `preinit`'s boot image issued no update).
- ea07646b6: stock's framebuffer geometry (`omap2fb.vram=0:2629632` = 856x1536x2, virtual 856x1536):
  X's `OMAPFB_SETUP_MEM` to that size had reallocated the region, a black first X frame.
The takeover now logs "keeping NOLO's display"; NOLO's logo, then the boot image, then X's boot screen,
no black gap (me, boot 180). Left: stock blinks the white LED 5 times at boot, we don't (mce's
power-on pattern is never triggered here).

Notes: `ramboot/arm.sh` waits for NOLO when the phone is up in a stock USB mode; the init keeps the
previous boot's last MyDocs dmesg copy (`dmesg-prev.txt`) and pstore's records; fb0 is auto-update only
in the init's shell mode (Harmattan's X drives it). On a test boot, mce shows the low power clock and
the lock screen only with autolock on (`ramboot/unlock.sh` turns it off for tests).

## CORE/L3 scaling (2026-10-03)

I wanted power scaling ("I absolutely want power scaling"), so CORE/L3 (VDD2) scales as on
stock, in three parts, all in `../linux_mainline_rm696`:
1. The mechanism (`omap3-core-dvfs.patch`): DPLL3's M2 divider 1 ↔ 2, so CORE 390.4 ↔ 195.2 MHz and
   L3/SDRC 195.2 ↔ 97.6 MHz, done from SRAM with the SDRAM in self-refresh and its refresh rate
   reprogrammed (`RFR_CTRL` 0x5b701 ↔ 0x2c701), VDD2 through the voltage processor (VSEL 0x30 ↔ 0x20,
   1.2 ↔ 1.0 V). Tested on boot 67: a 64 MB RAM pattern intact across switches and 60 s at OPP50.
2. The policy (commit "ARM: OMAP3: L3 scaling policy"): OPP50 unless something holds L3 high. The
   CPU above its minimum holds it: stock's rule was the lowest OPP (300 MHz); I keep my own
   600 MHz floor (`apps/min_freq`) and L3 scales at it (user, 2026-10-03). Lowered 1 s after the last
   hold, raised at once.
3. The SGX: `EnableSGXClocks()` holds L3 high before the SGX gets its clock (CORE/2) and
   `DisableSGXClocks()` lets go after, so its clock never changes while it runs; pvr's `sgx_fck`
   notifier takes `pvr_dev_lock` only when the SGX is clocked (the hold runs under that lock).

The first switches showed a mainline bug: the SSI (modem link) clock notifier wrote a suspended port's
divisor, an L3 "In-band Error" on every change; fixed (commit "HSI: omap_ssi_port: ..."). Boot 69
(300 MHz floor for the test): 178 GPU tests with the display off, 32 L3 switches, no failure, no L3
error, no abort, RAM pattern intact. Boot 71 (my 600 MHz floor, `ondemand` with my tune),
5 min of settled standby with the display off: 6% CPU load, the CPU at 1 GHz 13% of the time
(`schedutil`: 40%), L3 at OPP50 45% (`schedutil`: ~9%), a switch every 1.6 s; GPU tests after, no
failure. Not held high yet, unlike stock: the display, USB and WLAN (bandwidth at OPP50 hasn't been
short so far; add holds if it is). The 1 s lowering delay is a guess: shorter would keep L3 low longer
after each CPU burst, at more switches.

Holds as stock (2026-10-03, boots 72-79; I picked option B for the display): each holder by
name in debugfs `omap3_l3` (`... holds cpu 0 sgx 0 dss 1 usb 1 wlan 0`). Stock's requests were
`omap_pm_set_min_bus_tput` (Nokia's kernel): the display 500000 KiB/s while started
(`omap_dss_start_device`, "DSS does not work properly if DSS clocks are over 100MHz and VDD2 is at the
lowest OPP"; `dpll4_m4_ck` here is 172.8 MHz), USB 780800 from VBUS connect to disconnect, WLAN 780800
when associated and out of power save. Tested:
- Display: held from power on to power off and while the screen is on; in the standby screen (LPM)
  released, and held again for each clock update only while the DSS runs (about 1 s a minute: DSI
  wakes, then ULPS 500 ms after the update). I saw the clock update cleanly. Covered proximity
  (display off): released. Fallback A (stock: held in LPM too) is sysfs `l3_lpm_hold` 1, untested.
- USB: held while plugged in; within 2 s of an unplug the controller suspends and the hold goes.
- WLAN: idle and associated, the chip sleeps 98% of the time (0.2 s awake in 10 s) and the hold is
  mostly off; pings every 200 ms keep it awake 36% of the time (held in 40% of samples, 5-10 ms
  RTT); at 1 s intervals ~140 ms RTT, 802.11 power save.

Three mainline bugs found on the way (Layout table): wlcore kept a runtime PM reference after its
first bring-up (wlancond sets the TX power before association; mac80211 passes INT_MIN; wlcore
refused it and skipped the put), so the WLAN chip never entered ELP and the WLAN hold never went;
a firmware switch path leaked another. musb's runtime resume restored the unplug-time endpoint
registers over the ones a host had just configured: after any USB replug, macOS never got the ECM
"connected" notification (the notification endpoint left at TXMAXP 0, restarted every 128 ms) and
kept the link down (with runtime PM blocked the replug worked; boots 73-78). And an AP whose country
element lists every channel at -128 dBm made mac80211 limit the TX power to 0 dBm; wlcore never
applied it (its default level is 0, so the radio stayed at the firmware's default), and it also never
applies mac80211's regulatory cap (13 dBm on 5805 MHz, IT): open, a compliance question.

Measuring with the cable in: `echo -usb > /sys/kernel/debug/omap3_l3` (and `-wlan` if needed) stops
counting those holds. Not measured yet: standby time at OPP50 with the display hold (A vs B), frame
pacing (`ramboot/butter.sh`) and USB/WLAN throughput at OPP50 vs OPP100 (`low`/`high`), and the
lowering delay (next step).

## Display power, lock screen, frame pacing (tested 2026-10-01)

Harmattan's mce drives the display through stock's kernel interfaces; with them it works as on
stock:
- Brightness: `omapfb-panel-stock-power.patch` registers the panel's DCS backlight (0x51, 0-255) as
  `/sys/class/backlight/display0`, the name mce looks for (6.18's omapfb `panel-dsi-cm` never set
  `use_dsi_backlight`). Under `device/`, the Pyrenees controls of stock's `panel-nokia-dsi`: `lpm`
  (DCS idle mode, 300 ms after the last update), `dimming` (the panel fades) and `hbm` (with ACL).
- Screen timeout as stock (dim 30 s, blank 5 s later, gconf): dimmed at brightness 7, then off,
  locked, the panel in low power mode and the standby screen (clock, status) drawn; mce's colour
  profile (`[Display-fe]` Neutral, DISPC CPR) applies.
- Double tap to wake: `atmel-mxt-wake-gesture.patch` adds Nokia's `wait_for_gesture` (mce writes 4
  when the display goes off): touch reports off, T24 on, 50 ms scans, the gesture as
  `EV_MSC/MSC_GESTURE`, after which the T9/T24/T7 bytes are restored (Nokia reset the chip, which
  here would bring back its NVM configuration). Also `disable_ts`, `calibrate`, and stock's input name
  "Atmel mXT Touchscreen", which mce and udev (`/dev/input/ts`) match. mce reaches it through
  `/sys/class/i2c-adapter/i2c-2/2-004b`, which 6.x dropped (`i2c-adapter-class.patch`). Tested: the
  double tap wakes the phone to the lock screen, as stock.
- `evdev-noop-llseek.patch`: mce seeks input devices after each event it handles; 6.18 refused
  (435 "Illegal seek" errors in minutes) where 2.6.32 accepted. A `.llseek` alone wasn't enough
  (boot 26: `lseek` on `/dev/input/event*` still `ESPIPE`, 10 errors after a few touches):
  `evdev_open()` calls `stream_open()`, which clears `FMODE_LSEEK`, and `vfs_llseek()` refuses before
  reaching `.llseek`. The patch sets `FMODE_LSEEK` again after it (reads still ignore the position,
  `FMODE_STREAM`).
- The notification LED (2026-10-01): LP5521 at I2C2 0x32 in `omap3-n9-nokia.dtsi` (enable GPIO 41,
  32 kHz external clock, 5 mA), `lp5521:channel0` as stock, LED class built in. Configured as stock's
  driver did (`leds-lp5521-cp-off.patch`: Nokia's `lp5521_configure()` writes `PWRSAVE_EN |
  CP_MODE_OFF | R_TO_BATT`; CONFIG reads 0x64 here, with 558 Hz PWM). Tested (boot 26, me
  watching): mce's `PatternCommunication` (`[LEDPatternNJoyRM696]`, engine 1: two pulses, then
  2 s) blinks the front LED. Direct `brightness` writes don't light it once mce has stopped a
  pattern: the driver leaves engine 1 "disabled" (OP_MODE 0x0f), not in direct mode. A dim white
  glow stays between the pulses: not this chip (it stays with the LP5521 unpowered, GPIO 41 low, the
  TWL's LED outputs off, proximity off, the panel off and USB unplugged, and is on from boot); likely
  NOLO's (the kernel is loaded over USB, not flashed). Left for last (user, 2026-10-01).
- A dim red light at the camera flash (back), not there on stock (user). Suspect: the AS3645A flash
  controller (I2C2 0x30, a red indicator output, `indicator@1` in mainline's `omap3-n950-n9.dtsi`),
  which stock's camera driver resets at boot and nothing drove here. But its registers read idle on
  boot 26 (CONTROL 0x80: external-torch mode, torch, strobe and output off; INDICATOR 0x01; FAULT
  0x08, two LEDs). With `LEDS_AS3645A=y` (boot 27: it probes, "NSC" variant, and sets indicator
  mode with the output off) the light stays: something else (a GPIO or PMIC output NOLO leaves
  on?). Left for last with the LEDs (user, 2026-10-01).
- Done since (2026-10-06, rm696 9ad462fb4): the keypad disable path
  (`i2c-1/1-004a/twl4030_keypad/disable_kp`) and `/sys/devices/omapdss/display0/hw_revision` ("Small
  interfaces Harmattan reads").

Frame pacing ("Project Butter"). The vsync path: X page-flips between fb0's three buffers, each flip
is a panel update at TE (`omapfb-panel-split-update.patch`), and the client's swap completes on
Nokia's DSS notifier, so drawing is clocked by the panel. Measured with `ramboot/butter.sh`
(injected flicks and page swipes on the home screen, the panel's `update_stats`):
- About 1 frame in 10 was shown twice during animations.
- Not the CPU: it ran at 1 GHz most of each test, and stock's 600 MHz floor (stock's ondemand sat at
  600 MHz, its PM optimizer's eMMC rule) changed nothing. Not deep idle: CORE retention (C5+) was
  never entered with or without stock's display-on 6 ms idle limit (kept, as stock, in
  `idle_latency_us`). Tested with USB connected.
- An update ready just after TE waited a whole frame. In reverse mode TE is mid-scan and a first
  half takes 6 of the 8.3 ms the scan spends in the other half, so it can still start up to about 2 ms
  late (`split_late_us`, default 2000, bounded by the longest first half seen). Frames shown twice:
  28 to 18, 22 to 8, 36 to 14 (flick, page, flick); on time 91-93%.
- The rest: requests 2-15 ms after TE, frames that took longer than a refresh to draw; the 3- and
  4-period gaps are mostly the slow end of kinetic scrolls. Most requests (85%) come with the next
  frame already queued.

## Smoothness, SmartReflex, erratum 1.85, storage (2026-10-03 afternoon, boots 80-85; SR on 2026-10-04)

Frame pacing again (`ramboot/butter.sh`, boot 82). Two fixes in `../linux_mainline_rm696`:
- The late start of a split frame's first half was off for the whole boot after one slow half (it
  compared with the longest half since boot, 8.2 ms once, normally 6.1): frames shown twice had gone
  from 1 in 10 to 1 in 3. The longest half now fades (commit "let the longest split half fade"):
  on time 91-94% again.
- X flips fb0's three buffers; a split frame used to be latched only at its first half (at TE), so a
  pan to the next buffer made before TE replaced the frame unseen (about 1 frame in 6-7 of an
  animation; `update_stats` couldn't see it) and X's next update slept in the DSI bus lock (about 1 s
  per test, X's main loop stalled). Stock latched it when it was asked for (`omap_dss_lock_cache`);
  now so do we (commit "latch a split update's frame when it's asked for", sysfs `region_latch`,
  `update_stats` "early pans" and "blocked"): 0 blocked, 0 replaced.
- GPU boost (`sysutils.c` in `pvr_sgx_rm696`, `/sys/module/pvrsrvkm/parameters/cpu_min_khz`, default 800000): a CPU
  floor while the SGX is busy. Stock had none (its `sgx_lock_perf` only asked for L3 OPP100, which
  pvr already holds); kept on at my wish. No measurable effect on swipes, where input boost
  and ondemand already run the CPU at 1 GHz.

DM3730 erratum 1.85 (SPRZ319F): DPLL3 kept locked (workaround 1; mainline had it in automatic mode,
harmless only while CORE never reaches retention). `CM_AUTOIDLE_PLL` 0x08 on boot 80. Stock used
workaround 2 (automatic mode around CORE retention only, at L3 OPP50 / VDD2 OPP100): worth doing once
CORE reaches retention.

L3 lowering delay (item 2), settled standby, 5 min each: 1000 ms OPP50 39% / 39 switches a minute,
500 ms 61% / 43, 250 ms 66% / 49, 100 ms 77% / 53, 0 ms 79% / 60: 100 ms is the default now.

SmartReflex (branch `sr` in `../kernel_sr`, boot 85): 3630 VP limits (VP2's were 3430's, VDDMAX 1.15 V
below our 1.2 V OPP100), SR stopped around every voltage change, erratum 1.46's ramp delay from the
real voltage, no SR at voltages without an eFuse nTarget. eFuse nTargets all present. With C3+ off and
the frequency pinned, 45 s of md5sum loops each, 0 errors:

| | nominal | with SR |
|---|---|---|
| VDD1 600 MHz | 1.200 V | 0.975 V |
| VDD1 800 MHz | 1.325 V | 1.0875 V |
| VDD1 1 GHz | 1.375 V | 1.1625 V |
| VDD2 L3 OPP100 | 1.200 V | 0.950 V |

On by default since 2026-10-04 (rm696, boots 108-109): SR pauses around MPU/CORE retention (as we
then thought stock did: it didn't, stock ran class 1.5, see "SmartReflex class 1.5"), and Harmattan's pmconfig turns it on for both VDDs through stock's `/sys/power/sr_vdd*_autocomp`.
Boot 108 showed VDD2's SR armed but idle (VP2 never enabled) for as long as L3 didn't change: class 3
starts only at a voltage the voltage layer knows, and it learned VDD2's only at the first L3 change,
which USB's hold postpones for the whole boot; the L3 policy now sets VDD2 to OPP100's voltage when it
starts (boot 109: VP2 on at 13 s, 0.95 V). With SR on and idle states on (`build/sr-6b5257b-check.txt`):
VDD1 0.875/0.975/1.0875/1.175 V at 300/600/800/1000 MHz under load, VDD2 0.95 V at L3 OPP100 and
0.8375 V at OPP50, md5sum loops and the DSP decodes clean. `tests/srtest.sh` is the bring-up test
(it switches SR off at its end).

Storage: the eMMC (Hynix, 15 GB) runs 4-bit at 48 MHz, as on stock: MMC2's DAT4-7 balls are MMC3's
data lines for WLAN (stock's `.wires = 8` couldn't be used either). Sequential direct reads 9.5-16 MB/s,
random 4 KiB 1.7 MB/s (about 425 reads a second). Cold-reading Harmattan's 1658 libraries (32 MB):
14.1-14.6 s with any scheduler (mq-deadline, bfq, kyber, none), 13.9 s with 512 KiB readahead. The
eMMC's own latency is the limit; F2FS would need reformatting (my call, not now).

DSP: see "DSP bridge" below (working since boot 94).

## DSP bridge (2026-10-03 evening and night, boots 89-106)

Branch `dsp` (worktree `../kernel_dsp`, c82b47bf5, 26 commits; fast-forwarded into `rm696` the same night): staging tidspbridge from Linux
3.16 ported as `bridgedriver.ko` (same ioctl ABI as Nokia's for Harmattan's gst-dsp, Nokia's
`ti_bridge` policy sysfs), a 6 MiB DT carveout (`dsp_pool` at 0xbfa00000), the mailbox, the IVA2 MMU
and WDT3 interrupts. Loaded by hand on these test boots (`chroot /newroot modprobe bridgedriver`);
since 2026-10-04 group-hal loads it at boot as stock (harmattan.patch no longer disables its
modprobe). Never `rmmod` it (the IVA2 keeps running: L3
error, panic).

What it took, each found by comparing with stock (Nokia's kernel-plus-harmattan 2.6.32 sources, and
measurements on stock with the same commands), in the order found:
1. **The DSP hung right after boot** (boots 89-90): it sent two messages (0x101, then 0x2010 "gate my
   tick timer GPT5"), then serviced no interrupt (GPT6 overflow pending, never acked) and its
   watchdog (WDT3, 5 s) reset it forever. Found by disassembling the base image (GNU binutils for
   C6x, `tests/dsp/`): DSP/BIOS's BPWR transport busy-waits after a clock-off request until the
   timer's bits in CM_FCLKEN_PER **and CM_ICLKEN_PER** read 0, and hwmod's `_setup_iclk_autoidle()`
   enables every interface clock that isn't OCPIF_SWSUP_IDLE for good. Fix: `cc0a19929` (GPT5-8
   interfaces software-supervised; stock had no timer hwmods).
2. **The phone froze hard on the first decode after the DSP hibernated** (5 idle seconds, msg
   0x200a; IVA2 OFF): the MPU stalled on its first access to the powered-down IVA2 and the TWL4030
   PMIC watchdog power-cycled the board (RAM lost: pstore is empty after such hangs; stream
   `cat /dev/kmsg` and trace_pipe to the Mac instead). Stock gated the IVA2 clock at hibernation and
   enabled it first on wake (its 2.6.32 clockdomain code then woke the domain and waited for it).
   Fix: `1e400d5be` (force the IVA2 domain on and wait); and `853fa8e79`: the warm boot address
   (PWRM's restore code by physical address, DSP 0x204a2000 -> 0xbfea2000), as stock's
   `set_warmboot_addr()`.
3. **IVA2 clock**: Nokia's kernel (CONFIG_BRIDGE_DVFS on in its bridgedriver.ko) ran the IVA2 at the
   VDD1 OPP's rate, programming DPLL1 and DPLL2 together (`resource34xx.c program_opp_freq()`), told
   the DSP its OPP after every CPU frequency change and served the DSP's own requests (0x200b) as a
   minimum VDD1 OPP. The port left it at the boot loader's 250 MHz. `eaaeff7fe`: the IVA2 follows
   cpufreq (300/600/800/1000 MHz CPU -> 260/520/660/800 MHz IVA2, slowed before the voltage drops,
   sped up once it rose), POSTNOTIFY to the DSP, DSP requests as a CPU frequency floor.
4. **H.264 decoded no frame in most runs** (MPEG-4 fine): the stock reference (same pipeline on
   stock, `tests/dsp/stock-dsp.sh`) decoded every time, with the same ioctl sequence. The ioctl logger
   showed the DSP answering every buffer, yet gst-dsp pushed no frame (each frame's parameter block
   held a status word 0x401, not compared with stock); reading the first input
   buffer (the stream's SPS/PPS, 0x21 bytes) through a non-cacheable /dev/mem view at hand-off showed
   DRAM still holding old heap bytes. gst-dsp never flushes its data buffers (on stock either:
   identical flush/invalidate calls); 2.6.32's `get_user_pages()` called `flush_dcache_page()` per
   page, which cleaned and invalidated it; on 6.18 ARM's `flush_dcache_folio()` returns early on VIPT
   non-aliasing caches. Fix: `9d4a0692c` (write each page back as it is mapped). 6 of 6 H.264 runs
   then decoded all 396 frames.
5. **Speed** (`tests/ioctl-log.c` with `IOCTL_LOG=sum`, then kprobes inside the kernel): our flush and
   invalidate took 160-620 us against stock's 6-11 us, mostly waiting for `proc_lock`, which every
   map holds for milliseconds; stock flushed the user range immediately under `mmap_sem` only:
   `d928d5575`. Maps took one `get_user_pages()` per page (25 us each, 0.6 s of a 1.3 s decode):
   `c82b47bf5`, one call per map.

Dropped on the way (wrong theory, no stock counterpart): setting GPT5-8 SYSCONFIG/TWER as dmtimer
did; two commit messages were corrected after the real cause was found (`dsp-before-cleanup` keeps
the old history).

Results, Nokia's own clips, `uridecodebin ! video/x-raw-yuv ! identity name=out ! fakesink
sync=false`, CPU at 1 GHz / IVA2 at 800 MHz on both:

| clip | stock 2.6.32 | dsp branch | + `perf-v7` kernel config, same cgroup as stock |
|---|---|---|---|
| H.264 Main 854x480, 396 frames (user guide) | 12.59-12.69 s | 12.68-13.07 s | 12.64-12.88 s |
| MPEG-4 SP 854x480, 100 frames (MProgressIndicator) | 0.85-0.90 s | 1.06-1.20 s | 0.96-1.05 s |

Per call (MPEG-4, average): map 1.1 ms on stock vs 3.1 ms here (each frame buffer is fresh memory:
~25000 page faults per 100-frame decode on both; ours costs more per page: fault, two-pass DMA write
back, PTE); put message 56 vs ~300 us; flush/invalidate 6-10 vs 27-35 us. Data in `build/stock-*.txt`,
`build/ours-*.txt`, `build/kbench-*.txt`, `build/perf-v7-system.txt`.

Open then (2026-10-03): (a) the MPEG-4 gap above and the kernel's process switch cost (next section);
(b) recovery after a DSP MMU fault; (c) the IVA_SS in-band error at start; (d) a 720p H.264 MMU fault;
(e) group-hal loading it, playback, the encoders. All closed since: see "DSP open points closed"
below.

### DSP open points closed (2026-10-05 evening, boots 157-158)

rm696 7546a2e33 (`build/zImage-n9-7546a2e`). The same script on stock and ours, as user, under each
kernel's ondemand (`tests/dsp/dspref.sh`; `build/dspref-stock.txt`, `build/dspref-7546a2e.txt`); the
720p clips are 3 s of ffmpeg's testsrc2 (the script's header has the commands). Harmattan has no
videotestsrc, so the encoders get the DSP decoder's frames:

| | stock 2.6.32 | rm696 7546a2e |
|---|---|---|
| decode 720p H.264 Baseline, 90 frames | 2.13 s | 2.03 s |
| decode 720p H.264 Main, 90 frames | 9.04 s | 8.89 s |
| decode SD MPEG-4 (MainAnimation, an AVI), 100 frames | 0.92 s | 0.88 s |
| 720p decode + MPEG-4 encode (the camera's format, `dsphdmp4venc`) | 4.62 s | 4.43 s |
| 720p decode + H.264 encode (`dsphdh264enc`) | 5.01 s | 4.88 s |
| 720p decode + JPEG encode (`dspjpegenc`) | 3.25 s | 3.23 s |
| SD decode + H.264 encode (`dsph264enc`, video calls) | 4.30 s | 4.24 s |

- IVA_SS in-band error: fixed (Layout, commit "clock WDT3 before the DSP starts"). Before, 50 of 59
  starts in the saved logs since boot 94 logged it; after, 0 in 18: two boots' starts, 10 back-to-back
  restarts (`build/dsprestart 10`) and the 6 recovery reloads below.
- 720p MMU fault: not reproducible. 720p H.264 Baseline, Main, Main with B-frames and 4 references,
  and MPEG-4 SP 720p all decode to the end into fakesink, with exact-size UYVY frame buffers (0x1c2000,
  as on stock). The clip of the old report is unknown (boot 94's `avidemux` trace was the SD clip).
- Recovery: works for a single crash with time to settle; not after several, nor for a decode 3 s
  after the reload (boots 159-160, "SmartReflex class 1.5, the mailbox after a DSP crash"). Fixed since
  (boot 164, 10 crashes in a row, every decode after them normal): "DSP crash recovery". Two real DSP MMU faults (`IOCTL_UNMAP=N` in `tests/ioctl-log.c` unmaps one of
  gst-dsp's frame buffers right after it's mapped) and four WDT3 overflows (the DSP MMU's table walk
  switched off mid-decode through /dev/mem, after checking PM_PWSTST_IVA2 reads ON: the DSP stalls on
  the TLB miss) each reloaded the DSP within 0.5 s, and the next decode ran normally (90/90 frames,
  2.01-2.11 s). Killing a player mid-decode (4 times) caused no fault at all.
- Seen once, not again in 5 more recoveries: for ~25 s after the first recovery of boot 158 the
  mailbox queue to the DSP filled ("Try increasing MBOX_TX_QUEUE_LEN", `mbox_send_message` -105, 9
  times), then cleared by itself; the next decode was normal. Not traced (`build/dsp-trace-158.txt` has
  the later, clean ones; the SR messages below pushed the burst out of the saved log). Two differences
  from stock made since: "SmartReflex class 1.5, the mailbox after a DSP crash".
- Cosmetic, as Nokia's stop path: stopping a hibernated DSP logs "ERR: clock id 2/0 already disabled"
  (its GPT6 and IVA2 clocks were gated at hibernation; the bridge's own bookkeeping catches it).
- Not the DSP, found on the way: SmartReflex "sr_v2_disable: Smartreflex disable timedout" (SR1,
  480c9000; SR2 on boot 153), thousands per boot since boot 116 (10597 by 755 s on boot 158, from 291
  s), with or without DSP use. Each is a 200 us busy-wait. Cause and the stock way: "SmartReflex
  class 1.5, the mailbox after a DSP crash".

## SmartReflex class 1.5, the mailbox after a DSP crash (2026-10-05 night; rm696 9355f8a80, boot 160)

Branch `sr1p5` in `../linux_mainline_rm696` (rm696 7546a2e33 + 5 commits, `build/zImage-n9-9355f8a`;
fast-forwarded into rm696 after the tests), booted as boot 160 (boot 159: rm696 7546a2e33, the same tests first). Tests: `tests/sr1p5test.sh`,
`tests/dsp/recovery.sh`, `tests/busy.sh`, `tests/idlestates.sh` (with `ramboot/lock.sh`).

Results (boot 160 against boot 159, `build/*-9355f8a.txt`, `build/*-7546a2e.txt`):
- Calibrated (debugfs `sr_calib`), each OPP the voltage class 3 settled at on boot 159: VDD1 875 /
  975 / 1087.5 / 1162.5 mV at 300 / 600 / 800 / 1000 MHz, VDD2 837.5 / 950 mV at L3 OPP50 / OPP100.
  The first two (1 GHz and OPP100) were calibrated as soon as pmconfig turned autocomp on; the rest
  the first time each OPP ran. md5sum loops at every OPP clean (56-152 per OPP, 0 wrong).
- SR disable timeouts: 0 (boot 159 also had none: it wasn't one of the flood boots).
- Idle, screen locked: busy 1.0-3.6% (boot 159 1.2-2.3%). The C-states can't be compared: on boot
  160 UART2 was active (its 555 us latency request: C3 at most, 97% of the time), on boot 159, after
  another session's Bluetooth tests, it wasn't (C5 92%).
- DSP crashes (`tests/dsp/recovery.sh`: an MMU fault, then decodes 3 s after the reload; a WDT3
  overflow, then a decode): boot 159 failed both rounds (next decodes "couldn't start node", the DSP
  faulting at 0x204f0080 ~5.8 s after the reload, later "In-band Error seen by IVA_SS" and
  DSP_SYSERROR 0x102); a decode 25 s after the reload or 3 s after a clean restart (`dsprestart`) ran.
  Boot 160 passed 3 of 3 rounds (6 recoveries, every next decode 90/90 frames, no failed sends). But the
  reference set right after them failed after its first decode ("couldn't start node", DSP MMU faults
  at 0x46821140, 0x404ba4c0, 0xfb47c268), and so did every decode after, after a clean restart too and
  with SR off (nominal voltages, so not class 1.5): the DSP stayed unusable until a reboot. So the
  DSP's recovery isn't robust on either kernel (the earlier "Recovery: works" held for a single crash
  with time to settle), and whether the mailbox changes help is not settled by one boot each. Cause found
  and fixed since (a failed node create left its library loaded across the reload): "DSP crash recovery".

SmartReflex. Stock never ran class 3. Nokia's board file registers class 1.5 (`board-rm696.c`,
`sr_class1p5_init()`; stock's kallsyms has both classes, only 1.5 registers): after a change to an OPP
without a calibrated voltage, SR and the VP run until the VP's voltage settles, that voltage becomes the
OPP's and SR stops; the OPP runs at it from then on, recalibrated after 24 h from 50 mV above. The idle
path's `omap_smartreflex_disable()` calls we had copied into class 3 (e7f916d32: SR stopped and
restarted at every C3+ entry, ~300 a second) do nothing there once an OPP is calibrated, and keep the
domain out of retention while it calibrates. The SR disable timeouts came from those stops: in the
saved logs they appear on 10 of the boots since 108, always one SR at a time, and once they start they
go on for the rest of the boot (~5 a second for SR2, 20-290 for SR1). Why the SR stops
acknowledging wasn't found (mainline's stop order, errgen first, differs from Nokia's); class 1.5 stops
SR only at the end of a calibration, about once per OPP per boot.

Nokia's class 1.5 sampled the VP's voltage on SR's MCUBOUNDS interrupt, but that interrupt never
reached the CPU: `sr_late_init()` did `disable_irq()` after `request_irq()`, and each calibration
disabled it once more than it enabled it. So stock's calibration always found "no samples" at its second
check (two 5 ms work periods, one jiffy each at HZ 128) and took the VP's voltage there. The port
(commits "ARM: OMAP2+: voltage: run an OPP at its calibrated voltage", "ARM: OMAP3: PM: don't stop
SmartReflex for every idle entry", "ARM: OMAP3: SmartReflex class 1.5, as Nokia's N9 kernel") reads the
VP's voltage at the same checks: settled when two in a row agree, else the highest after five (Nokia's
"oscillating" case). Debugfs `sr_calib` lists each OPP's nominal, next starting and calibrated voltage;
autocomp off drops the calibrations (as Nokia's). Class 3 measured VDD1 0.875/0.975/1.0875/1.175 V and
VDD2 0.95/0.8375 V on this chip; class 1.5 should calibrate close to those. Stock's own values for this
chip: `/sys/kernel/debug/pm_debug/sr_calib` on stock (root).

Mailbox. Two differences from stock that bear on a full queue to the DSP (what filled it on boot 158 is
not known: that log is lost):
- Nokia's `sm_interrupt_dsp()` sent nothing unless the board was stopped, running, in retention or
  hibernating (its `wake_dsp()` refused "unexpected state"); ours sent in any state but stopped, so after
  a crash (`BRD_ERROR`, until the recovery, which waits for every handle to close) anything sent waited
  behind the dead DSP's FIFO. Now refused as stock (commit "staging: tidspbridge: send nothing to a DSP
  that can't take it, as Nokia's"); a failed send names the message and the board state.
- Nokia's queue held 64 messages (a 256-byte kfifo, `CONFIG_OMAP_MBOX_KFIFO_SIZE`), the framework's 20,
  two per event (the wakeup ahead of each). Now 64 (commit "mailbox: a queue of 64 messages, as Nokia's
  OMAP mailbox").

## DSP crash recovery (2026-10-05 night; rm696 23a276efd, boots 163b-164)

The DSP that stayed broken after crashes (boot 160, `docs/dsp.md`) was a codec library
left loaded across a reload. Fixed as Nokia's bridge did (commit "staging: tidspbridge: unload a node's
library when its create fails, as Nokia's").

Reproduced on boot 163b (rm696 470c55a0a, fresh boot, kprobes on the bridge's crash, reload, node
and loader paths: `build/dsp-recovery-trace-163b.txt`). Six MMU-fault crashes, each followed 3 s later
by a decode, were all fine, and so was the Main profile clip after them (8.78 s). One WDT3 overflow
(`tests/dsp/recovery.sh`'s step) was enough: the next Baseline decode ran, the next Main decode failed
("couldn't start node", DSP MMU fault at 0x46821140, boot 160's address), and after that every decode
did (the Baseline one at 0xfffffff8).

The cause, from the trace and the code:
- The watchdog step switches the table walk off while the decoder's node is being created, so
  `disp_node_create()` times out (-ETIME) and the DSP is reloaded 4 s later. The node has no node
  environment then, so `node_delete()` skips it (state ALLOCATED: nothing to delete on the DSP), and
  `delete_node()` frees the node's loader object with a plain `kfree()`. Nothing unloads its library:
  h264bphddec, with its dependent libraries usn and ringio.
- The loaded libraries are `dbll_library_obj`s on the DBLL target's list. The target belongs to the code
  manager, created once when the bridge's device is created (`init_cod_mgr()`) and kept until the module
  unloads. A reload makes a new node manager, a new `nldr` and a new RMM (all DSP code memory free), but
  the target's list keeps the leaked libraries with `load_ref > 0`.
- After the reload, `dbll_load()` for those libraries loads nothing and resolves their symbols at the
  old addresses. The next Baseline decode allocated no DSP memory (no `rmm_alloc` in the trace) and ran
  on the old copy, still in the DSP's memory. The Main decoder isn't on the list: the new RMM placed it at
  0x20000000, over usn and ringio, and the DSP faulted when the create phase called into them. From then
  on everything using those libraries runs over other code; a clean restart (`dsprestart`) doesn't help,
  since it keeps the same target.
- Nokia's `node_create()` unloads the library when the create fails without a node environment
  (kernel-plus-harmattan `drivers/dsp/bridge/rmgr/node.c`, the block before "Phase II/Overlays"); TI's
  v3.16 driver we ported doesn't have it. A failed create leaks the same way without a crash, but stays
  harmless until the next reload.

Tested on boot 164 (rm696 23a276efd, `build/zImage-n9-23a276e`): the same WDT3 overflow, and the failed
create now unloads (`nldr_unload` right after the -ETIME); after the reload the decode loads its libraries
again; Baseline 2.08 s, Main 8.98 s, Baseline 2.05 s; DSP memory allocations and frees balance (47/47).
Then `tests/dsp/recovery.sh 5` (`build/recovery-23a276e.txt`): 5 MMU faults and 5 WDT3 overflows, each
reloaded, and all 15 decodes after them ran (90/90 frames, 2.01-2.16 s). The kernel log has only the 10
crashes, their reloads and the cosmetic "clock id 2 already disabled": no IVA_SS errors, no
DSP_SYSERROR, no failed mailbox sends. Right after, the whole reference set (`build/dspref-23a276e.txt`)
ran as on boot 158: 2.04 / 8.91 / 0.87 s for the decodes, 4.48 / 4.94 / 3.20 / 4.21 s for the encodes.

Checked and ruled out on the way:
- Stale message or channel control blocks in shared memory (`docs/dsp.md`): read
  through /dev/mem (SHM at 0xbfdf0000, the message controls at 0xbfdf8360/0xbfdf83f0) after a reload,
  before any decode. Both message buffers were empty with no message count; the bridge clears the
  channel header and the DSP's start resets the rest.
- The clocks carried across a reload (hypothesis 3): the dead DSP's `dsp_per_clks` (GPT6, id 2) is
  disabled twice (the "already disabled" message), and the new DSP asks for the same clock itself at
  start, so it starts with the clocks of a fresh one.
- A node manager kept when `node_delete_mgr()` fails (hypothesis 1): it fails only for a NULL manager.
- 0x204f0080 (boot 159's fault 5.78 s after a reload) is the first page of the DMM pool, where user
  buffers are mapped: the base image's `_EXT_END` is 0x204effff and the pool starts after it. It wasn't
  seen on boots 163b-164. Boot 159 ran rm696 7546a2e33, without the mailbox changes, and up to its test
  it had run another session's tests for 35 minutes. Whether a leaked library caused it is not known.

Seen on boot 164, not investigated: at 70-72 s two decodes failed with "dsp init failed", before any node
call reached the bridge, while Harmattan's boot animation (MProgressIndicator) was still decoding on the
DSP (it released it at 78 s). From 97 s on the same decode ran.

## Video playback (2026-10-04, boots 110-115)

How Harmattan plays a video (read from the PR1.3 rootfs, then measured on stock as user while the
player ran, `tests/video-playprof.sh`): the Videos app (`video-suite`, D-Bus
`com.nokia.maemo.meegotouch.VideoSuiteService` `play(as)`) hands the file to MAFW's renderer
(`qmafw-dbus-wrapper` with `libqmafw-gst-renderer-plugin.so`), gst-dsp decodes on the DSP, and Nokia's
X driver shows the frames through Xv on a DSS video plane: on stock, Nokia's own `Nokia Pure.mp4`
(H.264 854x480, 173 s) ran on VID2, 854x480 in and out, at 0,0, ~110 DSP mailbox and ~112 display
interrupts a second, the renderer's 11 threads at nice -11. Three things stood in the way here, each
fixed in `../linux_mainline_rm696` as stock did it:

1. **No memory for the video plane** (boot 110): X asks omapfb for its Xv buffers when a video
   starts, 1280x720 16 bpp x 6 = 11059200 bytes on fb1/fb2, what Nokia's board file reserved at boot
   (`board-rm696-video.c` `rm696_video_mem_init()`, "VID1/2 1280x720x16bpp, 6 buffers"). Mainline
   omapfb allocates from CMA at run time, and that failed every time: only two 1 MiB-aligned windows
   were big enough and both held one unmovable page (tracefs `page_isolation/test_pages_isolated`
   gave the PFN, `/proc/kpageflags` a mapped, dirty, unevictable shmem page, `tests/findpfn.pl` a SysV
   segment Xorg maps; pvr pins memory X wraps with `get_user_pages()`). The player got no plane and
   stopped. Fix: omapfb takes its memory from a carveout when the DSS node has a `memory-region`
   (commit "video memory from a DT carveout, as Nokia's VRAM"), 14 MiB on the N9 (stock's 13.05 MiB,
   rounded up so the Xv buffers also fit next to fb0 at `omap2fb.vram=0:3M`).
2. **The renderer at nice 0** (boot 111): MAFW stopped after 13-85 s with "A lot of buffers are being
   dropped" (frames too late at the sink). Per-thread CPU was close to stock's; the difference was
   priority. ohmd's cgroups plugin classifies processes as they start
   (`/usr/share/policy/etc/noswap/syspart.conf`: the renderer in group `mediasrc`, priority -11; Xorg
   and pulseaudio -8; the foreground app's group) and learns about them from the kernel's process
   events connector, which stock builds in; here `CONFIG_CONNECTOR` was a module (never shipped) and
   `CONFIG_PROC_EVENTS` off, so nothing was classified. Fix: both `=y` in rm696.config. Since then
   (boot 112) the renderer runs at -11, Xorg and pulseaudio at -8, apps in their groups, and our ssh
   session lands in `/system` like stock's (it was in `/system/applications/standby`: see
   `docs/performance.md`). Nokia Pure plays to its end.
3. **Scaled video black** (boot 112): Dolby's `Dolby Soundscapes.mp4` (H.264 864x486, E-AC-3) played
   with sound and a black screen: X scales it to 852x480 at 2,0, and omapdss refused ("failed to find
   scaling settings"): `check_horiz_timing_omap3()` wants horizontal blanking for the scaler, and the
   DSI command-mode panel has none (timings hfp/hsw/hbp 0; the DISPC runs in stall mode with FIFO
   handcheck). Nokia's DSS skipped those checks for manual-update displays ("Assume FIFO
   stall/handcheck saves the day"); so does ours now. And the split update cut only unscaled
   overlays, so a scaled one spanning both halves was left out of both: scaled overlays are now cut
   with their input columns in proportion, rounded to even as Nokia's `configure_overlay()` did (its
   comment: odd cuts repeat a column, "a vertical bar in the middle of the screen"). Boot 113: plays.

4. **Half-screen tearing** (boot 113, seen by me twice in Dolby's 155 s): the two halves of a
   frame a frame apart. New `update_stats` counters ("halves late") showed why: in reverse mode the
   second half goes out from a timer at 52% of the TE period once its window is written (a DCS write
   in a work item after the first half); when that came after the timer, nothing started it until
   the next frame's timer (21 in 158 s; a first half started late, up to 2 ms after TE, leaves the
   write ~0.6 ms). Now it goes out at once if it still ends before the next TE (commit "send a late
   second half in its own frame"): boot 115, 27 missed, 25 out late, 2 a frame late; no half past
   its window. `tests/video-play.sh` plays a clip and prints the counters.

Measured over 40 s of Nokia Pure, same script on both kernels (boot 111, before the connector fix;
`build/playprof-*.txt`):

| | stock | ours |
|---|---|---|
| CPU idle | ~53% | ~45% |
| renderer / pulseaudio / Xorg (1/100 s) | 1168 / 359 / 119 | 1311 / 406 / 141 |
| DSP mailbox interrupts a second | ~110 | ~280 |

Open: 2 second halves in 159 s still a frame late (their window write finished too late: measure
the work's latency before changing the late-start margins); the per-process CPU gap is the kernel
speed item (`docs/performance.md`); camera recording with the cameras (the DSP encoders themselves work:
"DSP open points closed"). Since closed: the mailbox interrupts (now as stock's) and the DSP points.
A cold-started video-suite drops its first `play` request, on stock too.

## Video: my clips (2026-10-06, boots 181-185)

My test clips (`~/Desktop/test-videos` on the Mac): one 24 s Pixel recording re-encoded as H.264
Baseline, Baseline "fast", Main and High, each 1080x720 (9:16 portrait, stored anamorphic: SAR 3:8)
and larger 1080x1080/1080x1920 versions (stress tests only, beyond the DSP's 720p: "the N9 is NOT good
at playing 1080p", me). HDR HLG, so colours aren't expected to be right. Acceptance: the 720 ones.

- DSP decode only (`tests/gst-test`, fakesink), 709 frames: Baseline 15.2 s, Baseline fast 14.4 s;
  Main and High ~10 fps (649 and 631 frames in 61.8 s). Stock decoded 720p Main at the same speed
  ("DSP open points closed"), and I found Main and High don't play on stock either.
- The Videos app showed black for the Baseline ones: X scales the 1080x720 picture to 270x480 at 292,0
  (stock's plane is the same: `vid2 in=1080,720 out=270,480 pos=292,0`), and omapdss refused every
  set-up ("failed to find scaling settings"). Stock's omapdss debugfs (readable as user) during
  playback: each split half cuts the plane to 560 and 520 input columns for 140 and 130 output
  columns, 5 taps (`VID_ATTRIBUTES` 0x006083f7, `FIR` 0x06001000), with the DISPC at lck 172.8 MHz /
  pck 43.2 MHz: 4x, fixed in Nokia's board file (`lck_div` 1, `pck_div` 4, the DISPC clock from DSS1,
  not the DSI PLL). Mainline's DSI command-mode calculation picked 147.84 / 49.28 MHz, 3x, and a 4x
  horizontal downscale needs a core clock of 4x the pixel clock (`calc_core_clk_five_taps()`).
- Tried first and dropped (branch `video-noclk`): no core clock check for manual-update displays, as
  Nokia's `calc_lclk()` returned 1 for them. The plane was programmed at 3x, the picture came out
  garbled, a frame never finished ("Framedone not received for 250ms") and the DSI link stayed wedged
  until a reset. With the check kept, a plane the clocks can't feed stays black instead.
- Fix: `CONFIG_FB_OMAP2_DSS_MIN_FCK_PER_PCK=4` (omapdss's own knob, "Video plane scaling requires
  higher FCK than normally"): 147.84 / 36.96 MHz; the DSI link unchanged (221.76 MHz DDR), the split
  halves still 6.0-6.1 ms. Boot 185 (`build/zImage-n9-d95c8f8`, with omapdss debugfs on top): both
  Baseline clips play to the end, me: "seems now fine", "yes it's ok now". Panel stats for
  Baseline fast: 636 frames at 2 TE periods, 66 at 1, 39 at 3, 2 at 4+; 4 second halves out a frame
  late. Dumps: `build/stock-dss-bl720.txt`, `build/ours-dss-idle-361e0e2.txt`.
- The Videos app keeps its resume position in `/home`, which the RAM overlay inherits from stock: a clip
  last stopped on stock resumes there.

Found on the way, open:
- USB mass storage writes failing on the test kernel: fixed since, "USB mass storage writes" below.
- **A panic** (boot 181, 1806 s, rm696 ea07646, `build/ramboot-console-181.txt`): `rcu_core` called a
  NULL callback. RCU's own check (`debug_rcu_head_callback()`) dumped the `rcu_head` first: offset 2012
  of a 2240-byte `task_struct`, which is `task_struct.rcu` in this build (offsetof compiled against the
  build tree: `rcu` 2012, `rcu_users` 2020): a task's `delayed_put_task_struct` callback whose `func` had
  become 0, as when the struct is freed and reused by a fork (which copies the parent's 0) while the
  callback waits, or overwritten. No `refcount_t` warning anywhere before it (so not an underflow of
  `usage`/`rcu_users`), and nothing in our ported code (bridge, Aegis, pvr, secure driver) keeps or
  frees task pointers. That boot had done the stalled mass storage export (4 min of bulk resets, then
  `rmmod g_file_storage` after an unplug, 1147 s), a video with the plane refused (1420 s) and DSP decodes
  of which two ended mid-stream by gst-test's timeout (until ~1760 s); seen once in ~186 test boots.
  Replayed on a debug build (branch `panic-debug` 3bf0532c6: `slub_debug=FZPU,task_struct`,
  `DEBUG_OBJECTS_RCU_HEAD`/`_FREE`, which report a freed `task_struct` written to and a free of memory
  holding a queued `rcu_head`, with stacks; boot 187): the gadget loaded and unloaded, then 5 rounds of a
  Main-profile decode ended by the timeout plus one killed mid-decode, with tasks exiting all along
  (`tests/panic-replay.sh`): no report, no panic. Then boot 188 on the same build with the musb fix
  reverted (branch `panic-debug2` 110c62821): 5 minutes of the stalled-write resets on a RAM LUN, the
  cable pulled mid-copy and the gadget unloaded, as on boot 181: no report, no panic
  (`build/ramboot-console-188.txt`). Parked by me until it shows again. Seen on that boot only: after the replug USB networking stayed dead (usb_moded's
  `ifdown`/`ifup usb0` at the replug, no ARP answer for 10 min), on the reverted musb code.
- Stock's USB stuck twice after a mode change (nothing enumerated until a reboot of stock); I
  want it looked at.

## USB mass storage writes (2026-10-06, boots 181-186)

MyDocs exported read-write (`ramboot/mydocs-rw.sh`, at my request, to copy the test clips) took
the Mac's writes at 0 MB/s: a command block (CBW) completed with 0 bytes (`bulk_out_complete --> 0,
0/31`, "invalid CBW: len 0"), f_mass_storage stalled bulk-in, the write's data was read as command
blocks, and the Mac reset the device every 30 s. Reads had worked (boot 39); stock wrote 22 MB in a
few seconds over the same cable and port.

Traced on a RAM-backed LUN (`tests/msc-ramdisk.sh`, musb's tracepoints; boot 185, rm696 + omapdss
debugfs, `build/msc-trace-ramdisk.txt`): a 7 MB copy went through (md5 equal) after 2 such losses,
from which the Mac recovered by a bulk reset; on the eMMC it never did. Both lost command blocks
arrived 5 and 7 us after their request was queued: the RX interrupt found `RXCSR` 0x0003 (a packet
ready) and `RXCOUNT` 0. The other 867 command blocks, from 6 us on, came whole. Queueing an OUT
request runs `musb_ep_restart()`, which since mainline 3fc137386c46 writes `FLUSHFIFO` to `RXCSR`
(twice) when no packet is waiting; a packet that arrives during those writes is emptied and reported
with length 0. Our 2026-10-02 change (`usb-musb-rx-early-packet.patch`, 38d783f94) reads a packet that
is already waiting from a work, but had kept the flush for the empty FIFO.

Fix (commit "usb: musb: gadget: don't flush the RX FIFO when queueing a request", rm696
4a06d32ac since 2026-10-06, `build/zImage-n9-4a06d32`, boot 186): with no packet waiting, the FIFO is left alone and the
RX interrupt reads the next packet into the request, as before 3fc137386c46 and as Nokia's 2.6.32
(`rxstate()` only). Tested: a 43.7 MB copy to the RAM LUN, 4 files md5-equal, 0 lost command blocks
(the trace covered the first 12.4 MB, the kernel log all of it), no resets; then MyDocs itself (me: "yes, then delete them"): 43.7 MB copied and synced in 4 s, read back md5-equal after an
unmount and mount on the Mac, deleted again; no resets, 0 "invalid CBW", `fsck.vfat -n` clean, the
720 clips already there unchanged. macOS's eject sends no SCSI eject to the gadget (the LUN stays
open): the scripts end on unplug or after their time.

## Cameras (ported 2026-10-06, rm696 fe27ef0a9, boots 191-225: both cameras, viewfinder, stills, 720p video)

The goal: Harmattan's own camera stack unchanged (camera-ui, libqcamera, camerabin2, gstreamer's
subdevsrc2 with libgstcamera2, the 3A library libomap3camd; FCam is on the rootfs, unused). Branch
`camera` in `../linux_mainline_rm696` (worktree `../kernel_camera`): 15 commits on rm696 4a06d32ac,
6a190206b, merged into rm696 (fast-forward, 2026-10-06), plus the PVR fix in `osfunc.c` (pvr_sgx_rm696, below). Status (boot 223, image `build/zImage-n9-e85a924`
= camera + SLUB debugging): camera-ui and a Qt camera app show a live, exposed viewfinder at 30 fps from
both cameras, switch between them, and camera-ui records 720p video (MPEG-4 + AAC, plays on the Mac).
The stills and the recording speed were fixed afterwards on branch `dsp-camera`, also merged into rm696
(fe27ef0a9): the subsection "Cameras: the DSP stage and the stills" below. Me, 2026-10-06:
"consider camera as ported" (the flash firing wasn't checked on the phone).

What stock does (Nokia's kernel-plus-harmattan, its camera files identical at db0828b and at its
HEAD; the PR1.3 rootfs's `omap3-isp.ko`, `smiapp.ko`, `smiapp-power.ko`, `ad58xx.ko`, `as3645a.ko`,
which Harmattan's `xsession/extra-modules` job loads; `board-rm696-camera.c`):
- Main module: Nokia's own smiapp driver (Vimarsh Zutshi's, not mainline's smiapp/ccs). It powers
  up at I2C2 0x10 and the driver moves it to 0x37 (again after the firmware's power-on soft reset).
  CSI2A on CSIPHY2: clock lane 2, data lanes 1 and 3, all inverted, CRC; XCLKA 9.6 MHz. The modules:
  `smiapp-003` (Fujinon, Sony imx125, sensor 0b-0125) or `smiapp-004` (Toshiba jt8ew9, 0c-560f);
  `smiapp-001`/`-002` were prototypes. Analog gain limits from the board for the Toshiba ones.
- Its modes are register lists from Nokia's firmware, `/lib/firmware/smiapp-sensor-<manu>-<model>-
  <rev>.bin` (`tests/camera/smiafw.py` dumps them): 3280x2464, 3568x2016, 2728x2048, 3144x1772,
  1632x1232, 1776x1008, 816x608, raw10 or DPCM8, at 796.8, 840, 768 or 1996.8 Mbit/s over the two
  lanes (D-PHY clock up to 499.2 MHz, the link frequencies mainline's N9 DT already listed).
  libomap3camd's tuning (`/etc/omapcam/C0010.enc`, `C0011.enc`) is calibrated against these modes.
- Lens: ad58xx at 0x0e (AD5836 or AD5817; BU8051GWZ on ROHM modules), on the main module's VANA and
  XCLKA; for the Toshiba module the AD5817's internal clock and its protection modes.
- Flash: AS3645A at 0x30 as a V4L2 subdev, strobed by the sensor (flash 200-320 mA, torch 20-60 mA,
  timeout 100-150 ms); a status event.
- Front module: smiapp at 0x10, MIPI CSI-1 (`ccp2_mode` 0, data/clock) on CSIPHY1 (clock lane 1,
  data lane 2), XCLKB 10.8 MHz, XSHUTDOWN on GPIO 97 (held low at boot), mounted 180 degrees; firmware
  `smia-sensor-01-022e-*.bin` (vw6558) or `0c-2134` (tcm8500md).
- VANA is VAUX3 (2.8 V) for all three modules, kept off 10 ms between users (`smiapp-power`). Both
  sensors answer at 0x10 until the main one is moved, so the board file never lets XCLKA's users
  (main sensor, lens) and XCLKB's (front) be on together (-EBUSY).
- The ISP: Nokia's 2011 omap3isp, mainline's ancestor (same entity names, pads, default links,
  statistics path). The D-PHY timing from the mode's output clock, the pixel clock from the mode,
  both through board callbacks; L3 held at 740000 KiB/s while streaming.

What Harmattan's userspace needs from the kernel (its call sites disassembled; Nokia's headers
compared with 6.18's uapi by `tests/camera/camabi.py`):
- The V4L2 ioctls at 6.18's numbers and sizes, the ISP's private ones (193-199) included, and the
  same media bus codes and flash controls. The exceptions:
  - the media controller: Nokia's pre-merge ioctls, `_IOWR('M', 1..4)` with 6.18's structs;
  - libgstcamera2 enumerates entities by id 1, 2, 3... without `MEDIA_ENT_ID_FLAG_NEXT` and uses
    id - 1 as a list index; 6.18's ids are sparse (one counter with pads and links);
  - `VIDIOC_DQEVENT` 0x80785659: Nokia's 120-byte `v4l2_event`, payload at offset 4 (6.18's time32
    one: 128, at 8); libomap3camd reads the type, payload, sequence and timestamp;
  - the CCDC's private `V4L2_EVENT_OMAP3ISP_HS_VS` (0x08000104) per frame, which mainline replaced
    with `V4L2_EVENT_FRAME_SYNC`;
  - uninitialised fields 6.18 checks: `which` in ENUM_MBUS_CODE/ENUM_FRAME_SIZE, the pad of the
    sensor's S_FRAME_INTERVAL;
  - the viewfinder queues omapxvsink's buffers, omapfb VRAM mapped from `/dev/fb`, as USERPTR to
    the resizer output; vb2 refuses PFN mappings since 5.19.
- Names: camd matches the sensor exactly (`smiapp-003` → C0011, `smiapp-004` → C0010, front
  `tcm8500md` → C0005-180), the lens and flash by prefix (`ad5817 2-000e`, `bu8051gwz`,
  `as3645a 2-0030`), and the entity types 0x10001 / 0x20000 by mask.
- Sensor controls: Nokia's `V4L2_CID_MODE_*` (0x9b0901-0x9b0908, class 0x9b0000, mainline's FM_TX
  numbers: harmless on the sensor's own handler), EXPOSURE (us), GAIN, flips; lens FOCUS_ABSOLUTE
  and its private ones; the flash's standard ones; the preview's brightness and contrast.
- sysfs: `/sys/devices/platform/i2c_omap.2/i2c-2/2-0037/{nvm,ident}` (camd, FCam; `ident` = name and
  three hex fields).

The branch (`git log rm696..camera` in `../linux_mainline_rm696`):
| Commit | What |
|---|---|
| 814959c57 media: mc: Harmattan's media ioctls | the 'M' ioctls; entity ids by position in registration order (1..N), pad flags sink/source only |
| b2effda7c media: v4l2-ioctl: Harmattan's struct v4l2_event | VIDIOC_DQEVENT in Nokia's layout, as the time32 variants |
| 9426ffc1a media: v4l2-subdev: Harmattan's uninitialised which and frame interval pad | invalid `which` in enumerations = TRY (as then); a single-pad subdev's frame interval on pad 0 |
| d2c81db51 media: videobuf2: Harmattan's user pointers | `get_vaddr_frames()` takes a VM_IO/VM_PFNMAP mapping's PFNs again and keeps them PFNs (VRAM has struct pages but no kernel mapping: mapped as a resource, no CPU cache maintenance); dma-contig takes 32-byte aligned user pointers (Nokia's ISP did; 64 refused every other gst buffer) |
| d8dbc76c7 media: omap3isp: Harmattan's interfaces | HS_VS event; D-PHY timing from the sensor's link frequency (8 MP DPCM8: THS_SETTLE 48 as stock, not 42); one IOMMU mapping per buffer; QUERYCAP per node; a second STREAMON -EBUSY; DQBUF with nothing queued -EINVAL; Nokia's gamma bits; statistics stamped with the wall clock; L3 held while streaming (`omap3_l3` holder "isp") |
| df99de755 i2c: omap: the controllers' 2.6.32 sysfs names | `/sys/devices/platform/i2c_omap.N` links |
| eea14b1ac media: i2c: Harmattan's N9 camera drivers | `drivers/media/i2c/nokia-camera`: Nokia's smiapp, ad58xx and as3645a on the 6.18 APIs; the board file's glue in `nokia-camera.h`; pixel rate (stock's per-line average) and link frequency for the ISP; lens and flash bound through the sensor (`lens-focus`, `flash-leds`); init at probe, the main module waiting for the front one's XSHUTDOWN |
| b152ccc33 ARM: dts: omap3-n9: the cameras as stock | both modules, lens, flash, both ISP ports |
| ea7919a99 ARM: rm696.config: the cameras | ISP and drivers built in, the AS3645A LED driver out (Nokia's V4L2 one still turns off NOLO's red indicator at probe) |
| 1b2c8963f media: omap3isp: histogram buffers for the DMA engine's device | mainline bug: the histogram's buffers were allocated for a NULL device, which the ARM DMA API dereferences (the first VIDIOC_OMAP3ISP_HIST_CFG oopsed, boot 191) |
| 062c59031 media: videobuf2-dma-contig: keep a PFN user pointer's offset in its page | mainline bug: a VM_PFNMAP user pointer was mapped from its page's start; Harmattan's are 32-byte aligned into VRAM, so each frame went up to a page early |
| 74d9d3a45 media: omap3isp: CSI2 video port at least as fast as the link | the receiver's video port divider came from the pixel rate, which Nokia's smiapp gives as the line average (56.7 Mpixel/s for 1776x1008, 79.7 within a line): port at L3/3, and the preview engine finished ~1 frame a second (7 of 523); now from the link rate as well, L3/2 as stock's board file: 3000 of 3000 frames at 30 fps (boot 209) |
| d2e537990 media: omap3isp: time32 statistics requests with the caller's buffer | mainline bug: the time32 VIDIOC_OMAP3ISP_STAT_REQ ran on a zeroed struct ("userspace's buffer size is not enough"): the 3A got no statistics, set no exposure, black viewfinder (boot 218) |
| f9ce98a51 media: omap3isp: several video nodes streaming in one pipeline | each STREAMON allocated and each STREAMOFF freed the pipeline's entity enumeration: a double free (heap corruption, oops in __kmalloc, boots 219/221 with SLUB debugging) when the camera source streams two nodes (switching cameras, stills); plus each STREAMOFF stopping the pipeline again |
| 6a190206b media: omap3isp: MIPI CSI-1 receiver as Nokia's driver set it | CCP2_CTRL.IO_OUT_SEL and no CRC for the CSI-1 front camera, as Nokia's driver and board files: the receiver saw nothing before (boot 222); front camera at 576x432 (boot 223) |

`kernel/build.sh` puts all of stock's `smiapp-sensor-*.bin`/`smia-sensor-*.bin` (150 KB) into the
initramfs: the drivers probe at boot, before Harmattan's root is mounted.

The GPU crash (boots 197-216: "In-band Error seen by SGX at address 0", omap_l3_smx's BUG, Xorg's
context, a fifth of a second into streaming) was ours in the driver's `osfunc.c` (pvr_sgx_rm696): gltexturesink puts the frames
in omapfb's VRAM (fb2, reserved above lowmem, so no struct page) and has EGL wrap them
(EGL_NOK_image_yuv_framebuffer); `OSAcquirePhysPageAddr()`'s fallback for such a VM_IO mapping took the
physical address from `vm_pgoff`, which 2.6.32's fb mmap set to the PFN and 6.18's `remap_pfn_range()`
leaves at the file offset (0) for shared mappings: the SGX read from physical 0. It now takes each page's
PFN from the page tables (`follow_pfnmap_start()`), boot 218 ("pvr: wrapping a PFN mapping from
0xbef44000"). Stock has no HIGHMEM either (`VMSPLIT_3G_OPT`); its VRAM was in lowmem.

What works (boots 218-223, `build/cam-223-*.png`, `build/cam-223-video.mp4`):
- At boot all four modules probe (main `smiapp-003`, Sony imx125; front `tcm8500md`; lens `bu8051gwz`;
  flash `as3645a`), nodes numbered as stock, `i2c_omap.2` sysfs as stock.
- Viewfinder: my Qt app (qt5-cameratest, QtMultimedia over camerabin2 and gltexturesink, GPU
  textures) and camera-ui, 30 fps with AEWB/AF/histogram statistics (~240 ISP interrupts a second),
  exposed and white balanced; front camera (mirrored, as a front camera); switching both ways.
- Video recording (camera-ui, video mode, HD): `DCIM/*.mp4`, MPEG-4 Simple Profile 1280x720 (DSP
  encoder) + AAC 48 kHz stereo, decodes fully (ffmpeg), plays on the Mac (me: "video and audio
  looks fine").
- Autofocus moves the lens (ad58xx), the flash driver is programmed for a still (as3645a).

How a still is taken (traced with kprobes, boot 223): viewfinder off; a short full-pipeline run; the raw
frame through CSI2a to memory ("CSI2a output"); then 3 memory-to-memory passes: the raw frame back
through the CCP2 receiver's memory input ("CCP2 input") to CCDC, preview (Nokia's 3A parameters) and
resizer, each pass its own STREAMON/STREAMOFF; then the YUV still goes to the DSP's JPEG encoder (the
bridge maps it: both apps, the Qt plugin included). Each ISP stage was checked on its own with
`ispcap` (`ISPCAP_RAW`, `ISPCAP_M2M`): the raw frame and one memory-to-memory pass are clean.

Open:
- (Fixed on `dsp-camera`, below: the DSP's address pool, the scaled DPCM8 modes.) Stills failed in the DSP stage. camera-ui: "DSP_MMUFAULT, addr=0x215de160", inside a region the bridge
  had mapped (user 0x9a07a000, ordinary memory, DSP 0x215d4000 + 0x2ec000) and not yet unmapped; the DSP
  is reloaded, camera-ui says something is wrong with the camera and restarts. The Qt app: a JPEG
  (816x608) with full-width colour streaks. The DSP port's area (`../kernel_dsp`); the ISP's output is
  clean.
- (Not a bug: the debug image's DMA-API debugging, below.) Recording ran at ~19 fps: frames come every 33 or 66 ms, and the viewfinder slows down as well while
  recording (backpressure from the encoder: the ISP drops the frames it has no buffer for). The IVA2 is at
  800 MHz and L3 at 195 MHz; the bridge maps and cache-cleans each frame buffer page by page.
- In a single stream, a memory-to-memory pipeline's second single-shot frame never comes: 6.18's
  `call_s_stream()` refuses to start a subdev it counts as started (a warning per module), and omap3isp
  restarts its modules with s_stream(SINGLESHOT) per frame. Harmattan's passes STREAMON/STREAMOFF each,
  so only `ispcap ISPCAP_M2M` with more than one frame hits it.
- The first camera start after boot can fail with "dsp open failed": the DSP bridge's policy (guest
  mode, one guest at a time) refused the app while camera-ui's prestarted instance was the guest. A test
  setup effect (apps started from ssh don't ask Harmattan's resource policy); a second start works.
- Twice (boots 207, 210) DSME exited ~21 s after it started (status 0, a requested shutdown), taking
  BME (battery shows 0) and mce with it; only on camera kernels (me: never in 200 boots before).
  Not seen again in 13 boots since; the ramboot now logs DSME at debug level (`harmattan.patch`
  dsme.conf `-l syslog -v 7`) and fatal signals (`ramboot/init`), to catch the reason next time.

Tools (`tests/camera/README.md`): `ispcap` (capture with Harmattan's ABI; front camera, raw, DPCM and
memory-to-memory modes; saves a frame), `uyvy2ppm.py`, `camtest.sh` (camera-debug's switches and
counters), `fbshot.py` (framebuffer screenshot), `camabi.py`, `ioctlscan.py`, `smiafw.py`;
`ramboot/tap.pl` (a touch tap). Debug branches (not for merging): `camera-debug` (ISP interrupt
counters, the CSI2 divider and autoidle bits as module parameters, a non-fatal L3 handler),
`camera-slub` (camera + SLUB and DMA API debugging).

### Cameras: the DSP stage and the stills (2026-10-06 evening, boots 223-225)

Branch `dsp-camera` in `../linux_mainline_rm696` (worktree `../kernel_dspcam`), 2 commits on `camera`
(= rm696 6a190206b), fe27ef0a9, merged into rm696 (fast-forward, 2026-10-06), image `build/zImage-n9-fe27ef0` (boot 225). Test-only branch
`dsp-camera-dbg` (bdc27af65: + a CCP2 DPCM predictor knob, boot 224; deletable). The three open points
of the camera port:

| Commit | What |
|---|---|
| 35585001c staging: tidspbridge: a 256 MiB DSP address pool for user buffers, as Nokia's | camera-ui's stills: the DMM pool (DSP addresses for mapped user buffers) was v3.16's 64 MiB with 15-bit page counts; Nokia's is 256 MiB with 31-bit counts |
| fe27ef0a9 media: i2c: nokia-camera: don't offer DPCM8 modes with sensor scaling | the Qt app's striped stills: the imx125's 2728x2048 and 3144x1772 DPCM8 modes are disabled when the firmware is imported |

1. **camera-ui stills: DSP MMU fault** (0x204f0800, 0x2237ad80, 0x204f0580 on boot 223). Traced with
   kprobes on `proc_reserve_memory`/`dmm_reserve_memory` (return), `proc_map` (+ return),
   `proc_un_map`, `remove_mapping_information`, `bridge_brd_mem_map`/`_un_map`, `hw_mmu_pte_set`/`_clear`
   and `mmu_fault_isr` (`build/dspcam-trace-still2-223.txt`): an 8 Mpixel still maps the viewfinder's
   buffers (5 MiB, 4 x 488 KiB), the JPEG node's 2.9 MiB and three 3248x2448 UYVY frames of 15.9 MiB. With
   two frames mapped the 64 MiB pool had 14 MiB free at its start and 9.3 MiB at its end:
   `dmm_reserve_memory()` returned -ENOMEM. gst-dsp doesn't check the reserve, maps the frame at DSP
   address 0 (-ENOENT, which logs the bogus "remove_mapping_information: failed to find given map info"),
   hands the encoder the frame anyway, and the DSP faulted milliseconds later on a parameter buffer gst-dsp
   had just unmapped (the fault address is whatever the confused node touches; the pool's first page twice).
   Nokia's bridge (kernel-plus-harmattan `plat-omap/include/dspbridge/dmm.h`, `pmgr/dmm.c`): 256 MiB and
   31-bit `struct map_page` counts (15 bits can't describe more than 128 MiB). Ported; the page tables grow
   to 262 L2 tables (262 KiB, as stock) in the 6 MiB carveout. Boots 224-225: 8 Mpixel (3248x2448),
   7 Mpixel (3552x2000) and lowest 4:3 (2048x1536) stills saved and clean, every reserve succeeded, no
   fault (`build/dspcam-224-*.jpg`, `build/dspcam-cui-225.jpg`).
   The unexplained 0x204f0080 fault (boot 159) is on the same first pool page;
   whether a failed reserve caused it then is not known.
2. **The Qt app's stills: colour streaks.** The encoder's input already had them: `tests/ioctl-log.c` with
   `IOCTL_DUMP=prefix` (new, writes each input buffer of 64 KiB+ at NODE_PUTMESSAGE as the CPU sees it)
   dumped the 816x608 UYVY frame, striped (`build/dspcam-qt-jpegin-223.png`); the DSP encodes it
   faithfully. `IOCTL_V4L2=1` (new: subdev/video S_FMT, STREAMON/OFF, media links) showed the still path:
   sensor 2728x2048 DPCM8 (816 is less than a quarter of 3280, beyond the resizer's 4x), CSI2a writes DPCM8
   to memory (bpl 2752), then the CCP2 memory input decompresses it (DPCM8 -> raw10) into CCDC, preview,
   resizer. The raw DPCM8 frame (`ispcap` with ISPCAP_RAW=1 ISPCAP_DPCM=1, a scratch change) decoded
   offline (`build/dspcam-tools/dpcm*.{c,py}`): even lines are fine, every odd line has a constant
   per-colour offset from x=0. In this mode (and 3144x1772: the two lists with the sensor's scaler on,
   0x0401=2) the sensor codes the first two pixels of each odd line as DPCM against the same pixels two
   lines up instead of PCM; checked against a frame of the same scene decompressed by CSI2a
   (ISPCAP_DPCM=2: CSI2 source raw10), which is clean: the implied predictor matches that pixel within the
   noise between the two frames. 3280x2464 and 3568x2016 start every line with PCM; camera-ui uses only
   those (its 8, 7 and lowest resolutions). CCP2's decompressor fails on the scaled modes with
   SRC_DPCM_PRED set (Nokia's driver, mainline) and cleared (boot 224, `dsp-camera-dbg`'s knob, LCM_CTRL
   read back 0x032200a0), so Nokia's stack most likely striped these modes too. Fix: such modes are
   disabled at firmware import ("2728x2048 DPCM8 mode with sensor scaling disabled" in dmesg); Harmattan
   then takes the sensor's 816x608 raw10 mode for this still: clean (boot 225, `build/dspcam-qt-225.jpg`).
   Front camera stills through the Qt app: clean (576x434, `build/dspcam-front-225.jpg`).
3. **Recording at ~19 fps** was the test image: `camera-slub` (e85a924, boot 223) has
   CONFIG_DMA_API_DEBUG and SLUB debugging. Per frame gst-dsp invalidates the MPEG-4 encoder's whole
   756 KiB output buffer, and the bridge's invalidate (`proc_memory_sync()`) does a
   `dma_map_page()`/`dma_unmap_page()` per page, each tracked by dma-debug: 30 ms a frame (16.6 of 28 s in
   that one call), so input frames went to the DSP every ~50 ms. A normal build (boots 224-225): 1.45 ms,
   720p MPEG-4 at 30.0 fps (every frame interval 33/34 ms, 487 and 533 intervals, `build/dspcam-rec-225.mp4`),
   no change needed. Measure camera speed on non-debug images only.

Tools: kprobe recipes above (tracefs needs mounting; `dmm_un_reserve_memory` can't be probed);
`tests/ioctl-log.c` IOCTL_DUMP/IOCTL_FLUSHIN/IOCTL_V4L2 (the DPCM decoders stay in
`build/dspcam-tools/`); camera-ui ignores LD_PRELOAD (Aegis credentials: secure exec): kprobes only.
Open: gst-dsp still doesn't check reserves (userspace); the scaled DPCM8 modes stay off (a sensor register
that restarts DPCM on every line in them would bring them back).

## Small interfaces Harmattan reads (2026-10-06 evening, rm696 9ad462fb4, boot 226)

Ported from Nokia's kernel (`../kernel-plus-harmattan`) on branch `small-ifaces`, 7 commits on rm696
fe27ef0a9, fast-forwarded into rm696 on my go (rm696 = 9ad462fb4; booted as
`build/zImage-n9-bfc11d8`, the same tree), each checked on the phone with `tests/small-ifaces.sh`:
- **The TWL4030 keypad and USB PHY where 2.6.32 had them** (twl-core): 2.6.32's twl4030-core put each
  child under the I2C client of its registers' slave, named after its driver, and mce opens two of
  them by those paths: `i2c-1/1-004a/twl4030_keypad/disable_kp` and `i2c-1/1-0048/twl4030_usb/vbus`.
  The keypad is now created under the 0x4a client before `of_platform_populate()`, the PHY named
  `twl4030_usb` by the auxdata table. mce now keeps `vbus` open (it watches it).
- **`disable_kp`** (twl4030_keypad), as Nokia's: 1 releases every key, masks the keypad's interrupts
  (`KEYP_IMR1` reads 0x0f) and disables its IRQ; 0 restores them (0x0a). mce writes it only when it
  leaves the user state (shutdown, reboot, charging while off), in soft-off and in malfunction state:
  with the display off and the lock on it leaves the keypad on for the volume keys
  (`/etc/mce/mce.ini` `DisableKPImmediately=2`; `ts_kp_disable_policy()` in Nemo's mce). Locked with
  the display off, mce writes only the double-tap gesture (`wait_for_gesture` 4), as before.
- **`/sys/devices/omapdss/display0/hw_revision`** (omapfb): 2.6.32's omapdss bus had the displays at
  `/sys/devices/omapdss/displayN`; a root device `omapdss` now links each display there to its panel
  device. The panel's `hw_revision` shows the IDs read at power on, as Nokia's (mainline's read them
  over DSI and failed with the panel off): `fe.91.96`, display on or off. mce's "Cannot open ...
  hw_revision" is gone.
- **The touch configuration job** (`mxt-configure`, `/usr/bin/mxt_configure.sh`, after mce starts):
  Nokia's `firmware_version`, `config_crc` (CRC24 of the chip's configuration area, T7 onwards),
  `nv_config_crc` (the chip's T6 checksum), `clear_config` and `write_config` (Nokia's file format
  through `request_firmware()`, which finds Harmattan's `/lib/firmware`). The script runs to the end as
  on stock: product rm-696, panel fe.91.96, firmware 1.6 give `RM-696_Pyrenees_SMD_ES40_V1_6.bin`, CRC
  `0x29b82f`; running and NVM checksums are the same, "Running config already same", "Configuration
  already in nv memory", nothing written. The chip's NVM already holds this configuration: stock's
  driver logs the same checksum at every boot (`Atmel mXT Touchscreen v1.6 (0x29b82f)`); stock wrote
  its RAM at 11.5 s of every boot only because its driver first put the older `cfg.h` configuration
  there. The update path by hand (clear: CRC 0x0; write: 0x29b82f; `disable_ts` 1 and 0) restores the
  same bytes. `backup_config` (the NVM write) is left out (`REMOVED.md`): the script calls it only when
  the NVM checksum differs from the file's, which it doesn't here.
- **Nokia's `condition` match and `CONDITION` target** (`net/netfilter/xt_condition.c`, with RATEEST
  and rateest built in): wlancond's throughput rules (`/etc/network/wlan_iptables.sh`) need them. Nokia's ABI (match revision 2 with a value, a target), not xtables-addons'.
  Harmattan's iptables 1.4.8 loads the script and lists its rules with names and values; the same
  rules on usb0 set the variable to 1 under 300 KiB of traffic and to 2 once idle;
  `/proc/net/nf_condition` takes decimal and hex; deleting the rules removes the files. wlancond loads
  them only during a call (disassembly, 0xdab4/0x1137c: on OHM's `com.nokia.policy.context` decision
  for `call_audio_type`, the handler logging "VOIP call"/"Call cleared", while connected; it also
  moves its CQM RSSI threshold from -70 to -80 dBm), not for a plain connection: WLAN up on boot 226
  loaded nothing. Not tried yet: a VoIP call over WLAN, where wlancond writes `enable_throughput` and
  reads the `ABOVE`/`BELOW` NFLOG messages.
- Not ported: stock's touch report limit (`REMOVED.md`).

## Idle since the cameras, DAC33 low power, charger detection, OFF mode (2026-10-06 night, boots 227-238)

I asked for three ports: the DAC33's low power mode, Nokia's charger-type detection and OFF
mode. Branches in `../linux_mainline_rm696`, none merged yet that night (all merged on 2026-10-07: "Later
the same day" below; branches and worktrees deleted since): `off-mode` (worktree `../kernel_off`),
`dac33` (`../kernel_dac33`), `bcc` (`../kernel_bcc`), and `combo` (`../kernel_combo`, test only: the
three on rm696 9ad462fb4). Research notes and the OFF mode plan (stock, mainline and TI's errata with
line references): `build/offmode-plan.md`, summarised below.

**Idle was stuck in C1 since the cameras (fixed, boot 227, `off-mode` e1792b9bf).** On boot 226 the
CPU never went below C1 (C2-C7 entered 0 times; MPU, PER and CORE never left ON): the ISP's IOMMU
(`480bd400.mmu`) was runtime-active from probe on (the ISP attaches it there), its hwmod held `cam_ick`,
and with it CAM's automatic sleep dependency on the MPU (`PM_WKDEP_CAM` 0x6, `CM_CLKSTST_CAM` 1, CAM
ON). Mainline's `omap3_enter_idle_bm()` uses only C1 while CAM is ON, and its C1 keeps the MPU
clockdomain active (`OMAP_CPUIDLE_CX_NO_CLKDM_IDLE`), so CAM never idled. Nokia's ISP also held the
IOMMU from probe to remove (`omap3isp/isp.c`, `iommu_get()`), but stock's C1 let the MPU clockdomain
idle and CAM followed. Fix: the ISP takes the IOMMU's runtime PM reference with its first user and
drops it with the last. Boot 227: the IOMMU suspended (2 s active in 106), `cam_ick` 0, CAM RET; C2,
C3 and C5 used (most idle time in C5, MPU RET); both cameras still stream (`ispcap`: main 30.0 fps,
front 15.1). The standby power the cameras' merge cost (boots 191-226) is back.

**The clocksource back on the 32 kHz counter (`off-mode` a7b61bb36, reverts rm696 14486a623).** GPT10
(CORE, 19.2 MHz) as clocksource and sched_clock keeps CORE's clocks on for good: no CORE retention or
OFF with it (REMOVED.md's row). Stock used the 32 kHz counter. Cost as measured on 2026-10-05:
clock_gettime 0.78 -> 1.15 us, a process switch ~1 us more. Booted from 228 on.

**The DAC33's "Mode 7 Low Power" (branch `dac33`, 6 commits; booted 228-230).** Stock: the kernel
defaults to Bypass and Harmattan's `/etc/pulse/pulseaudio_pre-start.sh` selects `'FIFO Mode' 'Mode 7
Low Power'` (our `ramboot/harmattan.patch` had commented that line out; it's back). The FIFO modes run
only for periods over 40 ms; PulseAudio opens the card with 10 ms periods, 140 ms when its policy
asks for long buffering (`audio_buffering=long`, xpolicy), so stock too plays short-period streams in
Bypass. Mode 7 LP over Mode 7: an alarm threshold interrupt "ATHR time" (10 ms) above the lower
threshold starts the McBSP, a timer stops it after the burst; inactive, the McBSP is force-idled with
its functional clock gated, and a 10 ms CPU latency request holds while playing. Ported from Nokia's
`tlv320dac33.c`, `omap-mcbsp.c` and board data (`ti,burst-bclkdiv` 3, `ti,keep-bclk`), with the ASoC
`request_power_level` DAI op Nokia added; mainline's McBSP latency request is dropped while inactive.
Tested on boot 228 with 140 ms periods (`aplay` straight to `hw:dfl61dac33`, a tone piped from perl):
~8-10 DAC33 interrupts a second, McBSP2's fclk gated in ~80% of samples, the latency alternating 10000
and 1666 us, PER RET ~1000 times in 10 s against none in Bypass; one aplay underrun in four runs (the
ssh session runs in Harmattan's low-priority standby cgroup; not seen in the other three). Not
checked: how it sounds (needs headphones and me: the Music app with the screen off).

**Charger-type detection (branch `bcc`, 4 commits; booted 229-230).** Stock (`twl5031-bcc.c`): on
VBUS, with the PHY powered down, data contact detection, then the BCC's state machine (100 mA = a host
port, 500 mA = a charging port), then for a charging port D+'s line state with its pull-up (both
lines high = a wall charger); the gadget connects only after a successful data contact and never to a
wall charger. BME reads `/sys/class/power_supply/usb/uevent`: type `USB`/`USB_CDP` with
`CURRENT_NOW` 100/500/900 mA, or `USB_DCP` = wall-charger mode. Ported into the 6.18 TWL USB PHY
driver (it owns VBUS and the PHY's power) through the usb_phy charger framework, musb told of VBUS
after detection; `CONFIG_USB_GADGET_VBUS_DRAW=500` (stock's gadgets declared 500 mA; the configfs one
defaulted to 2). Boot 229 on the Mac: `USB_CHARGER_SDP_TYPE`, `TYPE=USB PRESENT=1 CURRENT_NOW=500`,
`bmestat`: charger type USB500MA, charging STARTED; the USB network link came up normally. Not checked
(needs me): a wall charger (`USB_DCP`, USBWALL, no gadget), unplug and replug.

**OFF mode (branch `off-mode`), so far.** The N9 is DM3730 ES1.2: SPRZ319F's 1.86 and 1.87 affect
silicon 1.0 and 1.1 only (both kernels gate them by revision already: i582/i583); 1.107 affects 1.2.
Done:
- `fcc18ed79` stock's policy (PER OFF only with CORE OFF; CORE OFF only with CAM, DSS, IVA2, SGX and
  USBHOST off; `disable_core_off` works; the IVA2 left to the DSP bridge) and an arm switch:
  `pm_debug/off_mode_armed`, 0 at boot on the N9, so pmconfig's `enable_off_mode 1` waits until a
  test session writes 1;
- `5383469c6` `CONFIG_OMAP3_L2_AUX_SECURE_SAVE_RESTORE=y` (PPA service 43), as stock;
- `24447b079` erratum 1.107 at boot, as stock (EN_MPU sleep dependencies for 100 us, other bits kept);
- **MPU OFF works (boot 230)**: `disable_core_off 1`, `off_mode_armed 1`: MPU and NEON OFF ~14 times a
  second (C4, C6), CORE and PER never OFF, 30 checksums of a 20 MB library identical across 371 MPU
  OFF cycles, dmesg clean. The HS ROM's restore path (PPA 40, 42, 43) works with Nokia's PPA;
- `c2f638ca4` the secure RAM image (0xC040 bytes, 48 KiB after omap_hs's resize) in a 64 KiB
  reservation at 0x8f100000 (below 0x90000000 for the ROM), saved at every CORE OFF entry as stock;
  a failed save sends that entry to CORE retention instead of hanging. Boot 233: saved at boot
  (`pm_debug/secure_ram_saves` 1, fails 0), `bb5-test.sh` passes. The first version had the
  reservation `no-map`: boots 231 and 232 died before the console came up (pstore had nothing newer
  than boot 230). No-map regions elsewhere (DSP pool, VRAM) are in highmem, outside the linear map;
- `9e65783c7` the scratchpad saved again after every DPLL3 M2 change and cpufreq transition, as
  stock (`resource34xx.c`); not tested with CORE OFF yet.
Left (`build/offmode-plan.md`): the scratchpad saved again after DPLL1/DPLL3 changes (else the ROM
wakes the MPU at boot rates with current voltages), erratum 1.85 workaround 2 (1.84: no CORE OFF with
DPLL3 locked), IO pad wakeups (pinctrl-single clears every pad's wake bit at probe) and the IO chain,
GPIO outputs held through PER OFF, the mailbox's interrupt enables across CORE OFF, stock's latency
limits, and stock's TWL5031 power scripts and resource config. The TWL holds neither stock's nor
mainline's idle config (read-only dump, boot 229: VDD1 and the LDOs sleep-remapped to SLEEP, stock:
OFF and ACTIVE); `CFG_P*_TRANSITION` 0x7f has STARTON_SWBUG clear, so a TWL that switches off stays
off until USB is plugged in. The TWL write and every CORE OFF test wait for me at the phone;
CORE idle also needs Bluetooth off (UART2) and USB unplugged. (Bluetooth on no longer keeps CORE on since branch `bt-idle`,
2026-10-07: "Bluetooth and UART2 idle".)

**Later the same night: CORE idle (boots 233-238; me: "keep the revert", "OFF only when BT off",
"do [the TWL scripts], i will test it with you").** Tested with USB unplugged, Bluetooth off, display
locked (ssh over a WLAN hotspot when it was up; the phone can't join WPA3):
- Two more CORE blockers found and fixed, both mainline: `off-mode` 0790e6776 **the DSI PLL's input
  clock leaked one enable per display on/off** (dsi_display_uninit_dsi() never undid dss_pll_enable()'s
  clk_prepare_enable(); dss2_alwon_fck at 26, then 50): DSS never left ON; since the fix DSS reaches
  RET and OFF. 12e998bcd **the OMAP3 bandgap's clock (ts_fck) only around a conversion** (it had none
  but single reads, yet held CORE's clock for good).
- Still no CORE RET. Ruled out with measurements: pending wakeups (PM_WKST_* 0), I2C's 1 s
  autosuspend, the mailbox's and SHA12's interface clocks (each off for 60 s), the GPMC/SMS/SDRC idle
  modes (smart, as stock), SDRC_POWER (0x9 on stock too).
- **Stock read on the same phone** (normal boot, pm_debug readable as user): unplugged standby gave
  CORE OFF 1322 times, RET 94, 188 s of 346 s in OFF; its registers (`build/offmode-2026-10-06/
  stock-regs-boot.txt`, ours `ours-regs2.txt`).
- `off-mode` 4d1e42064 **erratum 1.85 workaround 2, as stock**: our L3 policy kept DPLL3 locked for good
  (workaround 1), which rules CORE retention out; stock's omap_sram_idle() sets AUTO_CORE_DPLL around
  CORE RET/OFF with L3 at OPP50 and VDD2 at OPP100's voltage (confirmed in its binary). Ours: the same
  from omap_sram_idle() with interrupts off (VDD2 through the VP, voltdm_scale_noirq()), only when no
  CORE functional clock runs (stock's pwrdm_can_idle(core)); with L3 at OPP100 CORE stays ON instead.
  Runs (107-135 entries per 3 min unplugged), no errors; CORE still no RET.
- 434fe6b03 **SHA12 (omap-sham) disabled in the N9/N950 DT**: no driver, but its hwmod kept the clock
  on and the module never idle; stock had it off and idle. Done (sha12_ick 0, idle); CORE still no RET.
- **What's left against stock's dump: the EMU (debug) domain is ON here** (CM_CLKSTCTRL_EMU 2 =
  forced awake, PM_PWSTST_EMU ON; stock: 3, OFF). Writes to CM_CLKSTCTRL_EMU and RM_RSTST_EMU don't
  stick (stock's own init clears RM_RSTST_EMU's DOMAINWKUP_RST and sets HW_AUTO, pm34xx.c:1489-1499).
  Suspects not in stock's 2.6.32: the PMU node's `debugss` hwmod (emu_clkdm, emu_src_ck) and ARM
  hw_breakpoint's CP14 access at boot. Next: a build without both, then check PM_PWSTST_EMU and
  core_pwrdm. Debug branch `core-idle-dbg` (../kernel_combo) counts, at each CORE idle attempt, the CORE
  functional clocks and not-idle modules (`/sys/kernel/debug/core_idle_dbg`; not for merging).
- **The lights are our kernel's**: the dim white glow at the front and the red light at the back are
  absent while only NOLO has run (user, 2026-10-06), so some driver or DT setting of ours turns them on.
- **"Wrong charger" at unplug is ours** (stock: none): when the unplug starts with a bus suspend
  (the gadget's suspend ~100 ms before the disconnect) BME logs "bq24153: Charging stopped by unknown
  error"; without the suspend, nothing. Reporting the suspend's 2 mA after 500 ms (`bcc` 55efcfa23)
  didn't change it: cause open.
- Seen once: `sscd` spinning in userspace (85% CPU, Phonet poll loop) after an unplug/replug with
  workaround 2 active; gone after a reboot.
- **RAM-booting stock's own kernel (the raw zImage in `unpacked/`) through 0xFFFF hangs after NOLO
  with no watchdog recovery: I had to pull the battery.** Never again.
- Two USB-network losses after a replug (the gadget's ECM closed 3 s after connecting, usb_moded?);
  the session reboot recovered them.

## CORE retention found: the watchdog (2026-10-07, boots 239-248)

**CORE reaches retention since `off-mode` 35a7fec2d: WDT2 as a ti-sysc module allowing force idle
only** (`omap3.dtsi`, legacy `wd_timer2` hwmod data dropped). The hwmod had `HWMOD_SWSUP_SIDLE`, so the
watchdog sat in no-idle (`WD_SYSCONFIG` 0x09) for as long as it ran, and Harmattan's DSME always runs
it: no CORE clock domain idle, so no CORE RET, with every CORE status bit looking idle. Stock wrote
0x01 (force idle) at probe (`kernel-plus-harmattan/drivers/watchdog/omap_wdt.c:336-337`). The hwmod's
own comment says smart idle blocked CORE too, so force idle is the only working mode.
- Boot 247, by hand: 715 C5 attempts, RET 0; after `WD_SYSCONFIG` 0x09 -> 0x01, 132 of 132 RET.
- Boot 248, the fix alone: 147 of 147 RET, INA 430; the sleep-indicator lights blink from ~2 min
  after unplug. The watchdog is still fed (`WD_SYSCONFIG` 0x05).
- Found from the prior-art search `build/core-ret-prior-art-2026-10-07.md` (Paul Walmsley 006c7f18449a:
  an active WKUP clock domain keeps CORE_L3/CORE_CM from idling).

**Next limiter: I2C's 1 s runtime-PM autosuspend.** Of 2992 C5 entries cpuidle wanted on boot 248,
2789 were refused up front because a CORE functional clock ran: I2C1 2037, I2C3 1447, I2C2 602, MMC2
641, SSI 61 (counts overlap). Stock released the I2C clocks after each transfer. With
`autosuspend_delay_ms` 0 by hand (boot 244) refusals drop, but I2C3 still runs often (sensors).

**Ruled out on the way** (each with the CPU idling and the counters running):
- mailbox (DSP bridge unbound: mailbox suspended, still RET 0), GPMC and OneNAND (unbound), the
  EMU domain (OFF with the PMU node disabled), VC errors (none in `PRM_IRQSTATUS_MPU`).
- `CM_IDLEST1_CORE` at idle entry and at wake shows SDRC, OMAPCTRL and MAILBOXES accessible in every
  case, as in stock's dump: iclk-only modules only get idle requests during a clock-domain transition
  (the mailbox stays accessible even in force idle), so those bits say nothing.
- The DPLL3-relock and SDRC-ready polls after WFI can't show CORE idle: the MPU runs from DPLL3, so it
  only executes once DPLL3 is locked again (always 1 poll).

**Other findings:**
- **Lights:** the front glow and the red back light are the R&D sleep indicators (GPIO 92 `sleep_ind`
  ORs sys_clkreq and sys_off_mode into them). Stock drives GPIO 92 low; we leave it floating (the DT's
  gpio-leds `debug::sleep` needs `CONFIG_LEDS_GPIO`, which is =m and not shipped). Driven low: off
  (user-confirmed). Driven high they show sys_clkreq: dark when the device retains, a free indicator.
  `build/lights-2026-10-07.md`.
- **"Wrong charger" at unplug:** BME's uevent socket holds one uevent on 6.18 (600-byte rcvbuf); the
  `bcc` PHY's own uevents arrive first and BME drops the power supply's "not present", keeps charging and
  fails its next check. Fix on `bcc-uevent` (revert of 55efcfa23 + 28af5005b: a second
  `power_supply_changed()` 200 ms later). Boots 244/245: BME saw the unplug at once, no error.
  `build/wrong-charger-2026-10-07.md`.
- **`sscd` spin (seen twice, both after a USB replug):** cause and fix in "Later the same day" below
  (netlink dump accounting, 552122361; `csd` did the same). An earlier NETCONF theory was wrong.
- **UART2 (BT) sometimes stays runtime-active with BT down**, holding a 555 µs CPU latency limit that
  rules out C4-C7 (boots 241 and 245, not 242/246); unbinding omap8250 releases it. Cause and fix (2026-10-07): "Bluetooth and UART2 idle" below.
- **DSP bridge unbind crashes** at the next cpufreq change (its cpufreq notifier stays registered:
  `dsp_opp_cpufreq` -> `dev_get_io_mgr`, boot 246).
- **Data across a crash:** RAM-boot syslog lives in the RAM overlay and is lost on reboot; ramoops
  keeps the console when our kernel boots next (USB plugged, 0xFFFF armed). Stock has no `/dev/mem`.
- The OTG soft reset by hand (stock's power-off sequence) cost the USB network until a reboot.

### Later the same day: merged into rm696, I2C, lights, the sscd/csd spin (boots 249-255)

**rm696 is now 552122361**: `off-mode` (with the WDT2 fix), `dac33`, `bcc` without the debounce and its
revert, plus the wrong-charger fix, then three new commits (all verified on the phone):
- 0342d26bd **lights off at boot**: `CONFIG_LEDS_GPIO=y` and no default trigger on the N9's `debug::sleep`
  LED (GPIO 92). `echo 1 > /sys/class/leds/debug::sleep/brightness` turns the sleep indicator on.
- 68b9826ec **I2C autosuspend 0**, as stock (idle after each transfer). Unplugged with the display off,
  CORE now retains about 130 times a minute (boot 248: about 50) and spent 263 of 266 s in RET; the
  lights blink 30 s after unplug instead of 2 min. Startup is sometimes slower: the CPU stayed busy until
  ~215-240 s in 3 of 4 boots with delay 0, never in 5 boots with 1000 ms (one boot each at 10 ms:
  partly). I accepted that ("if retention is kept i am fine with either").
- 552122361 **netlink: refuse a dump chunk only when the receive queue is already full.** The `sscd`
  spin (and the same in `csd`) after USB replugs: libisi sets SO_RCVBUF 16384 (sk_rcvbuf 32 KiB) and
  reads with a 16 KiB buffer, so 6.18's dump chunks are 17920 bytes; `netlink_dump()` charged the chunk
  before comparing with sk_rcvbuf, refused it at dump start and in the `netlink_recvmsg()`
  continuation, and the -ENOBUFS went into sk_err. libisi then polls that socket with events 0 and
  never clears the error: ppoll() returns POLLERR at once, 400 times a second (kprobes on ppoll's
  pollfd array, netlink_dump's return and sk_error_report). Fixed by comparing the memory from before
  the chunk. Boot 252: two long and one short unplug/replug, no -ENOBUFS, no error, no spin (before:
  spin at the first long replug). An earlier group-number theory (`build/sscd-spin-2026-10-07.md`)
  is wrong: groups 21/22 are Phonet's in both 2.6.32 and 6.18.

**The launcher spinner after the boot animation** (user: stock shows the icons at once): not the RAM
overlay. Stock's caches on the eMMC show through it, and a boot writes only two MeeGo Touch string caches
(`/var/cache/meegotouch/css/*_string_cache`) and database copy-ups to RAM, no pixmap or style cache
rebuild. Harmattan starts the launcher and apps in stages gated on load (`load-launcher.sh`), so a busier
startup shows the spinner longer; not measured against stock yet (stock's syslog is readable as user).

## Bluetooth and UART2 idle (2026-10-07, boots 255-260)

Branch `bt-idle` (worktree `../kernel_bt`, on rm696 552122361), **fast-forwarded into rm696 on my go: rm696 = 828c50ecb**, image `build/zImage-n9-828c50e` (= `build/zImage-n9-bt-828c50ecb`); branch `bt-uart2` holds its first two commits (the Bluetooth-off fixes
alone, `build/zImage-n9-bt-9378f210e`). Tests: `tests/bt-idle.sh` (all of the below but CORE),
`tests/bt-downrace.pl` (power-offs racing queued HCI commands), `tests/coretest-bt.sh` (CORE retention,
unplugged). Reports `build/bt-uart2-2026-10-07.md`, `build/bt-research-2026-10-07.md` (stock's and
Nemo's hci_h4p, the TI1273 firmware decoded: `build/bt-decode-fw.py`). Images built apart from
`build.sh`'s tree: `KERNEL=../kernel_x BRANCH=x build/build-bt.sh` (any worktree; VM `~/projects/sgx-bt`, output
`build/zImage-n9-bt-<sha>`; `build/zImage-n9` untouched).

**UART2 stuck active with Bluetooth off** (boots 241, 244: "CORE retention found" above). The stuck
boots were those whose bluetoothd power-off took 30 s (241: 06:21:32 -> 06:22:02, 244: 31 s; the clean
ones 0-1 s): the tty close waited out `closing_wait`.
1. `nokia_shutdown()` put the chip in reset first; a command queued before the power-off was still
   sent after it (`hci_dev_close_sync()` purges `cmd_q` only later), and a chip in reset leaves CTS high
   (UART2's CTS pad is pulled up, `omap3-n950-n9.dtsi:127`): auto-CTS held the bytes in the TX FIFO.
2. The close waited 30 s for them, then `omap_8250_shutdown()` cleared IER. `serial8250_start_tx()` had
   taken a runtime PM reference for TX, given back only by the TX-empty interrupt (OMAP raises it only
   for an empty FIFO): leaked, so UART2 never suspended and kept its 555 µs CPU latency request.
- Reproduced at will on rm696 (boot 255): `bt-downrace.pl 5 20`: 5 of 5 power-offs 30.0 s, UART2 then
  active with 555 µs for good. A bluetoothd restart loop (`tests/bt-uart2-restart.sh`) didn't hit it.
- f96b15a50 **serial: 8250: drop the TX runtime PM reference at shutdown** (mainline bug since
  d74d5d1b7288, 2014; master unchanged on 2026-10-07). Alone (boot 257): a power-off still stalled 30 s,
  but UART2 suspended 3 s after it.
- 9378f210e **hci_nokia: flow control off before the chip goes into reset** (stock reset the UART at
  close). Both (boot 256): 25 power-offs with 20-50 commands queued, 0.01 s each, UART2 suspended;
  btloop 1527/1527.

**Bluetooth on: UART2 and CORE idle**, as stock's hci_h4p let them (it gated the UART clocks between
bursts).
- The first two bytes lost at a chip wakeup (boot 39, "Bluetooth" above) were most likely not lost to a
  late RTS: upstream hci_nokia's runtime resume raised RTS and then set flow control, a termios change,
  and on OMAP3 every termios change ends in 8250_omap's i202 MDR1 erratum path, which clears the receive
  FIFO (`omap_8250_mdr1_errataset()`); two bytes below the 48-byte trigger raise no interrupt first.
  Stock cleared the FIFO first and raised RTS after.
- cc413cc8f **RTS alone** in the runtime PM callbacks, `rts_delay_us` (test knob) to raise it late. Boot
  258, RTS low 98% of each inquiry: 9 inquiries of 3-4 devices, 0 receive errors, 0 reassembly failures,
  0 command timeouts, also with RTS raised 20 ms after host wakeup; btloop clean. The chip waits for RTS.
- 40900cbd7 **release the UART while the chip sleeps**: the serdev controller's runtime PM reference
  (`serdev_device_open()`'s) is dropped with RTS when the serdev device suspends, taken back (UART2
  resumes, FIFOs cleared) before RTS goes up, and before every close (a wrapper around `hdev->close`).
  Boots 259-260: BT on and quiet, UART2 suspended 100% of 10 s, no latency limit; inquiries at RTS delay
  0 and 20 ms: 3-4 devices, 0 errors, UART2 suspended ~80% of the time even then; btloop clean.
- 828c50ecb **let a transmission end before the power-off**, an older hci_nokia race the power-off
  tests showed (rm696 too: boots 255-257 logged 4, 23, 2 "Runtime PM usage count underflow!" for
  `serial0-0`): a `nokia_dequeue()` waiting for the UART across a power-off and the next power-on put
  its reference after `nokia_setup()` had (kprobes with stacks: setup 4 gets, 7 puts). The shutdown
  flushes the write work. Boot 260: 0 underflows in 53 power-offs.
- **CORE retention with Bluetooth on** (boot 260, unplugged, display off, `coretest-bt.sh`): the sleep
  indicator blinked within 10 s of the unplug (me). CORE RET entries per 40 s: BT on 406 (first),
  237, 107 (after an inquiry), 101; BT off 99, 105, 100. An inquiry from CORE idle found 3 devices.

**Throughput and file transfers** (branch `bt-tx` on rm696 828c50ecb, boots 261-263; **fast-forwarded
into rm696 on my go: rm696 = 3a56aa7af**, image `build/zImage-n9-3a56aa7`; me: "i need BT file transfers to work"):
- ab9ec256d **end a transmission from a timer, as Nokia's hci_h4p**: upstream hci_nokia waited in
  `nokia_dequeue()` for the UART after every burst (`uart_wait_until_sent()` sleeps a tick or more
  between `tx_empty` checks: ~22 ms, HZ 128) and the next frame waited too. Now a delayed work lowers BT
  wakeup and puts the reference once the UART is empty, 100 ms after the queue ran dry (stock's
  `lazy_release`); a mutex orders it against the dequeue; shutdown and close flush and cancel it.
  btloop each way, 1 / 3 / 16 packets in flight: 18.7 / 39.9 / 40.4 KB/s -> 34.0 / 66.4 / 67.4.
- d57e894fd **`ti_baud`** (module parameter), the TI1271's rate at power-on: 921600 by default.
  3692300 (the firmware's rate, stock's) gave 98.8 / 225.8 / 225.3 KB/s in btloop and ~70000 packets
  without a lost one, but a real file transfer with an Android phone stalled on a corrupt ACL frame
  ("Frame reassembly failed", "ACL packet for unknown connection handle", a break on the line): in
  loopback the chip never sleeps. Stray bytes were also dropped twice at 3.69 Mbaud (121, 7). Branch
  `bt-tx-3m69` has 3.69 Mbaud as default. Suspect: a glitch on the chip's TX line at its wakeup, too
  short to be a character at 921600 (stock's UART was unclocked then and cleared its FIFO before RTS).
- 3a56aa7af **Bluetooth: keep the scan mode a stack without mgmt writes**: 6.18's
  `hci_update_scan()` rewrites the scan mode from HCI_CONNECTABLE/HCI_DISCOVERABLE after every ACL
  connection and disconnection; only mgmt and the HCISETSCAN ioctl set them, and BlueZ 4 writes Write
  Scan Enable raw, so the first connection turned page scan off for good (seen in a capture: Write
  Scan Enable right after Connection Complete, `hciconfig` then without PSCAN): after one transfer the
  N9 took no incoming connection. Now the mode written counts without mgmt.
- File transfers with an Android phone (boots 262-263, OBEX Object Push, me): send works;
  receive works (receive, send, receive in a row, the scan fix); 0 receive errors. **On the RAM-boot test
  image received files can't be saved**: obexd writes to MyDocs (pictures to `MyDocs/Pictures`, other
  files such as PDFs to `MyDocs` itself), read-only there ("Read-only file system"); for the tests a
  tmpfs went over `MyDocs/Pictures` and `MyDocs/Documents` (RAM only). Not measured: a real transfer's
  speed. Tools: `tests/btmon.pl` decodes connection, L2CAP and RFCOMM setup now.

**3.69 Mbaud: what corrupted the frames** (2026-10-07 evening, branch `bt-baud` in `../kernel_baud` on rm696
3a56aa7af, boots 263-266, `docs/bluetooth.md`; **fast-forwarded into rm696 on my go: rm696 = ccfc3678b**,
image `build/zImage-n9-ccfc367` = `build/zImage-n9-bt-ccfc3678b`):
- Reproduced without a second device (`tests/bt-baud.sh`): 10 inquiries at 3.69 Mbaud on rm696, 181 stray bytes
  dropped, 2 reassembly failures, `pe` +2 in `/proc/tty/driver/serial`; at 921600, 0. kprobes on every received
  byte (`bt-baud.sh kp on`, analysed by `tests/bt-baud-trace.py`, structure only): both corrupt frames
  started with the first byte after RTS went up at a chip wakeup, LSR 0x0c (framing + parity error on an 8N1
  line), when the chip sent at once (2 of 12 such wakeups). `build/bt-baud-trace-263.txt`.
- Cause: `__omap8250_set_mctrl()` raised RTS through the MCR and then took the LCR to 0xbf (configuration mode
  B, to set auto-RTS in the EFR), which is also parity on and two stop bits: the chip's first character, framed
  in that window, came out wrong and the rest misframed. A window of a few register accesses fits in a 2.7 us
  character, not in a 10.8 us one. Stock's hci_h4p raised RTS with the EFR write and restored the LCR next.
  Not the chip's TX line, not the RX pad (hypotheses 1-2 of the handoff).
- cc5876990 **serial: 8250_omap: raise RTS after the EFR write when autoRTS is on**. 1e10a8a2b **hci_nokia: the
  TI1271 at 3.69 Mbaud** (default; `ti_baud=921600` for the old rate). ccfc3678b **hci_nokia: forget a frame cut
  short at power-off** (both rates: a partial frame left by a power-off took the next set-up's negotiation reply,
  "Negotiation failed: -110"; bt-downrace stopped 4 of 12 runs before, 0 negotiation failures in 31 after).
- With them, at 3.69 Mbaud: 95 inquiries, 160 spaced commands, 15 power cycles, gapped loopback (the chip
  sleeping between 210 packets), 43 SDP browses of the Mac (real radio, ACL data, no pairing): 0 receive errors,
  0 line errors. bt-idle passes. btloop 1 / 3 / 16 in flight: 99.3 / 225.3 / 225.8 KB/s each way (921600: 34.9
  / 70.2 / 69.1).
- With me (boot 266): OBEX with the Android phone at 3.69 Mbaud, 2 receives and 4 sends; one send failed
  with "Unknown response" from the Android side (nothing in the kernel log, no receive error), the 3 after it
  clean (captured with `tests/btmon.pl`, which decodes OBEX response codes now); "a fluke, i am ok with this".
  CORE retention with BT on at 3.69 Mbaud: RET entries per 40 s 382, 225, 101 (after an inquiry from CORE idle),
  108; BT off 100, 93, 100 (as boot 260). A first run was void: with `ramboot/unlock.sh`'s
  inhibit_blank_mode 3, mce ignores the display-off request and the panel's 6 ms idle limit keeps CORE out;
  `coretest-bt.sh` now sets it to 0 and locks through mce itself.
- Seen once (boot 266, bluetoothd starting during a power-off race run): a firmware command timeout (0xfddd)
  and the chip's "hardware error 0x23"; not in 19 runs since. Power-off races still log a few stray bytes and
  line errors at the cut (both rates); harmless since ccfc3678b.

Seen, open:
- Once (boot 260, ~4 min after boot, right after bluetoothd had run): 6 of 15 forced power-offs took
  0.5-5 s; not again in 52 since, traced ones take 22 ms (`nokia_shutdown()` 16 ms).
- (Fixed on `bt-tx`, above.) Every TX burst ends in `serdev_device_wait_until_sent()` (upstream hci_nokia's `nokia_dequeue()`),
  which sleeps at least a tick (HZ 128) between `tx_empty` checks: ~22 ms a burst (555 calls, boot 260),
  the next frame waiting. Stock has no such wait: its TX tasklet ends a burst from the TX-empty
  interrupt, drops BT_WAKEUP at once and gates the clocks from a 100 ms timer (`hci_h4p/core.c:126-135,
  565-620`). btloop (boot 260): 18.7 KB/s each way with 1 packet in flight (the wait after each), 39.9,
  40.0, 40.4 KB/s with 3, 8, 16: the ~40 KB/s ceiling is something else (candidate: the UART at 921600
  baud, stock 3.69 Mbaud; unchecked). A2DP (SBC ~41 KB/s): a steady stream would batch ~3 packets a
  burst and likely keep up, with ~45 ms jitter; untested with a headset.
- Not tested: profiles with a paired device (A2DP, HFP), Bluetooth on from Harmattan's UI (bluetoothd
  managing it), CORE OFF with BT on (host wakeup GPIO 101's pad wakeup and RTS's OFF pad state,
  `offmode-plan.md` commit 8).

## FM radio (2026-10-07 evening, boot 275; rm696 ffb5dcc35)

Stock PR1.3 ships no FM app; the community's fmrxd (under QML Radio and Kozhanov's FM Radio) and
Nokia's test servers use the WL1273 through `/dev/radio0`, the `dfl61wl1273` ALSA card (`hw:2`) and
its codec's controls. Mainline's radio was TX-only since v3.8 and went (with the codec) in 6.18-rc1,
so rm696 carries Nokia's own Harmattan drivers on 6.18, four commits (`docs/fm.md`: stock's facts,
the users' sequences, the branch): the WL1273 core (chip logic, firmware, tuning, seek, RDS; enable GPIO
and IRQ from the DT; an out-of-bounds RDS status read fixed), `/dev/radio0` (stock's ioctls on the
control framework), the codec with stock's ten controls ("Mode Switch", "Codec Mode", "Audio Switch",
...), and the DT node (I2C3 0x22, IRQ GPIO 43, enable GPIO 178) with the `dfl61-wl1273` card on
Nokia's codec (BT mode by default, so SCO is as before).

Tested on boot 275 (`tests/fm.pl`, `tests/fmscan.pl`; `build/fm-*-275.txt`):
- "Mode Switch" Rx 0.71-0.75 s with the firmware upload (Harmattan's `radio-wl1273-fw.bin`); tuning
  0.08 s a frequency; the interrupt only while FM is on.
- With my Nokia headphones (the antenna): band scan RSSI 7-37; 88.1 MHz: RDS 840 blocks in
  20 s, 0 errors, PI 5501, PS "*Radio1 "; seeks 0.24-0.48 s, the wrap included; I heard Radio 1
  through `arecord -D hw:dfl61wl1273 | aplay -D pulse`, what fmrxd does.
- fmrxd's HCI vendor command (`f3 88 01 02`, the chip's audio multiplexer) is needed for the I2S
  capture (else EIO); fmrxd's order keeps the audio after hci0 goes down again.
- Bluetooth SCO through Nokia's codec: BT mode, 8 kHz mono; PulseAudio's `sink.hw1` streams to it.
- Without an antenna a second seek from 108.00 MHz timed out (-110) in 4 of 5 cycles (an empty band);
  not with the antenna.
Not checked: CORE retention unplugged with FM off, a call through a Bluetooth headset, fmrxd itself
(not installed on the read-only root).

## The jack's buttons and ECI accessories (2026-10-07 late evening, boot 276; rm696 24b20f193)

Nokia's `twl5031-aci` (a module on stock) and `eci` drivers ported into `sound/soc/ti/dfl61.c` beside
the plug classification (branch `eci`, 008084bf6 on rm696 ffb5dcc35, tested; rebased and merged on my word: rm696 24b20f193; `docs/audio.md` has the stock facts,
the design and the test plan; `tests/eci.sh`). Harmattan reads one input device, "ECI Accessory"
(udev: `/dev/input/eci`, opened by qmkeyd2; X and ohmd by name), and ohmd an ECI accessory's memory
at `/sys/devices/platform/ECI_accessory.0/memory`; both kept. The ACI interrupt is the TWL's PIH line
6 (DT `interrupts-extended = <&twl 6>`), VAUX1 is held while a plug is in (stock's "v28").
- A basic headset's (or carkit's) button: KEY_PHONE from the ACI's comparator 1, Nokia's timing (a
  change reported 200 ms after its sample, sampled every 220 ms while held).
- ECI accessories: classification tries Nokia's bus reset between the video-cable and open-cable steps;
  then memory, "enhancement features" block, interrupt set-up, buttons read on each ACCINT and mapped
  with Nokia's table; the accessory's mic follows the "Headset Mic" widget.
- Different from stock, each because 6.18 would deadlock or misbehave otherwise: bus transactions run
  from process context (6.18 nests all TWL interrupts in one thread); the ECI mic switch from a work
  (stock's ran inside the DAPM event and took DAPM's lock again); a transaction steps only on its own
  interrupt bits. TWL5031 ES1.0/1.1's address-decode bug (stock's twl-core shadowed the ACI registers)
  isn't ported: those get no buttons; this phone's TWL5031 is revision 0x2b (IDCODE 77802f, ACI v.16).
- Tested (boot 276) with my Nokia one-button headset: classified as a headset (each pass's 10
  ECI resets refused at once); KEY_PHONE on press/release, autorepeat while held, double presses
  apart; qmkeyd2, ohmd and Xorg hold the device; the music player pauses and resumes on the button (me); unplugged while held, the key released; replugged, classified again and working; no
  `cpu_dma_latency` request left behind, no warnings. Not tested: an ECI remote (none here), CORE
  retention with a headset in and USB out.

## NFC (2026-10-07, boot 278; rm696 34c9fae34)

Harmattan's NFC stack (nfcd through `libNFCDAL`, D-Bus activated at every boot) opens Nokia's char
device `/dev/pn544` (stock's `drivers/misc/pn544.c`); mainline has only the NFC-subsystem pn544, which
Harmattan can't use, so nfcd failed and restarted ~300 times a minute for the first minutes of every
test boot. Ported as `drivers/misc/nokia-pn544.c` (stock's code, the board callbacks as GPIO
descriptors: I2C3 0x2b, IRQ GPIO 76, ENABLE GPIO 77, FW_RESET GPIO 78; DT node `nfc@2b`, built in;
`docs/nfc.md`). Two differences on purpose (`REMOVED.md`): firmware download mode (a rewrite of the
chip's flash, which nfcd starts whenever the chip's version differs from its HAL's image) is refused
unless `nokia_pn544.allow_fw_mode=1`, and stock's factory `nfc_test` sysfs file is left out.

Tested on boot 278: stock's probe self-test (RSET) passes; udev makes `/dev/pn544` nfc-owned; nfcd
starts once, checks the firmware (it matches: no firmware-mode request) and closes the device. NFC on
through mce, as Settings does: my Android phone held to the back was detected and read twice
("Tag doesn't contain NDEF data", as expected from a phone); NFC off: the device closed, its GPIOs low.
Not checked: an NDEF tag's content, NFC on during CORE OFF.

## CORE OFF (2026-10-07 night, boots 268-278; rm696 aed6f173d)

With Bluetooth off CORE now reaches OFF in unplugged standby, as on stock: ~700 CORE OFF entries in 10
minutes (runs 5 and 6, the modem talking every minute), clean wakes from OFF (RTC alarm, volume keys),
DVFS live, BB5's secure services and the modem link working after it. The plan and its first half are
in "Idle since the cameras, ..." above; the rest, each checked against Nokia's 2.6.32
(see `docs/power.md`):
- dd5510056, 3f1b231ce: Nokia's TWL5031 sleep and wake scripts and resource config (decoded from
  stock's binary), and the regulators no longer rewrite the sleep remaps (they had VDD1 and the LDOs
  sleep to SLEEP; stock: VDD1 OFF, the LDOs ACTIVE).
- 72d64f25f, be67433c1: the IO daisy chain armed around CORE RET/OFF, the wake bit on the pads of every
  GPIO interrupt and sys_nirq.
- d5525319a: erratum 1.45 around PER OFF (GPIO outputs held by their pulls); df1eb9813: the mailbox's
  idle mode and interrupt enables kept across CORE OFF.
- 346db0a2d: CORE OFF chosen when DSS and USBHOST go OFF with the MPU (their interface clocks' autodeps
  had demoted every C7 pick).
- e9943aa01: the N9 reboots with the global software reset, as stock. Mainline's DPLL3 warm reset
  drives SYS_OFFMODE and runs the TWL's sleep script: with VDD1 and VDD2 remapped OFF a SysRq-B left the
  phone dead until a battery pull (boot 268). Never boot a kernel with the scripts but without it.
- 4ea7a477f: a positive secure RAM save status counts as saved (the ROM returns 1 for ~99% of saves).
- aa4a23614, 1b8ad23f5, e89447038: the SSI port's spurious error interrupt acknowledged (it looped in
  the PIO thread: run 3's panic), the I2C interrupt thread leaves a suspended controller alone, and the
  error's report carries the port's state.
- aed6f173d: every pad as stock runs it (NOLO's values read by the `paddump` debug boot,
  `build/nolo-padconf-2026-10-07.txt`, plus stock's own 8 changes from its syslog).
Open then: the SSI port's garbage words after CORE OFF wakes (found and fixed 2026-10-08: next
section), CORE OFF with Bluetooth on (works: next section) and with WLAN associated, stock's OFF tuning
(oscillator 3.45 ms instead of 10, the N9's cpuidle latencies).

## CORE OFF with Bluetooth on, the SSI's stale status (2026-10-08, boots 279-280)

**Bluetooth on: works as stock, no change** (`docs/bluetooth.md`). Boot 279, rm696 24b20f193's first
boot (smoke test passed: TWL scripts as expected, pads as stock). With hci0 up
(bluetoothd paused) and an inquiry every 20 s through CORE RET, CORE OFF at fixed clocks and CORE OFF
with DVFS live, every inquiry completed (30, rc 0, 4-5 devices as plugged; `tests/coreoff1.sh BT=1`, which
now logs each inquiry, UART2's active time, and takes `P3`/`P4` lengths and `PADOFF`), 0 HCI errors, no
UART2 line errors; 626 CORE OFF entries, 762 secure saves without a failure. The chip woke the SoC from
OFF through GPIO 101's pad 8-21 times per inquiry and its events (258-byte EIR results included)
arrived whole: hci_nokia drops RTS before releasing UART2, as Nokia's hci_h4p turned auto-RTS off with
MCR RTS 0 before gating the UART's clocks (`drivers/bluetooth/hci_h4p/core.c` 166-178), and like stock
the pads have no OFF-mode values. Holding RTS/TX high in OFF (0x3a00: OFF_EN, OFFOUT_VAL and an OFF
pull-up with OFFOUT_EN clear, high whichever polarity OFFOUT_EN has; mainline's `PIN_OFF_*` macros
disagree about it) changed nothing, so it stays out. A second run, 9 min of CORE OFF at fixed clocks with
the modem toggled every minute, was clean too (31 inquiries).

**One unexplained ~40 s of CORE ON** (boot 279, uptime 350-392 s, at fixed clocks): the MPU kept going
OFF but CORE never left ON; cpuidle chose C4 and C6, so `omap_sram_idle()`'s CORE gate held it (a CORE
functional clock on, or erratum 1.85's DPLL3 M2/VDD2 condition, or SmartReflex 1.5 calibrating VDD2).
Ruled out: UART2 (its active time normal), the GPS on I2C3 (nped's `i2c_write: Remote I/O error` is its
own ready probe NACKing after the chip powers up, as often on stock: 1.4 per 10 min over 49 stock boots,
1.5 on ours; in run 2 the GPS ran a whole session with I2C3 active 28 s and CORE OFF went on), a
runtime-active I2C or SSI device (9-19 s each over the whole boot), BME. Not seen again in 9.5 min of the
same conditions with `tests/coresample.sh` running (every 3 s: CM_FCLKEN1/3_CORE, ICLKEN1, IDLEST1/3,
CLKSTST, CM_CLKSEL1_PLL's M2, PRM_VP2_CONFIG's enable; on a stall the runtime-active devices, enabled
clocks, latency limit and L3 holds; bit names `tests/cmcore-bits.txt`; log `build/coresample-279.txt`).

**The SSI's garbage words: a stale status.** Since CORE OFF the modem port took one garbage word
("ssi-protocol: command 0xf74dfdbf not supported", then a spurious error) per wake from OFF.
Nokia's 2.6.32 driver and mainline save and restore the same registers in the same order (research
report: stock `drivers/hsi/controllers/omap_ssi.c` 279-369 against `omap_ssi_port.c` 1289-1364), so a
debug build measured it (branch `ssi-dbg` 7edb5301a, boot 280, `build/coreoff1-ssidbg-280.txt`): every
port runtime resume that finds the context lost (MPU_ENABLE no longer as saved) reads MPU_STATUS
0x03efbfff, data available on every RX channel, a break and an error, while the SSR buffer, error and
break registers read 0; restoring MPU_ENABLE delivers it 0-8 ms later (39 resumes, 39 garbage words).
With the status acknowledged first, as ssi_flush() does (switched on mid-run): 35 resumes, 0 garbage
words, the modem link working. Fix: branch `ssi-loss` 58fde0d17, "HSI: omap_ssi_port: acknowledge the
status a context loss leaves", merged: rm696 = 58fde0d17 (image `build/zImage-n9-bt-58fde0d17`; booted
as such by me that night).

## Call audio without a SIM (2026-10-08, boot 281; rm696 cf6e32591)

Call audio is digital on the N9: the modem and the APE exchange 20 ms PCM frames over SSI port 1
(channel 1 speech control, 2 speech data), through Nokia's `cmt_speech` (`/dev/cmt_speech`),
Harmattan's libcmtspeechdata 2.1.1 and PulseAudio's `module-meego-cmtspeech`; no TWL5031 voice port.
Mainline's driver, ABI, buffer layout and DT channels match stock; branch `call-audio` (three commits on
rm696 58fde0d17, `docs/audio.md`; merged 2026-10-08 on my go: rm696 = cf6e32591, image
`build/zImage-n9-cf6e325`) adds what stock had: the peer-reset notice to the client when the
port is flushed while open (Harmattan's PulseAudio closes and reopens on it), a control `write()` that
waits for the previous one instead of failing with EBUSY (the library sends NEW_TIMING_CONFIG_REQ
right after SPEECH_CONFIG_RESP and never retries), and stock's SSI ready-pad handling around SSI clock
changes (mainline's idle state floated the data, flag and wake pads and left GPIO 154 undriven: read on
rm696, GPIO5 OE bit 26 = 1, an input; with the branch's hog an output driven low).

Tested on boot 281 (`tests/cmtramp.sh`, `tests/cmtramp.c`; `build/cmtramp-281*.txt`), PulseAudio stopped
for the test and reopening the device after each run:
- Control path: `SSI_CONFIG_REQ` on and off, as the library sends them at a call's start and end,
  answered with success by the modem in 0.1-6 ms, with no SIM and no call.
- Data path: the modem has the library's TEST_RAMP_PING. Each ping is answered with the modem's own
  request for an uplink ramp, then a downlink frame holding the ramp (324 bytes, intact): 100 of 100 at
  a ping every 20 ms (a call's frame rate) with the uplink ramps sent (downlink after 1.4 ms on average,
  1.8 at most), 10 of 10 at 100 ms, 10 of 10 back to back without uplink ramps (the downlink slots
  rotating as designed), 3 of 3 at 16 kHz's frame size (640-byte ramps). The downlink ramp doesn't echo
  the uplink (`ULX`), so uplink content isn't checked, only that the frames go out.
- Back to back with uplink ramps, the modem stops taking our frames on the third or fourth ping
  (SST busy, a ping and an uplink frame waiting at its third word, the modem's wake line down), an SSI
  RX error follows 0.2-1 s later and the modem resets 1.3 s after that: 3 runs, 3 resets, each
  recovered by itself (sscd restarts it, simless state again, Phonet up). Not seen with any gap. Stock
  does the same (2026-10-08, I ran `tests/cmtramp-stock.sh` as root on a stock boot;
  `build/cmtramp-stock.txt`): 10/10 spaced, then back to back the fourth ping stalls with the same
  registers (TXSTATE busy, BUFSTATE 0x6, CAWAKE 0) and the modem resets 2 s later: the modem's test
  mode, not our kernel. Stock's downlink comes 1.07-1.16 ms after a spaced ping, ours 1.3-1.5. On every such flush `cmt_speech` delivered `CS_ERROR` to the open device (the
  first commit), and the stalled control write waited the new 500 ms before EBUSY (the second).
- Harmattan's own pipeline: csd's `com.nokia.csd.Call.ServerStatus` sent by hand made PulseAudio's
  module raise the wake line and send SSI_CONFIG_REQ; the modem answered in 6 ms, the library went to
  CONNECTED and PulseAudio created "Cellular call up link"/"down link" on `source.voice`/`sink.voice`;
  ServerStatus false tore it down (answer in 1 ms, DISCONNECTED, streams deleted). PulseAudio's debug log:
  `build/call-audio-research/pulseaudio-debug-281.log`.
- L3 never switched during these runs (USB plugged and the CPU hold it at OPP100), so the SSI clock
  changes the third commit covers weren't exercised.
Left for a SIM: the speech frames through PulseAudio (SPEECH_CONFIG_REQ, the buffers, the uplink
timing), the audio by ear on each route, a call unplugged (L3 switching under the call), a modem reset
during a call.

## TV-out (2026-10-08 night, boots 298-300; rm696 cf6c40eba)

Composite TV-out over the AV jack works as on stock: the jack classifies a TV-out cable (mic line ~99
mV), TVOUT_EN (gpio 40) goes high before the cable is reported, Harmattan's ohmd and X turn the `tv`
display on (PAL 720x574 at 13.5 MHz, WSS 16:9) and clone the 854x480 framebuffer onto vid1 (645x516
in the PAL frame; the portrait UI shows sideways, as stock). Boot 300 (me, with a TV): picture
for 6 minutes, a video from the Videos app, PAL/NTSC and the aspect from Settings, unplug: 0 sync
losses, the TV off and its L3 hold released. Headphones still classify as headphones (TVOUT_EN stays
low). The port: `docs/tv-out.md` (PAL start, VENC's L3 hold, the TV DAC clock, the jack switch).

Two display bugs it found, both fixed in rm696:
- The DISPC ran on the DSI PLL (DSS_CONTROL bit 0 = 1), which the panel's ULPS powers off 500 ms
  after an LCD update: every ULPS exit came with "SYNC_LOST on channel tv" (boot 299: ULPS entries
  and the errors lined up at 0.1 s, also with the TV's plane off), and Harmattan's status bar redraws
  about once a second. Stock kept the DISPC on DSS1_ALWON_FCLK (`board-rm696-video.c`:
  `fclk_from_dsi_pll = false`). 95e3de665 does the same: 172.8 MHz core and 43.2 MHz pixel clock,
  stock's (147.84/36.96 before), the 4x ratio for Xv scaling kept, the DSI link on its PLL, split
  halves unchanged (6.0 ms).
- After those errors a split half's FRAMEDONE never came; the TE timeout and the DSI's framedone
  timeout both gave the DSI bus lock back, updates ran unlocked (a WARN flood: the phone crawled)
  until the DSI framedone timeout was armed twice: BUG_ON in `dsi_update_screen_dispc()` from the TE
  interrupt, a panic (boot 298, `build/tvout-298-dmesg-ramoops-1.txt`). 5fbca8420: the lock goes back
  once. A lone framedone timeout (boot 300 once, boot 183 once without TV-out) now costs one frame.

Open: omapdss's SYNC_LOST recovery leaves the TV's plane disabled until X sets it up again (stock's
error worker re-enabled the display); with the clock fix nothing triggered it in 6 minutes. A fix, unmerged and untested (nothing provokes a loss now): kernel branch `tv-recover`
18e4779b3, `docs/tv-out.md`. NTSC was
switched by me but not seen in the logs.

## The oscillator start-up time (2026-10-08 night, boot 302; rm696 8167154ce)

PRM_CLKSETUP is how long the PRCM waits for the system clock after asking for it back (it drops
sys_clkreq in CORE retention and OFF: PRM_CLKSRC_CTRL's AUTOEXTCLKMODE is 1). With no board-set
oscillator start-up time mainline uses 10 ms (`vc.c`: 328 cycles of 32 kHz, VOLTSETUP2 312 for OFF);
Nokia's board files set 113 ("3ms osc, 200us reg, 250us margin"), VOLTOFFSET 16 and VOLTSETUP2 97, the
same for retention and OFF (`board-rm696.c` and `board-rm680.c`, `rm696_vc_config`). 8167154ce gives
the N9 and N950 that start-up time (`pm.c`: 3448 us, 113 cycles; `vc.c` then derives stock's
VOLTSETUP2; VOLTOFFSET was 16 already). Boot 302: CLKSETUP 0x71 (cf6c40eba: 0x148), VOLTOFFSET 0x10,
VOLTSETUP2 0x61. VOLTSETUP2 read 0x61 on cf6c40eba too: the kernel writes it only at a CORE OFF entry, so
that was the bootloader's value.

Measured with `tests/oscsetup.sh` (one unplug, four 75 s phases, CLKSETUP switched with devmem between
them; `tests/wakelat` sleeps to random timer targets and logs how late each wake is, so the exit
latency of the idle state it woke from). The slow wakes cluster, and every cluster moves by 6.56 ms =
(328 - 113) cycles of 32 kHz:

| Wake from | CLKSETUP 328 (before) | 113 (stock, 8167154ce) |
|---|---|---|
| CORE retention (C5) | 11.2-11.4 ms | 4.6-4.8 ms |
| MPU OFF, CORE retention (C6) | 11.8-11.9 and 12.3-12.5 ms | 5.3 and 5.85-5.94 ms |
| CORE OFF (C7, OFF armed) | 23.3-23.4 ms | 16.8 ms |

So the 10 ms was waited out at every CORE retention wake of every boot, not only with OFF armed (OFF
stays unarmed on a normal boot): ~130 a minute in standby, and with the screen on since e16a0248f.
With 113 the wakes fit the N9's cpuidle table from stock (exit latency C5 5611 us, C6 7685, C7 22258);
with 328 each exceeded it. The run: 642 CORE retention and 36 CORE OFF entries, no reset, nothing in
dmesg. Phase A (retention, 113) caught only 14 slow wakes: 137 of its 285 C5 entries reached CORE
retention (phase B: 192 of 206); the phases with OFF armed show the retention wakes at 113.
Left of stock's OFF tuning: RET 0.8375 V and the WDT guard (`docs/power.md`).

## Stock Harmattan unmodified (2026-10-09, boots 303-306; rm696 22d8d4d85)

Me: "I want the harmattan.patch to become kernel fixes, 100%, I want this to behave
stocklike". `ramboot/harmattan.patch` is gone: the test init no longer changes any Harmattan file
for the kernel, and the release (`RELEASE.md`) needs no changed file either. Each hunk became a
kernel change (kernel commits on rm696, 8167154ce..22d8d4d85; the research behind each: Nokia's
2.6.32 in `../kernel-plus-harmattan` and the PR1.3 rootfs):

| Harmattan expected | Kernel now |
|---|---|
| power-off, charging while off (ACT_DEAD), alarm power-on | `ti,use_poweroff` back, stock's power-off (DEVOFF in P1/P2/P3, the start-on events left alone, so a charger starts ACT_DEAD); test boots halt instead (`twl4030_power.poweroff_halt`) |
| DSME opens `/dev/watchdog` (OMAP) and `/dev/twl4030_wdt` | the TWL watchdog built in at stock's node name (a watchdog-core devnode), DT aliases for the ids, stop on close, NOLO's TWL watchdog re-armed for 30 s at probe as Nokia's `twl4030_wdt_hack.c`; test boots set `nowayout` in sysfs |
| `enable-swap`: `modprobe ramzswap`, `rzscontrol /dev/ramzswap0` | zram as the `ramzswap` module, its disks `ramzswap<N>`, rzscontrol's size/init/reset ioctls (init writes the swap header), LZO1X |
| `wl1271-cal`: CAL's NVS through nl80211 testmode, `allow_adhoc` at `/sys/devices/platform/wl1271` | wlcore takes the NVS push as Nokia's driver (with the regional band-edge TX limits the tool applies) and has `allow_adhoc` there (0 refuses ad-hoc) |
| PulseAudio's pre-start: `omap-mcbsp.N/max_*_thres`, `soc-audio.N/pmdown_time` | `dfl61.c` links stock's paths and puts each McBSP in threshold mode, as Nokia's machine drivers |
| the TI1273 firmware at `/lib/firmware/ti1273*.bin` | hci_nokia asks for stock's names |
| Nokia's firmware from the phone (Bluetooth, camera sensors) | BT's UART driver and the camera sensor/lens/flash drivers are modules udev loads once the root is up (as stock's); nothing of Nokia's is in the image |
| the eMMC as `mmcblk0` | already so (DT alias; older notes saying mmcblk1 are stale) |
| CAL written by libcal (BME, DSME, libbb5) | OneNAND written as stock: no cache program, no write verify, NOLO's locks kept, no OTP; test boots set `onenand_omap2.read_only` |

The test-only hunks went (boot watchdog off, `|| true`, DSME's verbosity, sshd off): stock's sshd has
port 22 on test boots, the test dropbear 2222 (`build/s.sh` and the ramboot tools try 2222 first).
The init gives Harmattan a depmod'd `/lib/modules/<release>` tree in module-init-tools 3.4's form
(only the modules Harmattan loads: udev loads whatever `modules.alias` lists) and leaves MyDocs to
stock's `mount-home` (read-only through fstab on test boots: its own bind had made mount-home cover
MyDocs with a tmpfs, boot 304).

RAM (`REMOVED.md` 5): stock's swap job gives 256 MB only above 1,000,000 kB of MemTotal; Nokia's
kernel left ~1,008,400 ("Memory: 1002MB 2MB = 1004MB total"), ours 990,420 (64 MB swap). Mainline
stole 1 MiB for an unused secure RAM base and with it dropped another 1 MiB; the kernel log, W^X
padding, ramoops, hash tables and omap2plus' built-ins for other boards cost the rest. Now
MemTotal 1,002,720 kB, 1004 MB of RAM as stock, the image 7.3 MB (was 8.5), and stock's job sets up
256 MB of `ramzswap0` (boot 306).

Boots: 303 (the init refused to start Harmattan: `CONFIG_WATCHDOG_SYSFS` was off, so `nowayout`
couldn't be set: the strict check worked), 304 (all hunks; MyDocs covered, `wl1271-cal` exit 6 on the
missing `allow_adhoc`), 305 (both fixed), 306 (RAM). On 306 I checked: WLAN associated
(-51 dBm), Bluetooth send (receive fails only on the test boot's read-only MyDocs), both cameras with
autofocus and the flash firing (their Qt app; camera-ui stays in standby on a read-only MyDocs), the
speaker. Backups of the rootfs, /home and CAL were taken first (`~/n9-backup/2026-10-09`, checksums
matched on both sides). Not checked yet: power-off, ACT_DEAD and alarm power-on (test boots halt),
CAL writes (test boots read-only), headphones.

## WLAN: Nokia's driver and stock's firmware (2026-10-16/17; rm696 1c7f2dcac)

Standby on a 5 GHz access point drew 119-158 mA on wlcore (CORE ON 45-100%), where stock draws
9.7 mA on the same channel in the same spot (stock: `tests/stock-current.sh`, BME's battery current
every 10 s). What it wasn't, from unplugged A/B runs: wlcore's beacon filter and early termination on
5 GHz (`02e4b43be`, unmerged), its forced legacy power save, waking every 3rd DTIM instead of every one
(126/132 vs 144/144 mA), the menu governor and the -EBUSY idle fix, the CPU's clock; stock's two idle
delays (ELP 5 ms, the WLAN slot's SD host 10 ms) took 17 mA off and are kept (`8f1aa5bd8`,
`6878fd12c`). linux-firmware's multi-role 6.5.7.0.50 doesn't run on this chip (TX stuck, recovery loop).

Stock runs its own wl12xx (2.6.37/38-era mainline plus Nokia's changes; kernel-plus-harmattan's copy
holds 152 of the 154 messages in stock's `wl12xx.ko`) with TI firmware 6.1.1.39.339, which wlcore can't
drive (pre-roles API). It's ported as `drivers/net/wireless/ti/wl1271` (modules `wl12xx` and
`wl12xx_sdio`, as stock; `CONFIG_WL1271_NOKIA`, wlcore left out). Stock's firmware loads from Harmattan's
`/lib/firmware`, the NVS comes through `wl1271-cal`'s testmode push, and the sysfs knobs `wlancond` uses
are back at `/sys/devices/platform/wl1271`.

The first run of the port idled at 113 mA too, which settled it: its firmware counters (decodable for
6.1) read `ps_enter` 0, and wlcore's 6.3 ones had read the same. The driver's flags (a kprobe on
`wl1271_ps_elp_sleep`, `+52(%r0)`) said PSM requested but never associated: 2.6.3x mac80211 reported
the BSSID and the association in one `bss_info_changed`, and the join the BSSID triggers set the
association up; 6.18 reports the BSSID at authentication and the association alone. Setting it up on
its own (`50ad704e2`): 18.2 mA over 3 hours on the same channel and spot (median 15; CORE ON 13%,
RET 39%, OFF 25%; 0.9 WLAN interrupts a second). What's left to stock's 9.7 mA is CORE OFF.

Port notes: 6.18 scans idle (2.6.3x left idle for a scan), so the driver joins for a scan from idle;
op_tx's station rides to the TX work in the rate slot mac80211 leaves to drivers with their own rate
control; Nokia's `ieee80211_{en,dis}able_dyn_ps()` (BT coexistence) became a driver flag; the MAC
address comes from the chip's fuse (Nokia's driver registered zeros and nothing in Harmattan sets one).

## I2C after CORE OFF (2026-10-17 evening; rm696 9e69d67db)

BME (`bme_RX-71`, `/dev/i2c-1` and `-2`) and DSME (the watchdog kicks through the TWL) spent 1-2.3% of
standby in the kernel in runs of ~14 ms, only once CORE had slept. Kprobe timings on the I2C runtime
resume (`tests/slowcall.sh` with entry/return probes, two 2-minute captures): the clocks under 0.34 ms,
`omap3xxx_cm_wait_module_ready` under 0.3, the clock-domain and power-domain steps under 0.13, but
`_enable_sysc()` exactly 13.977 ms in 152 of 649 hwmod enables: its `_wait_softreset_complete()` ran
the whole 10000 x `udelay(1)` timeout with IRQs off. After CORE OFF the I2C comes back reset and sets
RESETDONE only once I2C_EN is set (i2c-omap's reset says so), which the driver does after the hwmod's
wait; the driver then went on with the bit still 0, as it always had.

`9e69d67db` drops SYSS_HAS_RESET_STATUS from the OMAP3 I2C's hwmod sysconfig: `_enable_sysc()` 0.09 ms
at most, the I2C enables 125 ms in 2 minutes instead of 2252. Standby on 5 GHz (3.7 h, channel 100):
CORE OFF 40-42% (25% before), 13-15 mA for an hour and the last 30 minutes, 23-24 mA for 2.5 hours in
between with the CORE states, wake-ups, interrupts and CPU clocks unchanged: something outside the SoC
(the modem's network state, most likely; stock's own run had 6-8 and 11-16 mA phases).

## Kernel speed against stock (2026-10-03 night, boots 101-106)

`tests/kbench.c` on the same phone, CPU at 1 GHz:

| | stock 2.6.32 (`/system` cgroup) | rm696/dsp (ssh session's `standby` cgroup) | `perf-lean` (standby) | `perf-v7` (root cgroup) |
|---|---|---|---|---|
| syscall | 0.30 us | 0.54-0.68 | 0.37 | 0.37 |
| sched_yield | 2.30 | | | 1.55 |
| pipe write+read, no switch | 2.25 | | | 1.87 |
| thread switch | 7.8-8.6 | | | 9.6 |
| process switch | 9.0-9.4 | 30-32 | 20.6-22.5 | 14.5 |
| page fault (fresh page) | 6.0 | 10.0 | 8.0-9.6 | 6.6 |
| memset / memcpy MB/s | 1426 / 345 | 1400 / 350-370 | | |

Memory bandwidth is the same: the kernel is the difference. Config experiments on top of `dsp`
(branches, not for merging): `perf-lean` = no SMP (one core), no Spectre-v2 branch predictor
hardening (`HARDEN_BRANCH_PREDICTOR`, `_HISTORY`; nothing like it in 2012), no software PAN
(`ARM_PAN`), no audit, no schedstats, no stack zero-init; `perf-v7` = that plus the N9's SoC only:
omap2plus also builds the OMAP2 (ARM1136) boards, so the normal kernel is compiled for an **ARMv6
baseline**; without them it's ARMv7-only, and stock's 3G/1G split without highmem (`VMSPLIT_3G_OPT`;
needed pvr's cache flush to use `__cpuc_flush_dcache_area()`). Each step helped; the A9/A15 errata
and highmem come in through OMAP4/5 and "Typical OMAP configuration" (`perf-lean2`, which only
switched those off, fails the config check).

Harmattan puts processes in cgroups with very different weights: our test kernel's ssh session lands
in `/system/applications/standby` (cpu.shares 64, three levels; `active` has 4096), stock's own ssh
session in `/system` (1024). Every earlier test run through ssh on our kernel ran there: compare from
the same group (`echo $$ > /newroot/syspart/system/tasks`). Group depth also costs per switch and per
fault (cpu and memory controllers per level).

### The config decisions (mine, 2026-10-03) and how to turn each back on

Committed as `e5de31377` on rm696 ("ARM: rm696.config: an N9-only, single-core kernel without Spectre
mitigations"): the settings of `perf-v7`, measured above; the whole set built but **not yet booted**
(test it before relying on it). Each line is at the end of `arch/arm/configs/rm696.config` in
`../linux_mainline_rm696`; to turn one back on, change or delete its line there, commit, rebuild
(`kernel/build.sh` checks every line of that file stuck).

| Setting | Line in rm696.config | Why off | Turn back on if |
|---|---|---|---|
| N9 SoC only (OMAP3, ARMv7) | `# CONFIG_ARCH_MULTI_V6 is not set`, `# CONFIG_ARCH_OMAP2 is not set`, the same for `ARCH_OMAP4`, `SOC_OMAP5`, `SOC_AM33XX`, `SOC_AM43XX`, `SOC_DRA7XX`, `SOC_TI81XX`; `# CONFIG_ARCH_OMAP2PLUS_TYPICAL is not set` with its selects listed (`I2C`, `I2C_OMAP`, `NEON`, `VFP`, `REGULATOR`, `REGULATOR_FIXED_VOLTAGE`, `TWL4030_CORE`, `TWL4030_POWER`) | omap2plus' OMAP2 boards (ARM1136) made the whole kernel ARMv6, and OMAP4/5 brought Cortex-A9/A15 errata workarounds | the same kernel must boot another OMAP |
| Stock's memory split, no highmem | `CONFIG_VMSPLIT_3G_OPT=y`, `# CONFIG_HIGHMEM is not set` | all 1 GB is lowmem (MemTotal 1005796 kB on boot 105), no temporary mappings; user processes get 2.75 GB of address space, as on stock | a process needs more than 2.75 GB of virtual address space (then `CONFIG_HIGHMEM=y` and the default `VMSPLIT_3G`, or the top ~250 MB of RAM is lost) |
| One core | `# CONFIG_SMP is not set` (and so `# CONFIG_CPU_FREQ_GOV_SCHEDUTIL is not set`: schedutil needs SMP; Harmattan runs ondemand) | the N9 has one core: SMP locking and per-CPU code for nothing | never on the N9 |
| No Spectre-v2 mitigations | `# CONFIG_HARDEN_BRANCH_PREDICTOR is not set`, `# CONFIG_HARDEN_BRANCH_HISTORY is not set` | branch predictor flushes on context switches; 2.6.32 had none. Since rm696 fd20d1f6a this also drops the Cortex-A8 BTB flush on every mm switch, which mainline did even without hardening (process switch 16-17 -> 12 us) | untrusted code runs on the phone and Spectre-v2 attacks between processes matter, or Thumb-2 programs segfault at random under load (erratum 687067 on boards whose firmware sets IBE, as the N9's does: see "Context switch cost") |
| No software PAN | `# CONFIG_ARM_PAN is not set` | a domain-register switch around every user-memory access; absent in 2012 | you want the kernel to fault on stray user-pointer accesses (exploit hardening) |
| No VMAP stacks | `# CONFIG_VMAP_STACK is not set` | entry checks and TLB pressure; absent in 2012 | debugging kernel stack overflows (they then crash cleanly instead of corrupting memory) |
| No stack zeroing | `CONFIG_INIT_STACK_NONE=y` | zeroing every local variable costs everywhere; absent in 2012 | hardening against kernel info leaks: `CONFIG_INIT_STACK_ALL_ZERO=y` |
| No syscall audit | `# CONFIG_AUDIT is not set` | per-syscall hooks; Harmattan runs no auditd, stock had it off | an audit daemon is installed |
| No schedstats | `# CONFIG_SCHEDSTATS is not set` | scheduler debug statistics, unused | scheduler debugging (`/proc/schedstat`) |

The set together gave the `perf-v7` numbers in the table above; the settings weren't measured one by
one, so turning one back on costs an unknown share of the difference (measure with `tests/kbench.c`,
from the same cgroup, CPU at 1 GHz).

Booted on 2026-10-04 (boot 107): as `perf-v7`. In the same cgroup as stock (`/system`) a process switch
costs about twice stock's (19.4 vs 9.0-9.4 us) and a page fault 1.3-1.6x: `docs/performance.md` has the
numbers, what's ruled out and the candidates (the ~5 us below compared our root cgroup with stock's
`/system`). Left: a process switch still costs ~5 us more than stock's while a thread switch is about equal, so
the cost is in changing address spaces; `cpu_v7_switch_mm` itself is two register writes. Next:
profile the ping-pong with `build/kprof` (PMU sampling, kernel symbols), try `CONFIG_CPU_SPECTRE`
itself off and `PERF_EVENTS`, look at `check_and_switch_context`/`check_vmalloc_seq`. Then decide with
me what goes into rm696.config (an N9-only config, UP, the mitigations off) and remeasure.

## Context switch cost (2026-10-04 evening, boots 119-128)

Where a switch's extra time went, measured with the cycle counter (the only PMU counter that counts on
this HS device) at points of the scheduler and around single functions (branches `perf-schedprof`,
`perf-spf-up`, `perf-pf` in `../linux_mainline_rm696`, not for merging: per-function timers via
`include/linux/sched_prof.h`, debugfs `sched_prof`; writing `2` runs a microbenchmark of the
switch_mm steps). Two causes, both fixed on rm696:

1. **Load tracking on one CPU** (rm696 0658adb07). Linux 6.17 made SMP unconditional in the scheduler
   ([LWN](https://lwn.net/Articles/1023575/): Ingo Molnar measured a 5% regression on a UP x86). On
   the N9, with Harmattan's four cgroup levels, every enqueue, dequeue and pick ran PELT and computed
   each group's share with 64-bit divisions in software (the A8 has no divide instruction):
   `update_load_avg` ~1200 cycles a switch, group shares ~450. Back to v6.16's UP paths:
   `update_load_avg()` only calls the cpufreq hook (ondemand samples from it), `update_cfs_group()`
   takes `tg->shares`, `sched_balance_newidle()` and `remove_entity_load_avg()` do nothing. Wakeup
   3850 -> 2990 cycles (threads), 6650 -> 4100 (processes); a switch ~1 us less.
2. **A branch predictor flush on every address space change** (rm696 fd20d1f6a). Since the 2018
   Spectre-v2 work, mainline's Cortex-A8 `switch_mm` is `cpu_v7_bpiall_switch_mm`, hardening or not
   (`arch/arm/mm/proc-v7.S`: "Cortex-A8 - always needs bpiall"). It's a no-op unless the firmware set
   ACTLR.IBE; the N9's ACTLR reads 0x42 (IBE set), so it costs 576 cycles (`cpu_switch_mm` 805 cycles
   with it, 172 without), and everything after a process switch ran 30-50% slower per call with a
   cold predictor (`update_curr` 146 -> 216 cycles, `rcu_note_context_switch` 158 -> 260, ...).
   Stock's 2.6.32 had no flush (`rm581_defconfig`: no `ARM_ERRATA_430973`) on the same firmware. Now
   the flush comes only with `CONFIG_HARDEN_BRANCH_PREDICTOR`. **Risk**: mainline made the flush
   unconditional after random segfaults of Thumb-2 (armhf) userland on r3p2 A8 boards whose
   bootloader set IBE, put down to erratum 687067 ([thread](https://linux-arm-kernel.infradead.narkive.com/Esh7UIgf/arm-errata-430973-on-multi-platform-kernels-was-omap3-n900-add-microphone-bias-voltages)).
   Harmattan's userland is the one stock ran without the flush; if random segfaults show up, set
   `CONFIG_HARDEN_BRANCH_PREDICTOR=y` (rm696.config) or revert fd20d1f6a. I decided to keep it
   (2026-10-04 night).

Not causes: the switch's own instructions (isb 16 cycles, dsb 34, CONTEXTIDR or TTBR0 write + isb 69),
the scheduler features (`tests/schedfeat.sh`: none moves the switch by more than noise), `-Os` like
stock (`perf-os`: with GCC 14, switches 14-16 us and faults 9-11 us, much slower).

Result, `tests/compare.sh` as user under ondemand, all three in `/system/applications/standby` (kbench
prints it; stock's too, boot of 2026-10-04 22:10: `build/compare-stock-2.txt`; ours:
`build/compare-fd20d1f-4.txt`, before: `build/compare-a546538-2.txt`):

| | stock 2.6.32 | rm696 a546538 (before) | rm696 fd20d1f |
|---|---|---|---|
| syscall | 0.34-0.40 us | 0.49-0.60 | 0.47-0.49 |
| clock_gettime (reads the 32k counter) | 1.09-1.10 | 1.16-1.41 | 1.16-1.17 |
| sched_yield | 2.29-2.31 | 1.97-2.30 | 1.81-1.82 |
| pipe write+read | 2.25-2.53 | 2.08-2.80 | 1.94-2.01 |
| thread switch | 7.3-7.6 (8.2-8.4 on 10-04 afternoon) | 11.5-13.5 | 10.2-10.4 |
| process switch | 9.3 (9.8-10.1) | 16.5-17.4 | 11.8-13.1 |
| process minus thread | ~1.8 | ~5 | ~1.7 |
| page fault | 6.1-6.4 | 7.4-8.4 | 7.2-8.5 |
| memset / memcpy MB/s | 1425 / 344-347 | 1161-1417 / 323-336 | 1235-1420 / 302-402 |
| video, whole-system busy share (20 s) | 44.3% (`build/compare-stock-3.txt`) | 54.8% | 54.1% |
| file fault, a page of a cached library (kbench `filefault`) | 1.77-2.41 (stock visit 2026-10-05, `build/stock-visit-11.txt`) | | 0.84-0.98 (f49e9543d: fault-around maps 16 pages a fault) |
| fork+exec+exit (kbench `spawn`; 300 busybox spawns) | 3615-3809 us; 1.01 s | | 3817-5877 us; 1.65 s (f49e9543d) |
| video: interrupts in 20 s | 14422 | 34930 | 34411 |

So stock reads the 32k counter as slowly (gettime equal), zeroes memory as fast, and runs kbench at
the same cgroup depth: the gaps left are the switch itself (+2.9 us) and page faults (+1.5 us).

What's left of a switch (~2 us), per switch at 1 GHz with the fixes: `sched_clock()` ~1060 cycles
(1.35 reads of the 32 kHz counter behind the 19.2 MHz wakeup L4, ~780 cycles each; stock reads the same
counter, `plat-omap/common.c`), `update_curr` ~900 (5.9 calls: each cgroup level), `pick_eevdf` ~450,
EEVDF lag arithmetic ~600, `rcu_note_context_switch` ~150: the 6.18 fair class at four levels, spread
thin. A page fault (7.5 us): zeroing 2800 cycles (memset speed), allocation 550, memcg charge 700, LRU
550, rmap 370, the rest ~2400 in the fault and VMA walk: no single culprit either.

The video workload barely moved (54.8% -> 54.1% busy): ~2400 switches a second, so ~0.6% of the CPU.
Per-process system ticks (`/proc/PID/stat`) mislead for short-burst tasks: a whole tick goes to whoever
runs when it fires, and HZ differs (250 here, 128 on stock); pulseaudio's own split varied 87/127,
124/77, 139/76, 203/26 (user/system) between runs of the same kernel while its total stayed ~220.
Sampled per process (`KPROF_PID=n build/kprof`), its kernel time is ~1.6% of the CPU, about stock's 30
ticks. Compare video by the whole system's busy share instead (`compare.sh` prints it).

**Video against stock** (2026-10-04 night): busy 44.3% on stock vs 54.1% here, and here more of it at
1 GHz (9.6 vs 6.6 s): a real 10-point gap the switch fixes don't touch. Interrupts by source in 20 s
(`build/irq-video-stock.txt`, `build/irq-video-fd20d1f.txt`):

| IRQ | stock | rm696 fd20d1f |
|---|---|---|
| PRCM wakeup (`pm_wkup`) | 0 | 9576 |
| timer | 3576 (HZ 128) | 6206 (HZ 250 + hrtimers) |
| DSP mailbox | 2052 | 5221 |
| sDMA | 2005 | 2617 |
| DSS / panel TE / I2C | 2044 / 1198 / ~1235 | 2002 / 1198 / ~1271 |
| mmc0 | 18 (clip cached) | 1342 (first play of the boot) |

The PRCM wakeups: a kprobe on `omap3xxx_prm_clear_mod_irqs` counted 525 handler runs a second, half
of them finding a latched wakeup, PER ~230/s and WKUP ~34/s: the PER domain idles between events here
and every PER interrupt (GPIO2 TE, McBSP2 audio, ...) wakes it through the PRCM; each handler run reads
10+ PRM registers in the slow wakeup domain. Stock took none during video. Together with the extra
timer and mailbox interrupts that's maybe 2% of the CPU, not 10. Per process (`KPROF_TASKS=pid
build/kprof`, per-thread CPU-clock events): the renderer 28.9% of the CPU (user 20.3, kernel 8.6: the
DSP buffers' cache flush `v7_flush_kern_dcache_area` is the largest kernel part), pulseaudio 9.7% (user
8.1). Stock can't be sampled per process: its kernel has no perf events, schedstats or taskstats, and
its tick counts are biased. Stock with the screen off, idle: busy 1.2%.

The PRCM wakeups were McBSP3, the TWL5031's audio port (kprobe at `omap3xxx_prm_clear_mod_irqs+0x5c`,
module in r5, latched PM_WKST bits in r3: in 10 s PER bit 1 x2089, WKUP GPT1 x476, GPIO2 x78, I2C3
x29). Mainline's `omap3_prm_init_pm()` groups McBSP2/3/4 with the MPU, Nokia's `prcm_setup_regs()` did
not: fixed on rm696 (3a5439de6, booted on 2026-10-05: `PM_MPUGRPSEL_PER` 0x7e840, audio runs): video
busy 52.1%, PRCM interrupts 3106 in 20 s (GPT1, the system timer, and the panel TE remain, ~0.1% CPU).
Our idle baseline with the screen off is 5.3-6.3% (stock 1.2%): tracker-miner-fs re-crawls MyDocs on
every test boot (its database comes through the RAM overlay), the test harness's loops, ohmd (26-27
ticks vs 14), and the CPU thermal zone's bandgap read once a second (a busy-wait conversion,
`ti_bandgap_force_single_read`; `polling-delay = <1000>`; stock polled no thermal sensor). The DSP
mailbox then (rm696 e1159462f, booted 2026-10-05): its TX path no longer takes an interrupt per message:
mailbox interrupts 2040-2055 in 20 s (stock 2052), video busy 50.0% in two runs (a first run right after
the player started measured 61.5%: the compositor was busy, not the kernel; measure after the first
seconds). Left in video: the timer at HZ 250 (310/s vs 179), I2C3 (sensord's accelerometer: 882-3080
vs 715), the renderer (610 ticks vs 577), and the idle baseline above.

2026-10-05, items 5-7 (rm696 281cc3d23 + the quieter init, `build/zImage-n9-281cc3d-fw`): idle with
the screen off 2.2-2.3% (stock 1.2%; tracker's crawl and ohmd 18-20 ticks vs 14 are most of the rest);
timer interrupts in video 4220-4280 (128 Hz); pinned 1 GHz: thread switch 9.74-9.79 us, process
11.33-11.49, page fault 7.1-7.4. The I2C3 traffic is the magnetometer when sensord runs it (9.4 Hz,
4 transfers a sample, as Nokia's driver; off most of the time) plus the accelerometer's three
transfers per sample at 5 Hz. Block reads for the accelerometer (`st,use-block-read`, branch
`perf-lis3-blockread`) worked, but the boots that tried them (and the first 128 Hz boot) hit the
conndlgs/bluetoothd storm above, then traced to the firmware path; not retried, the gain is ~0.2%.

## mmap and munmap (2026-10-05 night)

A file mmap+munmap cost 16.6-18.5 us on rm696 against stock's 3.5 (forkbench as user, chrooted into the
read-only ext4 so paths and filesystem match stock's run; the overlay doesn't change this one). A
profile with kernel call chains (`kprof` with `KPROF_CHAIN=1`) put about half of it in the VMA maple
tree and the rest spread over the 6.18 mmap/munmap paths. Three changes on rm696, each a commit:

1. **No RCU mode for the VMA tree** (99afc1677): without per-VMA locks (they need SMP) every reader
   holds mmap_lock, so the node copy and RCU free of every store buy nothing.
2. **Node stores in place** (5d18d64ac): outside RCU mode the maple tree still built each store in a
   zeroed node on the stack and copied it back (two 256-byte copies and a clear); now the slots after
   the new range are shifted within the node. The kernel's maple tree test suite passes
   (`tools/testing/radix-tree`, `./maple`).
3. **A free area hint** (e87ff0337), as 2.6.32's `free_area_cache`: the gap tree walk for every mmap
   without an address scanned the whole top leaf on 32-bit (the stack's reserve above `mmap_base` is a
   gap too big to skip), ~2 us. The area under a per-mm hint is tried first and confirmed free with one
   VMA lookup. The area may not be the highest that fits, as on 2.6.32.

Same procedure for the kernel before and after (idle, screen locked): file mmap+munmap 16.6-18.5 ->
12.6 us, mmap alone 10.5 -> 6.6, munmap 8.2 -> 6.2, anonymous mmap+munmap 15.8 -> 9.7, mprotect
split+merge pair 12.8 -> 8.6. Still 3.6x stock's: what's left (tree walks ~1.9 us, two stores with gap
updates ~2 us, page table teardown ~1.5 us, the file's i_mmap tree ~1.1 us) is the maple tree's design
and the bigger 6.18 code paths on a 32-bit in-order CPU, no single item. Tried and dropped: `-Os` for
these files (slower), Tiny RCU (no gain for spawns). Details: `docs/performance.md`, `REMOVED.md`.

## Fork's cost per VMA (2026-10-05 night)

A fork costs stock 2.65 us per VMA (copied at fork, torn down at exit); rm696 6.8. Boosters and
applauncherd have 600-650 VMAs, so this is most of their fork time. A profile with call chains put ~3 us
of it in anon_vma bookkeeping: since 2.6.34 every anonymous VMA of a forked child gets its own anon_vma
(an allocation, a second chain link and interval tree insert, their teardown at exit), so that rmap
walks of a child's own pages skip its siblings. Four commits on rm696:

1. **The child shares the parent's anon_vma** (42ab3b71f), as 2.6.32: the VMA keeps the inherited
   anon_vma and `anon_vma_clone()` counts it, as when it reuses one. Reclaim and migration then visit
   the siblings' VMAs for pages a child copied: fine with a phone's dozens of processes. Tested with
   `tests/cowstress.c` (five processes' copy-on-write data checked while zram swaps them out: 0 errors)
   and video playback (CMA migration).
2. **Process accounting without a VMA walk** (0a00d483a): every exit summed all VMAs for BSD
   accounting's memory size; `total_vm` is that number.
3. **No uprobes** (b00ac605c): hooks in mmap, munmap and fork, unused by Harmattan.
4. **One pointer store per copied VMA** (d0bec3fb6): after the bulk copy of the maple tree, fork
   replaced each entry with a generic store; `mas_replace_entry()` writes the slot.

Same procedure before and after: per VMA 6.72-6.94 -> 4.91-5.14 us, booster-like fork (590 VMAs)
5190-5233 -> 4336-4453 us (stock 2682). Small processes' spawn is unchanged (their fork cost is mostly
per fork, not per VMA). What's left per VMA is spread over the page table copy and zap, the one anon_vma
link and the VMA iteration. Details: `docs/performance.md`, `REMOVED.md` section 2.

## Speed against stock: where it stands (2026-10-05 late night)

rm696 d0bec3fb6 (`build/zImage-n9-d0bec3f`) against stock 2.6.32 on the same phone, both as user in
Harmattan's `/system/applications/standby` cgroup. I accepted these numbers for now (2026-10-05:
"i am ok with those numbers for now"). Ours: `build/kbench-d0bec3f.txt` (kbench under ondemand, as
stock's had to run), `build/forkab-d0bec3f.txt` (forkbench in `chroot /harmattan`, plain ext4 like
stock; spawnbench on the RAM overlay, which slows our exec path lookups somewhat), `build/mmbench-e87ff03-ab.txt`
(mmap rows; untouched since), video and idle from `tests/busy.sh`. Stock: `build/stock-visit-11.txt`,
`build/compare-stock-2.txt`, `build/forkbench-stock.txt`, `build/spawnbench-stock*.txt`,
`build/busy-stock-*.txt`. Repeat ours with `tests/forkab.sh` / `tests/mmab.sh` (they wait for an idle
phone; leave the screen locked).

Since 2026-10-06 the clocksource is the 32 kHz counter again (a7b61bb36, for CORE retention and OFF), so
the GPT10 gains in these numbers are gone: about clock_gettime 0.78 -> 1.15 us (level with stock),
sched_yield 1.25 -> 1.60 (still ahead) and ~1 us more per switch (process switch about level with stock
or a little behind), as measured when GPT10 went in (`REMOVED.md`). Not remeasured since; getting it
back without blocking CORE idle: `docs/performance.md`.

| Ahead of stock | stock | ours |
|---|---|---|
| clock_gettime | 1.09-1.21 us | 0.78-0.84 |
| sched_yield | 2.29-2.41 us | 1.25-1.27 |
| pipe write+read | 2.25-2.53 us | 1.83-1.95 |
| thread switch | 7.31-8.33 us | 7.23-7.48 |
| process switch | 9.25-10.00 us | 8.95-9.15 |
| file-backed page fault | 1.77-2.41 us | 0.83-0.94 |
| stat / open+close (plain ext4) | 4.60 / 7.84 us | 3.98-4.08 / 7.67 |
| open+read+close / pread of /proc/PID/stat | 31.3 / 20.4-21.3 us | 29.3 / 13.8-14.4 |
| first read of a page after fork (young bit) | 2.57-2.59 us | 1.96-1.97 |

| About equal | stock | ours |
|---|---|---|
| copy-on-write fault | 20.4-20.9 us | 20.6-20.7 |
| readlink /proc/self/exe | 8.36 us | 8.36-8.41 |
| memset / memcpy | 1330-1425 / 344-347 MB/s | 1424 / 344-387 |
| getppid | 0.34-0.48 us | 0.49-0.51 under ondemand, 0.34 at a pinned 1 GHz |

| Behind stock | stock | ours | ratio |
|---|---|---|---|
| anonymous page fault | 6.13-7.04 us | 6.94-7.07 | ~1.1x |
| file mmap+munmap | 3.5 us | 12.6 | 3.6x |
| anonymous mmap+fault+munmap | 17.9-18.1 us | 28.1-28.5 | 1.6x |
| mprotect split+merge | 3.6 us | 6.4-6.5 | 1.8x |
| fork, per VMA | 2.65-2.86 us | 4.78-4.98 | 1.8x |
| booster-like fork (590 VMAs) | 2682-2705 us | 4281-4294 | 1.6x |
| fork+exit | 1160-1194 us | 1695-1730 | 1.45x |
| fork+exec /bin/true | 3195-3236 us | 4662-4686 | 1.45x |
| vfork+exec of a 492-byte static binary | 993-1069 us | 1746-1747 | 1.7x |
| kbench spawn | 3615-3809 us | 4961-4971 | 1.35x |
| 300 busybox spawns | 1.01 s | 1.48 | 1.47x |
| video busy (20 s of Nokia Pure) | 39.8-44.3% | 46-47% | +2-6 points |
| idle, screen off | 1.2% | 2.2% (the test harness included) | +1 point |

What the behind rows have in common: the VMA layer (maple tree, anon_vma chains, the 6.18 mmap paths;
"mmap and munmap", "Fork's cost per VMA" above) and fixed per-process costs of exec, exit and page
table setup, plus Harmattan's ohmd classifying every new process (~220 us more per spawn than on
stock, `docs/performance.md`). Next candidates if speed work resumes: those fixed spawn costs, then the
anonymous fault (memcg bookkeeping).

## Porting plan: status and what's left (2026-10-01)

(The 2026-10-01 record, kept as written, with what became of an item in parentheses; the current list
is `UNPORTED.md`.)

Done and tested on the phone (sections above):
- Linux 6.18 RAM-booted through NOLO, nothing flashed; stock Harmattan PR1.3 to its home screen on
  read-only eMMC with RAM overlays, Aegis in open mode with the real BB5 (Nokia's secure driver,
  Harmattan's own `libbb5` and `validator-init`).
- Graphics: the SGX with Harmattan's own EGL/GLES2/X (DRI2), the panel in landscape, tear-free.
- Display power: brightness, dim, standby screen (low power mode), lock screen, double tap to wake,
  colour profile; frame pacing improved (late first half).
- Input: touch (stock's configuration, protocol A, top-edge swipes), volume keys, accelerometer.
- Power: battery and charging (BME, 500 mA host), DVFS 300 MHz-1 GHz with voltage scaling, input
  boost, zram, RTC.
- WLAN (WPA2, DHCP, internet), audio (speaker through PulseAudio), modem at the ISI level (no SIM),
  Bluetooth (controller up, bluetoothd's services), the vibra and light/proximity drivers, Nokia's
  secure-world driver (as modules).
- Since 2026-10-01 evening: headphones (plug classification as stock, sound out), compass and GPS,
  ALS and proximity through sensord, DSME's `/dev/iphb`, the notification LED's patterns, mce's
  input seeks.

What's left, in suggested order:
1. Tested on boot 26 (`build/build-final.log`): DSME opens `/dev/iphb` (no "failed to open kernel
   connection"); the LP5521 on stock's configuration lights with mce's pattern. Tested on boot 27
   (`build/build-gps.log`): compass and GPS (above), the evdev seek fix (`lseek` works, mce's
   "Illegal seek" count 0). The AS3645A driver probes and resets the chip, but the red light at the
   flash stays: not that chip's state (left with the LEDs, for last).
2. Built, not yet run (`build/build-batch4.log`): the BT wake-up fix and the BT SCO card (McSPI1/3/4
   off for its DMA channels). On the next boot: an inquiry completes with UART2 on runtime PM;
   `/proc/asound/cards` lists dfl61wl1273 and PulseAudio holds it; UART2 and the wake lines with
   BT off; a USB mode switch with `/tmp/.ramboot-usb-modes` (mass storage read-only on the Mac,
   with a timed `set_mode charging_only` to get ssh back); then I unplug USB for a battery
   test (`MyDocs/.ramboot/power.txt`). (All run since: "Bluetooth", "USB modes"; the SCO card runs on
   Nokia's WL1273 codec since the FM port.)
3. Checks that need a person: the haptics' feel, Bluetooth pairing and A2DP/headset audio, calls,
   SMS and mobile data with a SIM. Tested by me since: headphones (TRS plays, EarPods are
   refused as wrong pinout), GPS.
4. Known problems:
   - Bluetooth: see item 2 and the Bluetooth section.
   - Fixed 2026-10-05: the modem's `COMM_SERVICE_NOT_AUTHENTICATED` (resource 0x59): the test image had
     disabled stock's self-test server ("Modem").
   - NOLO's logo isn't kept: the panel is found reset before the takeover ("Standby crash, NOLO's
     logo"), so the screen is black until Harmattan's boot image. (Fixed 2026-10-06, rm696 ea07646b6.)
   - USB modes: done in the kernel (USB modes section); mass storage mounts on the Mac since
     `usb-musb-rx-early-packet.patch` (boot 39). In the test image mass storage and Ovi Suite are
     opt-in (`MyDocs/.ramboot/usb-modes`), mass storage read-only; Ovi Suite (MTP) untried.
   - Jobs that fail by design or harmlessly: `cherryui` (the setup wizard, skipped through
     `/var/dont_start_suw`: its state is sealed by BB5), `mxt-configure` (runs as stock since
     2026-10-06, rm696 9ad462fb4: "Small interfaces Harmattan reads"),
     `apps/ondemand-tune` (a tweak on this phone for the ondemand governor; the kernel ran
     schedutil then; ondemand as stock since 2026-10-03, with this tune). `pvrsrv-watch` runs now. Also on this phone, not stock: `apps/min_freq` (600 MHz
     floor) and FasterN9 (syspart.conf cgroup shares, VM writeback on display state).
   - mce's keypad disable path: there since 2026-10-06 (rm696 9ad462fb4).
   - MyDocs' FAT dirty flag is set (a warning at each rw remount of the log writer); an fsck from
     stock would clear it.
5. Not ported yet:
   - Audio: call audio (`cmt_speech` in PulseAudio), Bluetooth SCO, Nokia's ECI remotes and the
     headset button (done since 2026-10-07, rm696 24b20f193: the button works, ECI untested), TV-out
     video, the DAC33's low power mode.
   - FM radio, NFC, and the cameras (reference below). (All ported since: the cameras 2026-10-06, FM
     radio and NFC 2026-10-07.)
   - Video: Xv's scaled overlays in the split update (unscaled only now). (Done 2026-10-04: "Video
     playback".)
   (Since: the DAC33's low power mode in rm696 from 2026-10-07, a listen left; call audio in rm696
   2026-10-08, a call with a SIM left; TV-out works since 2026-10-08, "TV-out"; still open: a call
   through a Bluetooth headset.)
6. Real BB5 as stock: done (2026-10-02, "Secure world / BB5"). My next steps: the eMMC
   read-write (the init's changes must then stay off the eMMC: stock's Aegis would refuse them), later
   a closed-mode kernel (Aegis enforcing). (Both parked by me since.)
7. Battery life: idle blockers found and partly fixed (Performance, "Idle power"); idle drain without
   USB not measured yet (power.txt). OFF mode needs stock's secure RAM save with `omap_hs` (the N9
   DT has no `ti,twl4030-power-idle`). SmartReflex: Harmattan's pmconfig enabled it; here off, to be
   tried with someone at the phone (a wrong voltage would crash it). Boost OPPs untried. (Since:
   SmartReflex on from 2026-10-04, class 1.5 as stock from 10-05; CORE retention and, with Bluetooth
   off, CORE OFF from 10-07; idle drain still not measured.)
8. SGX details only hardware shows: the `ti-sysc` idle quirks, GPTIMER11 (userspace timing), the L3
   bandwidth request `omap_pm_set_min_bus_tput` made.
9. From test boot to replacement: today the kernel is loaded over USB for every boot and Harmattan
   runs read-only. A daily kernel needs it installed (a flash: my decision, with the power
   button broken) and Harmattan read-write (later, my call), with DSME owning the watchdog.

Reference for the remaining ports (stock addresses from Nokia's `board-rm696-peripherals.c`,
github harmattan/kernel-plus-harmattan):
- FM radio: wl1273 at I2C3 0x22, IRQ GPIO 43, reset GPIO 179 or 178 by board revision. 6.18 keeps
  `mfd/wl1273-core.c` but removed the V4L2 `radio-wl1273` (stock's `/dev/radio0`) and the ASoC codec:
  take their last mainline versions. Its audio goes through the dfl61 cards (`dfl61wl1273`).
- NFC: pn544 at I2C3 0x2b, GPIOs 76 (IRQ), 77 (enable), 78 (firmware).
- Cameras, the hardest item: `omap3isp`, `ccs` (ex-smiapp, with the N9 sensors' quirks) and
  `as3645a` are mainline, the main camera has a DT node. The closed userspace (`libomap3camd`,
  `libv4l2media`, gst `subdevcam`, `libFCam`) is built against Nokia's 2011 media/ISP ABI:
  - entities by name: the ISP's match, the sensor's ("smiapp-001".."004") and the flash's
    ("as3645a", a V4L2 subdev on stock, LED class with v4l2-flash here) don't;
  - the lens ("ad5807"/"ad5817"/"ad5836", stock `ad58xx.ko`) has no mainline driver;
  - FCam hardcodes `/dev/video2..6`, `/dev/v4l-subdev0..10` and `/dev/i2c-2`;
  - the front camera (smiapp at I2C2 0x37, CCP2) has no DT node;
  - first compare the `VIDIOC_OMAP3ISP_*`, `MEDIA_IOC_*` and `VIDIOC_SUBDEV_*` structs with
    mainline's uapi, as check-abi.py did for pvr, then choose kernel compat or an LD_PRELOAD shim.
