#!/bin/bash
# mkiso.sh — 澜岫 ISO 重打（母本，派生改 VERSION 即可）
# 用法: VERSION=1.5.1 bash scripts/mkiso.sh
set -e
VERSION="${VERSION:?需要 VERSION=}"
Q="$(cd "$(dirname "$0")/.." && pwd)"
ISO=/home/agentuser/lanxiu-linux-$VERSION.iso

rm -rf /tmp/qyiso && mkdir -p /tmp/qyiso/live /tmp/qyiso/boot/grub
cp $Q/var/sysroot/boot/vmlinuz-7.2.9 /tmp/qyiso/boot/vmlinuz
[ -f /tmp/live-initramfs.img ] || { echo "缺 /tmp/live-initramfs.img (live initrd，见 scripts/build-initramfs.sh)"; exit 1; }
cp /tmp/live-initramfs.img /tmp/qyiso/boot/initramfs.img
[ -f /tmp/BOOTX64.EFI ] || { echo "缺 /tmp/BOOTX64.EFI (standalone grub，见 scripts/build-bootefi.sh)"; exit 1; }
cp /tmp/BOOTX64.EFI /tmp/qyiso/BOOTX64.EFI
[ -f /tmp/initramfs-install.img ] || { echo "缺 /tmp/initramfs-install.img"; exit 1; }
cp /tmp/initramfs-install.img /tmp/qyiso/live/initramfs-install.img

SQCOMP="${SQCOMP:-zstd}"
echo "=== mksquashfs (-comp $SQCOMP) ==="
sudo mksquashfs $Q/var/sysroot /tmp/qyiso/live/rootfs.squashfs -comp $SQCOMP $([ "$SQCOMP" = gzip ] && echo "-Xcompression-level 9") -e $Q/var/sysroot/var -e $Q/var/sysroot/home -noappend > /tmp/mksq.log 2>&1

cat > /tmp/qyiso/boot/grub/grub.cfg <<'EOF'
set timeout=3
set default=0
menuentry "LANXIU Linux (live)" {
    linux /boot/vmlinuz console=ttyS0
    initrd /boot/initramfs.img
}
menuentry "LANXIU Linux (rescue)" {
    linux /boot/vmlinuz console=ttyS0 single
    initrd /boot/initramfs.img
}
EOF

echo "=== grub-mkrescue ==="
rm -f "$ISO"
grub-mkrescue -o "$ISO" /tmp/qyiso > /tmp/grub-rescue.log 2>&1
ls -la "$ISO"
echo "CHAIN-ISO-COMPLETE $VERSION"
