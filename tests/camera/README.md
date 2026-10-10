# Camera port tools (2026-10-06)

- `camabi.py NOKIA_TREE MAINLINE_UAPI_ROOT`: compares the camera ABI of Nokia's 2.6.32 headers
  (`../../kernel-plus-harmattan`) with 6.18's uapi (`git -C ../linux_mainline_rm696 archive rm696
  include/uapi arch/arm/include/uapi | tar -x -C DIR`), as an ARMv7 build sees them: every constant
  both define and every struct layout (clang `--target=armv7a-linux-gnueabi`).
- `ioctlscan.py LIB...`: the V4L2 ('V') and media ('|') ioctl numbers in ARM binaries (movw/movt
  pairs and literal words), e.g. Harmattan's `usr/lib/libomap3camd.so.0.0.0`. Nokia's media ioctls
  are type 'M': resolve r1 at the `ioctl@plt` call sites for those.
- `smiafw.py FW...`: dumps Nokia's sensor register-list firmware (`/lib/firmware/smiapp-sensor-*.bin`):
  each list's type, mode size, format, frame time, pixel and output clocks.
- `ispcap.c` (built by `tests/build.sh` as `build/ispcap`; run in Harmattan: `chroot /newroot /tmp/ispcap`):
  `ispcap [frames [width height [sensor-width sensor-height [prv]]]]` streams the main camera through
  sensor, CSI2a, CCDC, preview and resizer (or the preview output, `prv`) with MMAP buffers and no 3A,
  as Harmattan's camera source sets the pipeline up (Nokia's 'M' media ioctls, `nokia-media.h`;
  the subdev structs as its binaries use them: the SDK's headers in n9-qemu's sysroot are older), and
  prints the frame rate. The resizer downscales at most 4x.
- `fbshot.py OUT.png`: a screenshot of the RAM-booted phone's framebuffer (X's screen, not DSS video
  planes such as an Xv viewfinder).

Running Harmattan's camera apps on a test boot (as root, through `build/s.sh`):
- MyDocs is read-only there, which camera-ui takes for USB mass storage ("you cannot use camera while
  usb is connected"): `mount -t tmpfs -o size=300m,uid=29999,gid=29999 tmpfs /newroot/home/user/MyDocs`
  first (RAM only, hides the real MyDocs until unmounted; with 64 MB camera-ui says "out of space" and
  won't record), unlock the screen (`ramboot/unlock.sh`),
  kill the prestarted `camera-ui`, then `chroot /newroot su user -c ". /tmp/session_bus_address.user;
  dbus-send --session --type=method_call --dest=com.nokia.maemo.CameraService /org/maemo/m
  com.nokia.MApplicationIf.launch"`.
- My Qt test app: `chroot /newroot su user -c ". /tmp/session_bus_address.user; DISPLAY=:0
  /opt/qt5-cameratest/bin/qt5-cameratest"` (its console.log lines report the camera status: 8 = active).

ispcap's other modes (environment variables, combinable with ISPCAP_SAVE=file, which keeps the last frame;
save to the MyDocs tmpfs, /newroot/tmp is a 4 MB tmpfs):
- `ISPCAP_FRONT=1`: the front camera through CCP2 (`ispcap 60 320 240 576 432`).
- `ISPCAP_RAW=1`: raw SGRBG10 frames straight from CSI2a to memory, as Harmattan's still capture
  (`ispcap 10 0 0 1632 1232`).
- `ISPCAP_M2M=file`: a raw frame from the file through the CCP2 receiver's memory input, CCDC, preview
  and resizer (`ispcap 1 816 612 1632 1232`), as Harmattan's still processing. One frame per run: a
  second single-shot frame in one stream never comes on 6.18 (NOTES.md "Cameras").
- `ISPCAP_DPCM=1`: the sensor's DPCM8 modes (the 8 Mpixel ones at 15 fps); the CCDC refuses them
  (-ENOSPC, as stock's driver: their line-average pixel rate is above L3/2).
- `uyvy2ppm.py IN.yuv W H OUT.ppm`: a saved UYVY frame as an image (`sips -s format png` for PNG).
- `camtest.sh CSI2_VP_DIV OCP_AUTOIDLE SBL_AUTOIDLE [ispcap args]` (on the phone, branch `camera-debug`
  only): one ispcap run with the debug switches, then the frame rate, the ISP/SBL/CSI2 interrupt counters
  and the dividers chosen.
- `ramboot/tap.pl /dev/input/event3 X Y`: a tap on the touchscreen (landscape framebuffer coordinates).
- `ISPCAP_DPCM` with `ISPCAP_RAW=1`: 1 keeps the sensor's DPCM8 data in memory (`BD10`), 2 has CSI2
  decompress it to raw10; with `ISPCAP_M2M`, the input file is DPCM8 for the CCP2 to decompress (the
  DSP agent's additions; `build/dspcam-tools/dpcm*` decode such frames offline).
