# DSP and video

The OMAP3630's DSP (IVA2.2) runs Harmattan's own DSP codecs through the TI DSP/BIOS Bridge,
brought back from Linux 3.16's staging tree as `bridgedriver.ko` with the interface Harmattan's
gst-dsp uses. Video decoding (H.264 and MPEG-4 up to 720p), the cameras' JPEG and video encoders and
the video-call encoder run as fast as on stock, and the DSP recovers from its own crashes without a
reboot.

## How it's set up

- **The driver**: `bridgedriver.ko` (`CONFIG_TIDSPBRIDGE=m`), which Harmattan loads itself, as on
  stock (`group-hal`, with `/etc/modprobe.d/bridgedriver`: `shm_size=0x500000
  base_img=/lib/dsp/baseimage.dof`). It loads the phone's own DSP base image and codec libraries from
  `/lib/dsp`. Userspace talks to `/dev/DspBridge` with the v3.16 driver's ioctls, the same as Nokia's.
- **Access policy**: Nokia's `/sys/class/ti_bridge/{policy,enabled,guest_mode,preempt}`
  (`55f40eaba`), through which Harmattan's resource policy (ohmd's dspep plugin) gives the DSP to one
  application at a time; the others get `SIGURG`, then `SIGKILL` after the preempt timeout.
- **Memory**: a 6 MiB DT carveout (`dsp_pool`) for the shared-memory segment, the DSP's external
  memory (base image and codec libraries, DSP addresses from 0x20000000) and the DSP MMU's page tables.
  User buffers are mapped through the DSP's MMU into a 256 MiB address pool, as Nokia's (`35585001c`).
- **Interrupts and mailbox**: the DSP mailbox (built in), the IVA2 MMU's and WDT3's interrupts, from the
  DT (`bd246db12`).
- **Clock**: the IVA2 follows the CPU's OPP, as Nokia's kernel did (`eaaeff7fe`): CPU 300, 600, 800,
  1000 MHz give IVA2 260, 520, 660, 800 MHz, slowed before a voltage drop and raised after a rise. The
  DSP is told its OPP after each change, and its own requests become a CPU frequency floor.
- **Idle**: an idle DSP hibernates after 5 s (the IVA2 off); the next message wakes it.

## What it took

Each item found by comparing with Nokia's 2.6.32 kernel, or by running the same commands on stock.

| Commit | Why |
|---|---|
| `27a077bcf` | the DSP's timers GPT5-8 from the 32 kHz clock: on the system clock DSP/BIOS's tick came every 1.7 µs instead of every 1 ms |
| `cc0a19929` | GPT5-8's interface clocks software-supervised: after asking for a timer's clocks off, DSP/BIOS waits until its `CM_ICLKEN_PER` bit reads 0, which hwmod never cleared; the DSP hung at its first request |
| `0903749ac` | the DSP timers' wakeups enabled (mainline clears them for timers Linux doesn't use) |
| `1e400d5be`, `853fa8e79` | the IVA2 powered up and waited for before waking a hibernated DSP (the first decode after a hibernation froze the phone); the warm boot address set, as stock |
| `28d9d8117`, `eaaeff7fe` | the DSP's OPP table in shared memory, and the IVA2 at the VDD1 OPP, as Nokia's |
| `a483a1b2c`, `00bac7b5f` | a wakeup ahead of every message, as Nokia's driver sent it; stale messages drained from the mailbox before a start |
| `7546a2e33` | WDT3 clocked before the DSP starts: most starts logged "In-band Error seen by IVA_SS" |
| `9d4a0692c` | user pages written back before the DSP maps them. 2.6.32's `get_user_pages()` cleaned each page; 6.18 doesn't on the Cortex-A8's cache, and gst-dsp never flushes its buffers: H.264 decoded no frame in most runs |
| `d928d5575`, `c82b47bf5`, `a54653863`, `5b477cdbd` | speed: flush and invalidate without the bridge's lock, one `get_user_pages()` per map, one cache pass per sync as Nokia's, one whole-cache flush for maps of 256 KiB and more |
| `bd79040af`, `e1159462f`, `9355f8a80` | the mailbox as Nokia's: no TX interrupt per message (5221 mailbox interrupts in 20 s of video against stock's 2052), a queue of 64 messages |
| `df1eb9813` | the mailbox's idle mode and interrupt enables kept across CORE OFF, which resets it |
| `b62e3bc98`, `23a276efd` | crash recovery (below) |
| `3d02bb8f8` | a use-after-free in `node_allocate()` (found with KASAN) |

## Speed against stock

The same script on both kernels (`tests/dsp/dspref.sh`), as user. The 720p clips are 3 s of ffmpeg's
`testsrc2`; Harmattan has no test source, so the encoders get the DSP decoder's frames.

| | stock 2.6.32 | 6.18 |
|---|---|---|
| decode 720p H.264 Baseline, 90 frames | 2.13 s | 2.03 s |
| decode 720p H.264 Main, 90 frames | 9.04 s | 8.89 s |
| decode SD MPEG-4, 100 frames | 0.92 s | 0.88 s |
| 720p decode + MPEG-4 encode (the camera's format) | 4.62 s | 4.43 s |
| 720p decode + H.264 encode | 5.01 s | 4.88 s |
| 720p decode + JPEG encode | 3.25 s | 3.23 s |
| SD decode + H.264 encode (video calls) | 4.30 s | 4.24 s |

## Video playback

The Videos app hands the file to MAFW's renderer, gst-dsp decodes on the DSP, and Nokia's X driver
shows the frames through Xv on a DSS video plane. Besides the bridge, playback needed:

- video memory for the Xv planes from a carveout, as stock's VRAM, and Xv scaling on the command-mode
  panel (see [Display](./display));
- the kernel's process events connector (`CONFIG_CONNECTOR`, `CONFIG_PROC_EVENTS`): ohmd's cgroups
  plugin classifies processes as they start, and without it the renderer ran at nice 0 instead of -11
  and stopped with "A lot of buffers are being dropped".

H.264 Baseline plays up to 720p (also 1080x720 portrait clips). H.264 Main and High decode at about
10 fps at 720p, on stock too, so such clips don't play smoothly; at 854x480 Main plays at full rate.
1080p is beyond the DSP. A cold-started Videos app drops its first play request, as on stock.

## Crash recovery

When the DSP crashes (an MMU fault, or a WDT3 watchdog overflow), the bridge tells userspace, refuses
messages to the dead DSP (`b62e3bc98`, as Nokia's), waits for every open handle to close and reloads
the base image within about 0.5 s.

A node whose create failed (for instance one the watchdog interrupted) used to be deleted without
unloading its codec library. The list of loaded libraries outlives reloads, so after the reload the
decoder's libraries counted as loaded at addresses the new DSP memory manager gave to other code, and
every decode failed ("couldn't start node") until a reboot. Nokia's `node_create()` unloads the
library in that case; so does this driver now (`23a276efd`). Tested with 5 MMU faults and 5 watchdog
overflows in a row: each reloaded, all 15 decodes after them normal, and the reference set above
unchanged right after.

## Gotchas

- Never `rmmod bridgedriver`: the IVA2 keeps running, and the next access is an L3 error and a panic.
- Never read or write IVA2 registers (the DSP MMU at 0x5D000000 and the rest) while the IVA2 is off
  (`PM_PWSTST_IVA2`, 0x483060E4, bits 1:0 read 3 when it's on): an L3 timeout, a panic.
- "ERR: clock id 2 already disabled" (or id 0) at a recovery or when a hibernated DSP is stopped is
  harmless: the bridge's own bookkeeping catches a clock gated twice.
- Apps started from a shell bypass Harmattan's resource policy, and get "dsp open failed" or "dsp init
  failed" while another user holds the DSP (camera-ui's prestarted instance, the boot animation).
- `/sys/module/bridgedriver/parameters/flush_all_min_kb` (256): buffers this large and over get one
  whole-cache flush when mapped; 0 cleans them page by page, as stock.
- With DMA API debugging the bridge's per-page cache work is very slow (camera recording fell to about
  19 fps): measure speed on normal builds.

## Tools

The build kit's `tests/dsp/` (its `README.md` has the details): `dspref.sh` (the reference set above,
on stock and here), `recovery.sh` (provoked MMU faults and watchdog overflows, then decodes),
`dsprestart` (stop, load and start through the bridge's ioctls), `dofsym.py` (the base image's
sections and symbols); and `tests/ioctl-log.c`, an `LD_PRELOAD` logger of the bridge's ioctls
(`IOCTL_LOG=sum` for a time profile, `IOCTL_UNMAP=N` to provoke an MMU fault), and `tests/gst-test.c`,
since Harmattan has no `gst-launch`. The reference pipeline:

```sh
uridecodebin uri=file:///tmp/clip.mp4 name=d d. ! video/x-raw-yuv ! identity name=out ! fakesink sync=false
```
