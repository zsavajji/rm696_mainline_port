#!/bin/bash
# Build the on-phone tests for Harmattan (eglibc 2.10, hard-float, loader /lib/ld-linux.so.3) on the Mac
# with n9-qemu's sysroot and GCC runtime (../n9-qemu/build/{sysroot,gcc}, made by its setup.sh).
# Output: build/pvr2d-test, build/gles2-test, build/glesbench, build/memtrace.so, build/mallocfault, build/wlan-nvs, build/kprof, build/gst-test, build/ioctl-log.so, build/kbench, build/swprof,
# build/tlbbench, build/loopop, build/forkbench, build/spawnbench, build/cowstress, build/dsprestart, build/cmtramp, build/wakelat
set -euo pipefail
cd "$(dirname "$0")/.."
Q=$PWD/../n9-qemu/build
mkdir -p build
CC=(/opt/homebrew/opt/llvm/bin/clang --target=arm-linux-gnueabihf --sysroot=$Q/sysroot
  --gcc-install-dir=$Q/gcc/lib/gcc/arm-none-linux-gnueabi/14.2.0
  -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -O2 -Wall
  --ld-path=/opt/homebrew/opt/lld/bin/ld.lld -Wl,--dynamic-linker=/lib/ld-linux.so.3)
"${CC[@]}" -o build/pvr2d-test tests/pvr2d-test.c -lpvr2d
"${CC[@]}" -o build/gles2-test tests/gles2-test.c -lEGL -lGLESv2 -lX11
"${CC[@]}" -o build/glesbench tests/glesbench.c -lEGL -lGLESv2 -lX11 -lrt
"${CC[@]}" -shared -fPIC -o build/memtrace.so tests/memtrace.c -ldl
"${CC[@]}" -o build/mallocfault tests/mallocfault.c -lrt
"${CC[@]}" -o build/wlan-nvs tests/wlan-nvs.c -l:libcal.so.1
"${CC[@]}" -o build/kprof tests/kprof.c
"${CC[@]}" -o build/devmem tests/devmem.c
"${CC[@]}" -o build/kbench tests/kbench.c -lrt -lpthread
"${CC[@]}" -o build/swprof tests/swprof.c -lrt -lpthread
"${CC[@]}" -o build/tlbbench tests/tlbbench.c -lrt
"${CC[@]}" -o build/loopop tests/loopop.c -lrt
"${CC[@]}" -o build/forkbench tests/forkbench.c -lrt
"${CC[@]}" -o build/spawnbench tests/spawnbench.c -lrt
"${CC[@]}" -o build/cowstress tests/cowstress.c
"${CC[@]}" -o build/cmtramp tests/cmtramp.c -lrt
"${CC[@]}" -o build/wakelat tests/wakelat.c -lrt
"${CC[@]}" -o build/dsprestart tests/dsp/dsprestart.c
"${CC[@]}" -std=gnu99 -o build/ispcap tests/camera/ispcap.c
S=$Q/sysroot/usr
"${CC[@]}" -o build/gst-test tests/gst-test.c -I$S/include/gstreamer-0.10 -I$S/include/glib-2.0 \
  -I$S/lib/glib-2.0/include -I$S/include/libxml2 -lgstreamer-0.10 -lgobject-2.0 -lglib-2.0
"${CC[@]}" -shared -fPIC -o build/ioctl-log.so tests/ioctl-log.c -ldl
