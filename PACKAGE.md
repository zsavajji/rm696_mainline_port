# Distributing the kernel as a package

Notes for a Harmattan package (`.deb`) that installs the release image on other N9s, as kernel-plus
was distributed. Nothing here is built yet. (2026-10-18)

## What the package would carry

One file: the release image (`RELEASE=1 kernel/build.sh` -> `build/zImage-n9-release`, ~7 MB), which
is self-contained: the kernel with the DTB appended, the initramfs with its modules (the SGX driver's
among them), the regulatory database and the rescue SSH server. Nokia's firmware (WLAN, Bluetooth, FM,
cameras, DSP, secure world) stays on each phone, in Harmattan's own `/lib/firmware` and `/lib/dsp`, as
the image already expects ([FIRMWARE.md](FIRMWARE.md)).

- Format: Harmattan's `dpkg` reads gzip only: build with `dpkg-deb -Zgzip`, architecture `armel`.
- Licences: the kernel and the SGX driver are GPL-2.0 (point to their sources: linux_mainline_rm696
  and pvr_sgx_rm696 on GitHub, the exact commit in the package version), BusyBox GPL-2.0, dropbear and
  musl MIT, wireless-regdb ISC, the kit MIT.
- The description has to say what's untested: charging while the phone is off (ACT_DEAD) has never
  run on a phone.

## The limit: NOLO locks the kernel partition

The phone must be in open mode: NOLO boots no unsigned kernel otherwise. And when NOLO boots a kernel
without Nokia's signature, stock's own open-mode kernel included, it locks CAL, its own blocks and the
kernel partition tight until the next reset (found 2026-10-10 on CAL: writes fail with
`onenand_wait: controller error 0x0400` on stock in open mode and on 6.18 alike; a warm reboot into
NOLO clears it: Nokia's flasher wrote the kernel right after one on 2026-10-18).

So on an open-mode phone no running system, stock or 6.18, can rewrite the kernel partition, and a
package's `postinst` that just writes it would fail. That holds for updates from 6.18 too: 6.18 writes
OneNAND exactly as stock (`onenand_omap2.read_only` is off on the release image; only the RAM-boot
test init sets it); the lock is NOLO's.

Stock has the tools a script would use (`/usr/sbin/flash_erase`, `nandwrite`, `nanddump`, `flashcp`,
`mtd_debug`), for a phone where the partition isn't locked.

## Routes

- **USB, with Nokia's flasher (works, 2026-10-18):** `ramboot/fiasco.py FIRMWARE IMAGE OUT` makes a
  14 MB FIASCO file from the stock firmware: its cert-sw entries, its ape-algo and IMAGE as the kernel.
  Then, as root on the x86 computer with flasher 3.12: `flasher -F OUT --flash-only=kernel -f -R`,
  and reboot the phone into NOLO. The ape-algo is Nokia's flashing system, a 2.6.32 kernel and an
  initramfs running softupd: the flasher RAM-boots it and softupd writes the images (the flasher
  refuses without it: "APE algorythm has to be provided"). The file carries Nokia's files: for owners,
  not for publishing. 0xFFFF can't do this: NOLO refused its flash of any kernel, Nokia's own
  included, most likely because NOLO itself doesn't flash on the N9.
  Back up the partition first, from the rescue SSH (`cat /dev/mtd2 > backup`). The partition holds
  NOLO's own 4 KiB `NOLO!img` header and then the zImage, and the header is added at flashing:
  restore the zImage from offset 4096 (up to the trailing 0xFF), never the dump as it is.
- **On the phone, stock's own route: closed to open-mode phones (NOLO secondary 2.3.6, read
  2026-10-18).** Stock updates its kernel from a package: `kernel-flasher` ships a `.fiasco` in
  `/usr/share/osso/` and its postinst runs `fiasco-flasher-stage`, which links it into
  `/var/lib/fiasco-flasher/staging`. After `reboot -u` (Nokia's upstart reboot: RESTART2 "update";
  6.18's `omap3xxx_restart` writes the same 'BM' + 'u' word to the scratchpad that 2.6.32 did) NOLO
  boots with `bootmode=update`, `getbootstate` says FLASH, the upstart job `flash-check` runs
  `fiasco-flasher-update`, and `fiasco-flasher` writes the image through `/proc/mtd` and
  `/dev/mtdN` (partition names `kernel`, `bootloader`... as our DT has them; it handles unsigned
  kernels unless the device lock is on). If flashing fails it runs `enter_malf`, which writes
  `/var/malf`. But NOLO allows update mode only for a Nokia-signed kernel: when the signature check
  fails and update mode was asked for, it prints "Update mode not allowed!" and resets (code at
  0x22c0; it clears the scratchpad word first, so it boots normally after: no loop). A normal boot of
  an unsigned kernel takes the "View-openmode" path, which locks CAL, NOLO and the kernel blocks
  with lock followed by lock-tight (OneNAND 0x2a, 0x2c: op +0x40 of the flash ops at 0x13870).
  So once a phone runs 6.18 (or Nokia's open-mode kernel) nothing on it can rewrite the kernel
  partition: a package can't flash, and updates go through the USB route above. A package could
  only do the first install, from a phone still on Nokia's signed kernel (untested).
  kernel-plus's thread (talk.maemo.org, "[Announce] kernel-plus for Harmattan", page 1, saved by the
  user) shows it failing exactly so: its `install.sh` (the author: "No clue how to do Debian
  packaging") ran `fiasco-flasher` on a running open-mode phone and got `MEMERASE (blocks 0..31):
  Input/output error`, and `fiasco-flasher` then tried to mark block 0 bad (`MEMSETBADBLOCK`, which
  failed too). Never run `fiasco-flasher` on a running phone: on a partly writable partition that
  bad-block marking would spoil good blocks.
- **Not flashing at all (ideas, not built):** kernel-plus's own recommended install was a tarball and
  ubiboot ("Gone are the days of flashing kernels!"), a loader flashed once that boots kernels from
  files. Our release image could do the same: kexec a newer image from
  the rootfs at boot, so a package would only install a file.

A package's removal should put back the kernel it replaced: back the partition up (`nanddump`) before
flashing, to the phone's MyDocs, and flash it back the same way.
