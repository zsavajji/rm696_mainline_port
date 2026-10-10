# Cameras

Both cameras work with Harmattan's own camera stack, unchanged: the viewfinder at 30 fps with
exposure, white balance and autofocus, switching between the cameras, stills up to 8 Mpixel, 720p
video at 30 fps, and the flash. The OMAP3 ISP is mainline's driver with the 2011 interfaces Harmattan's
binaries use; the sensors, the lens and the flash run on Nokia's own drivers.

## The hardware

| Part | Bus | Driver | Notes |
|---|---|---|---|
| Main camera, 8 Mpixel | CSI-2 (CSI2A on CSIPHY2, two data lanes), I2C2 0x10, moved to 0x37 | Nokia's `smiapp` | `smiapp-003` (Sony imx125) or `smiapp-004` (Toshiba), by module; XCLKA 9.6 MHz |
| Lens | I2C2 0x0e | Nokia's `ad58xx` | AD5836, AD5817 or BU8051GWZ, by module |
| Flash | I2C2 0x30 | Nokia's `as3645a` (a V4L2 subdev) | strobed by the sensor; its probe also turns off the red indicator NOLO leaves lit |
| Front camera | CSI-1 (CCP2 on CSIPHY1), I2C2 0x10 | Nokia's `smiapp` | `tcm8500md` or vw6558, mounted 180 degrees; XCLKB 10.8 MHz |

Both sensors answer at 0x10 until the main one is moved, so, as in Nokia's board file, the main
sensor and lens (XCLKA) and the front sensor (XCLKB) are never powered together. Both camera modules
take their analog supply from VAUX3 (2.8 V).

The sensor modes are Nokia's register lists, read from the phone's own firmware files
(`/lib/firmware/smiapp-sensor-*.bin`, `smia-sensor-*.bin`). Harmattan's 3A tuning (`/etc/omapcam/`) is
calibrated against those modes.

## Harmattan's camera stack

camera-ui, and Qt apps through QtMultimedia and camerabin2, drive GStreamer's `subdevsrc2` with
`libgstcamera2`, which sets the ISP pipeline up through the media controller and V4L2. The 3A library
`libomap3camd` reads the ISP's statistics and sets exposure, gain and focus. The viewfinder goes into
omapfb's video memory (an Xv plane) or into GPU textures; stills and video are encoded on the DSP
through gst-dsp (see [DSP and video](./dsp)).

What Harmattan's binaries expect, and where the kernel gives it to them:

| Harmattan expects | Commit |
|---|---|
| Nokia's media controller ioctls from before the merge, `_IOWR('M', 1..4)` | `814959c57` |
| entity ids 1, 2, 3... in registration order, used as list indices (6.18's are sparse) | `814959c57` |
| `VIDIOC_DQEVENT` with Nokia's 120-byte `struct v4l2_event` | `b2effda7c` |
| fields it leaves uninitialised: `which` in enumerations, the frame interval's pad | `9426ffc1a` |
| viewfinder buffers as user pointers into omapfb's VRAM (PFN mappings, 32-byte aligned) | `d2c81db51`, `062c59031` |
| the CCDC's per-frame `V4L2_EVENT_OMAP3ISP_HS_VS`, the ISP's private ioctls, Nokia's gamma bits | `d8dbc76c7` |
| the sensor at `/sys/devices/platform/i2c_omap.2/i2c-2/2-0037/{nvm,ident}` | `df99de755`, Nokia's driver |
| subdev names camd matches (`smiapp-003`, `ad5817 2-000e`, `as3645a 2-0030`...), Nokia's sensor controls | Nokia's drivers (`eea14b1ac`) |

## How a still is taken

The viewfinder stops and the pipeline runs briefly; the raw frame goes from CSI2A to memory; then
three memory-to-memory passes take it back through the CCP2 receiver's memory input into the CCDC, the
preview engine (with the 3A's parameters) and the resizer, each pass its own `STREAMON`/`STREAMOFF`.
The YUV still then goes to the DSP's JPEG encoder. An 8 Mpixel still maps three 15.9 MiB frames and
more into the DSP's address space at once; the DSP bridge's pool for user buffers is 256 MiB, as
Nokia's, for that (`35585001c`).

## The commits

| Commit | What |
|---|---|
| `814959c57`, `b2effda7c`, `9426ffc1a`, `d2c81db51` | Harmattan's media, event, subdev and user pointer interfaces (above) |
| `d8dbc76c7` | omap3isp with Harmattan's interfaces: the HS_VS event, the D-PHY timing from the sensor's link frequency, one IOMMU mapping per buffer, statistics stamped with the wall clock, L3 held while streaming (`omap3_l3` holder `isp`) |
| `eea14b1ac` | Nokia's smiapp, ad58xx and as3645a on the 6.18 APIs, with the board file's glue (`drivers/media/i2c/nokia-camera`) |
| `b152ccc33` | the DT: both modules, the lens, the flash, both ISP ports |
| `ea7919a99`, `d793f1183` | the ISP built in; the sensor, lens and flash drivers modules (`smiapp`, `ad58xx`, `as3645a`) that udev loads once the root is up, so the firmware comes from the phone, as stock |
| `1b2c8963f` | mainline bug: the histogram's buffers were allocated for a NULL device; the first histogram set-up oopsed |
| `062c59031` | mainline bug: a PFN user pointer was mapped from its page's start; each frame landed up to a page early |
| `74d9d3a45` | the CSI2 video port at least as fast as the link; the preview engine had finished one frame a second |
| `d2e537990` | mainline bug: the time32 statistics request ran on a zeroed struct, so the 3A got nothing (a black viewfinder) |
| `f9ce98a51` | several video nodes streaming in one pipeline: switching cameras or taking a still freed the pipeline twice |
| `6a190206b` | the CSI-1 receiver set up as Nokia's driver did: the front camera |
| `fe27ef0a9` | the main sensor's scaled DPCM8 modes not offered (below) |
| `e1792b9bf` | the ISP's IOMMU powered only while the ISP is in use; it held the CAM domain on, and the CPU never left C1 |

Outside the kernel, the SGX driver (`osfunc.c` in `pvr_sgx_rm696`) takes a PFN mapping's addresses from
the page tables: 6.18 no longer keeps the PFN in the mapping, and the GPU read from physical address 0
when an app put the viewfinder in GPU textures (an L3 error, a panic).

## Checking it

```sh
dmesg | grep -i "smiapp\|ad58\|as3645\|omap3isp"
lsmod | grep "smiapp\|ad58xx\|as3645a"
ls /dev/media0 /dev/video* /dev/v4l-subdev*
cat /sys/devices/platform/i2c_omap.2/i2c-2/2-0037/ident   # the main sensor
cat /sys/kernel/debug/omap3_l3                            # the isp hold while streaming
```

The build kit's `tests/camera/` has the tools used for the port: `ispcap` (captures with Harmattan's
interfaces: front camera, raw, DPCM and memory-to-memory modes), `camabi.py` (compares Nokia's camera
headers with 6.18's), `smiafw.py` (dumps a sensor's register lists), `uyvy2ppm.py`.

## Limitations

- **The main sensor's scaled DPCM8 modes** (2728x2048, 3144x1772) are switched off when the firmware
  is read (`... DPCM8 mode with sensor scaling disabled` in the log). In them the sensor codes the
  first pixels of each odd line against the line two above, which the CCP2 memory input can't
  decompress: stills came out with colour streaks, and Nokia's stack most likely had them too.
  Harmattan picks another mode instead; camera-ui's resolutions never used these.
- gst-dsp doesn't check its DSP memory reservations (userspace): with a smaller pool an 8 Mpixel still
  made the DSP fault. The 256 MiB pool makes them succeed.
- In one stream, a memory-to-memory pipeline's second single-shot frame never comes (6.18 counts the
  modules as started). Harmattan runs one frame per stream, so only test tools see it.
- An app started from a shell instead of through Harmattan may get "dsp open failed" while camera-ui's
  prestarted instance holds the DSP (the bridge's access policy); start it again.
- camera-ui refuses to start ("cannot use camera while usb is connected") when MyDocs isn't writable.
- Measure speed on a normal kernel: with DMA API debugging the DSP bridge's cache work cost 30 ms a
  frame and recording fell to about 19 fps.
