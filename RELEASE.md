# Release: a flashable 6.18 kernel for the Nokia N9

The plan for turning the RAM-boot test kernel (`../linux_mainline_rm696`, branch `rm696`) into a kernel
I flash to the N9's kernel partition and run day to day, Harmattan read-write on the eMMC, the
RAM overlays and the test harness gone.

**I run every step of the procedure below by hand.** Flashing, powering off and writing the eMMC
are never scripted: my test phone's power button is broken, so a bad flash couldn't easily be
recovered. This file is the procedure for when I decide to go ahead.

## Do not start until these hold

1. **Calls work with a SIM** ([Audio](docs/audio.md), [Modem](docs/modem.md)): call audio passed SIM-less, but a real
   call is untested. The release waits for it (me, 2026-10-04).
2. **Video works**: done (NOTES.md "Video playback", "Video: my clips").
3. **Cameras work**: done (NOTES.md "Cameras"); in the release (me, 2026-10-06).
4. I have **decided to run Harmattan read-write on the eMMC** (parked today) and to flash. Until
   then the release can't even be built: the whole point is dropping the read-only overlays.

(4: read-write decided 2026-10-09, see below; the flash is still my call.)

## Status (2026-10-17)

- **The image**: `RELEASE=1 kernel/build.sh` -> `build/zImage-n9-release`. Kernel: rm696 = bcac265b3 since 2026-10-17
  (me: "ok so merge everything"): the WLAN chip runs Nokia's driver with stock's firmware (5 GHz standby 18 mA,
  wlcore drew 119; `NOTES.md`, "WLAN: Nokia's driver and stock's firmware"), stock's ELP and SD-slot idle delays,
  the stock C7 (9066b7305); before: 0ffa2dc43, 2026-10-10 (v6.18.55 merged, the OFF-mode fixes of 592e0d149;
  before: 4c925f7a5, 2026-10-09 16:35 (me: "the main kernel repo should only have the last working state to be
  pushed": release-image fast-forwarded into rm696, every other branch deleted, kept in
  `~/n9-backup/2026-10-09/kernel-branches-before-cleanup.bundle`; 4c925f7a5 = 777e7d932 + `README.md`).
  On rm696 22d8d4d85: 4a49c49ed (`g_ether` =m),
  e31461965 (u_ether messages without a gadget), b8b84a9ed (gadget debug off), 03b14d1de (gpio sysfs
  `name`), 1ffbf0536 (NOLO's `gpio=` boot parameter), 777e7d932 (musb early-packet fix). Ramdisk:
  `ramboot/release-init` (this repository's `release-image` branch, unmerged).
- **Step B (the day of RAM-boot use) started 14:08 on 777e7d932**. Checked on that boot: rescue SSH on the
  cable only (WLAN 2222 closed), `usb_moded`'s `g_ether` with `usb0` 192.168.2.15, stock sshd on 22,
  DSME holds both watchdogs, OneNAND writable as stock, MemTotal 1,002,732 kB and 256 MB swap, rootfs rw
  as NOLO mounts it, modem up (no SIM), no oops.
- **Found on the release boots, fixed**:
  - the modem didn't power on after a clean reboot ("SSI connection DOWN", `csd` spinning, "problem with
    the SIM"): NOLO's `gpio=` lines (`cmt_*`) weren't requested and exported for udev's `/dev/cmt` links
    -> 1ffbf0536, 03b14d1de;
  - an oops at a cable replug (u_ether's `eth_stop` debug message with the gadget gone) -> e31461965,
    b8b84a9ed;
  - the USB network dead after a replug (phone to Mac fine, nothing back): our musb work for an OUT
    packet that came before its request ran softirqs mid-giveback and lost the next packet's interrupt
    -> 777e7d932 (reproducer: `usb0` down/up in a loop with the Mac on the cable; stuck in round 6
    before, 20/20 after);
  - the rescue server: stock's SDK-mode ids (0x0421:0x0519) so the Mac reuses its interface, interface
    `rescue0` so `usb_moded` gets `usb0`, keys through a ramdisk bind (dropbear refuses keys under
    Harmattan's group-writable `/`), pstore records kept in `/var/lib/n9-618/pstore/<date>/`.
- **Seen once, not reproduced**: a panic at 336 s on the debug image (NET_RX softirq count off, a smashed
  IRQ stack) during a `usb0` down/up loop with htop open; the same mix again ran clean.
  Records in `build/pstore-htop/`. If the phone resets during the
  day, its record is in `/var/lib/n9-618/pstore/<date>/`.
- **Same as stock** (checked against stock boots in syslog): the setup wizard's `cherryui` SIGSEGV at
  boot (no `/var/lib/cherry/state`), "maximal mount count reached" (stock ignores mount counts too),
  preinit's "Root filesystem state ok", `ModemState=Tablet SimState=Missing` without a SIM, WLAN not
  reconnecting after a reboot (my setting).
- **Debug variant**: `RESCUE_ANY=1` -> `build/zImage-n9-release-debug`, the rescue server on every
  interface (WLAN too, still key-only): for debugging the USB link itself, never distributed.
- **Publication** (2026-10-09 afternoon): the public documentation is the VitePress site in `docs/`
  (install, rescue SSH, build, status, the kernel; `REMOVED.md` and `FIRMWARE.md` included as they
  are). `kernel/build.sh` builds on any Linux machine (`BOX=local`, the default there; a first build
  needed `vmlinux` before `modules_install`, fixed) with Alpine pinned to v3.24; the kernel has a
  `README.md` (release-image). My working notes are folded into the docs (hardware, GPU, power and
  performance pages, 2026-10-10) and stay out of the published history. Published under
  github.com/zsavajji: `rm696_mainline_port` (this kit), `linux_mainline_rm696` (the kernel) and
  `pvr_sgx_rm696` (the SGX driver); the commits are blackbird5308@gmail.com's in all three.
  Licence (me, 2026-10-09): MIT for the kit, `LICENSE`; `tests/camera/nokia-media.h` stays
  GPL-2.0, as does the SGX driver, its own repository (`pvr_sgx_rm696`) since 2026-10-10.
- **The day of use (2026-10-09 evening to 2026-10-10)**, found and fixed, all in rm696 (see the docs'
  [Power](docs/power.md), [Performance](docs/performance.md), [Display](docs/display.md)):
  - standby drain far above stock: OFF mode was never armed on the N9 (0a14c7129, armed at boot from
    `pmconfig` now) and wl12xx kept mainline's 1500 ms power-save timeout (1839014b6, 100 ms as stock);
  - `devel-su` root had no capabilities: Aegis set SECURE_NOROOT under a policy even in open mode
    (85f673cc2);
  - typing lagged and fast typing queued up: after the first CORE OFF the SDRAM stayed in
    self-refresh at every pause, about 3x slower, because the SDRC_POWER restore was gated on the 3430
    (75eaae875; confirmed live: random loads 695 -> 211 ns, typing fine);
  - CORE never reached retention again after a wall charger was unplugged (1c87ecc8b);
  - the panel slept 100 ms at every TE switch and timed the first frame after a pause from a replayed
    TE edge (8eedc154f, 592e0d149, both as stock);
  - not a kernel bug: CAL writes fail because NOLO locks CAL for unsigned kernels, as on stock's open
    mode; nothing is written.
  Image 592e0d149 booted 2026-10-10 14:37; linux-stable v6.18.55 merged after it (c8d5deece, README
  0ffa2dc43), built, not booted yet.
- **Checked on 592e0d149 (2026-10-10, cable out)**: after 812 CORE OFF entries SDRC_POWER still reads
  0x9 and 8 MB random loads take ~240 ns (the slow mode was ~700); 14 min unplugged: 334 CORE OFF / 986
  RET; on a wall charger CORE kept retaining, and after its unplug too (+417 RET in 5 min, musb stayed
  suspended).
- **Next**: 6.18.55 (0ffa2dc43) on the phone; a stock boot, to see stock clean after read-write use;
  then the flash decision (mine).

## My decisions (2026-10-09)

"I want the harmattan.patch to become kernel fixes, 100%, I want this to behave stocklike." These
supersede the sections below wherever they differ:

- **No Harmattan file is changed, not even through a bind mount**: every hunk of
  `ramboot/harmattan.patch` becomes a kernel fix, and the test-only hunks (boot watchdog off, `|| true`,
  DSME's verbosity, sshd off) just go: stock's sshd keeps port 22 since dropbear moves to 2222. What
  stays outside the eMMC's stock files is additive: our kernel's modules under `/lib/modules/<6.18>`.
  The kernel side, hunk by hunk: zram as stock's `ramzswap` (`modprobe ramzswap` + `rzscontrol
  /dev/ramzswap0`, which `enable-swap` runs under `sh -e`); the eMMC as `mmcblk0` (stock's fstab,
  `mount-home`, `preinit`'s `check_rootfs`); `wl1271-cal`'s NVS push and `modprobe wl12xx` bringing up
  the SDIO chip; PulseAudio's pre-start finding McBSP and `pmdown_time` at stock's sysfs paths;
  Bluetooth firmware at stock's names.
- **Power-off, charging while off (ACT_DEAD) and alarm power-on, all three as stock.** The N9 DT deletes
  `ti,use_poweroff` today (the test phone's fail-safe); the release powers off. Test boots on the test
  phone keep a halt instead, at least until I say otherwise (its power button is broken).
- **The eMMC is `mmcblk0`, as stock** (a DT alias; NOLO already passes `root=/dev/mmcblk0p2`).
- **The TWL watchdog built in, both watchdogs fed by DSME** at stock's device names.
- **CAL writes as stock** (OneNAND's config partition; section 1's "OneNAND is never written" no longer
  holds for the release; test boots stay read-only until I say otherwise).
- **Rescue dropbear** (2026-10-09): kept, so ssh works even when Harmattan doesn't come up. The
  ramdisk starts it as soon as the eMMC root is mounted, before `preinit`: port 2222, bound to the USB
  address only, keys from the phone's own `/root/.ssh/authorized_keys` (`-D /newroot/root/.ssh`, read
  at each login; ed25519, RSA, ECDSA), landing in the ramdisk's shell with Harmattan at `/newroot`.
  The ramdisk brings up its own SDK-mode USB network at boot and hands the port to `usb_moded` when
  that loads a gadget. Password access configurable: `/root/.ssh/dropbear-password` (root-only)
  present = root's own Harmattan password too (copied from `/newroot/etc/passwd` at boot: Harmattan
  has no shadow, traditional DES), refused while it is still the factory `rootme`. No key or password
  in the image.
- **This phone already runs a flashed unsigned kernel** (found 2026-10-09): the community open-mode
  PR1.3 kernel with the L2 cache fix (`2.6.32.54-dfl61-20121301 (juice@alaspin)`, built 2013-03-02 from
  `kernel-2.6.32-openmode_l2`; the dump of 2026-10-01, `build/stock/mtd2.bin`, kept with the backups as
  `~/n9-backup/2026-10-09/mtd2-kernel-openmode_l2.bin` and `zImage-openmode_l2-2.6.32.54`). So NOLO
  boots a flashed unsigned kernel here, and the phone is in open mode already. **Its revert image is
  that kernel, not the FIASCO's**: with thp's ACT_DEAD fix (below) a closed-mode kernel ends in MALF.
- **thp's ACT_DEAD fix stays** (https://thp.io/2025/n9-actdead.html, applied by me): Harmattan's
  `/sbin/getbootstate` is a script that always says `USER` (the original kept as
  `/sbin/getbootstate.orig`), so a charger or cable boots the phone to its UI, never to ACT_DEAD; with
  no power button that's how a powered-off phone comes back (our power-off keeps the charger start-on
  events, as stock). Not part of the release: it's this phone's. ACT_DEAD can't be tested here.
- **The unsigned kernel**: "we'll see"; I am open to reflashing. kernel-plus-harmattan, an
  unsigned modified kernel, booted flashed on the N9 (with warnings).

## How the release image differs from the test image

The test image (`ramboot/init`, `kernel/build.sh`) is built for safety on a phone that can't be flashed:
read-only disks, a 10-minute watchdog session, writes only to a MyDocs log. The release inverts all of
that. Each change below is a build/init change to make, not yet made.

### 1. Boot the eMMC, not overlays

- **`switch_root` into Harmattan on the eMMC**, read-write, instead of `chroot` into a tmpfs overlay
  (`ramboot/init:128-275`). The initramfs becomes a thin early-boot stub: mount the real rootfs
  read-write, apply the Harmattan init adjustments as **bind mounts from the initramfs** (not `patch`
  into an overlay — stock's kernel enforces Aegis and must still boot the untouched eMMC files), then
  `switch_root`.
- The read-only guards go (`ramboot/init:63-74, 117-118`: `blockdev --setro`, the "not read-only, not
  booting" refusal). `onenand-read-only.patch` stays (OneNAND is never written; it holds CAL, see
  FIRMWARE.md "Per-device data").
- `check_rootfs` in `preinit` runs again (the test image's `harmattan.patch` comments it out at
  `sbin/preinit`): on a real read-write rootfs it must fsck/repair as stock.

### 2. The test harness comes out

- **The watchdog session** (`ramboot/init:14-38`): gone. **DSME feeds the watchdogs** as stock. 6.18
  names the TWL watchdog `/dev/watchdog1` where DSME opens `/dev/twl4030_wdt`; the hardware WDT2 the
  OMAP core wants is another node. Make the names DSME expects (udev rule or symlinks) and confirm DSME
  opens both and `/dev/iphb` with no "failed to open kernel connection".
- **The MyDocs log writer and `power.txt`** (`ramboot/init:76-113`): gone. MyDocs mounts read-write as
  stock (it's my data partition).
- **`harmattan.patch`'s test-only hunks revert to stock**: `boot-watchdog` back on, `group-dsme` and
  `group-mce` without the `|| true` carry-on, DSME back to default verbosity, the `reboot` stanzas
  (`ramboot/init:211-213`) left in place. Keep only the hunks that are real 6.18 ports: zram for swap,
  the wl1271-cal NVS path, the PulseAudio McBSP/DAC sysfs paths (`ramboot/harmattan.patch`). Those
  belong on the eMMC as persistent edits or initramfs bind mounts — decide which (bind mounts keep the
  eMMC files stock, which Aegis prefers).
- **`var/dont_start_suw`** (`ramboot/init:195`): the setup wizard. On my own already-set-up
  phone, leave it skipped; for a clean redistributable image this is a real first-boot step — open
  decision, tied to Aegis/BB5 state.

### 3. sshd and USB as stock, plus my dropbear addition

- **sshd as stock**: restore `start ssh` in `group-mce` (the test patch comments it out). Stock's sshd
  owns port 22.
- **USB modes as stock** (me, 2026-10-08): `usb_moded` applies the Settings mode (SDK on this
  phone); mass storage (MyDocs read-write), Ovi Suite (MTP) and charging only behave as stock. The
  test init's USB routing, the read-only MyDocs export and the SSH-gadget keepalive
  (`ramboot/init:161-192, 232-272`) all go. **`g_ether` must ship**: `CONFIG_USB_ETH=m` in
  `rm696.config` and in `kernel/build.sh`'s module list (today only `g_nokia` and `g_file_storage`
  ship; the test init stood in for `g_ether` with its own configfs gadget).
- **The dropbear addition** (me, 2026-10-08, "update SDK so it allows me to go directly through
  your dropbear"): keep a root dropbear reachable in SDK mode, **over USB only**, key-only (`-s`), on
  **port 2222** (stock's sshd keeps 22). Its keys come from the phone, not the image:
  `dropbear -D /newroot/root/.ssh` — Harmattan's own `/root/.ssh/authorized_keys` (root's home in
  stock's passwd), which only root can write (`devel-su`). Read at each login, so a key changes without
  a rebuild; no file, no login. `ssh -p 2222 root@<usb-ip>` with the key the owner installed. Port 2222
  so stock's sshd keeps 22.

### 4. No secrets baked into the image (it is redistributed)

I redistribute this image, so nothing per-device or secret may be compiled in.

- **No SSH key**: drop `kernel/build.sh:92` (it copies `build/ramboot-key.pub` into
  `/root/.ssh/authorized_keys`); dropbear reads the phone's own file instead (3 above). The release
  must never carry `build/ramboot-key*`.
- **A fresh RNG seed per device, not per build**: `kernel/build.sh:143-151` bakes one random
  `rng-seed` into the DTB and reuses it on every boot of that image (marked `ponytail:` there, fine for
  a test image). A redistributed image sharing one seed across phones is not fine. Options: drop the
  baked seed and let the kernel gather entropy (dropbear may block for minutes at first boot, the reason
  the seed exists — the OMAP3630 has no cycle counter for jitter entropy and the N9's RNG is off), or
  have first boot write a per-device seed to the eMMC. Decide with me.
- **No per-device firmware or calibration** in the image: FIRMWARE.md "Per-device data" — WLAN NVS and
  camera calibration stay on the phone and are read at run time. The release already does this; keep it.
- **Nokia firmware is not redistributable** (FIRMWARE.md): the image must not embed it. Today
  `kernel/build.sh` copies Nokia's TI1273 Bluetooth and smiapp camera firmware into the initramfs. For
  a redistributable image these must be loaded from the phone's own Harmattan root at run time instead
  (as the DSP, FM, secure-world and camera-tuning blobs already are), or the image ships without them
  and documents that my own PR1.3 phone already carries them. Open: Bluetooth and the cameras
  need their firmware *before* the eMMC root is up today (registration ~2.8 s in; sensor probe) —
  moving them to run-time load needs the probe deferred or the rootfs mounted earlier. Resolve before
  redistributing.

## Procedure (I run every step on the phone)

### A. Back up first

Before anything is flashed, back up what a bad flash or a read-write rootfs could lose:

- **The rootfs and `/home`**: image both partitions (`/dev/mmcblk0p2` rootfs, `p3` home on 6.18's
  aliases) off the phone, over the USB network or to a host, while they are quiescent. Verify the
  images restore.
- **CAL / per-device data** is on OneNAND and is never written by this kernel; still, record that it
  exists (WLAN MAC/NVS, IMEI, simlock) so a later mistake is recognised.
- Keep the **stock signed kernel** (next section) to hand before flashing anything.

### B. Validate the exact image by RAM boot, for a day

The image that will be flashed is RAM-booted first and run for a full day (me, 2026-10-04): same
build, through `0xFFFF -m kernel:build/zImage-n9-<commit> -l -b` (load-boot, RAM only, nothing written).
Only once a day of normal use is clean does flashing even come up. This is the last safe checkpoint: a
RAM boot leaves the flashed stock kernel untouched, so a reset returns to stock.

### C. Install (flash) — my decision and my hands

- The kernel lives in its own MTD partition (**16 MiB**). The release zImage+DTB is a drop-in
  for it. The flash is done with `0xFFFF` (the same tool as the RAM boot, with its flash mode rather
  than `-l -b`). **The exact `0xFFFF` invocation is not settled — this project has never flashed
  anything — so confirm it against 0xFFFF's own docs and the stock kernel's partition layout before
  running it.** Do not improvise a flash command.
- Flash **only the kernel partition**. Do not touch rootfs, home, CAL or the bootloader.
- After flashing, the phone boots the new kernel from flash without `0xFFFF` armed.

### D. Revert to stock

**On my phone**: flash back the kernel it had (the open-mode l2fix kernel above, from the
backups), not the FIASCO's signed one. The rest of this section is for a phone still on Nokia's own
closed-mode kernel.

The way back is stock's own signed kernel, which I flash the same way:

- Source: the PR1.3 FIASCO image
  `DFL61_HARMATTAN_40.2012.21-3.480.04.1_PR_LEGACY_480_ARM_RM-696_PRD_signed.bin`
  (sha256 `7f3515bde7b81b1d648567f717a656190feb487081cc1145e454b4494003df5b`, FIRMWARE.md); the signed
  kernel is inside it. Extract it before flashing our kernel, so revert needs no download.
- Flashing stock's signed kernel back restores the original boot. (Stock's kernel is signed; ours is
  not — NOLO 2.3.6 RAM-boots unsigned images, but whether it *boots a flashed* unsigned kernel from the
  kernel partition on this device's secure configuration is an open question to settle before the first
  flash, not after.)

### E. Recovery if a flash goes wrong

- **A RAM boot always overrides a flashed kernel**: arm `0xFFFF` with a known-good image (stock's, or a
  previous good build) and it boots from RAM regardless of what's in the kernel partition. This is the
  primary recovery and needs no cold-flash.
- **Never RAM-boot stock's *raw* zImage** (the one in `unpacked/`): it hangs after NOLO with no watchdog
  recovery and needed a battery pull (NOTES.md). Recovery RAM boots use our image or
  stock's properly packaged signed kernel, not the raw zImage.
- Cold-flash (boot ROM, `0421:0106`) is the last resort if NOLO itself is damaged; flashing only the
  kernel partition should never reach that, since NOLO lives elsewhere. Documented here only so it's
  known; not expected.

## Open decisions for me

- eMMC read-write and a closed-mode (Aegis-enforcing) kernel are parked today (`n9-bb5-task`,
  `n9-user-preferences`); the release needs the read-write decision at least.
- Redistributable vs. this-phone-only image: the firmware-redistribution and first-boot-wizard points
  (section 4, section 2) only bite for an image given to others. If the first target is just my
  own phone, several of these relax.
- The RNG-seed approach (section 4). (The dropbear port, 2222, and `harmattan.patch` are settled: the
  patch is gone, every hunk is a kernel fix, Harmattan runs unmodified.)
- The exact `0xFFFF` flash command and whether NOLO boots a flashed unsigned kernel on this device
  (section C, D): settle by reading, with no trial flash.
