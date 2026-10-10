# What this kernel removes, and how to put each back

Everything the N9 kernel (`../linux_mainline_rm696`, branch `rm696`) leaves out or switches off
compared with mainline Linux 6.18 (`omap2plus_defconfig`) and the stock N9 kernel (2.6.32), with the
reason, what it measured, and how to undo it. Config lines live in
`arch/arm/configs/rm696.config` (change the line, commit, rebuild: `kernel/build.sh` checks every line
stuck); code changes are single commits on `rm696` (`git revert <commit>`). The full story of each is
in `NOTES.md` ("Kernel speed against stock", "Context switch cost").

Measurements are kbench at a pinned 1 GHz in Harmattan's `/system/applications/standby` cgroup unless
said otherwise; stock 2.6.32 in the same cgroup: thread switch 7.3-7.6 us, process switch 9.3, page
fault 6.1-6.4, pipe write+read 2.25-2.53, syscall 0.34-0.40.

## 1. Speed: hardware support and kernel features (config)

Decided by me on 2026-10-03 ("as fast as stock", none of what 2012's kernel didn't have),
extended on 2026-10-05.

| Removed | rm696.config | Why | Effect measured | Put it back if |
|---|---|---|---|---|
| Other OMAP SoCs and the ARMv6 baseline | `# CONFIG_ARCH_MULTI_V6`, `ARCH_OMAP2`, `ARCH_OMAP4`, `SOC_OMAP5`, `SOC_AM33XX`, `SOC_AM43XX`, `SOC_DRA7XX`, `SOC_TI81XX`, `ARCH_OMAP2PLUS_TYPICAL` (`is not set`; its selects listed) | omap2plus' OMAP2 (ARM1136) boards made the whole kernel ARMv6; OMAP4/5 brought Cortex-A9/A15 errata work | with the rest of this table: process switch 30-32 us -> 14.5 (2026-10-03) | the kernel must boot another OMAP |
| Highmem | `CONFIG_VMSPLIT_3G_OPT=y`, `# CONFIG_HIGHMEM` | all 1 GB as lowmem, stock's 3G/1G-like split, no temporary mappings | (in the set above) | a process needs more than 2.75 GB of address space |
| SMP (one core) | `# CONFIG_SMP` (so also `# CONFIG_CPU_FREQ_GOV_SCHEDUTIL`) | the N9 has one core | (in the set above) | never on the N9 |
| Spectre v2 mitigations | `# CONFIG_HARDEN_BRANCH_PREDICTOR`, `# CONFIG_HARDEN_BRANCH_HISTORY` | 2.6.32 had none; since rm696 fd20d1f6a this also drops the Cortex-A8 BTB flush on every process switch (section 2) | (in the set above) | untrusted code runs on the phone; or random Thumb-2 segfaults (section 2) |
| Software PAN | `# CONFIG_ARM_PAN` | domain switch around every user access; absent in 2012 | (in the set above) | exploit hardening wanted |
| VMAP stacks | `# CONFIG_VMAP_STACK` | entry checks, TLB pressure; absent in 2012 | (in the set above) | debugging stack overflows |
| Stack variable zeroing | `CONFIG_INIT_STACK_NONE=y` | zeroes every local; absent in 2012 | (in the set above) | info-leak hardening: `CONFIG_INIT_STACK_ALL_ZERO=y` |
| Stack protector | `# CONFIG_STACKPROTECTOR` (2026-10-05, 1bab15612) | a canary check in every function with a local array; ARM got it in 2.6.36, stock had none | pipe write+read 1.90-1.99 -> 1.74-1.75 us; thread switch 9.23-9.62 -> 9.16-9.37 | stack-smashing detection wanted |
| Syscall audit | `# CONFIG_AUDIT` | per-syscall hooks; Harmattan runs no auditd, stock had none | (in the set above) | an audit daemon is installed |
| Schedstats | `# CONFIG_SCHEDSTATS` | scheduler debug statistics, unused | (in the set above) | scheduler debugging |
| cgroup controllers stock didn't have: cpuacct, perf_event, blkio, devices; CFS bandwidth | `# CONFIG_CGROUP_CPUACCT`, `# CONFIG_CGROUP_PERF`, `# CONFIG_BLK_CGROUP`, `# CONFIG_CGROUP_DEVICE`, `# CONFIG_CFS_BANDWIDTH` (2026-10-05, 36a157526) | Harmattan's syspart mounts every controller the kernel has; stock had cpu, memory, freezer | thread switch 9.74-9.79 -> 9.23-9.62 us, process 11.33-11.49 -> 10.94-11.01; syspart mounts `cpu,memory,freezer` as on stock | per-cgroup CPU accounting, I/O or device control, or CPU quotas are needed |
| Memory-cgroup charging of kernel allocations (memcg kmem) | `cgroup.memory=nokmem` in `CONFIG_CMDLINE` (2026-10-05) | 2.6.32 charged only user pages; 6.18 charges every slab allocation of a fork or exit too | 300 fork+exec+exit 1.65 -> 1.52 s; page faults slightly cheaper | memory limits must also bound kernel memory: drop `cgroup.memory=nokmem` |
| 250 Hz tick (now 128) | `CONFIG_HZ_128=y` (a choice added to arch/arm/Kconfig; 2026-10-05, 281cc3d23) | stock's rate, a whole 256 cycles of the 32 kHz timer | video: timer interrupts 5832-6466 -> 4220-4280 in 20 s (stock 3576) | finer scheduling ticks wanted: `CONFIG_HZ_250=y` |
| Schedutil | `# CONFIG_CPU_FREQ_GOV_SCHEDUTIL` | needs SMP; Harmattan runs ondemand (my choice after idle measurements) | | (needs SMP) |

## 2. Speed: work the code no longer does (commits on rm696)

| Removed | Commit | Why | Effect measured | Undo |
|---|---|---|---|---|
| Load tracking (PELT) and group-share divisions on one CPU | 0658adb07 "sched/fair: no load tracking or group-share division on one CPU" | Linux 6.17 made SMP unconditional; a UP kernel ran SMP load tracking and a 64-bit division per cgroup level on every enqueue/dequeue/pick. Back to v6.16's UP paths (`update_load_avg()` only the cpufreq hook, shares = `tg->shares`, no newidle balance, no removed-load bookkeeping) | ~1 us a switch: wakeup 3850 -> 2990 cycles (threads), 6650 -> 4100 (processes) | revert (only matters on a UP kernel) |
| The Cortex-A8 branch predictor flush on every process switch | fd20d1f6a "ARM: Cortex-A8: BTB flush on mm switch only with branch predictor hardening" | mainline flushed BTAC/BTB on every mm switch; the N9's firmware sets ACTLR.IBE (0x42), so it ran: 576 cycles plus a cold predictor; stock had no flush. **Risk** (accepted by me, 2026-10-04): mainline added it after random Thumb-2 segfaults on r3p2 A8 boards with IBE set (erratum 687067) | process switch 16.5-17.4 -> 11.8-13.1 us | `CONFIG_HARDEN_BRANCH_PREDICTOR=y`, or revert, if random segfaults appear |
| McBSP wakeups waking the CPU | 3a5439de6 "ARM: OMAP3: PM: don't wake the MPU for McBSP wakeups" | mainline groups McBSP2/3/4 with the MPU; every audio FIFO request woke the CPU with a PRCM interrupt (~210/s); Nokia's kernel grouped only GPIO2-6 and UART3 | video busy 54-55% -> 52.1%; PRCM interrupts 9668 -> 3106 in 20 s | revert |
| A TX interrupt (and mailbox thread run) per DSP message | bd79040af "mailbox: omap: flush, ...", e1159462f "staging: tidspbridge: send mailbox messages without a TX interrupt" | messages now go straight into the FIFO, as Nokia's mailbox; a full FIFO still uses the interrupt | video busy 52.1% -> 50.0%; mailbox interrupts 5240 -> ~2050 (stock 2052) | revert both |
| `update_curr()` at cgroup levels with one entity when picking | 011f4ba41 "sched/fair: no runtime update at levels with one entity when picking" | alone on its cfs_rq the entity is the pick; its runtime is accounted at the next update there (exec_start stays) | thread switch -0.6 us (kbench 9.16-9.37 -> 8.25-8.68 us) | revert |
| An I-cache invalidation for every executable page mapped | f49e9543d "ARM: mm: sync the I-cache once per change of a page, not per mapping" | now once per change of the page's contents (PG_icache_clean, as arm64) | 300 busybox spawns 1.82 -> 1.65 s | revert |
| CPU temperature read every second (now every 5 s) | 4fee13dd9 "ARM: dts: omap3-n9: read the CPU temperature every 5 s" | each read of the OMAP3630 bandgap (mainline: unreliable) busy-waits up to 2.5 ms; stock read no CPU sensor. Above the passive trip (80 C) it still polls every 250 ms | ~0.2% CPU | `polling-delay` in `omap3-n9.dts` |
| RCU mode of the VMA maple tree (a node copy and an RCU free for every store) | 99afc1677 "mm: the VMA maple tree without RCU mode when there are no per-VMA locks" | without per-VMA locks (they need SMP) every reader of the tree holds mmap_lock, and every writer holds it for writing | on the perf branches (with Tiny RCU): file mmap+munmap 16.6 -> 14.0 us, mprotect 5.7-6.5 -> 4.5 us, fork 7.0 -> 6.8 us a VMA; all three rows together: next row but one | revert (needed if `CONFIG_PER_VMA_LOCK` ever comes back) |
| Two 256-byte node copies and a clear for each maple tree store | 5d18d64ac "maple_tree: node stores in place outside RCU mode" | outside RCU mode nobody reads the node mid-store: the slots after the new range are shifted in place (the kernel's maple tree test suite passes) | ~5% (perf branches): loop mmap+munmap 15.1 -> 14.3 us, mprotect pair 10.3 -> 9.2 | revert |
| A walk of the gap tree for every mmap without an address (top-down first fit: the highest gap) | e87ff0337 "mm: a free area hint for top-down mmap, as 2.6.32's free_area_cache" | on 32-bit the walk scans the whole top leaf every time (the stack's reserve above mmap_base is a gap too big to skip): ~2 us. Now the area under a per-mm hint (the last area found, or the top of the last hole munmap made) is tried first, confirmed free with one VMA lookup, else the walk runs. **Changes placement**: the area found may not be the highest that fits, as on 2.6.32; a new mapping can land next to (and merge with) another, e.g. forkbench's mprotect buffer: 5.9 -> 6.4 us | mmap alone 8.1 -> 6.8 us; old rm696 55a7a12 -> e87ff0337 (all three rows, plain ext4, idle): file mmap+munmap 16.6-18.5 -> 12.6 us (stock 3.5), anonymous 15.8 -> 9.7, mprotect pair 12.8 -> 8.6 | revert |
| A new anon_vma for every anonymous VMA of a forked child (an allocation, a second chain link and interval tree insert per VMA, their teardown at exit) | 42ab3b71f "mm: the child shares the parent's anon_vma at fork, as 2.6.32" | ~3 us of fork's 6.8 us a VMA. The child keeps the parent's anon_vma, as 2.6.32 did. **Trade-off**: reclaim, migration and KSM looking for the processes that map a page the child copied also visit its siblings' VMAs (fine with dozens of processes; mainline changed it in 2.6.34 for servers forking thousands). `tests/cowstress.c` (COW data checked under zram swap-out, 0 errors) and the video test (CMA migration) pass | fork, per extra VMA, 6.72-6.94 -> 5.22-5.40 us | revert |
| A walk of all VMAs at every process exit (BSD process accounting's memory size) | 0a00d483a "acct: the exiting mm's size from total_vm, not a walk of every VMA" | total_vm is that size, kept with every mapping | with uprobes off (next row): per VMA -0.15 us | revert |
| uprobes | `# CONFIG_UPROBES`, `# CONFIG_UPROBE_EVENTS` (b00ac605c) | hooks in every mmap, munmap and fork; Harmattan has no tracer for them (kprobes stay) | (with the row above) | user-space probes are needed |
| A generic maple store for each VMA copied by fork | d0bec3fb6 "mm: dup_mmap replaces each copied tree entry with one pointer store" | after the bulk tree copy the iterator is on the slot already: `mas_replace_entry()` writes it | per VMA 5.07-5.26 -> 4.91-5.14 us; with the three rows above, old rm696 e87ff0337 -> d0bec3fb6 (gated, plain ext4): fork per VMA 6.72-6.94 -> 4.91-5.14 us (stock 2.65), booster-like fork 5190-5233 -> 4336-4453 us (stock 2682) | revert |
| Stopping and restarting SmartReflex at every MPU or CORE retention entry (~300 a second) | 5857f2ef3 "ARM: OMAP3: PM: don't stop SmartReflex for every idle entry" (rm696) | our own e7f916d32 had added it, reading Nokia's idle path as a class 3 pause; Nokia's ran class 1.5, where that call does nothing once an OPP is calibrated. Since then the stops often timed out ("sr_v2_disable: Smartreflex disable timedout", a 200 us busy-wait each, thousands a boot) | no timeouts since; the idle cost itself isn't measurable apart (see NOTES.md) | revert (only meaningful with class 3, next section) |

## 3. Stock compatibility (Harmattan expects stock's interfaces)

| Removed | Where | Why |
|---|---|---|
| omapdrm and its DSI panel | `# CONFIG_DRM_OMAP`, `# CONFIG_DRM_PANEL_DSI_CM` | Harmattan's X and omaplfb drive omapfb's `/dev/fb0` and ioctls |
| Framebuffer console | `# CONFIG_FRAMEBUFFER_CONSOLE` | `/dev/fb0` belongs to omaplfb and X |
| Power-off | `n9-harmattan.patch`: `ti,use_poweroff` deleted | the power button is broken: a power-off halts and the watchdogs reset into stock instead |
| TWL4030 charger node | `n9-harmattan.patch` | BME charges, as stock; the kernel only reports the charger (`twl5031-bcc.patch`) and, since 2026-10-07, its type (Nokia's charger-type detection, rm696 e084ac271) |
| Carkit MADC routing | `twl4030-madc-chardev.patch` | Nokia's `/dev/twl4030-adc` for BME |
| SGX smart idle/standby while powered | `sgx-sysc-no-smart-idle.patch` | after standby the SGX wedged mid-reset (external abort, panic) |
| SmartReflex class 3 (SR and the voltage processor running all the time) | `# CONFIG_POWER_AVS_OMAP_CLASS3`, `CONFIG_POWER_AVS_OMAP_CLASS1P5=y` (rm696 271ae6cb6; the calibrated voltages are class 3's) | stock ran class 1.5 (`board-rm696.c`: `sr_class1p5_init()`): each OPP's voltage calibrated once, again after 24 h, SR off in between (NOTES.md "SmartReflex class 1.5"). To go back: the two lines swapped in rm696.config, and revert 5857f2ef3 if class 3 should pause in idle again |
| Touch report limit (one report per 7 ms after a touch's first 25 ms) | Nokia's `atmel_mxt.c` (`rlimit_min_interval_us`, `rlimit_bypass_us`) not ported | more samples were wanted (me, 2026-10-01: "a small touch precedes every swipe"); nothing in Harmattan sets the limits (NOTES.md "Harmattan boot", touch sampling). To put back: port the two sysfs knobs and the limit in the T9 report path |
| PN544 sysfs `nfc_test` | rm696 34c9fae34 (`drivers/misc/nokia-pn544.c`) | the board's GPIO self-test, read only by `stserver`'s factory tests at a 2.6.32 path (`/sys/devices/platform/i2c_omap.3/...`); stock's left the chip powered in firmware mode. To put back: a read-only attribute that sets FW_RESET 0 then 1 with ENABLE high and reports whether the line followed (`docs/nfc.md`) |
| V4L2 flash LED class, pstore compression | `# CONFIG_V4L2_FLASH_LED_CLASS`, `# CONFIG_PSTORE_COMPRESS` | flash LED built in without V4L2; ramoops records readable as is |

## 4. Safety (the test phone: broken power button, nothing written)

| Removed | Where | Why |
|---|---|---|
| OneNAND writes, erases, bad-block marks, locks, on test boots | `onenand_omap2.read_only`, set by `ramboot/init` (branch stock-userspace, 2026-10-09; before: `onenand-read-only.patch`, always) | never write the phone's flash from a test boot; the kernel itself writes CAL as stock (no cache program, no write verify, NOLO's locks kept) |
| OTP writes and locks | `# CONFIG_MTD_ONENAND_OTP` (as stock) | a lock of the OTP area is permanent |
| mtdoops | `# CONFIG_MTD_OOPS` | stock wrote oopses to NOLO's "log" partition; to put back after the write path is proven on "log" |
| Power-off, on test boots | `twl4030_power.poweroff_halt`, set by `ramboot/init` (branch stock-userspace; before: `ti,use_poweroff` deleted from the DT) | the test phone's power button is broken: a power-off halts and the watchdogs reset it. The kernel powers off as stock otherwise |
| Watchdogs that stop on close, on test boots | `/sys/class/watchdog/watchdog{0,1}/nowayout`, set by `ramboot/init` (branch stock-userspace; before: `CONFIG_WATCHDOG_NOWAYOUT=y`) | the session feeds them; if it dies, they reset the phone. The kernel stops them on close as stock otherwise |
| Touch controller NVM writes (Nokia's `backup_config`) | rm696 a3bde6b3a "Input: atmel_mxt_ts: Nokia's configuration controls for mxt_configure.sh" | an NVM write on the touch chip; `mxt_configure.sh` asks for it only when the chip's NVM checksum differs from the configuration file's, and on this N9 they match (`0x29b82f`, NOTES.md "Small interfaces Harmattan reads"). To put back: a write-only `backup_config` that sends T6 BACKUPNV (0x55), as Nokia's `mxt_backup_settings()` |
| PN544 firmware download (a rewrite of the NFC chip's flash) | rm696 34c9fae34: `PN544_SET_FW_MODE` 1 returns `-EPERM` unless `nokia_pn544.allow_fw_mode=1` (boot argument or `/sys/module/nokia_pn544/parameters/allow_fw_mode`) | nfcd rewrites the chip whenever its 4 version bytes differ from `libNXP_NFC_HAL`'s image; on this N9 they match (never asked). To put back: set the parameter, or drop the check in `pn544_do_ioctl()` |
| eMMC writes (test boots) | `ramboot/init`: `blockdev --setro`, RAM overlays | Harmattan runs read-only until I decide otherwise |
| Nokia's `hsi_char` (stock's board registered it) | `CONFIG_HSI_CHAR` not set (as omap2plus) | used only by Nokia's modem flasher (`fiasco-flasher`); call audio and Phonet don't need it (`docs/audio.md`). To put back: `CONFIG_HSI_CHAR=y` and a client on the SSI port |

## 5. RAM for Harmattan (branch stock-userspace, 2026-10-09, my go)

Harmattan's `/etc/init/enable-swap.conf` gives 256 MB of compressed swap above 1,000,000 kB of
MemTotal, 64 MB below. Nokia's kernel left ~1,008,400 kB ("Memory: 1002MB 2MB = 1004MB total",
1,008,256 KB available), rm696 990,420: a ~14.7 MB bigger image, 4.2 MB more log buffer, 1 MiB more
ramoops, 2 MiB of RAM dropped. Measured with scratch builds and on the phone.

| Removed | Where | Freed | Put it back |
|---|---|---|---|
| 1 MiB taken off the top of RAM for `omap_secure_memblock_base`, which nothing reads; it also left mapped RAM off a 2 MiB boundary ("Ignoring RAM at 0xbea00000-0xbff00000") | rm696 commit "ARM: OMAP2+: don't steal 1 MiB of RAM for an unused secure RAM base" | 2 MiB | revert |
| The 1 MiB kernel log and its 3.2 MiB of printk metadata | `CONFIG_LOG_BUF_SHIFT=18` (256 KiB), no `log_buf_len=1M` | 3.4 MB | `log_buf_len=1M` in `CONFIG_CMDLINE` (a debug image) |
| W^X padding around the kernel's text and rodata (stock had no W^X) | `# CONFIG_STRICT_KERNEL_RWX` | 0.9 MB | `CONFIG_STRICT_KERNEL_RWX=y` |
| ramoops' 6 records (now 2) | `omap3-n9.dts` ramoops `reg` 512 KiB | 0.5 MB | `reg = <0x8f000000 0x100000>` |
| Half the dentry and inode hash buckets | `dhash_entries=65536 ihash_entries=32768` in `CONFIG_CMDLINE` | 0.4 MB | drop both |
| WLAN's firmware built in (now a file next to the modules, `firmware_class.path`) | `CONFIG_EXTRA_FIRMWARE` without `ti-connectivity/wl127x-fw-5-sr.bin` | 0.4 MB | add it back |
| IPv6 built in (a module, as stock's: `net-pf-10` autoloads it) | `CONFIG_IPV6=m` | 0.4 MB if never loaded | `CONFIG_IPV6=y` |
| omap2plus' built-ins for other boards, unused on the N9 and by Harmattan: NFS, root NFS, IP autoconfiguration, UBI/UBIFS (fstab's `ubi0:var` is `noauto`; stock had them), zstd, Ethernet, ATA/SCSI (so USB host storage), PCI, raw NAND/CFI, JFFS2/CRAMFS/ext2 (ext4 mounts ext2)/quota, other boards' PMICs, regulators and DMA, remoteproc, DVB/analog TV/SDR/test media, gadget audio/MIDI/HID/EEM, ethtool netlink, kexec (so `/proc/atags`, which stock didn't have either), IKCONFIG | the `is not set` block at the end of `rm696.config` | 4.5 MB | delete its line |

## 6. The test harness (not the kernel; `ramboot/init`, 2026-10-05)

| Removed | Why | Effect |
|---|---|---|
| Forks in the init's loops (`sleep`, `date`, `stat`, `grep`, `cat`, `ip`): `read -t` on a FIFO and shell builtins instead; the session's age checked once a minute (ends 600-660 s after the last touch) | ~4 forks a second, each a process event Harmattan's ohmd classifies | idle with the screen off 5.3-6.3% -> 2.2% busy (stock 1.2%) |
| The MyDocs kernel log every 10 s (now every 30 s) | an eMMC remount and write each time; pstore keeps a crash's last words anyway | fewer eMMC writes at idle |

## Tried and not kept (nothing removed)

- Lazy preemption (branch `perf-lazy`: ARM32 support for PREEMPT_LAZY written, with tiny RCU as a
  result): thread switch 7.73-8.10 -> 8.96-9.24 us, process 9.15-9.53 -> 10.16-10.65, video busy
  44-45% -> 48%, no fewer switches; only page faults gained a little. The ARM32 support commit is there
  if wanted later.
- The fair server (deadline server for fair tasks) off: no measurable difference; it stays on.
- Deep idle states off (C1/C2 only): video busy ~1 point lower, within noise; they stay on.
- Tiny RCU with full preemption, as 2.6.32 (branch `perf-tinyrcu`, d12a27dca): no gain for spawns
  (300 fork+exec+exit, spawnbench within noise), loop mmap+munmap ~0.5 us; left out because it changes
  RCU's semantics for little.
- `-Os` for the maple tree, mm/vma.c and mm/mmap.c only (branch `perf-mmap`, 97d630d5c, reverted):
  file mmap+munmap 14.3 -> 18.3 us, slower like the whole-kernel `-Os` (the A8's 32 KB I-cache isn't
  what limits these paths).

- Block reads for the accelerometer (`st,use-block-read`, branch `perf-lis3-blockread`): worked, ~0.2%
  CPU, but its boots hit a conndlgs/bluetoothd storm later traced to the firmware path; not retried.
- `-Os` like stock (branch `perf-os`): with GCC 14, switches 14-16 us and faults 9-11 us, much slower.
- Scheduler feature switches (`tests/schedfeat.sh`): none helped.
- Fault-around smaller (debugfs `fault_around_bytes`): 4 KB makes spawns ~4% faster but library faults
  3x slower (2.73-2.88 us a page vs 0.89-0.95); the default 64 KB stays.
- Fewer proc-connector events for ohmd: Nokia's 2.6.32 already sent comm and ptrace events
  (backported), so stock's ohmd gets the same; nothing to trim.
- Taking GPT1 (the system timer) out of the MPU's wakeup group: it wakes the CPU from the deeper idle
  states; ~0.1% CPU at stake.
- GPT10 on the 19.2 MHz system clock as clocksource and sched_clock instead of the 32 kHz counter
  (9dd028eba, 0011bae2d, 14486a623; the counter sits on the wakeup L4, ~780 ns a read, GPT10 ~250 ns):
  clock_gettime 1.15 -> 0.78 us, sched_yield 1.60 -> 1.25, process switch 10.40-10.68 -> 9.15-9.53 us.
  Reverted (a7b61bb36, 2026-10-06; me: "keep the revert"): GPT10's running clock keeps CORE out of
  retention and OFF. The other two commits stay, inert without `ti,timer-clocksource`. Getting the
  speed back without blocking CORE idle: `docs/performance.md`.
