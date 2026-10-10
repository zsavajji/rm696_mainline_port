# Audio

Audio is set up as on stock, with Nokia's cards under Nokia's names, so Harmattan's PulseAudio and its
policy run unchanged. The speaker, the earpiece and microphone paths, headphone detection and the
headset button work. Not tried yet: listening to the DAC33's low-power FIFO mode, an ECI remote,
and a real call (no SIM so far; see [Modem](./modem)).

## The cards

| ALSA card | Interface | Codec | Used for |
|---|---|---|---|
| 0 `dfl61twl4030` | McBSP3 (I2S) | TWL5031 (mainline's `twl4030` codec) | the speaker (its amplifier on TWL GPIO 7), the earpiece, the digital microphones, the headset microphone, call routing |
| 1 `dfl61dac33` | McBSP2 | TLV320DAC33, then the TPA6140A2 headphone amplifier | headphones |
| 2 `dfl61wl1273` | McBSP4 | Nokia's WL1273 codec | Bluetooth SCO and the FM radio ([Bluetooth](./bluetooth#headset-audio-sco), [FM](./fm)) |

Harmattan's PulseAudio opens the first two by name (`hw:dfl61twl4030`, `hw:dfl61dac33`), and its
`system.pa` fails until both exist. The third is optional for PulseAudio; fmrxd expects it at index 2.

## The machine driver

`sound/soc/ti/dfl61.c` is Nokia's `dfl61-twl4030.c`, `dfl61-tlv320dac33.c` and `dfl61-wl1273.c` as one
DT driver (`omap3-n9-audio.dtsi`). It runs on mainline's codec drivers, whose control names match
PulseAudio's profile sets in `/usr/share/pulseaudio/alsa-mixer`.

| Commit | |
|---|---|
| ac1f7c3f8 `ASoC: ti: add Nokia's dfl61 machine driver` | the two main cards, the jack and its plug classification; the TPA6140A2 as its own model (mainline matched it as a TPA6130A2 and gave it the wrong volume control) |
| bf07a897c `ASoC: ti: dfl61: McBSP threshold mode and stock's sysfs paths` | each McBSP in threshold mode, as Nokia's machine drivers set it; links at 2.6.32's paths: `/sys/devices/platform/omap-mcbsp.{2,3,4}/max_{tx,rx}_thres` and `soc-audio.{0,1,2}/pmdown_time`, which PulseAudio's pre-start script writes |
| 24b20f193 `ASoC: ti: dfl61: the AV jack's buttons and Nokia's ECI accessories` | [below](#headset-buttons-and-eci-accessories) |
| cf6c40eba `ASoC: ti: dfl61: switch the AV jack to video for a TV-out cable` | TVOUT_EN (GPIO 40) high for a video cable, low otherwise ([TV-out](./tv-out)) |

Without the sysfs paths, PulseAudio's pre-start only logs a failure: the McBSPs stay in element mode (one
DMA request per sample) and the power-down delay stays at 5 s instead of stock's values.

## Headphones and the DAC33's low-power mode

Harmattan's `/etc/pulse/pulseaudio_pre-start.sh` selects the DAC33's `'FIFO Mode' 'Mode 7 Low Power'`.
That mode was Nokia's own (mainline has Bypass, Mode 1 and Mode 7) and is ported:

- 2cfd2979c `ASoC: tlv320dac33: Nokia's Mode 7 Low Power FIFO mode`: the DAC33 reads from the McBSP in
  bursts. An alarm interrupt ("ATHR time", 10 ms by default) starts the McBSP before the FIFO runs low,
  and a timer stops it after the burst. In between, the McBSP is force-idled with its functional clock
  gated, and a CPU latency request of the ATHR time is held while playing.
- 755ab739b, b778d7c84: Nokia's runtime power-level requests for the CPU DAI and the McBSP.
- 0c2950672 `bypass the FIFO for short periods, as Nokia's`: the control only selects the mode, and
  streams with periods of 40 ms or less run in Bypass whatever is selected. PulseAudio uses 10 ms
  periods normally and 140 ms when its policy asks for long buffering, so as on stock only
  long-buffered playback uses the FIFO.
- 43ef969c6, a5ea5ba25: the burst bit clock divider and the continuous bit clock from Nokia's board data.

Measured with 140 ms periods: 8-10 DAC33 interrupts a second, McBSP2's clock gated about 80% of the
time, and the PER domain entering retention during playback (about 1000 times in 10 s, none in Bypass).
Headphones played a test tone and the [FM radio](./fm) during the port; the low-power mode itself has
not been listened to yet (music with the screen off).

## The AV jack

The card has Nokia's jack input device, "dfl61-twl4030 Jack". It is fed by AvPlugDet (TWL GPIO 0, high
when something is plugged in), and ohmd's accessories plugin follows its switches. Each plug is
classified as Nokia's `twl5031-aci` did it, from the TWL5031's accessory comparators and the mic line
measured through the MADC:

| Result | Notes |
|---|---|
| wrong pinout | a CTIA headset such as Apple EarPods; the speaker stays on, as with stock's logic |
| headphones | mic line below 40 mV; reported as `SND_JACK_HEADPHONE` alone |
| video cable | below 500 mV; the jack switches to video ([TV-out](./tv-out)) |
| ECI accessory | answers Nokia's ECI bus reset; its buttons [below](#headset-buttons-and-eci-accessories) |
| basic headset, carkit | one button, `KEY_PHONE` |
| open cable, unknown | |

The headphone amplifier is off before the first measurement, and passes repeat until two in a row
agree, giving up with "unknown" after 24, as Nokia's driver did. The kernel log names each result
("AV jack: ...").

Two gotchas from the port:

- Report headphones as `SND_JACK_HEADPHONE` **alone**. With `SND_JACK_MECHANICAL` set too, ohmd reads
  the plug as an unknown accessory and keeps the speaker.
- A widget forced on with `snd_soc_dapm_enable_pin()` (for the measurement) stays forced. DAPM then
  never re-evaluates what follows it, and the TPA's mute stayed on during playback. Widgets are now
  handed back by disabling and then enabling them.

## Headset buttons and ECI accessories

Stock read the jack's buttons with Nokia's `twl5031-aci` and `eci` drivers. They are ported into
`dfl61.c` (24b20f193), and Harmattan sees what it did on stock:

- One input device, **"ECI Accessory"**. udev links it as `/dev/input/eci` and `/dev/input/accessory`.
  qmkeyd2 reads it, X takes it as a keyboard, and ohmd finds it by name.
- **A basic headset's (or carkit's) button**: `KEY_PHONE` (169), from the ACI's comparator 1 with
  Nokia's timing (a change reported 200 ms after its sample, sampled every 220 ms while held), with
  autorepeat (period 400 ms).
- **ECI accessories** (Nokia remotes and carkits with a chip on the mic line, reached over a one-wire bus
  through the TWL5031's ACI block): classification tries Nokia's bus reset between the video-cable and
  open-cable steps, then reads the accessory's memory, its "enhancement features" block and the
  interrupt set-up, and maps the buttons with Nokia's table (volume, play/pause, stop, forward/rewind,
  send/end, mute...). ohmd reads the memory from `/sys/devices/platform/ECI_accessory.0/memory`.
  The accessory's microphone follows the "Headset Mic" widget.
- The ACI interrupt is the TWL's PIH line 6 (`interrupts-extended = <&twl 6>`), and VAUX1 (stock's
  "v28") is held while a plug is in.

Differences from stock, each needed on 6.18: bus transactions run from process context (6.18 nests all
TWL interrupts in one thread, where waiting would deadlock), the mic switch runs from a work (Nokia's ran
inside the DAPM event, which needs DAPM's lock here), and an ECI accessory whose init fails is still
reported as a headset. Every held key is released on unplug, and the memory walk is bounded. TWL5031
ES1.0/ES1.1 (an address-decode bug that stock's twl-core worked around) get no buttons. The probe prints
the revision ("TWL5031 ACI v.N (IDCODE ... rev ...): jack buttons"); the tested phone has 0x2b.

Tested with Nokia's one-button headset: it is classified as a headset; `KEY_PHONE` arrives on press and
release, repeats while held, and a double press comes through as two presses; the music player pauses
and resumes on it. Unplugged while held, the key is released, and plugged in again it works. No CPU
latency request is left behind between transactions. Not tested: an ECI remote, and CORE retention with
a headset in and USB out.

## Call audio

On the N9, call audio is digital all the way. The modem and the SoC exchange 20 ms PCM frames over the
SSI link, through Nokia's `cmt_speech` (`/dev/cmt_speech`) and PulseAudio's `module-meego-cmtspeech`,
which holds the device open from boot. No TWL5031 voice port is involved. PulseAudio converts between
the frames and 48 kHz on `hw:dfl61twl4030`, and its routes use controls that exist on card 0: the earpiece
(DAC2, Earpiece Mixer), the loudspeaker (PredriveR), the headset (PredriveL and the DAC33's analog
bypass into the TPA6140A2), the digital microphone or the headset's, and sidetone through the digital
loopback. Without a call, setting these paths by hand plays to the earpiece and records the digital
microphones. The modem side, the kernel fixes and the SIM-less tests are on the [Modem](./modem#call-audio-link)
page.

## Checking it

```sh
cat /proc/asound/cards                              # 0 dfl61twl4030, 1 dfl61dac33, 2 dfl61wl1273
amixer -c dfl61dac33 sget 'FIFO Mode'               # Mode 7 Low Power once PulseAudio has started
dmesg | grep "AV jack\|jack buttons"                # each plug's classification
grep -A4 "ECI Accessory" /proc/bus/input/devices    # the buttons' input device
grep twl5031_aci /proc/interrupts                   # one or two per button press
od -An -tx1 /sys/devices/platform/ECI_accessory.0/memory   # "No such device or address" without an ECI accessory
```

PulseAudio's job reboots the phone if PulseAudio dies too often: stop it with `initctl stop pulseaudio`
(and `start` again), never with `kill`.
