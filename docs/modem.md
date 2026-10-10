# Modem and BB5

The cellular modem comes up at the ISI level as on stock: Harmattan's `csd` and `sscd` reach their
ready states, and the call-audio link was tested up to the start of a call, without a SIM. Calls, SMS
and mobile data with a SIM haven't been tried yet. Nokia's BB5 secure environment works as on stock,
with Nokia's driver built in and Harmattan's own `libbb5` and `validator-init`.

## The modem link

| | |
|---|---|
| Link | SSI port 1, 96 Mbit/s, frame mode, synchronized flow |
| Channels | 0 McSAAB control, 1 speech control, 2 speech data, 3 McSAAB data (stock's numbering) |
| Drivers (mainline's, built in) | `omap_ssi`; `ssi_protocol` (McSAAB, the Phonet interface `phonet0`); `cmt_speech` (`/dev/cmt_speech`); `nokia-modem` |
| GPIOs | `cmt_en` 23, `cmt_rst_rq` 88, `cmt_apeslpx` 93, the modem's reset indication on 34, the SSI wake (cawake) on 151 |
| Harmattan's users | `csd` (calls, SMS, data), `sscd` (modem power and state), PulseAudio's `module-meego-cmtspeech`, Nokia's `stserver` and `infoserver` |

`nokia_modem.pm=0` is on the kernel command line. NOLO leaves the modem powered (`cmt_en` high) and
stock's kernel never drove its GPIOs; with `pm=1` the driver would pull them low. `hsi_char` is not
built, because only Nokia's modem flasher used it ([Removed](./removed)).

## What Harmattan needs from the kernel

| Commit | Why |
|---|---|
| f1b0bc027 `phonet: allow the phonet group too (phonet_gid)` | mainline lets only `CAP_SYS_ADMIN` create Phonet sockets and bind resources. Nokia's kernel also allowed a group, and sscd and csd run without the capability (`phonet.phonet_gid=30012` on the command line, the group from Harmattan's `/etc/modprobe.d`) |
| 58bbb08e1 `genirq: an interrupt's /proc/interrupts line in Linux 2.6.32's form`, 470c55a0a `HSI: nokia-modem: name the reset interrupt cmt_rst_ind, as Nokia's kernel` | csd's GPRS plugin reads the modem's reset count from `/proc/interrupts` with `"%*d: %u%*[ ]GPIO%*[ ]cmt_rst_ind%c"`. That one line is printed in 2.6.32's columns (`181:   0   GPIO  cmt_rst_ind`); every other line keeps 6.18's. Before the fix, csd logged "could not read CMT reset count" |
| 552122361 `netlink: refuse a dump chunk only when the receive queue is already full` | libisi reads with a 16 KiB buffer, 6.18's dump chunks are 17920 bytes, and netlink refused them with an error libisi never clears: sscd and csd spun at 50-85% CPU after a USB replug |
| ec906f020 `HSI: omap_ssi_port: don't write the divisor of a suspended port` | a mainline bug: every L3 frequency change wrote the port's divisor with its clocks off (an L3 "In-band Error") |
| aa4a23614, e89447038 `HSI: omap_ssi_port: acknowledge a spurious error interrupt`, `report the port's state with a spurious error` | the unacknowledged interrupt looped in the port's thread until the phone panicked |
| 58fde0d17 `HSI: omap_ssi_port: acknowledge the status a context loss leaves` | after every wake from CORE OFF the port delivered one garbage word ("ssi-protocol: command 0x... not supported"), from a stale status register |

**Local Phonet resources.** At boot, Nokia's self-test server (`stserver -z`) and `infoserver` bind some
Phonet resources on the SoC side (self-test 0x59 and 0x35; security, phone info and others), and Phonet
delivers requests for them locally, as 2.6.32 did. If they don't run, sscd's self-test query reaches the
modem, which answers `COMM_SERVICE_NOT_AUTHENTICATED` (`59 f0 17 02`). That error is not a BB5 or kernel
problem. With Harmattan unmodified, both run as on stock.

## Call audio link

On the N9, call audio is digital. The modem and the SoC exchange 20 ms PCM frames on SSI channels 1
(control) and 2 (data) through `cmt_speech`:

- `/dev/cmt_speech` allows one opener. Commands are 4-byte words through `read()`/`write()`, and one
  `mmap()`ed page holds the buffers. The ioctl ABI (`CS_GET_IF_VERSION`, `CS_CONFIG_BUFS`,
  `CS_SET_WAKELINE`, ...) and the buffer layout are the same in mainline as on stock. udev and
  PulseAudio's pre-start make the device `root:pulse 0660`.
- Harmattan's `libcmtspeechdata` (2.1.1) and PulseAudio's `module-meego-cmtspeech` hold it open from
  boot. csd's `com.nokia.csd.Call.ServerStatus` signal starts a call's audio: wake line up, then
  `SSI_CONFIG_REQ`. The modem then sends `SPEECH_CONFIG_REQ` (8 or 16 kHz), the library sets up the
  buffers and answers, and asks for the uplink timing. On a peer reset (`CS_ERROR`) the library closes
  the device and reopens it.

Three fixes bring it to what stock did:

| Commit | |
|---|---|
| 6a7b35f30 `HSI: cmt_speech: report a flushed control channel as a peer reset` | when `ssi_protocol` resets the port (a modem reset, its watchdog), mainline only logged "Cmd flushed while driver active". Nokia's driver queued `CS_ERROR`, and Harmattan's PulseAudio module relies on it to reopen |
| 4fba8507b `HSI: cmt_speech: wait for a pending control write instead of -EBUSY` | the library writes `NEW_TIMING_CONFIG_REQ` right after `SPEECH_CONFIG_RESP` and never retries; a `write()` now waits up to 500 ms for the previous one. "Write still pending on control channel." in the kernel log is the old failure |
| cf6e32591 `ARM: dts: omap3-n9: hold the modem link still as stock around SSI clock changes` | around an SSI clock change or flush, stock changed only the two ready pads (ready-TX to safe mode with a pull-down, ready-RX to GPIO 154 driven low). Mainline's idle state also floated the data, flag and wake pads, and left GPIO 154 undriven. Now the idle state is stock's, with GPIO 154 hogged low (`ssi_ready_rx`) |

Tested without a SIM, with `tests/cmtramp.c` (the library's test interface, PulseAudio stopped):

- **Control**: `SSI_CONFIG_REQ` on and off, as at a call's start and end, answered with success in
  0.1-6 ms, with no SIM and no call.
- **Data**: the modem supports the library's `TEST_RAMP_PING`. 100 of 100 pings at a call's frame rate
  (one every 20 ms) came back as intact 324-byte downlink ramps, about 1.4 ms after the ping (stock: about
  1.1 ms). 16 kHz frames (640 bytes) also passed. The downlink doesn't echo the uplink, so only the
  uplink frames' delivery was checked, not their content.
- **Harmattan's pipeline**: a hand-sent `ServerStatus` signal made PulseAudio raise the wake line and
  configure the link, and create its "Cellular call up link"/"down link" streams. `false` tore them down.
- **Don't send ramp pings back to back with uplink answers.** The modem stops taking frames on the third
  or fourth one and resets itself about 2 s later. Stock does exactly the same, so this is the modem's
  test mode, not the kernel. sscd brings the modem back by itself.

Left as they are, on purpose: `ssi_protocol`'s watchdog timeout is 2 s (stock 500 ms; it times McSAAB,
not call audio). The wake line is raised from a work, while stock raised it at once. And mainline's
`ssi_async()` may resume the port from atomic context if a resume races the port's 250 ms autosuspend:
no sign of it so far, but "scheduling while atomic" in the kernel log would be it.

## Checking it

```sh
grep cmt_rst_ind /proc/interrupts            # "GPIO  cmt_rst_ind", the modem's reset count
cat /sys/class/net/phonet0/operstate
dmesg | grep -i "ssi\|hsi\|cmt\|mcsaab"      # no "Cmd flushed", "Write still pending", "SSI error"
grep ssi_ready_rx /sys/kernel/debug/gpio     # out lo
ls -l /dev/cmt_speech                        # root pulse, 0660
ls -l /proc/$(pidof pulseaudio)/fd | grep cmt_speech
```

In syslog, csd says "Phonet up" and sscd reaches `SystemReady`. **sscd writes the phone's IMEI to
syslog**: filter it out (and IMSI, ICCID, serial numbers, phone numbers from csd) before sharing a log.

## Not done

- Calls, SMS and mobile data with a SIM: the speech frames through PulseAudio, the audio on each route
  by ear, an incoming call.
- A call with USB unplugged, so that the L3 frequency (and with it the SSI clock) changes during the
  call. In the SIM-less tests L3 never switched, so cf6e32591's path wasn't exercised.
- A modem reset during a call (PulseAudio should log "modem reset detected" and reopen).

## BB5: the secure environment

The N9 is an OMAP3 HS device. Its secure world (Nokia's "BB5") runs signed protected applications (PAs)
for Harmattan through `/dev/omap_sec`. Harmattan's own `libbb5` uses it, and so do `validator-init` (the
Aegis policy loader, whose hash NOLO passes to the kernel), aegisfs (Aegis's encrypted storage, mounted
through FUSE, built in as on stock), `secure-clean` and others. Mainline has no such driver.

### The driver

25e77c513 `ARM: OMAP3: add Nokia's HS secure environment driver (omap_sec)`: Nokia's driver, GPL in
their published kernel tree, in `arch/arm/mach-omap2/` and built in (`CONFIG_OMAP3_SEC=y`) as on stock.
It was checked against the code of stock's own kernel image.

- `omap_sec` (`sec.c`, `pa.c`): the misc device `/dev/omap_sec`, and loading and marshalling the PA
  firmware. It takes `kci=`, which NOLO passes as `omap_sec.kci=958`.
- `omap_hs` (`hs.c`, `sec_hal.c`, `sec_hal_entry.S`): the secure-side operations and the RPC handler,
  with the `smc #1` entry (r12 the service, r6 = 0xff). Its init resizes the secure RAM to 48 KiB, as on
  stock.
- Firmware: `omap3_pafmt_958.bin`, `omap3_pa_958.bin` and `omap3_papub_958.bin` from the phone's
  `/lib/firmware`, loaded at the first secure command ([Firmware](./firmware)). The format file is
  verified by the ROM. Stock's unsigned fallback (`omap3_pafmt.bin`) is compiled out.

Changes for 6.18: the secure side reads its argument block by physical address, so the block is
`kmalloc`ed rather than built on the stack (Nokia passed varargs). The RPC handler allocates with
`GFP_ATOMIC`, because it runs inside a secure call with interrupts off. SHA-1 comes from the crypto
library, and the rest are API renames. The kernel's `PAGE_OFFSET` (0xc0000000, stock 0xb0000000) never
reaches the secure side: the 51 commands in `omap3_pafmt_958.bin` take only physical pointers.

### Secure RAM and OFF mode

When CORE goes OFF, the ROM restores the secure RAM from a saved image. Two commits make this work as on
stock:

- c2f638ca4 `save the HS secure RAM (48 KiB) at every CORE OFF, as stock`: a 0xC040-byte image (mainline
  saved 0x803f bytes once at boot). It goes into 64 KiB reserved at 0x8f100000, because the ROM saves only
  below 0x8fffffff, and it is saved again at every CORE OFF entry, since secure calls change the state
  after boot. If a save fails, that entry goes to CORE retention instead.
- 4ea7a477f `a positive secure RAM save status counts as saved, as stock`: the ROM returns 1 for most
  saves.

`/sys/kernel/debug/pm_debug/` counts `secure_ram_saves`, `secure_ram_save_fails` and
`secure_ram_save_positive`. In the CORE OFF tests, hundreds of saves showed no failure. The L2
auxiliary control register is also restored through the PPA, as on stock
(`CONFIG_OMAP3_L2_AUX_SECURE_SAVE_RESTORE`). Separately, the secure ROM's random number generator (PPA
service 29) feeds `hw_random` through mainline's N900 driver.

### Checking it

```sh
ls -l /dev/omap_sec
cat /sys/kernel/debug/pm_debug/secure_ram_saves        # grows with every CORE OFF entry
cat /sys/kernel/debug/pm_debug/secure_ram_save_fails   # 0
```

Tested: the secure ROM's RNG; Nokia's signed test PA (`PA_ROT13`), which the secure world loads, verifies
and runs; the PA version query; Harmattan's whole boot with the real `libbb5` and `validator-init` up
to the home screen; sscd at `SystemReady`; aegisfs mounting its filesystems. `secure-clean` can't read
the wipe state (EAGAIN), as on stock.

### Limits

- Aegis runs in open mode only (`aegis.mode=open`): it logs what it would refuse and refuses nothing.
  Several 6.18 changes were needed for Harmattan's validator to run at all (files measured at
  `file_post_open`, overlay layer devices matched in hash lists, open mode logging enforcement instead
  of panicking). See [The kernel](./kernel#aegis).
- Persistent secure storage goes through `libcal` to CAL on the OneNAND, which the kernel writes as stock
  does. CAL writes weren't exercised during the port's test boots, which kept the flash read-only.
