#!/bin/bash
# Build the N9 kernel and the SGX driver on a Linux machine (a kernel doesn't build on macOS): the
# kernel is ../linux_mainline_rm696 (Linux 6.18.55 and this project's changes as commits, Nokia's
# Aegis as ported by n9-qemu included), with omap2plus_defconfig + its arch/arm/configs/rm696.config;
# the SGX driver (../pvr_sgx_rm696, its own repository) as external modules against it; the RAM-boot
# test initramfs (ramboot/: busybox and dropbear from Alpine, the modules Harmattan loads,
# build/ramboot-key.pub for root) built in.
# Output: build/zImage-n9 (zImage with omap3-n9.dtb appended, for NOLO: build/0xFFFF -m kernel:build/zImage-n9 -l -b),
#         build/pvrsrvkm.ko, build/omaplfb.ko
#   BOX=  ssh target; it builds in ~/projects/sgx (default: n9-qemu's local build VM, which
#         ../n9-qemu/kernel/buildvm.sh starts); BOX=local (the default on Linux) builds here, in build/box,
#         from KERNEL as it is checked out (BRANCH unused)
#   BOX_SSH_CONFIG=  an ssh config file to reach BOX with (default: that VM's, if it exists)
#   CROSS=  the cross compiler prefix there
#   KERNEL= the kernel repository (default ../linux_mainline_rm696), BRANCH= its branch or tag (rm696):
#           what's committed there is built
#   PVR=    the SGX driver's checkout (default ../pvr_sgx_rm696), built as it is checked out
#   RELEASE=1  the release image instead (build/zImage-n9-release): ramboot/release-init (Harmattan on the
#           eMMC read-write, the rescue dropbear with the phone's own keys), no SSH key and no random
#           seed in it (RELEASE.md); with RESCUE_ANY=1 a debug variant whose rescue server listens on
#           every interface, not only USB (build/zImage-n9-release-debug: never to distribute)
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname)" = Linux ] && BOX=${BOX:-local}
BOX=${BOX:-builder@n9-buildvm}
BOX_SSH_CONFIG=${BOX_SSH_CONFIG-$PWD/../n9-qemu/build/buildvm/ssh_config}
CROSS=${CROSS:-arm-linux-gnueabihf-}
SSH=(ssh); [ -f "$BOX_SSH_CONFIG" ] && SSH=(ssh -F "$BOX_SSH_CONFIG")
mkdir -p build
[ -f build/ramboot-key ] || ssh-keygen -q -t ed25519 -N '' -C n9-ramboot -f build/ramboot-key
K=${KERNEL:-../linux_mainline_rm696} BR=${BRANCH:-rm696} P=${PVR:-../pvr_sgx_rm696}
[ -f "$P/Kbuild" ] || { echo "no SGX driver at $P (clone pvr_sgx_rm696 there, or set PVR=)" >&2; exit 1; }
# box CMD runs CMD in the box's home; D is where the box keeps the build
if [ "$BOX" = local ]; then
  mkdir -p build/box/projects/sgx
  box() { (cd build/box && HOME=$PWD bash -c "$1"); }
  D=$PWD/build/box/projects/sgx KREF= S=$(cd "$K" && pwd)
  echo "building $K as checked out: $(git -C "$K" describe --always --dirty)"
else
  box() { "${SSH[@]}" $BOX "$1"; }
  D=$BOX:projects/sgx S=
  # The kernel's branch goes to the box's tree under a ref named after its commit (so never a forced
  # update) and is checked out there: only the files that changed are rewritten
  [ -z "$(git -C "$K" status --porcelain)" ] || echo "note: $K has uncommitted changes; building $BR as committed"
  KREF=refs/build/$(git -C "$K" rev-parse --short "$BR^{commit}")
  box 'S=projects/sgx/src/linux-6.18.55; [ -d $S/.git ] || git init -q $S; git -C $S config receive.shallowUpdate true'
  GIT_SSH_COMMAND="${SSH[*]}" git -C "$K" push -q "$D/src/linux-6.18.55" "$BR^{commit}:$KREF"
fi
rsync -az --delete -e "${SSH[*]}" --rsync-path="mkdir -p projects/sgx && rsync" ramboot \
  build/ramboot-key.pub "$D/"
rsync -az --delete --exclude=.git -e "${SSH[*]}" --rsync-path="mkdir -p projects/sgx/pvr && rsync" "$P/" "$D/pvr/"
box "CROSS=$CROSS KREF=$KREF S=$S RELEASE=${RELEASE:-} RESCUE_ANY=${RESCUE_ANY:-} bash -s" <<'EOF'
set -euo pipefail
N=$HOME/projects/sgx
S=${S:-$N/src/linux-6.18.55} O=$N/build/linux R=$N/build/initramfs
M="make -s -C $S O=$O ARCH=arm CROSS_COMPILE=$CROSS -j$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))"  # two cores left free
mkdir -p $O
if [ -n "$KREF" ]; then
  git -C $S checkout -q -f --detach $KREF && git -C $S clean -qfd
  git -C $S for-each-ref --format='%(refname)' refs/build | { grep -vxF $KREF || true; } | xargs -r -n1 git -C $S update-ref -d
fi

# The initramfs: Alpine armv7's static busybox, dropbear (with its libraries), ramboot/init. Alpine's
# branch is pinned: a newer one may give dropbear libraries this list doesn't fetch
A=$N/alpine U=https://dl-cdn.alpinelinux.org/alpine/v3.24/main/armv7
mkdir -p $A
[ -f $A/APKINDEX ] || curl -fsSL $U/APKINDEX.tar.gz | tar -xzO APKINDEX > $A/APKINDEX
rm -rf $R && mkdir -p $R
for p in busybox-static dropbear musl utmps-libs skalibs-libs zlib; do
  v=$(awk -v p=$p '/^P:/{n=substr($0,3)} /^V:/ && n==p {print substr($0,3); exit}' $A/APKINDEX)
  [ -f $A/$p-$v.apk ] || curl -fsSL -o $A/$p-$v.apk $U/$p-$v.apk
  tar -xzf $A/$p-$v.apk -C $R --exclude='.*' 2>/dev/null
done
mv $R/bin/busybox.static $R/bin/busybox
cp $N/ramboot/${RELEASE:+release-}init $R/init && chmod 755 $R/init	# the kernel runs it only if executable
[ -z "$RESCUE_ANY" ] || { mkdir -p $R/etc && touch $R/etc/rescue-any; }
mkdir -p $R/proc $R/sys $R/dev $R/tmp $R/etc/dropbear $R/root/.ssh
# Firmware built into the kernel (rm696.config CONFIG_EXTRA_FIRMWARE, from $N/firmware), none of it
# Nokia's: Nokia's own (Bluetooth, the camera sensors, the DSP...) loads from the phone's /lib/firmware.
# WLAN's from linux-firmware (stock's 2011 wl1271-fw.bin is older than wlcore accepts; single-role
# only: multi-role (P2P) and PLT (production test) left out to keep the image small)
LF=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain
mkdir -p $N/firmware/ti-connectivity
for f in ti-connectivity/wl127x-fw-5-sr.bin; do
  [ -s $N/firmware/$f ] || curl -fsSL -o $N/firmware/$f $LF/$f
done
# and the signed wireless regulatory database (wireless-regdb, signed with a key 6.18 has built in),
# which cfg80211 loads at boot: it then follows the AP's country instead of the world domain's limits
RG=https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain
for f in regulatory.db regulatory.db.p7s; do
  [ -s $N/firmware/$f ] || curl -fsSL -o $N/firmware/$f $RG/$f
done
echo 'root:x:0:0:root:/root:/bin/sh' > $R/etc/passwd
echo 'root:x:0:' > $R/etc/group
echo /bin/sh > $R/etc/shells
# dropbear refuses keys under a group-writable home (the build user's umask may make it so); the
# release has no key (its dropbear reads the phone's /root/.ssh)
chmod -R go-w $R && chmod 700 $R/root/.ssh
[ -n "$RELEASE" ] || { cp $N/ramboot-key.pub $R/root/.ssh/authorized_keys && chmod 600 $R/root/.ssh/authorized_keys; }
mklist() {  # a gen_init_cpio list of $R, all files root's
  (cd $R && find . -mindepth 1 | sort | while read -r f; do p=${f#.}
    if [ -L "$f" ]; then echo "slink $p $(readlink "$f") 777 0 0"
    elif [ -d "$f" ]; then echo "dir $p $(stat -c %a "$f") 0 0"
    else echo "file $p $R$p $(stat -c %a "$f") 0 0"; fi
  done; echo "nod /dev/console 600 0 0 c 5 1") > $N/build/initramfs.list
}
mklist
{ echo "CONFIG_INITRAMFS_SOURCE=\"$N/build/initramfs.list\""
  echo "CONFIG_EXTRA_FIRMWARE_DIR=\"$N/firmware\""; } > $O/initramfs.config

$M omap2plus_defconfig
$S/scripts/kconfig/merge_config.sh -m -O $O $O/.config $S/arch/arm/configs/rm696.config $O/initramfs.config >/dev/null
$M olddefconfig
# Every line of n9.config must have stuck (a missing dependency silently drops an option)
bad=0
while read -r l; do
  case "$l" in
    CONFIG_*) grep -qxF "$l" $O/.config || { echo "not applied: $l"; bad=1; } ;;
    "# CONFIG_"*" is not set") s=${l#\# }; s=${s%% *}; ! grep -q "^$s=[ym]" $O/.config || { echo "still set: $s"; bad=1; } ;;
  esac
done < $S/arch/arm/configs/rm696.config
[ $bad = 0 ]
# modules first: pvr links against their Module.symvers, and goes into the initramfs; vmlinux too, for
# modules_install's modules.builtin (a first build has none)
$M dtbs modules vmlinux > $N/build/kernel.log 2>&1 || { grep -E -A8 -m5 "error|undefined reference" $N/build/kernel.log; exit 1; }
$M M=$N/pvr modules > $N/build/pvr.log 2>&1 || { grep -E "error|ERROR" $N/build/pvr.log | head -80; exit 1; }
echo "pvr warnings: $(grep -c "warning:" $N/build/pvr.log || true)"
# The modules Harmattan loads (udev by alias, its jobs by name), as a /lib/modules/<release> tree the
# init gives Harmattan's root: depmod's files with absolute paths, the form Harmattan's
# module-init-tools 3.4 reads. Only these: udev loads whatever modules.alias lists
KREL=$(cat $O/include/config/kernel.release)
X=$N/build/modules && rm -rf $X
$M INSTALL_MOD_PATH=$X INSTALL_MOD_STRIP=1 modules_install >> $N/build/kernel.log 2>&1 ||
  { tail -20 $N/build/kernel.log; exit 1; }
K=$R/lib/modules/$KREL && mkdir -p $K/extra
# WLAN's chip drivers; icd2's IDLETIMER target; Nokia's USB gadgets for usb_moded; the DSP bridge for
# gst-dsp; swap (enable-swap's ramzswap); Bluetooth's UART driver; the camera sensors, lens and flash;
# IPv6 (autoloaded as net-pf-10); the TWL watchdog where a branch builds it as a module
for m in wlcore wl12xx wlcore_sdio xt_IDLETIMER g_nokia g_file_storage g_ether bridgedriver ramzswap \
  zsmalloc hci_uart hci_nokia btbcm smiapp ad58xx as3645a ipv6 twl4030_wdt; do
  find $X/lib/modules/$KREL/kernel -name $m.ko -exec cp {} $K/extra/ \;
done
# WLAN's firmware, where the init points the firmware loader (firmware_class.path), unless built in
grep -q "^CONFIG_EXTRA_FIRMWARE=.*wl127x" $O/.config ||
  install -D -m 644 $N/firmware/ti-connectivity/wl127x-fw-5-sr.bin $K/firmware/ti-connectivity/wl127x-fw-5-sr.bin
${CROSS}strip --strip-debug -o $K/extra/pvrsrvkm.ko $N/pvr/pvrsrvkm.ko
${CROSS}strip --strip-debug -o $K/extra/omaplfb.ko $N/pvr/omaplfb.ko
cp $X/lib/modules/$KREL/modules.builtin* $K/	# so depmod knows what's built in
/sbin/depmod -b $R $KREL	# (not in the build user's PATH)
rm -f $K/*.bin $K/modules.builtin* $K/modules.devname $K/modules.softdep $K/modules.weakdep
sed -i "s#\([^ :]*\.ko\)#/lib/modules/$KREL/\1#g" $K/modules.dep
ls $K/extra | tr '\n' ' '; echo
mklist
$M zImage >> $N/build/kernel.log 2>&1 || { grep -E -A8 -m5 "error|undefined reference" $N/build/kernel.log; exit 1; }
# The test image's device tree: omap3-n9's with a random seed (the OMAP3630 has no cycle counter for
# jitter entropy and the N9's RNG is off: without one, getrandom(), so dropbear, blocks for minutes
# after boot).
# ponytail: one seed per build, reused on every boot of that image; fine for a test image. Never in the
# release, which every copy would share
if [ -n "$RELEASE" ]; then
  cat $O/arch/arm/boot/zImage $O/arch/arm/boot/dts/ti/omap/omap3-n9.dtb > $N/build/zImage-n9
  exit 0
fi
D=$O/scripts/dtc/dtc
{ $D -q -I dtb -O dts $O/arch/arm/boot/dts/ti/omap/omap3-n9.dtb
  echo "/ { chosen { rng-seed = [$(head -c 64 /dev/urandom | od -An -tx1 | tr -d '\n')]; }; };"
} | $D -q -I dts -O dtb -o $N/build/omap3-n9-seed.dtb
cat $O/arch/arm/boot/zImage $N/build/omap3-n9-seed.dtb > $N/build/zImage-n9
EOF
for f in projects/sgx/build/zImage-n9 projects/sgx/pvr/pvrsrvkm.ko projects/sgx/pvr/omaplfb.ko; do
  box "cat $f" > build/$(basename $f)
done
[ -z "${RELEASE:-}" ] || mv build/zImage-n9 build/zImage-n9-release${RESCUE_ANY:+-debug}
rm -f build/zImage build/omap3-n9.dtb
ls -la build/zImage-n9* build/*.ko
