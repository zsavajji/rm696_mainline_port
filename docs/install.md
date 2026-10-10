# Install

The release is one file, `zImage-n9-release`: the kernel, the N9's device tree, and a small initramfs
with the kernel's modules, the SGX driver and the [rescue SSH server](./rescue). Nothing of Nokia's
is in it: the phone's own firmware and Harmattan are used as they are.

## What you need

- A **Nokia N9 (RM-696) on Harmattan PR1.3** (40.2012.21-3), with **developer mode** on, for root
  (`devel-su`).
- A computer with a USB port, Linux or macOS, and **0xFFFF**, the open-source tool that talks to the
  N9's bootloader (NOLO) over USB.
- The image: download `zImage-n9-release` from a release, or [build it](./build).

### 0xFFFF

On Linux, use your distribution's `0xffff` package if it has one, or build
[pali/0xFFFF](https://github.com/pali/0xFFFF) with `make`. It needs access to the USB device: run it
with `sudo` or add a udev rule for vendor `0421`.

On macOS it builds with Homebrew's libusb-compat, with two changes: it refuses libusb-1.0's
compatibility layer (slow device listing on Linux, no problem here), and the boot ROM's cold-flash
device is better left alone (claiming it sometimes fails and stalls the boot; left alone, the ROM
starts NOLO by itself):

```sh
brew install libusb-compat
git clone https://github.com/pali/0xFFFF && cd 0xFFFF
perl -0pi -e 's/\tif \( dlsym\(RTLD_DEFAULT, "libusb_init"\) \)\n\t\tERROR_RETURN\([^\n]*\n//' src/usb-device.c
sed -i '' '/0x0421, 0x0106,  0,  0, FLASH_COLD/d' src/usb-device.c
CPPFLAGS="-I/opt/homebrew/include -D_DARWIN_C_SOURCE" LDFLAGS="-L/opt/homebrew/lib" make   # -> src/0xFFFF
```

On macOS also set System Settings → Privacy & Security → **Allow accessories to connect** to
*Automatically When Unlocked*: NOLO is on USB for only a few seconds, and a prompt would miss it.

## 1. Back up

This kernel runs Harmattan **read-write** on the eMMC, as the stock kernel does: it is your phone's
real system, not a copy. Before the first boot, keep an image of the root filesystem
(`/dev/mmcblk0p2`), `/home` (`/dev/mmcblk0p3`) and CAL, the per-phone calibration partition
(`/dev/mtd1`), on a computer, and check that the copies are complete. For example, as root on the
phone, with the phone idle:

```sh
dd if=/dev/mmcblk0p2 bs=1M | ssh you@computer 'cat > n9-rootfs.img'
```

## 2. Put your SSH key on the phone

The image's [rescue SSH server](./rescue) lets you in only with a key the phone already has. As root
on Harmattan:

```sh
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat your-key.pub >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
```

## 3. Boot it from RAM

A RAM boot flashes nothing: NOLO loads the image over USB and runs it once, and the next reset boots
the kernel in the phone's flash again. Run it for a while like this before you think about flashing.

1. Connect the phone by USB and start 0xFFFF; it waits for NOLO:

   ```sh
   0xFFFF -m kernel:zImage-n9-release -l -b
   ```

2. Reboot the phone (as root: `reboot`). NOLO shows up on USB, 0xFFFF loads the image, and the phone
   boots into Harmattan on Linux 6.18. `uname -r` says `6.18.55-…`.

If 0xFFFF says *No device detected*, the phone was in one of Harmattan's USB modes when it started:
start 0xFFFF again once the phone has rebooted into NOLO, or start it while the phone is off.

On macOS, a 0xFFFF started before NOLO is on USB doesn't see it, and the phone boots its flashed kernel.
The build kit's `ramboot/arm.sh IMAGE` waits for NOLO to appear and starts 0xFFFF then (it runs
`build/0xFFFF`: put your 0xFFFF there).

## 4. Flash it

::: danger Not done by this project yet
The release has only been RAM-booted so far. Flashing writes the phone's kernel partition: a kernel
that doesn't boot leaves you with RAM boots (below) as the way back. Flash only after a RAM boot of the
same image has run cleanly for at least a day.
:::

The kernel is unsigned. NOLO boots an unsigned kernel from flash (community open-mode kernels for
PR1.3 work that way), but Harmattan then runs in open mode; find out what that means for your phone's
protected data before you flash. Flash only the kernel:

```sh
0xFFFF -m kernel:zImage-n9-release -f
```

## Going back

- **From a RAM boot**: reset the phone without 0xFFFF waiting, and NOLO boots the flashed kernel.
  Going back to Nokia's kernel after running this one read-write should be clean (no Harmattan file is
  changed; this release adds only `/var/lib/n9-618`), but that is still being checked.
- **From a flashed release**: flash the kernel you had before. For a phone on Nokia's own kernel that
  is the one in the PR1.3 firmware image
  (`DFL61_HARMATTAN_40.2012.21-3.480.04.1_PR_LEGACY_480_ARM_RM-696_PRD_signed.bin`):

  ```sh
  0xFFFF -M DFL61_HARMATTAN_40.2012.21-3.480.04.1_PR_LEGACY_480_ARM_RM-696_PRD_signed.bin -t kernel -f
  ```

  If your phone ran a community kernel before, flash that one back instead: changes made to a phone for
  an open-mode kernel can fail with Nokia's closed-mode one.
- **If a flashed kernel doesn't boot**: a RAM boot of a good image (this release, an earlier one) still
  works, since NOLO is untouched; from there, flash the previous kernel back. A RAM boot of Nokia's
  bare 2.6.32 `zImage` hung on this project's phone: use a complete image instead.
