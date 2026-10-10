# Performance

The aim is stock's speed or better, on the same phone with the same userspace. Against Nokia's 2.6.32
this kernel is ahead on system calls, scheduling and file access, level on memory bandwidth, the GPU
and DSP video, and behind on the VMA layer and process creation. This page has the numbers, the
changes behind them, what is left, and how to measure.

All comparisons are on the same N9, stock PR1.3 on Nokia's kernel against this one, both processes in
the same Harmattan cgroup. The phone ran the community FasterN9 package on both kernels, so its cgroup
policy is in every number.

## Against stock

`tests/kbench.c`, `forkbench.c`, `spawnbench.c` and `busy.sh`, as user in
`/system/applications/standby`, on rm696 `d0bec3fb6`:

| Ahead of stock | stock | 6.18 |
|---|---|---|
| clock_gettime | 1.09-1.21 us | 0.78-0.84 (see below) |
| sched_yield | 2.29-2.41 us | 1.25-1.27 |
| pipe write+read | 2.25-2.53 us | 1.83-1.95 |
| thread switch | 7.31-8.33 us | 7.23-7.48 |
| process switch | 9.25-10.00 us | 8.95-9.15 |
| file-backed page fault | 1.77-2.41 us | 0.83-0.94 (fault-around maps 16 pages) |
| stat / open+close (plain ext4) | 4.60 / 7.84 us | 3.98-4.08 / 7.67 |
| pread of `/proc/PID/stat` | 20.4-21.3 us | 13.8-14.4 |

| About equal | stock | 6.18 |
|---|---|---|
| copy-on-write fault | 20.4-20.9 us | 20.6-20.7 |
| memset / memcpy | 1330-1425 / 344-347 MB/s | 1424 / 344-387 |

| Behind stock | stock | 6.18 | ratio |
|---|---|---|---|
| anonymous page fault | 6.13-7.04 us | 6.94-7.07 | ~1.1x |
| file mmap+munmap | 3.5 us | 12.6 | 3.6x |
| mprotect split+merge | 3.6 us | 6.4-6.5 | 1.8x |
| fork, per VMA | 2.65-2.86 us | 4.78-4.98 | 1.8x |
| booster-like fork (590 VMAs) | 2682-2705 us | 4281-4294 | 1.6x |
| fork+exec `/bin/true` | 3195-3236 us | 4662-4686 | 1.45x |
| 300 busybox spawns | 1.01 s | 1.48 | 1.47x |
| video, whole-system busy (20 s of a clip) | 39.8-44.3% | 46-47% | +2-6 points |
| idle, screen off | 1.2% | 2.2% (test tools included) | +1 point |

These were measured with GPT10 as clocksource. Since `a7b61bb36` the clocksource is the 32 kHz counter
again, as stock, because GPT10 kept CORE out of retention: clock_gettime is about 1.15 us (level with
stock), sched_yield about 1.60 us (still ahead) and each switch about 1 us slower, which brings the
switches about level with stock. Not remeasured since.

## Scheduler and context switches

- `0658adb07`: Linux 6.17 made SMP unconditional in the scheduler; on one CPU with Harmattan's four
  cgroup levels every enqueue, dequeue and pick ran load tracking and 64-bit software divisions. Back
  to 6.16's UP paths: a wakeup 3850 -> 2990 cycles (threads), 6650 -> 4100 (processes).
- `fd20d1f6a`: mainline flushes the Cortex-A8's branch predictor on every address space switch, and
  the N9's firmware sets ACTLR.IBE, so it is real: 576 cycles and a cold predictor after it. Now only
  with `CONFIG_HARDEN_BRANCH_PREDICTOR` (stock had no flush). Process switch 16.5-17.4 -> 11.8-13.1 us.
  Mainline added the flush after random Thumb-2 segfaults on boards with IBE set (erratum 687067): if
  random segfaults ever appear, set that option or revert the commit.
- `011f4ba41`: no runtime update at cgroup levels with one entity when picking (-0.6 us a thread
  switch).
- 128 Hz tick as stock (`281cc3d23`); an N9-only, single-core ARMv7 configuration without Spectre
  mitigations, PAN, VMAP stacks, stack zeroing or the stack protector, with stock's cgroup controllers
  only and no kernel-memory charging in memory cgroups ([Removed and switched off](./removed)).

What is left of a switch, at 1 GHz: `sched_clock()` ~1060 cycles (1.35 reads of the 32 kHz counter
behind the 19.2 MHz wakeup interconnect, as stock), `update_curr` ~900, `pick_eevdf` ~450, EEVDF lag
~600: the 6.18 fair class at four cgroup levels, spread thin. A cycle-counter `sched_clock()` was
sized at about 0.1% of the CPU in video and not done.

## Memory management

- **mmap/munmap** (`99afc1677`, `5d18d64ac`, `e87ff0337`): the VMA maple tree without RCU mode (no
  per-VMA locks on one CPU), node stores in place, and a free-area hint as 2.6.32's
  `free_area_cache`. File mmap+munmap 16.6-18.5 -> 12.6 us, anonymous 15.8 -> 9.7, mprotect pair
  12.8 -> 8.6. The rest of the 3.6x is the maple tree's walks and stores, page table teardown and the
  file's i_mmap tree: no single item.
- **fork per VMA** (`42ab3b71f`, `0a00d483a`, `b00ac605c`, `d0bec3fb6`): the child shares the parent's
  anon_vma as on 2.6.32, no VMA walk at exit for process accounting, no uprobes, one pointer store per
  copied VMA. Per VMA 6.72-6.94 -> 4.91-5.14 us; a booster-like fork 5190-5233 -> 4336-4453 us. Boosters
  and applauncherd have 600-650 VMAs.
- `f49e9543d`: the I-cache is synchronised once per change of a page, not for every executable
  mapping of it (300 busybox spawns 1.82 -> 1.65 s).
- An anonymous fault (7.5 us) is zeroing 2800 cycles, allocation 550, memcg charge 700, LRU 550, rmap
  370 and ~2400 in the exception, VMA lookup and page table walk. Batching anonymous faults was
  checked and dropped: 6.18's multi-page anonymous faults need transparent huge pages, which 32-bit ARM
  has only with LPAE, and the gain would be ~1.2 ms of a 44 ms synthetic texture frame and nothing in
  video or the UI.

## The idle path

Every idle entry walked all 16 power domains before and after WFI: about 120 register accesses on the
wakeup interconnect, 40 us before WFI and 59 us after each wake-up. Stock walked four domains, and
only when the MPU slept. `8f5ac4e25` does the same (none for C1 and C2, MPU/NEON/CORE/PER for deeper
states, every domain when CORE sleeps), and `9d3ead4f4` caches each domain's programmed next state.
Now C1 and C2 walk nothing, and C3 and deeper 17-30 us per idle, before and after WFI together. `pm_debug/count_all_domains` 1 restores the full walk.

| One register read at 1 GHz | ns |
|---|---|
| PRM, 32 kHz counter (wakeup L4, 19.2 MHz) | 625-668 |
| CM, system control module (CORE L4) | 174-290 |
| SDRC (L3) | 107-415 |

With Nokia's C-state table (`bbd32bffc`, [Power](./power#idle-states)) short idles stay shallow:
screen-on idle C1 43%, C2 6%, C3 2% of the time (C3 87% before); video C2 47%, C3 0 (49% before).
Left: the PRCM wake-up interrupt reads two PRM registers per module on every run, ~6 us, about 500 a
second with the screen on.

## Video and the DSP

Interrupts during 20 s of a clip in the Videos app:

| Source | stock | 6.18 before | 6.18 now |
|---|---|---|---|
| PRCM wake-up | 0 | 9576 | 3106 (`3a5439de6`: McBSP wakeups no longer routed to the MPU) |
| timer | 3576 | 6206 | 4220-4280 (128 Hz) |
| DSP mailbox | 2052 | 5221 | 2040-2055 (`bd79040af`, `e1159462f`: no TX interrupt per message) |

`5b477cdbd`: a large buffer map to the DSP is one whole-cache clean and invalidate instead of ~13000
per-line operations for an 820 KiB frame (`bridgedriver.flush_all_min_kb`, default 256; 0 = per
page). The renderer's CPU share 28.0 -> 27.0% (stock 26.9%).

DSP codec times (`tests/dsp/dspref.sh`) are level with or ahead of stock's: 720p Baseline decode
2.02-2.05 s (stock 2.13), Main 7.95-8.49 s (9.04), SD 0.87-0.90 s (0.92), the four encoders 3.1-5.0 s
(3.25-5.01). The remaining +2-6 busy points in video are the renderer's, PulseAudio's and X's kernel
time (system calls, ioctls, the bridge's cache maintenance), the same work as stock at a higher cost.

## GPU and UI

The GPU stack is Harmattan's closed DDK on Nokia's kernel module, forward-ported with stock's
configuration: the SGX at 195.2 MHz (the N9's maximum), powered down 1 ms after idle, polled every
10 ms while powered. `tests/glesbench.c` on both kernels, unlocked with the display on:

| Mode | stock | 6.18 |
|---|---|---|
| `fill 1` | 58.4 fps | 60.6 |
| `fill 20` (8.2 Mpixel blended a frame) | 21.6 fps | 22.5 |
| `draws 200` | 41.9 fps | 45.7 |
| `tex 8 256` (2 MiB of uploads a frame) | 19.4 fps | 19.0 |
| `swap` | 64.6 fps | 67.1 |

In the texture test under Harmattan's session environment the kernel time is stock's within 1%.
During home-screen flicks the CPU is 87% idle, user 7%, kernel 4% (the GPU's kick ioctls, poll and X's
socket writes): the kernel is a bystander in animations. 94% of frames were on time in a flick test;
stock's pacing was never measured.

## The CPU governor

Mainline's `ondemand` picks below `up_threshold` the frequency closest to `min + load x range`, so at
70-75% load it oscillates between 800 MHz and 1 GHz; 2.6.32's left 1 GHz only below ~56% load. In a
CPU-heavy test stock sat at 1 GHz throughout, 6.18 at 800 MHz 17-28% of the time. A/B with
`sampling_rate` 50 ms:

| `up_threshold` / `sampling_down_factor` | texture frame | flicks late (2+ frames) | screen-on idle, 60 s at 1 GHz |
|---|---|---|---|
| 80 / 1 | 40.0-40.5 ms | 5.2-5.7% | 2.9-3.5 s |
| 60 / 1 | 40.3 ms | 6.3% | 7.4 s |
| 60 / 2 | 39.5 ms | 5.5% | 10.0 s |

Holding 1 GHz changed nothing measurable and cost idle power: the governor lowered the clock only
while the CPU waited for the GPU. Mainline's `ondemand` stays as it is.

## The memory path

`75eaae875` ([Power](./power#what-off-needs)): after the first CORE OFF of a boot the SDRAM went into
self-refresh at every pause (SDRC_POWER 0x129 instead of 0x9). Random dependent loads at 1 GHz:

| Working set | SDRC_POWER 0x129 | 0x9 |
|---|---|---|
| 512 KB | 211 ns | 64 ns |
| 2 MB | 578 ns | 182 ns |
| 8 MB | 695 ns | 211 ns |

The input method needed about 250 ms of CPU per key, and fast typing queued up for seconds. With the
fix, after 812 CORE OFF entries SDRC_POWER still reads 0x9 and random loads over 8 MB take ~240 ns.

The memory path with the fix, `tests/membench.c` at 1 GHz:

| | |
|---|---|
| L1 (16 KB) | 3 ns per random load |
| L2 (128 KB) | 9-11 ns |
| 512 KB | 64 ns |
| 2-32 MB | 187-225 ns |
| sequential read / write | 1195 / 1494 MB/s |
| copy | 347 MB/s (glibc `memcpy`), 500 MB/s (NEON) |

Software prefetch works: one load per cache line 165 -> 85 ns with PLD. The SDRAM runs at 195.2 MHz
(L3 OPP100) with timings at the LPDDR-400 limits (CL3, tRCD 20 ns, tRP 15 ns, tRAS 41 ns, tRC 56 ns,
tRFC 138 ns, refresh every 7.49 us): no safe headroom there. The rest of a miss is the interconnect;
Nokia's kernel did no SMS or L3 priority tuning either. What can still make the phone faster than
stock: this fix (stock's kernel has the same gate; whether stock is affected was not measured), the
opt-in 1.1 and 1.2 GHz OPPs ([Power](./power#cpu-frequency-and-voltage)), and less work in userspace.

## Memory and swap

Harmattan's swap job sets up 256 MB of compressed swap only above 1,000,000 kB of `MemTotal`; this
kernel leaves 1,002,720 kB, above it as stock's (see [Removed and switched off](./removed)). Read 19
minutes after a boot: 550 MB available, no swap used, no refaults, no allocation stalls, no cgroup
limit hit. There is no reclaim for swap or LRU tuning to act on (a heavy multi-app session has not
been read yet). Harmattan's prelinked libraries load at their
prelinked addresses, as on stock.

## Outside the kernel

- **Harmattan's malloc environment.** The session exports `MALLOC_MMAP_THRESHOLD_=32768` and
  `MALLOC_TRIM_THRESHOLD_=8192`, which make glibc mmap and fault in every malloc of 32 KiB or more.
  glibc ignores them in `AT_SECURE` processes, which includes applauncherd, its boosters and every app
  they start. Of the UI processes only meegotouchhome pays: about 1 ms a swipe. Kept as stock.
- **cgroups.** With FasterN9's policy, apps in standby get 64 CPU shares, the foreground app's
  `active` group 4096 and the input method a `super` group at 16392. The foreground app does move to its group, so
  this did not cause the typing lag (the SDRAM did). ohmd classifies every new process (~0.7 ms in
  userspace per spawn); its cgroup moves may wait for an RCU grace period (16-24 ms, unmeasured;
  `echo 1 > /sys/kernel/rcu_expedited` tests it at run time).
- **Storage.** The eMMC runs 4-bit at 48 MHz as on stock (its upper data lines carry the WLAN's SDIO).
  Cold-reading Harmattan's 1658 libraries takes 14.1-14.6 s with any I/O scheduler, 13.9 s with 512 KiB
  readahead: the eMMC's latency is the limit.
- **Start-up** shows no kernel hot spot: Harmattan's own start-up spread over ~15 processes, page
  faults, exec and path lookups. App launch time end to end against stock has not been measured.

## Known gaps

Process creation stays 1.35-1.7x stock's, the VMA layer up to 3.6x (file mmap+munmap), and anonymous
faults ~10% slower: the 6.18 memory-management design on a 32-bit in-order CPU, with Harmattan's four cgroup levels charged per
page. Rare memory-corruption panics are listed in [Status](./status#known-issues); two hours of the
workload that preceded one, under KASAN, reproduced nothing. KASAN's only report, at start-up, was a
use-after-free in the DSP bridge's node set-up (fixed, `3d02bb8f8`).

## How to measure

`tests/build.sh` builds the tools against Harmattan's libraries (it needs a Harmattan sysroot);
`membench.c` and `sdrcpwr.c` need only libc and can be built static with any ARM hard-float toolchain.

| Tool | Measures |
|---|---|
| `kbench.c` | syscall, yield, pipe, thread and process switch, anonymous and file faults, spawn, memset/memcpy |
| `forkbench.c`, `spawnbench.c`, `loopop.c` | mmap, mprotect, fork per VMA, fork+exec |
| `membench.c` | random-load latency per working set (16 KB to 32 MB), sequential read/write/copy bandwidth |
| `sdrcpwr.c` | reads SDRC_POWER through `/dev/mem` (root): 0x9 is right, 0x129 is the self-refresh bug |
| `lat.sh SECONDS TAG` | touch-down (the first touch interrupt after 150 ms of quiet) to the next display update: median, mean, p90, max |
| `keytrace.sh SECONDS` | per touch-down, when the input method, the Messaging app, X, D-Bus, the compositor, PulseAudio and the feedback daemons first run, and the display updates within 1.5 s |
| `glesbench.c` | GLES2 fill, draws, texture uploads, swaps (`glesbench-stock.sh` runs it on stock) |
| `mallocfault.c` | malloc+free cost and faults with and without Harmattan's malloc variables |
| `busy.sh [video]` | 20 s of whole-system busy share, frequencies, per-process ticks, interrupts by source |
| `kprof.c` | a sampling profiler on the cycle counter (kernel symbols, per process, call chains) |
| `idlecount.sh`, `idletime.sh`, `mmiolat.c` | register accesses and time per idle entry; one register read's cost |

`lat.sh` and `keytrace.sh` use tracefs and this kernel's interrupt numbers (maXTouch 184, DISPC 41):
check `/proc/interrupts` first.

Rules learned the hard way:

- Run both kernels' processes in the same cgroup (`echo $$ > /syspart/system/tasks`, or the group
  under test): Harmattan's groups differ 64x in CPU shares, and each level costs per switch and fault.
- Run after Harmattan's start-up (3-4 minutes; GPU tests after 15), with the phone idle: the file
  indexer can take half the CPU for minutes. Three runs at least.
- Pin the CPU at 1 GHz for kernel microbenchmarks; compare against stock under the same governor.
- With the lock screen up or the display off, GL swaps are not composited and run unthrottled.
- Set or clear Harmattan's malloc variables explicitly (`env -i ...`): a login shell has them, a plain
  `ssh` command doesn't.
- Only the cycle counter counts on this HS chip (no other PMU events); perf reprograms it, so don't mix
  perf with cycle-counter timing. Per-process tick counts are biased for short bursts: use the
  whole-system busy share or sampling.
