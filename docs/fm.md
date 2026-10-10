# FM radio

The WL1273's FM receiver works with Nokia's own Harmattan drivers, ported to 6.18: tuning, seek, RDS
and 48 kHz digital capture, played through PulseAudio to the headphones. The community's `fmrxd` daemon,
which the FM apps use, wasn't installed on the test phone; every step it takes was tested by hand. FM
transmit (unused on Harmattan) and the analog audio route are not used.

## Who uses it

Stock PR1.3 ships no FM application. The users of the kernel's interface are:

- **fmrxd** (D-Bus `com.javispedro.fmrxd`, runs as root), the backend of the community apps "QML Radio"
  and Andrey Kozhanov's "FM Radio".
- **Nokia's test servers** (`testserver`/`infoserver`, and `stserver`'s FM self-test through
  `/dev/i2c-3`, address 0x22).

Both drive three interfaces: the V4L2 radio device `/dev/radio0`, the ALSA card `dfl61wl1273` (card
index 2, which fmrxd hard-codes as `hw:2`), and an HCI vendor command to the Bluetooth core of the same
chip.

## Hardware

| | |
|---|---|
| Control | I2C3 at 400 kHz, address 0x22 |
| Interrupt | GPIO 43 (pad `gpmc_a10`), falling edge |
| Enable | GPIO 178 (pad `mcspi2_clk`), for board revision S1.1 and later (every retail N9); earlier boards used GPIO 179 |
| Audio | digital over McBSP4, shared with Bluetooth SCO; the analog route into the TWL5031's AUXL/AUXR exists but Harmattan never uses it |
| Antenna | the headset or headphone cable: without one plugged in, there is no reception |

NOLO leaves the pads set up; there is no regulator, clock or pinmux for FM, as in stock's board file.

## The drivers

Mainline's WL1273 radio driver had been transmit-only since v3.8, returned RDS as `v4l2_rds_data`, and
its codec had no "Mode Switch", so fmrxd would fail on it. The radio and the codec were removed in
6.18-rc1, and the core in 6.19-rc1. The kernel carries Nokia's versions instead:

| Commit | |
|---|---|
| 9038db178 `mfd: wl1273-core: Nokia's driver from Harmattan, on DT` | chip logic, firmware upload, tuning, seek, RDS from the interrupt thread; enable GPIO and IRQ from the DT; an out-of-bounds read of the RDS status fixed |
| 77ba4aa40 `media: radio: wl1273: Nokia's /dev/radio0 from Harmattan` | stock's file operations and ioctls on today's V4L2 control framework |
| 62a835098 `ASoC: codecs: wl1273: Nokia's BT/FM codec from Harmattan` | stock's ten controls |
| ffb5dcc35 `ARM: omap3-n9: the WL1273 FM radio, its codec on the BT/FM card` | the DT node `fm@22` (`omap3-n9-audio.dtsi`), the `dfl61-wl1273` card on Nokia's codec, `CONFIG_RADIO_WL1273` |

Stock's private V4L2 controls (no user found), its check of allowed modes, and FM transmit setup through
board callbacks were left out on purpose.

## The interfaces

**HCI command.** Before FM audio can flow, the Bluetooth core's audio multiplexer has to be set by a
vendor command, OGF 0x3f, OCF 0x000, parameters `f3 88 01 02` (`f3 88 01 01` when stopping). Without it
McBSP4 gets no I2S clocks and the capture fails with EIO. fmrxd brings `hci0` up for the command and
takes it down again a second later if Bluetooth was off; the audio keeps flowing after that.

**ALSA controls** on `dfl61wl1273`: "Mode Switch" (Rx, Tx, Off, Suspend), "Codec Mode" (Bt, FmRx, FmTx),
"Audio Switch" (Digital, Analog), "Region Switch", "Rds Switch", "Pre-emphasis", "Channel Spacing",
"Tx Power", "Tx Ctune", "Master Capture Volume". "Mode Switch" Rx powers the FM part up and uploads
the firmware. While another stream runs on the card, "Codec Mode" refuses changes with EPERM, as on stock.

**`/dev/radio0`** (udev: group `video`, mode 0660): `VIDIOC_QUERYCAP` (a tuner), `G_TUNER` (`.signal` is the
chip's signed RSSI), `S`/`G_FREQUENCY`, `S_HW_FREQ_SEEK` (blocking), mute and volume controls. RDS
comes from `read()` as raw 3-byte blocks: block id in status bits 0-2, uncorrectable-error flag in bit 4,
as fmrxd expects.

**Capture**: `hw:dfl61wl1273`, S16_LE, 48 kHz, stereo. fmrxd plays it through PulseAudio. In BT mode
the card allows only 8 kHz, so an FM capture opened while PulseAudio streams SCO to `sink.hw1` fails at
`hw_params`.

## Firmware

`/lib/firmware/radio-wl1273-fw.bin` from Harmattan's root, loaded at the first "Mode Switch" Rx (see
[Firmware](./firmware)). The power-up with the upload takes 0.7-0.75 s. The "Cmd: 102 fails" in the
kernel log is the reset after the upload, and is ignored as on stock.

## Trying it by hand

As root, with a headset or headphones plugged in, roughly what fmrxd does:

```sh
hciconfig hci0 up
hcitool cmd 0x3f 0x000 0xf3 0x88 0x01 0x02
amixer -c dfl61wl1273 cset name='Mode Switch' Rx
amixer -c dfl61wl1273 cset name='Codec Mode' FmRx
amixer -c dfl61wl1273 cset name='Audio Switch' Digital
# tune through /dev/radio0 (V4L2), then listen:
arecord -D hw:dfl61wl1273 -f S16_LE -r 48000 -c 2 -t raw | aplay -D pulse -f S16_LE -r 48000 -c 2 -t raw
# off, in this order:
amixer -c dfl61wl1273 cset name='Audio Switch' Analog
amixer -c dfl61wl1273 cset name='Codec Mode' Bt
amixer -c dfl61wl1273 cset name='Mode Switch' Off
```

`aplay -D pulse` needs an `.asoundrc` with `pcm.pulse { type pulse }` and `ctl.pulse { type pulse }`.
`tests/fm.pl` in the build kit runs the whole sequence: power-up, tuning, RSSI, seek, RDS, a capture
level check and power-off, logging each step. `tests/fmscan.pl` scans the band.

## Tested

- Tuning takes 0.08 s per frequency. A band scan with a headset as the antenna read RSSI 7-37 (-4 to -7
  without an antenna).
- RDS on a local station: 840 blocks in 20 s with 0 errors, and the PI code and station name were read.
- Seek with the antenna: 11 of 11, 0.24-0.48 s each, including the wrap from 107.9 to 87.6 MHz.
- Listening: a station played through PulseAudio to Nokia headphones and was heard clearly.
- The FM interrupt fires only while FM is on.

## Limitations and not done

- Without an antenna, a seek over an empty band can time out (`HW seek failed: -110`): stock's seek
  returns after 1 s while the chip may still be sweeping. It didn't happen with an antenna.
- Not tested: fmrxd and the FM apps themselves; CORE retention unplugged with FM off (GPIO 43 is a
  wakeup line, but the interrupt stays quiet with FM off); FM transmit.
