# Status

The kernel runs stock Harmattan PR1.3 day to day on a Nokia N9 (RM-696). Everything below was checked
on a real phone; each area's page has the details and how it was tested, and the build kit's
`UNPORTED.md` lists what was left out.

::: warning Release candidate
The release image is in its first days of daily use. Real calls, SMS and mobile data have not been
tried with a SIM yet, and the image has only been booted from RAM, never flashed (see
[Install](./install)).
:::

## Works

| Area | What was checked |
|---|---|
| [Display](./display) | the panel over DSI with omapfb as stock, landscape updates without tearing, brightness, dimming, the low-power standby screen, the lock screen, double tap to wake, NOLO's boot logo kept on screen until Harmattan draws, the first frame after an idle pause timed as stock |
| [GPU](./gpu) | the SGX 530 through Harmattan's own PowerVR libraries: X with Nokia's driver, GLES2, the compositor |
| [Video](./dsp) | playback with Harmattan's DSP codecs (the DSP bridge) and Xv scaling, 720p clips |
| [Cameras](./camera) | both cameras through Harmattan's camera stack: viewfinder, switching, stills, 720p video at 30 fps, autofocus, the flash |
| [Audio](./audio) | the speaker, headphones (a test tone, FM radio), the headset button, the earpiece and microphone paths; music through the DAC33's low-power mode not listened to yet |
| WLAN | association, Nokia's per-phone calibration (from CAL) applied as stock, power save with stock's 100 ms timeout |
| [Bluetooth](./bluetooth) | OBEX file transfers both ways at 3.69 Mbaud, as stock; Bluetooth on during CORE OFF |
| [FM radio](./fm) | tuning, seek, RDS, through Nokia's own WL1273 drivers |
| [NFC](./nfc) | Nokia's PN544 driver; an Android phone detected and read (tag contents not checked yet) |
| [TV-out](./tv-out) | composite PAL/NTSC over the AV cable, Harmattan's own clone mode |
| [Modem](./modem) | up at the ISI level as stock (csd, sscd); the call-audio link tested without a SIM |
| Sensors and GPS | accelerometer, magnetometer and compass, light and proximity, GPS, the touchscreen with Nokia's configuration |
| [Power](./power) | charging with charger-type detection, the battery as BME reads it, CPU frequency and voltage scaling with SmartReflex as Nokia's, CORE retention and OFF in standby, OFF mode armed at boot by Harmattan's `pmconfig` as stock |
| [Secure services](./modem#bb5-the-secure-environment) | the BB5 secure environment (Nokia's driver, Harmattan's libbb5) |
| USB | the SDK mode's network (stock's `usb_moded`), mass storage |
| [Memory](./performance) | 1004 MB of RAM as stock, so Harmattan's swap job sets up its 256 MB of compressed swap; full SDRAM speed after CORE OFF |

## Not done or not tried yet

- **Calls, SMS and mobile data with a SIM**: the modem and its call-audio link work without one.
- **Bluetooth profiles other than OBEX** (A2DP, headsets, PAN, DUN) and a call through a Bluetooth headset.
- **Power-off, charging while off (ACT_DEAD) and alarm power-on**: restored as stock in the kernel, not
  tried on a phone yet.
- **Ovi Suite (MTP)** USB mode: the gadget is there, untried.
- **wlancond's scan tunables** (`scan_size`, `scan_delay`): mainline's driver scans differently; not ported.
- **TV-out after a sync loss**: the TV plane stays off until the cable is replugged.
- **Aegis in enforcing (closed) mode**: the kernel carries Nokia's Aegis in open mode only: it logs and
  denies nothing (see [The kernel](./kernel#aegis)).

## Known issues

- Rare memory-corruption panics, three in a few hundred test boots, under different loads; not
  reproduced on purpose and the cause isn't known. A panic reboots the phone after 10 s and its record
  is kept on the phone (see [Rescue SSH](./rescue#crash-records)).
- CAL writes fail: NOLO locks Nokia's configuration store on the OneNAND whenever the kernel isn't
  signed by Nokia, as with stock's open-mode kernel, so `bme`, `mce` and `dsme` log failed writes
  (`onenand_wait: controller error`). Nothing is written; settings that live in CAL keep their values
  (see [Power](./power#cal-and-onenand)).
- WLAN's transmit power doesn't follow the regulatory database's caps (mainline's wlcore never applies
  them; Nokia's per-phone calibration limits do apply), so on a few 5 GHz channels in some countries
  the phone can transmit above the legal limit.
