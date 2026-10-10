# What isn't ported from stock

What stock Harmattan's 2.6.32 kernel gave the N9 that our 6.18 kernel (`../linux_mainline_rm696`,
branch `rm696`) doesn't yet, as of 2026-10-09 (rm696 22d8d4d85). Each item points to where the notes
are (`README.md` sections). What the kernel leaves out on purpose (speed, safety)
is in `REMOVED.md`, not here. Remove an item when it's ported and tested on the phone.
Sources for the ports, local: `../kernel-plus-harmattan` (2.6.32, near stock) and
`../kernel-adaptation-n950-n9` (Nemo's 3.5.3, which already carries ad58xx, smiapp, as3645a,
radio-wl1273, pn544, twl5031-bcc and hci_h4p forward).

Release scope (me, 2026-10-06): the cameras are in the first release (ported the same day,
README "Cameras"). The release waits for calls, video and the cameras (`RELEASE.md`).

## Not ported

- **Around CORE OFF, still open** (CORE OFF works with Bluetooth on and off: "Done" below): the SSI
  (modem) port's garbage word after each CORE OFF wake (harmless since aa4a23614; cause found
  2026-10-08, a stale status the context loss leaves: fixed in rm696 58fde0d17, merged 2026-10-08, I boot it that night), CORE OFF with WLAN associated (untested), stock's OFF tuning (RET 0.8375 V,
  the WDT guard; the oscillator's start-up time is in since rm696 8167154ce, "Done" below, the N9's
  cpuidle latencies since rm696 5b477cdbd, `docs/performance.md`), one unexplained ~40 s stretch of CORE ON seen once
  (`docs/bluetooth.md`; `tests/coresample.sh` names the holder if it recurs). `docs/power.md`. With the
  screen on CORE never retained in rm696 (the display's L3 hold and erratum 1.85's OPP50-only handling):
  stock's idle-time L3 switch is ported, with the WLAN hold dropped (rm696 e16a0248f, merged
  2026-10-08: 208 CORE retentions in 90 s, screen on, WLAN associated, 0 before; `docs/performance.md`).

## There, not finished or never tried end to end

- **Call audio**: PulseAudio's `module-meego-cmtspeech` holds `/dev/cmt_speech`; the earpiece and
  digital-mic paths work without a call (`tests/voicepath.sh`). No real call yet (no SIM). The next item
  in my order. (README "Audio".) In rm696 since 2026-10-08
  (cf6e32591: the peer-reset notice and the control-write wait in `cmt_speech`, stock's SSI ready-pad
  handling around clock changes), tested without a SIM (the modem link's control and speech
  data paths, Harmattan's PulseAudio up to call start; README "Call audio without a SIM"); a real call
  still needs a SIM: `docs/audio.md`.
- **Calls, SMS, mobile data**: the modem is up at the ISI level as stock (csd, sscd `SystemReady`), no
  SIM in the test phone. (README "Modem".)
- **Bluetooth SCO** (headset calls over PCM on McBSP4): the third card `dfl61wl1273` runs on Nokia's
  WL1273 codec since the FM port (rm696 ffb5dcc35): PulseAudio's `sink.hw1` streams to it in BT mode
  (8 kHz mono, `docs/fm.md`). Left: a real call through a Bluetooth headset (needs one, and me).
  (README "Bluetooth".)
- **Bluetooth profiles other than OBEX** (A2DP, HFP/HSP, PAN, DUN): need a paired device and me.
  OBEX send and receive with an Android phone work since 2026-10-07 (below). (README "Bluetooth and
  UART2 idle".)
- **The DAC33's low power mode** (Nokia's "Mode 7 Low Power"): in rm696 since 2026-10-07; Harmattan's
  pre-start selects it again; the FIFO, McBSP gating and PER retention during playback work.
  Left: a listen with headphones. (README "Idle since the cameras, DAC33 low power, charger detection,
  OFF mode".)
- **Charger-type detection** (Nokia's twl5031-bcc): in rm696 since 2026-10-07, with the fix for BME's
  "wrong charger" at unplug: the Mac's port detected as a host port, BME charges at 500 mA.
  Left: a wall charger (`USB_DCP`), unplug and replug, with me. (README "Idle since the cameras,
  ...", "Later the same day".)
- **Ovi Suite (MTP)** USB mode: the `g_nokia` compat is in, untried. USB modes behave as stock (me, 2026-10-08; this phone's setting is SDK): the release needs `g_ether` shipped (not built
  today), the rest is the test harness coming out. (README "USB modes".)
- **wlancond's scan tunables** (2026-10-09): Harmattan's wlancond writes Nokia's
  `/sys/devices/platform/wl1271/scan_size` (channels per scan chunk) and `scan_delay` (ms between
  chunks: a background scan that leaves room for traffic while connected). Mainline wlcore splits
  scans by time in the firmware (`split_scan_timeout`), so the two need a port into wl12xx's scan
  state machine (kernel-plus-harmattan `wl12xx/scan.c`, `main.c`), not just the files. The path
  itself and `allow_adhoc`, `hw_pg_ver` and `bt_coex_state` there are in (branch stock-userspace).
- **wlancond's throughput rules** (Nokia's iptables `condition` match is in): loaded only in a VoIP call
  over WLAN, not tried. (README "Small interfaces Harmattan reads".)

## Power: stock's behaviour not reached yet

- **wlcore's TX power**: never applies mac80211's limits (the regulatory cap, 13 dBm on 5805 MHz in IT,
  after a re-add). Left so by my choice (2026-10-09: no cap, for range); Nokia's NVS
  calibration and wl1271-cal's band-edge clamps apply. (README "CORE/L3 scaling".)
- **CORE OFF**: works with Bluetooth off and on (rm696 aed6f173d; Bluetooth on checked 2026-10-08).

## Off on the test phone, for the release to decide

Not ports, but stock does them and the release has to (the plan in `RELEASE.md`):
Harmattan read-write on the
eMMC (and so CAL writes for persistent secure storage; on the RAM boot received Bluetooth files can't be
saved either: obexd writes to MyDocs), DSME feeding `/dev/watchdog` and `/dev/twl4030_wdt` (6.18:
`/dev/watchdog1`), usb_moded and sshd as stock (plus the root dropbear on port 2222 in SDK mode, my addition, with no key baked in: its authorized_keys is the phone's `/root/.ssh`), Aegis enforcing (closed mode, parked by me).

## Done, though older notes still list it

- The oscillator start-up time (2026-10-08 night, rm696 8167154ce; README "The oscillator
  start-up time"): PRM_CLKSETUP 113 cycles of 32 kHz (3.45 ms) as stock instead of mainline's 10 ms:
  every CORE retention wake 6.6 ms sooner (11.3 -> 4.7 ms), CORE OFF wakes 23.4 -> 16.8 ms, on every
  boot (the PRCM waits it out in retention too). Not checked: the cold, a long standby soak, an N950.
- TV-out (2026-10-08 night, rm696 cf6c40eba; README "TV-out", `docs/tv-out.md`):
  composite PAL/NTSC over the AV jack as stock, Harmattan's own policy and X clone; 6 minutes with 0
  sync losses after the DISPC clock fix (95e3de665: DSS1_ALWON_FCLK, as stock) and the split update's
  bus-lock fix (5fbca8420). Open: omapdss's SYNC_LOST recovery leaves the TV plane off (stock's
  re-enabled it; a fix on kernel branch `tv-recover`, unmerged, untested: no sync loss to test it with).
- CORE OFF with Bluetooth on (2026-10-08, nothing to change; `docs/bluetooth.md`): with
  hci0 up and an inquiry every 20 s, every inquiry complete through CORE OFF (30 and 31 in two runs, 0
  HCI or UART2 errors); the chip wakes the SoC from OFF through GPIO 101's pad and waits for RTS, as with
  stock's pads (no OFF-mode values, as stock).
- ECI remotes and the headset button (2026-10-07, rm696 24b20f193, rebased from branch `eci`
  008084bf6; `docs/audio.md`, README "The jack's buttons and ECI accessories"): Nokia's
  twl5031-aci/eci buttons in `dfl61.c`. A basic headset's button works (KEY_PHONE through
  qmkeyd, the music player pauses and resumes). Not checked: an ECI remote (none here), CORE
  retention with a headset in and USB out.
- CORE OFF (2026-10-07 late night, rm696 aed6f173d; `docs/power.md`): ~700 CORE OFF entries in
  10 min unplugged, clean wakes (RTC alarm, keys), DVFS live, BB5 secure services and the modem link
  working. Nokia's TWL5031 scripts and remaps, IO pad wakeups, erratum 1.45, the mailbox, the reboot as
  stock (global software reset: mainline's DPLL3 reset ran the TWL's sleep script), every pad as stock.
- NFC (2026-10-07, rm696 34c9fae34; `docs/nfc.md`): stock's PN544 driver (`/dev/pn544`, Nokia's
  char device that Harmattan's libNFCDAL/nfcd use), firmware download mode refused unless
  `nokia_pn544.allow_fw_mode=1` (`REMOVED.md` section 4). nfcd starts once (the boot-time
  restart loop is gone), my Android phone detected and read twice, NFC on/off through mce as
  stock. Not checked: an NDEF tag's content, CORE idle unplugged with NFC off (the chip is off).

- FM radio (2026-10-07, rm696 ffb5dcc35; `docs/fm.md`): Nokia's own WL1273 drivers from Harmattan
  (core, `/dev/radio0`, the "dfl61-wl1273" card's codec with stock's "Mode Switch"/"Codec Mode"/"Audio
  Switch"), the interface fmrxd (the community FM apps) and Nokia's test servers use; Bluetooth SCO
  through the same codec. Tested: tuning, seek, RDS (PI and station name, 0 errors), 48 kHz capture
  over McBSP4 after fmrxd's HCI mux command; I heard Radio 1 on 88.1 MHz in Nokia headphones.
  Not checked: CORE retention unplugged with FM off, a BT headset call through the codec.

- Bluetooth (2026-10-07, rm696 ccfc3678b; README "Bluetooth and UART2 idle", `docs/bluetooth.md`,
  `docs/bluetooth.md`): UART2 no longer stuck active after a power-off, UART2 and CORE idle with
  Bluetooth on (CORE retains as often as with it off), a transmission ended from a timer as stock, the
  N9 connectable after a connection (scan mode kept for BlueZ 4), 3.69 Mbaud as stock (~225 KB/s each
  way in loopback); OBEX send and receive with an Android phone.
- CORE retention in standby (2026-10-07, rm696 552122361; README "CORE retention found: the watchdog",
  "Later the same day"): WDT2 in force idle as stock, I2C idle after each transfer; unplugged with the
  display off CORE retains ~130 times a minute and spends nearly all the time in RET. Erratum 1.85
  workaround 2 is in with it.
- Cameras (2026-10-06, rm696 fe27ef0a9, me: "consider camera as ported"): both cameras, viewfinder,
  switching, stills (camera-ui 8/7 Mpixel and smaller, the Qt app) and 720p video at 30 fps, with
  Harmattan's own camera stack; README "Cameras" and "Cameras: the DSP stage and the stills". The flash
  fires and autofocus works (my Qt app, the sensor drivers as modules since rm696
  22d8d4d85). camera-ui stays in standby on test boots: MyDocs is read-only there (qmsystem's
  `access()` check reads that as mass storage in use).
- Small interfaces Harmattan reads (2026-10-06, rm696 9ad462fb4; README "Small
  interfaces Harmattan reads"): mce's keypad disable path
  (`i2c-1/1-004a/twl4030_keypad/disable_kp`) and USB cable file (`i2c-1/1-0048/twl4030_usb/vbus`),
  `/sys/devices/omapdss/display0/hw_revision`, Nokia's touch configuration files (`mxt-configure` runs
  as stock; `backup_config`, the NVM write, left out: `REMOVED.md`), Nokia's iptables `condition`
  match and `CONDITION` target. Stock's touch report limit is left out on purpose (`REMOVED.md`).
- Xv scaled overlays: scaled video plays (README "Video playback", item 3), my
  Baseline 720 clips too (README "Video: my clips").
