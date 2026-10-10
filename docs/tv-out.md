# TV-out

Composite video, PAL or NTSC, over the AV jack works as on stock: plug a TV-out cable and Harmattan
clones the screen to the TV, with the standard and aspect ratio from Settings. Tested with a TV: six
minutes of picture without a sync loss, a video from the Videos app, PAL/NTSC and the aspect ratio
switched from Settings, and the unplug. After a sync loss the TV stays dark until the cable is
replugged.

## How it works

The kernel only switches the jack to video and reports the cable; Harmattan turns the TV on. The
chain is stock's:

1. **The jack.** At each plug the TWL5031 card of Nokia's `dfl61` machine driver sets TVOUT_EN
   (GPIO 40) low and classifies the plug. A video cable (mic line below 500 mV; the tested cable read
   about 99 mV) gets TVOUT_EN high, then the jack reports `SND_JACK_AVOUT` (`SW_LINEOUT_INSERT` and
   `SW_VIDEOOUT_INSERT`) on the input device `dfl61-twl4030 Jack`. The kernel log says
   `AV jack: video cable (...)`. An unplug leaves TVOUT_EN as it is.
2. **ohmd** (the accessories plugin) takes `SW_VIDEOOUT_INSERT` without `SW_JACK_PHYSICAL_INSERT` as
   "tvout". Its policy routes video to the screen and the TV, with the standard and aspect from GConf
   (`/system/tvout/encoding`, `pal` by default; `/system/tvout/aspectratio`, `wide`). The Settings
   applet only writes those keys: there is no on/off switch, the cable is the switch.
3. **ohmd's videoep** asks X through XRandR: output `TV`, CRTC 1, mode 854x480, properties
   `SignalProperties` and `TVAspectRatio`.
4. **Nokia's X driver** sets omapdss up: a video plane (`OMAPFB_SETUP_PLANE` on `/dev/fb2`) showing
   fb0's memory, moved to the `tv` manager, then `display1/timings` (`pal` or `ntsc`),
   `display1/enabled` 1 and `display1/wss` (widescreen signalling: 8, 7, 1, 11 for PAL 4:3, PAL 16:9,
   NTSC 4:3, NTSC 16:9). At an unplug or DPMS off: the plane off, `display1/enabled` 0.

On the TV: PAL 720x574 at a 13.5 MHz pixel clock, the 854x480 screen scaled to 645x516 in the frame,
WSS 16:9. Views in portrait show sideways, as on stock.

X needs `display0` to be `lcd` and `display1` to be `tv`, with manager N on display N; the probe order
gives that.

## The kernel side

The `tv` display is omapfb's VENC with the analog TV connector (`composite-video-connector` and the
VDAC, 1.8 V, in `omap3-n9.dts`). Its register tables are the same as Nokia's DSS2 VENC. What it took:

| Commit | What |
|---|---|
| `9d625f491` | VENC starts with PAL timings. A `display1/wss` write before the first enable hit a `BUG()` with VENC's lock held (a mainline bug; stock set PAL at probe) |
| `e455ff905` | L3 held at OPP100 from VENC's power on to its power off, as stock's request for any started display: the TV fetches from SDRAM all the time |
| `f8a8d6628` | the 3630's VENC takes the 96 MHz TV DAC clock (`dss_96m_fck`) too. omapfb took it on the 3430 and AM35xx only, so the clock framework could stop DPLL4's 96 MHz output under VENC |
| `cf6c40eba` | the TWL5031 card drives TVOUT_EN as stock. The DT had hogged it low, so the jack stayed in audio mode |
| `95e3de665` | the DISPC on DSS1_ALWON_FCLK, as stock. On the DSI PLL it lost its clock at every ULPS entry of the panel: "SYNC_LOST on channel tv" at each update after a pause |
| `5fbca8420` | after the sync losses, a stalled half of a panel update gave the DSI bus lock back twice: unlocked updates, a warning flood, then a panic. Now once |

Clocks, as stock: `dss_tv_fck` 54 MHz (DPLL4's M3 divider 16, as NOLO leaves it; stock relied on NOLO
too) and `dss_96m_fck` 96 MHz.

Headphones still classify as headphones, and TVOUT_EN stays low for them.

## Checking it

As root, with debugfs at `/sys/kernel/debug`:

```sh
D=/sys/devices/platform/omapdss
cat $D/display1/name $D/display1/enabled $D/display1/timings  # tv; 1 with a TV cable in
dmesg | grep -i "AV jack\|SYNC_LOST"
grep tvout /sys/kernel/debug/gpio                    # gpio-40: hi with a TV cable in
cat /sys/kernel/debug/clk/dss_tv_fck/clk_rate        # 54000000
cat /sys/kernel/debug/clk/dss_96m_fck/clk_rate       # 96000000
cat /sys/kernel/debug/omap3_l3                       # the dss hold while the TV is on
```

At an unplug `display1/enabled` goes back to 0, the L3 hold goes and CORE retains again in standby.

## Limitations

- **After a sync loss** ("SYNC_LOST on channel tv") omapdss's recovery leaves the TV's plane off, and X
  doesn't set it up again; stock's error handler turned it back on. Replug the cable. Since the DISPC
  clock fix nothing has caused a sync loss in testing; a fix (turning the planes back on after the
  restart) was written but isn't merged, since without a sync loss it can't be tested.
- NTSC was switched from Settings during the test but not confirmed in the logs.
- Writing `display1/timings` turns the TV on (6.18 disables, sets and re-enables); stock applied them
  only to a running TV. X writes them right before enabling the display, so Harmattan isn't affected.
- Stock's debugfs `avswitch` isn't there; only Nokia's factory test servers used it.

The LCD side of the DSS: [Display](./display). The jack's audio side: [Audio](./audio).
