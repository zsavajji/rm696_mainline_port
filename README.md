# rm696_mainline_port

Linux 6.18 for the Nokia N9 (RM-696), running the phone's own Harmattan PR1.3 userspace, unmodified.
This repository is the **build kit**: it builds the kernel and the GPU driver into one image that the
N9's bootloader (NOLO) boots.

**Documentation: https://zsavajji.github.io/rm696_mainline_port/** (installing, the rescue SSH
server, building, what works, and how each part of the phone is done).

## The three repositories

| Repository | What it is |
|---|---|
| [linux_mainline_rm696](https://github.com/zsavajji/linux_mainline_rm696) | the kernel: linux-stable 6.18.55 with the N9's changes, one commit each, branch `rm696` |
| [pvr_sgx_rm696](https://github.com/zsavajji/pvr_sgx_rm696) | the SGX (GPU) driver that Harmattan's closed GPU libraries need |
| rm696_mainline_port (this one) | the build script, the image's init, the test tools and the documentation |

## Building

On Linux with an ARM cross compiler (`gcc-arm-linux-gnueabihf`), the three repositories side by side:

```sh
git clone https://github.com/zsavajji/rm696_mainline_port
git clone --depth 1 --branch rm696 https://github.com/zsavajji/linux_mainline_rm696
git clone https://github.com/zsavajji/pvr_sgx_rm696
cd rm696_mainline_port
RELEASE=1 kernel/build.sh        # -> build/zImage-n9-release
```

From macOS, build on a Linux machine over SSH (`BOX=user@host`). The packages, the settings and what
the build downloads are on the [Build](https://zsavajji.github.io/rm696_mainline_port/build) page.

## Installing

Boot the image from RAM first (nothing is written to the phone), then flash it if you keep it: see
[Install](https://zsavajji.github.io/rm696_mainline_port/install). The image starts a rescue SSH
server on the USB cable before Harmattan, so the phone stays reachable even if Harmattan doesn't come up.

## What's here

| Path | What |
|---|---|
| `kernel/build.sh` | the build: kernel, GPU driver, initramfs, one bootable image |
| `ramboot/release-init` | the release image's init: the rescue SSH server, then Harmattan's own start-up |
| `ramboot/init`, `ramboot/*.sh` | the RAM-boot test image and the Mac-side tools for testing on a phone |
| `tests/` | the measurement and test tools used during the port |
| `docs/` | the documentation site (VitePress) |
| `NOTES.md` | the development log: every change, test and finding, in order |
| `RELEASE.md` | the release plan and its status |
| `UNPORTED.md`, `REMOVED.md`, `FIRMWARE.md` | what isn't ported yet, what is left out on purpose, and the firmware |

## Licence

MIT (`LICENSE`), except `tests/camera/nokia-media.h` (GPL-2.0). The kernel and the GPU driver are
GPL-2.0, in their own repositories.
