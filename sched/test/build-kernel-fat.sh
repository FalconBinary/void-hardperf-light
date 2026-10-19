#!/bin/sh
# vh-sched spike S1: build the kernel-fat configuration of .github/workflows/kernel-fat.yml
# (the Void linux6.18 x86_64 configuration + sched_ext + BTF + virtio built in) inside colima,
# bzImage only, for when the workflow cannot be dispatched. The configure step is the
# workflow's, line for line; the Void configuration is taken from void-packages at VOID_REV.
#   build-kernel-fat.sh
set -eu
VOID_REV=${VOID_REV:-1808133be7d656d11390fb9a87fe6f44d738e2a2}
kver=6.18.57
src=$HOME/k/linux-$kver
out=$HOME/k/b-fat
cache=${VHL_S1:-$HOME/.cache/vhl-s1}
dotconfig=$cache/void-linux6.18-x86_64-dotconfig
if [ ! -f "$dotconfig" ]; then
  curl -fsSL -o "$dotconfig" "https://raw.githubusercontent.com/void-linux/void-packages/$VOID_REV/srcpkgs/linux6.18/files/x86_64-dotconfig"
fi
sha256sum "$dotconfig"
mkdir -p "$out"
cp "$dotconfig" "$out/.config"
cd "$src"
./scripts/config --file "$out/.config" -e BPF_SYSCALL -e BPF_JIT -e BPF_JIT_ALWAYS_ON -e DEBUG_INFO -e DEBUG_INFO_DWARF5 -e DEBUG_INFO_BTF -e SCHED_CLASS_EXT \
  -d DEBUG_INFO_NONE -d DEBUG_INFO_REDUCED -d DEBUG_INFO_SPLIT \
  -e VIRTIO_PCI -e VIRTIO_BLK -e VIRTIO_NET -e VIRTIO_CONSOLE -e BLK_DEV_NVME -e E1000E -e EXT4_FS -e XFS_FS \
  -e DRM_BOCHS -e DRM_VIRTIO_GPU -d MODULE_SIG_FORCE
make O="$out" ARCH=x86_64 LLVM=1 olddefconfig
echo "=== key symbols"
grep -E '^CONFIG_(SCHED_CLASS_EXT|EXT_GROUP_SCHED|DEBUG_INFO_BTF|DEBUG_INFO_DWARF5|BPF_JIT|BPF_JIT_ALWAYS_ON|BPF_LSM|SECURITY_LOCKDOWN_LSM|SECURITY_LOCKDOWN_LSM_EARLY|LOCK_DOWN_KERNEL_FORCE_[A-Z]*|LSM|SERIAL_8250|SERIAL_8250_CONSOLE|VIRTIO|VIRTIO_PCI|VIRTIO_BLK|MAGIC_SYSRQ|MAGIC_SYSRQ_DEFAULT_ENABLE|BLK_DEV_INITRD|RD_GZIP|DEVTMPFS|PREEMPT|PREEMPT_DYNAMIC|HZ)=' "$out/.config" || true
echo "=== missing"
for s in SCHED_CLASS_EXT DEBUG_INFO_BTF BPF_JIT SECURITY_LOCKDOWN_LSM SERIAL_8250_CONSOLE BLK_DEV_INITRD RD_GZIP MAGIC_SYSRQ; do
  grep -q "^CONFIG_$s=y" "$out/.config" || echo "MISSING CONFIG_$s"
done
date
make O="$out" ARCH=x86_64 LLVM=1 KBUILD_BUILD_USER=vh KBUILD_BUILD_HOST=colima -j"$(nproc)" bzImage > "$cache/make-fat.log" 2>&1 || { echo "MAKE FAILED"; tail -40 "$cache/make-fat.log"; exit 1; }
date
grep -E "error|warning: .*BTF|pahole|BTF" "$cache/make-fat.log" | tail -20 || true
ls -l "$out/arch/x86/boot/bzImage" "$out/vmlinux"
cp "$out/arch/x86/boot/bzImage" "$cache/bzImage-fat-$kver"
cp "$out/.config" "$cache/config-fat-$kver"
llvm-objcopy --dump-section .BTF="$cache/vmlinux-fat-$kver.btf" "$out/vmlinux" /dev/null
(cd "$cache" && sha256sum "bzImage-fat-$kver" "config-fat-$kver" "vmlinux-fat-$kver.btf")
echo "BUILD_DONE fat"
