# Display

The N9's panel (the SMD "Pyrenees", 854x480 in landscape) runs as on stock: a DSI command-mode panel
under omapfb with Nokia's interfaces, so Harmattan's X driver, mce and the SGX driver work unchanged.
Landscape updates go out in two halves timed from the panel's tearing-effect (TE) line, as Nokia's
driver sent them, and the DSI link drops to ULPS half a second after the last update.

## How it fits together

| Part | What |
|---|---|
| Panel | SMD Pyrenees (DCS ID1 `fe`), a 480x864 portrait frame of which 854 rows are shown (DCS partial mode, as stock); `lcd0` in `omap3-n9.dts`, label `lcd` |
| Link | DSI command mode, two data lanes, 221.76 MHz DDR; omapfb's `panel-dsi-cm` driver, extended for the N9 |
| Landscape | DT `rotation = <90>`: DCS address mode 0x60 (the panel exchanges rows and columns), stock's `rotate` 1 |
| Framebuffer | fb0 854x480 RGB565, virtual 856x1536 (three buffers), `omap2fb.vram=0:2629632` in the built-in command line, as stock |
| Video memory | a 14 MiB DT carveout (`omapfb_vram`) for fb0 and Harmattan's Xv buffers (six 1280x720 16 bpp ones), stock's VRAM (`8c25e4128`) |
| DISPC clock | DSS1_ALWON_FCLK, 172.8 MHz core and 43.2 MHz pixel clock, as stock (`95e3de665`); at least 4x the pixel clock for Xv downscaling (`CONFIG_FB_OMAP2_DSS_MIN_FCK_PER_PCK=4`) |
| TE | GPIO 62, rising edge; its interrupt is `taal vsync` in `/proc/interrupts` |

What Harmattan's X driver (`fbdev_drv.so`), the SGX's `omaplfb` and mce need from omapfb:

- Nokia's DSS notifier (`d75b49787`): the SGX driver's flips complete on it.
- `update_mode` per display (`bc50f2992`): 2, manual update, for the panel.
- Displays named `lcd` and `tv`; `rotate` and `mirror` readable; `timings` as the unrotated panel
  frame, since X applies `rotate` itself (`410f27c56`).
- Overlays that detach from a manual-update display while no update runs (`5016007f2`), and a 0x0
  mode accepted for the empty overlay framebuffers.
- `/sys/devices/omapdss/displayN` as in 2.6.32, linking to the panel device (`5d2a14a7d`), and
  `hw_revision` from the IDs read at power on, so it reads also with the panel off (`46b12ba97`).

Under Harmattan every update is asked for by userspace with `OMAPFB_UPDATE_WINDOW` (X, and before X
the boot image of `preinit`); the driver never starts one itself. X page-flips between fb0's three
buffers, each flip is one panel update, and the client's swap completes on the DSS notifier, so
drawing is clocked by the panel.

## Landscape updates in two halves

The panel scans its 864 rows, which in landscape are the picture's columns, while an update writes
across them; a whole frame written at once always crosses the scan line, a diagonal tear even with
TE. Nokia's driver (`panel-nokia-dsi`) writes each half of the picture while the scan is in the other
half, and so does this one (`5f70ea330`):

- TE is moved to mid-scan (`SET_TEAR_SCANLINE` 432), stock's "reverse" scheme for the Pyrenees
  (`split_reverse` 1). The left half goes out at TE, the right half from a timer at 52% of the
  measured TE period. Each half takes 6.0-6.1 ms of the 16.7 ms period.
- Stock timed the second half for 46 fps (the panel slows down with ACL), which at 60 Hz ends it past
  the next TE and halves the update rate; here the timer follows the measured period.
- The frame is latched when it's asked for, as Nokia's `omap_dss_lock_cache()` did (`051cd6fbb`,
  `region_latch` 1): the overlays are taken then and the manager counts as updating until the second
  half is out, so X's pan to its next buffer waits and X's notification comes once the frame is out.
- An update asked for up to 2 ms after TE (`split_late_us`) still starts its first half at once if the
  slowest recent first half fits before the scan comes back (`8535169e2`: that peak fades by 1/32 a
  frame); otherwise it would wait a whole frame and the previous frame would show twice.
- A second half whose window write ended after its timer goes out at once if it still ends before the
  next TE (`acf559359`), not a frame later with the two halves from different frames. The window
  write runs on the high-priority workqueue.
- Scaled overlays (Xv video) are cut in proportion, the cut rounded to even as Nokia's
  (`59c9d7b80`); the horizontal blanking checks are skipped for a manual-update display, as Nokia's
  omapdss did (`107293d56`).

Measured on home-screen flicks and page swipes: 91-94% of frames on time. Scaled video plays without
halves a frame apart.

## ULPS and the TE line

- 500 ms after the last update (`ulps_timeout`, stock's board value) the link enters ULPS: TE off at
  the panel (`TEAR_OFF`), the TE interrupt disabled, the DSS runtime-suspended. The panel keeps
  showing the picture from its own memory.
- The next update leaves ULPS: the TE interrupt is enabled before the DSI comes up, then `TEAR_ON`.
  As stock, no TE counts from `TEAR_OFF` to `TEAR_ON`, and the first TE after `TEAR_ON` is skipped (the
  first two at power on: the Pyrenees sends a few irregular ones then). The first frame after a pause
  goes out at the second real TE, 17-33 ms after `TEAR_ON` (`592e0d149`). Before, a TE edge latched
  while the interrupt was off was replayed by `enable_irq()` at a random point of the scan and taken
  for a TE, so the first frame after a pause started out of step and could tear.
- Mainline slept 100 ms at every TE enable and disable, so at every ULPS exit and entry; Nokia's
  driver did that only for the Taal panel. Not for the Pyrenees any more (`8eedc154f`): the first frame
  after half a second without updates had been about 110 ms late.

## NOLO's boot logo

NOLO leaves its logo on the panel, the link in ULPS, and passes `omapdss.def_disp_enabled`. As stock,
the kernel takes the running panel over instead of resetting it (`f4cfe3111`): no panel reset at probe
(`147cff13e`), NOLO's ULPS left by hand at the first DSI enable (`679e31b7c`), then the panel's power
mode and brightness are read back. The log says `keeping NOLO's display (power mode .., brightness
..)`, or `NOLO's display is gone` and the panel gets a full power on. The framebuffer is RGB565 from
boot, so `preinit` draws its boot image (`a2e408b6a`), and has stock's geometry, so X doesn't
reallocate fb0 (`ea07646b6`). The screen goes from NOLO's logo to Harmattan's boot image to X without
a black gap.

## mce's controls and the standby screen

mce finds the panel at `/sys/class/backlight/display0` (brightness by DCS) and its controls under
`device/`:

| File | What |
|---|---|
| `brightness` | DCS brightness, 0-255 |
| `device/lpm` | low power mode for the standby screen: DCS idle mode (8 colours, a lower refresh rate), entered 300 ms after the last update so the standby clock is drawn first |
| `device/dimming` | the panel fades brightness changes |
| `device/hbm` | high brightness: 0 off, 1 400 cd/m² with ACL 80%, 2 the Pyrenees' 500 cd/m² with ACL 70% (stock's values) |

Screen timeout, dimming, blanking, the lock screen and the standby screen behave as on stock; mce's
colour profile (DISPC CPR) applies.

- **L3**: the display holds L3 at OPP100 while the DSS runs and while the panel is on outside low
  power mode, as stock's 500000 KiB/s request (`31d2b2475`). Unlike stock, the standby screen doesn't
  hold it, since the panel refreshes from its own memory; `l3_lpm_hold` 1 holds it there too. With the
  screen on and still, L3 is lowered inside the idle path while the DISPC isn't fetching (`ff7ed3abd`,
  `e16a0248f`), so CORE retains with the screen on (see [Power](./power)).
- **Idle latency**: while the panel is on outside low power mode, a CPU latency QoS request of
  `idle_latency_us` (6000), stock's PM optimizer's display rule. It keeps CORE OFF out and lets CORE
  retention in.
- `0790e6776`: the DSI PLL's input clock was never released when the display went off; the DSS power
  domain stayed on and CORE never retained.

## Diagnostics and tunables

On the panel device, `/sys/class/backlight/display0/device` (the same as
`/sys/devices/platform/68000000.ocp/48050000.dss/4804fc00.encoder/4804fc00.encoder:panel@0`):

| File | Default | What |
|---|---|---|
| `update_stats` | | frame pacing counters (below); any write clears them |
| `split_timing` | | `te` (the measured TE period), the last and peak first and second half, in µs |
| `split_reverse` | 1 | TE at mid-scan with the first half at TE (stock's Pyrenees scheme); 0: TE at the frame start, the first half from the timer |
| `split_mid_us` | 0 | µs from TE to the timer; 0 is 52% of the TE period in reverse mode, 50% otherwise |
| `split_right_first` | 0 | the right half first instead of the left |
| `split_late_us` | 2000 | how long after TE a first half may still start; 0 off |
| `region_latch` | 1 | latch a frame when it's asked for, as stock; 0 at its first half |
| `ulps` | | 1 while in ULPS; write 1 to enter, 0 to leave |
| `ulps_timeout` | 500 | ms from the last update to ULPS; 0 never |
| `idle_latency_us` | 6000 | the CPU latency limit while the panel is on outside low power mode; 0 none |
| `l3_lpm_hold` | 0 | 1 holds L3 in the standby screen too, as stock |
| `num_dsi_errors`, `hw_revision` | | the panel's DCS error count (wakes the link); its IDs, e.g. `fe.91.96` |

`update_stats` fields:

- `1: 2: 3: 4+:` frames by TE periods since the previous frame (1 is 60 a second); `pauses`: over
  100 ms.
- `requests at TE+`: when update requests came, after TE.
- `late starts`: first halves started after TE (`split_late_us`).
- `early pans (kept|replaced)`: frames a flip changed between request and first half; `blocked`:
  updates that waited over 1 ms for the DSI bus (X stalls meanwhile).
- `halves late`: `1st over` first halves that ended after the scan came back; `2nd missed` second
  halves not ready at their timer, `out late` those of them still sent in the same frame; `2nd over`
  second halves still going at the next TE.

```sh
P=/sys/class/backlight/display0/device
echo 0 > $P/update_stats            # clear, then use the phone
cat $P/update_stats $P/split_timing
grep "taal vsync" /proc/interrupts  # TE pulses: 60 a second while the link is up
```

## Gotchas

- **Redraws while idle come from userspace.** The kernel draws nothing on its own. On one test phone,
  a modified sysuid's network-speed readout (every second) and a status-bar theme that doubled the
  charging animation's rate kept the display busy; each redraw costs a ULPS exit, a frame and 500 ms of
  the DSS clocked. `update_stats` shows the pace.
- About 1% of TE pulses arrive 1.6-6 ms early and the next interval is that much longer (pairs add up to
  two periods), so the scan stays on schedule. Not handled; stock didn't either.
- The DSS interrupt line is shared by the DSI and DISPC handlers, so a trace shows each hardware
  interrupt twice; a split update raises about 4.
- A lone "Framedone not received" costs one frame. A stalled half used to give the DSI bus lock back
  twice, then unlocked updates and a panic (`5fbca8420`).
- omapfb's module is `omap2fb`: `omapfb.*` parameters do nothing.

All display commits: `git log --no-merges v6.18.55..rm696 -- drivers/video/fbdev/omap2` in the
kernel. TV-out shares the DISPC: see [TV-out](./tv-out).
