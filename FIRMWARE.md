# Firmware

Nokia's firmware can't be redistributed, so none of it is in this repository or in the image. Every
N9 on PR1.3 already carries it: the kernel loads it from the phone's own Harmattan root at run time, as
Nokia's kernel did. The drivers that need Nokia's firmware early (Bluetooth's UART driver, the camera
sensors, lens and flash) are modules that udev loads once Harmattan's root is up, as on stock.

## In the image (not Nokia's)

`kernel/build.sh` downloads them:

| File | For | From | Where |
|---|---|---|---|
| `ti-connectivity/wl127x-fw-5-sr.bin` | WLAN (stock's 2011 `wl1271-fw.bin` is older than wlcore accepts) | linux-firmware | the initramfs, next to the modules (`firmware_class.path`) |
| `regulatory.db`, `regulatory.db.p7s` | cfg80211's country limits | wireless-regdb | built into the kernel (`CONFIG_EXTRA_FIRMWARE`) |

## From the phone's Harmattan root

Nothing to copy: they stay on the phone.

| File | For | Loaded by | Package (PR1.3 version) |
|---|---|---|---|
| `/lib/firmware/ti1273_le.bin` (chip 0xd1/0xf1), `ti1273_prele.bin` (0xe1), `ti1273.bin` (others) | Bluetooth | kernel (`hci_nokia`), at each power-on | bt-firmware-ti1273 0.23+0m6 |
| `/lib/firmware/smiapp-sensor-*.bin` (17), `smia-sensor-*.bin` (4); this N9's: `0b-0125-*` (imx125, main), `0c-2134-*` (tcm8500md, front) | Cameras: Nokia's register lists | kernel (`smiapp`), at sensor probe | rx71-camera-fw 0.0.51+0m7 |
| `/lib/firmware/radio-wl1273-fw.bin` | FM radio | kernel (`wl1273-core`), at the first FM power-up | wl1273-fm-radio-firmware 2.26+0m6 |
| `/lib/dsp/baseimage.dof` | DSP bridge | kernel (`bridgedriver`), at modprobe and after a DSP crash; path from stock's `/etc/modprobe.d/bridgedriver` | omap3-dsp-baseimage-ti 0.i3.6-20+0m7 |
| `/lib/dsp/*.dll64P` (17) | DSP codecs (video, camera) | kernel bridge, when gst-dsp creates a node | omap3-dsp-libraries-ti 0.i3.6-20+0m7, omap3-dsp-hd-codecs 0.3.9-6+0m7 |
| `/lib/firmware/omap3_pafmt_958.bin`, `omap3_pa_958.bin`, `omap3_papub_958.bin` (958: NOLO's `omap_sec.kci`) | Secure world (BB5, `/dev/omap_sec`) | kernel (`sec.c`), at the first secure command | libbb5-secbins 2.6.2+0m7 |
| `/etc/omapcam/*.enc`, `omap3camd.conf` | Camera ISP/3A tuning | camd (userspace) | libomap3camd 1.136-1+0m8 |
| `/usr/share/mxt-config/configs/RM-696_Pyrenees_SMD_ES40_V1_6.bin` | Touchscreen config | `mxt_configure.sh`, only on a CRC mismatch (the chip's NVM normally holds it already) | mxt-config 0.0.29+0m6 |
| NFC image inside `/usr/lib/libNXP_NFC_HAL.so.1.0.0` | PN544 | nfcd would reflash the chip on a version mismatch; the kernel refuses firmware mode unless `nokia_pn544.allow_fw_mode=1` | libnfchal 2.2+0m8 |

Stock files nothing loads: `wl1271-fw.bin` and `wl1271-nvs.bin` (wl1271-firmware), `et8en2-000{2,4}.bin`
and `tcm8580md-0001.bin` (rx71-camera-fw), the `omap3_pa*` files for other KCI values, and
`omap3_pafmt.bin` (its unsigned fallback is compiled out).

## Where else to find them

The same files are in the PR1.3 firmware image
`DFL61_HARMATTAN_40.2012.21-3.480.04.1_PR_LEGACY_480_ARM_RM-696_PRD_signed.bin` (1219100278 bytes,
sha256 `7f3515bde7b81b1d648567f717a656190feb487081cc1145e454b4494003df5b`): the rootfs is inside the
FIASCO image. Only needed for reading them on a computer; the build doesn't use them.

## Per-device data: never copy between phones

- **WLAN calibration and MAC address**: CAL's `wlan-nvs-t1` on OneNAND. At every boot Harmattan's
  `wl1271-cal` job reads it and pushes it to the driver (nl80211 testmode), as on stock.
- **Camera module calibration**: the sensor's own NVM, which camd reads.
