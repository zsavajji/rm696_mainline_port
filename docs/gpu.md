# GPU

The SGX 530 runs Harmattan's own GPU stack as it ships: X with Nokia's driver, GLES2 apps and the
compositor, through Harmattan's closed PowerVR libraries. The kernel side is a forward-ported driver
with the same interface as Nokia's, kept in its own repository,
[`pvr_sgx_rm696`](https://github.com/zsavajji/pvr_sgx_rm696). Speed is on par with stock.

## How it fits together

| Layer | What | Where |
|---|---|---|
| Harmattan's userspace | the SGX DDK 1.4.14.2514 libraries (`*_r125.so`, `libsrv_um`, `libpvr2d`), Nokia's X driver (DRI2 over pvr2d), `pvrsrvinit_r125` | the phone's root filesystem, unchanged |
| The driver | `pvrsrvkm.ko` (services and the SGX, `/dev/pvrsrvkm`) and `omaplfb.ko` (the display class on `/dev/fb0`) | `pvr_sgx_rm696`, built against the kernel by `kernel/build.sh` (`PVR=`) |
| The kernel | omapfb rather than omapdrm (Harmattan's X driver and `omaplfb` use omapfb), the `registered_fb` export for `omaplfb` (`b5ec71112`), Nokia's DSS notifier the driver's flips complete on (`d75b49787`), the GPU node from omap36xx's device tree | `linux_mainline_rm696` |

At boot Harmattan's own `/etc/init/sgx.conf` loads the modules as on stock (`modprobe omaplfb` brings
`pvrsrvkm` with it) and runs `pvrsrvinit_r125`, which sets the SGX up through the driver.

The driver is Nokia's N900 driver as Maemo Leste forward-ported it to 5.0, brought to 6.18: it probes
from the device tree, powers the SGX through runtime PM, and its flip events, event timestamps and
mappings of framebuffer memory (EGL images for the camera viewfinder and video) are fixed. The driver's
README lists each change.

## Keeping Nokia's interface

The libraries are closed, so the driver must answer their ioctls exactly as Nokia's module did.
`check-abi.py` (in the driver's repository) compares the two modules' ioctl dispatch without a phone:
the same ioctl index range, the same 11 unhandled indices, the same 24 indices sharing a handler, and
the same first kernel call in each comparable handler (59 of 59). It checks the dispatch, not the
layout of each ioctl's arguments; those come from the same DDK headers, and a mismatch would show at
SGX initialisation or on the first GL call. The driver also refuses to build with any option set but
Harmattan's (release, EDM trace, command trace), because the libraries check it at start-up.

## Power and clocks

- The SGX runs at 195.2 MHz (CORE/2, the N9's maximum), powers down 1 ms after it idles and is polled
  every 10 ms while powered, as Nokia's driver.
- While the SGX is clocked it holds L3 at full speed (the `sgx` holder in `omap3_l3`, see
  [Power](./power#core-l3-frequency-scaling)), and CORE reaches OFF only with the SGX off.
- **CPU floor**: while the SGX is busy the CPU stays at or above 800 MHz
  (`/sys/module/pvrsrvkm/parameters/cpu_min_khz`, `0` turns it off). Stock had none.

## Speed

On Harmattan's own GLES2 benchmark runs (`tests/glesbench.c`, the same binary on both kernels) 6.18
matches or beats stock in fill, draw and swap rates and is about 2% slower on texture uploads; the table is
in [Performance](./performance#gpu-and-ui).

## Checking it

On the phone (as root, or through the [rescue SSH](./rescue)):

```sh
cat /proc/pvr/version                                   # the driver's DDK version, once loaded
grep -E 'pvrsrvkm|omaplfb' /proc/modules
cat /sys/module/pvrsrvkm/parameters/cpu_min_khz
```

The build kit's `tests/` has three GPU checks, run in Harmattan's session with the display on:
`pvr2d-test.c` (a GPU fill and copy through `libpvr2d`, every pixel checked), `gles2-test.c` (a GLES2
triangle through EGL on X, pixels read back) and `glesbench.c` (frame rates and CPU time per mode).

## Limits

- Only Harmattan's DDK 1.4.14.2514 userspace: the driver keeps that one interface, so other GPU stacks
  (Mesa, newer DDKs) don't run on it.
- The interface check covers the ioctl dispatch, not the argument structures (see above).
