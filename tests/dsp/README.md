# DSP (tidspbridge) debugging tools

Made during the bridge bring-up (2026-10-03, boots 89-106); see README "DSP bridge". All phone-side
scripts run as root on the RAM-booted test kernel unless noted.

- `../gst-test.c` (build/gst-test): runs a GStreamer 0.10 pipeline (Harmattan has no gst-launch),
  counts buffers at an element named `out` and at every fakesink. The reference pipeline, the same on
  stock and here: `uridecodebin uri=file://CLIP name=d d. ! video/x-raw-yuv ! identity name=out !
  fakesink sync=false`. `filesrc ! qtdemux ! dspvdec` fails on stock too; playbin2's sinks aren't
  counted.
- `../ioctl-log.c` (build/ioctl-log.so): LD_PRELOAD logger of the bridge's ioctls (magic 0xDB): cmd,
  args, return; message words for put/get message, library path for register; with
  `IOCTL_LOG=sum` only a per-command time profile at exit. As root it also compares the CPU's view
  with DRAM (non-cacheable /dev/mem) after flushes, invalidates and at input hand-off (that found the
  stale SPS/PPS). Works on stock as user (no DRAM view).
- `../kbench.c` (build/kbench): syscall, sched_yield, pipe, thread and process context switch, page
  fault, memset/memcpy. Compare kernels with the CPU at 1 GHz and from the same cgroup (Harmattan
  puts the test kernel's ssh session in /system/applications/standby, share 64: move to
  /newroot/syspart/system/tasks, stock's own session is in /system).
- `dspref.sh`: the reference set, the same on stock and the test kernel (as user): 720p H.264
  Baseline/Main and SD MPEG-4 decodes, and the DSP encoders (720p MPEG-4 as the camera, 720p H.264,
  JPEG, SD H.264 as video calls) fed by the DSP decoder. Results: README "DSP open points closed".
- `dsprestart.c` (build/dsprestart N, root, in `chroot /newroot`): stop, reload and start the DSP N
  times through the bridge's ioctls, the steps of its recovery (each start can be checked in the log).
- `IOCTL_UNMAP=N` with `../ioctl-log.c`: unmaps the Nth mapping of 1 MiB or more right after it's
  made, so the DSP writes to an address its MMU can't translate: a real DSP MMU fault and recovery.
  A DSP watchdog (WDT3) overflow instead: switch the DSP MMU's table walk off mid-decode
  (`devmem 0x5D000044 32 0x2`, then `devmem 0x5D000060 32 0x1`), only after PM_PWSTST_IVA2
  (0x483060E4) reads ON in the same command: any access to the IVA2 while it's off is an L3 timeout,
  a panic, a reset into stock.
- `stock-dsp.sh`: the reference decode runs, on stock as user (`ssh n9 sh -s < stock-dsp.sh`, with
  gst-test copied to stock's /tmp, a tmpfs: nothing on the eMMC).
- `dsptest.sh`: load the bridge, kprobes on its paths, one decode; read trace_pipe from the Mac.
- `kprof.sh` + `kprof.py`: entry/return kprobes on bridge functions (KPROF_FUNCS=...), one decode,
  then durations per function on the Mac (the trace clock is the 32 kHz counter: 30.5 us ticks).
- `dofsym.py`, `dofimg.py`: symbols/sections of the DSP base image; dofimg writes the loadable
  sections as a flat image at 0x20200000 (DOF sections are packets {num_relocs, size, checksum,
  data}). Disassemble with GNU binutils for C6x: binutils 2.43.1 `--target=tic6x-elf
  --with-system-zlib --disable-gdb --disable-gprofng --disable-sim --without-zstd`, `make
  MAKEINFO=true all-binutils` (bundled zlib fails on the macOS SDK); objcopy -I binary -O
  elf32-tic6x-le, --change-section-address .text=0x20200000, --add-symbol per DOF symbol.
