# Build

Three repositories, side by side:

- **`linux_mainline_rm696`**: the kernel. Linux 6.18.55 from linux-stable, with this port's changes
  as commits on branch `rm696` (see [The kernel](./kernel)).
- **`pvr_sgx_rm696`**: the SGX (GPU) driver, built as modules against the kernel; its README has the
  driver's origin and its changes for 6.18.
- **`rm696_mainline_port`**: the build kit. The initramfs's init (`ramboot/release-init`), the build script
  (`kernel/build.sh`) and these docs.

```sh
git clone https://github.com/zsavajji/rm696_mainline_port
git clone --depth 1 --branch rm696 https://github.com/zsavajji/linux_mainline_rm696
git clone https://github.com/zsavajji/pvr_sgx_rm696
cd rm696_mainline_port
RELEASE=1 kernel/build.sh
```

The result is `build/zImage-n9-release`, ready for [NOLO](./install#_3-boot-it-from-ram) (the zImage
with the N9's device tree appended and the initramfs built in). A full build takes a few minutes on a
recent machine.

## What the build needs

A Linux machine, or one you can reach over SSH (below). On Debian 13 (other distributions name the
packages alike):

```sh
sudo apt install gcc gcc-arm-linux-gnueabihf make bc bison flex libssl-dev libelf-dev \
  git rsync curl cpio xz-utils kmod openssh-client
```

The build downloads the rest:

- from **Alpine Linux** v3.24 (armv7): the static BusyBox and dropbear for the initramfs;
- from **wireless-regdb**: the signed regulatory database.

Nothing of Nokia's is needed or included: the phone loads its own firmware, the WLAN chip's included
(see [Firmware](./firmware)). Their licences, for anyone passing the image on: BusyBox is GPL-2.0 (its
source is Alpine's), dropbear and musl are MIT, and wireless-regdb is ISC.

## Where it builds

`kernel/build.sh` takes its settings from the environment:

| Variable | Default | Meaning |
|---|---|---|
| `RELEASE` | (empty) | `1` builds the release image. Without it the build is the project's RAM-boot **test** image, for development only: it keeps the phone's disks read-only and lets in the SSH key made at the first build (`build/ramboot-key`) |
| `BOX` | `local` on Linux; on macOS the project's own build VM, so set it there | `local` builds here, in `build/box`, from the kernel repository **as it is checked out**. Anything else is an SSH destination (`user@host`) that builds in its `~/projects/sgx`, with the kernel's `BRANCH` pushed there as committed |
| `BOX_SSH_CONFIG` | | an SSH config file for reaching `BOX` |
| `KERNEL` | `../linux_mainline_rm696` | the kernel repository |
| `PVR` | `../pvr_sgx_rm696` | the SGX driver's checkout, built as it is checked out (also over SSH) |
| `BRANCH` | `rm696` | the branch or tag built on a `BOX` over SSH |
| `CROSS` | `arm-linux-gnueabihf-` | the cross compiler's prefix on the machine that builds |

The build leaves two cores free; the kernel and its modules go to `build/box/projects/sgx/build`
(or the box's `~/projects/sgx/build`), the image to `build/`.

### From macOS

A kernel doesn't build on macOS, and a kernel checkout on macOS's case-insensitive disk loses files
that differ only in case. Build on a Linux machine or VM over SSH: the kernel's commits are pushed
there, so the Mac needs no checkout of its files.

```sh
git clone --no-checkout https://github.com/zsavajji/linux_mainline_rm696
git clone https://github.com/zsavajji/pvr_sgx_rm696
cd rm696_mainline_port
BOX=you@linux-box RELEASE=1 kernel/build.sh
```

The box needs the packages above, and enough room for the kernel (about 5 GB).

## Changing the kernel

The kernel's configuration is `omap2plus_defconfig` with `arch/arm/configs/rm696.config` on top.
`kernel/build.sh` checks that every line of `rm696.config` made it into the final configuration (a
missing dependency drops an option silently) and stops if one didn't. Change the fragment or the code,
commit, and build again; [Removed and switched off](./removed) lists what the configuration leaves out
and how to put each back.

## Checking the SGX driver's interface

Harmattan's GPU libraries are closed and talk to the kernel through `pvrsrvkm`'s ioctls, so the driver
must dispatch them exactly as Nokia's module did. `check-abi.py` compares the two modules' ioctl
dispatch without a phone. It lives with the driver, in `pvr_sgx_rm696` (by default it reads this kit's
`build/pvrsrvkm.ko`); its header says how to extract Nokia's `pvrsrvkm.ko` from the PR1.3 firmware
image. It needs `llvm-objdump`.
