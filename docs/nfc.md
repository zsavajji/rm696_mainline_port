# NFC

NFC works with Harmattan's own stack: the kernel carries Nokia's PN544 character-device driver
(`/dev/pn544`), which is what Harmattan's `nfcd` needs. Switching NFC on and off from Settings, and
detecting and reading a target (an Android phone), work. Reading an NDEF tag's content, and NFC during
CORE OFF, haven't been tested yet.

## What Harmattan expects

Mainline 6.18 has only the NFC-subsystem PN544 driver, which Harmattan can't use. Stock had Nokia's
`drivers/misc/pn544.c` (`pn544.ko`):

- **One user.** Only `libNFCDAL` opens the device, for `nfcd` (user `nfc`, D-Bus activated as
  `com.nokia.nfc`; no upstart job). It opens it with `O_RDWR | O_NONBLOCK` and watches it with `poll()`.
  Each `read()`/`write()` carries one LLC frame; the HAL builds the frames and CRCs, and the driver checks
  the CRC on write.
- **One ioctl**, `PN544_SET_FW_MODE` (0x40045002). Chip power follows `open()`/`close()`.
- **udev**: `/etc/udev/rules.d/92-n770.rules` gives the device to `nfc`, so it shows as
  `crw-rw---- nfc root`.
- **On/off** is an mce radio state (`NFCRadioState`, off by default). nfcd starts at every boot anyway
  (conndlgs' NFC agent asks for it), checks the chip's firmware, and closes the device again while NFC
  is off.

Without the driver, nfcd failed and was restarted about 300 times a minute for the first minutes of every
boot, with conndlgs logging "RegisterUIAgent ... com.nokia.nfc.Adapter doesn't exist".

## The driver

`drivers/misc/nokia-pn544.c`, commit 34c9fae34 `misc: add Nokia's PN544 NFC driver (/dev/pn544) for the
N9`, built in (`CONFIG_NOKIA_PN544=y`). It is stock's code, with the board file's callbacks replaced by
DT GPIOs and a regulator:

| | |
|---|---|
| Bus | I2C3 at 400 kHz, address 0x2b (DT node `nfc@2b` in `omap3-n9-nokia.dtsi`) |
| Interrupt | GPIO 76, rising edge; its pad has the IO wake bit, as NOLO sets it |
| Enable | GPIO 77 |
| Firmware reset | GPIO 78 |
| Supplies | Vdd_IO = VIO; VBat is the battery directly |

NOLO leaves the three pads as GPIOs, so the driver does no pinmuxing. At probe it runs stock's self-test:
it powers the chip for about 50 ms, sends a U-RSET link frame and expects `03 e6 17 a7` back. This
only talks to the chip and writes nothing to its memory. If the chip doesn't answer, no `/dev/pn544` is
created.

### Differences from stock, on purpose

1. **Firmware download mode is refused** (`-EPERM`, kernel log "firmware download mode refused
   (allow_fw_mode=0)") unless `nokia_pn544.allow_fw_mode=1` is set, either on the kernel command line or
   at `/sys/module/nokia_pn544/parameters/allow_fw_mode`. nfcd compares the chip's four version bytes with
   the firmware image built into `libNXP_NFC_HAL.so.1.0.0`, and on any mismatch rewrites the chip's flash.
   On a phone that ran stock nfcd, the two match and nothing is ever refused. If the message does appear,
   the chip's firmware differs from Harmattan's, and allowing it means a flash write on the NFC chip.
   The HAL's normal configuration writes at each NFC start are not affected, as on stock.
2. **The `nfc_test` sysfs file is left out.** It was the board's GPIO self-test, read only by `stserver`
   in factory test mode at a 2.6.32 path, and stock's version left the chip powered in firmware mode.
3. **The ioctls and open/close run under a mutex**: stock relied on the big kernel lock.

[Removed and switched off](./removed) lists the first two, with how to put each back.

## Checking it

As root on the phone:

```sh
dmesg | grep -i pn544                 # no "rset" error, no "firmware download mode refused"
ls -l /dev/pn544                      # crw-rw---- nfc root
grep pn544 /proc/interrupts           # counts only while NFC is on (and once at probe)
grep -E 'gpio-7[78] ' /sys/kernel/debug/gpio   # "enable" and "firmware": low while NFC is off
```

NFC on and off, as Settings does (mce's radio state bit 16):

```sh
dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request \
  com.nokia.mce.request.req_radio_states_change uint32:16 uint32:16   # on; uint32:0 uint32:16 for off
```

With NFC on, nfcd opens the device, ENABLE goes high and FW stays low, and the chip interrupts during
HCI start-up. With NFC off, the device is closed, both lines go low, the interrupts stop, and nfcd stays
running, as on stock.

## Tested

- The probe self-test passes; udev gives `/dev/pn544` to `nfc`.
- nfcd starts once at boot, checks the chip's firmware (it matches, so there is no firmware-mode
  request), and closes the device. The restart loop and the conndlgs errors are gone.
- With NFC on, an Android phone held to the N9's back was detected and read twice through Harmattan's
  stack. It reported "Tag doesn't contain NDEF data", which is expected from a phone presenting itself
  as a card.
- NFC off closes the device and powers the chip down.

## Not done

- Reading an NDEF tag's content (a sticker, or an Android app that emulates an NDEF tag), and Bluetooth
  pairing or sharing through NFC.
- NFC on during CORE OFF. GPIO 76's pad wakeup is in the DT (rm696 aed6f173d, every pad as stock runs it).
  With NFC off the chip is unpowered and its interrupt quiet, so idle shouldn't change.
