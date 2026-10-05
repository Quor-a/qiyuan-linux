#!/bin/busybox sh
# qyinstall — 启元安装器 v1 (CLI)
# 用法: qyinstall /dev/vda
# 说明: live 介质的 /media 挂载不随 switch_root 保留 → 安装器自行挂载 sr0
set -e
BUSY=/bin/busybox
DISK="$1"
[ -b "$DISK" ] || { echo "用法: qyinstall <整盘设备如/dev/vda>"; exit 1; }

# 0. 找 live 源
SRC=""
if [ -f /media/live/rootfs.squashfs ]; then
    SRC=/media
else
    $BUSY mkdir -p /tmp/isoroot
    $BUSY mount -t iso9660 -o ro /dev/sr0 /tmp/isoroot 2>/dev/null || true
    if [ -f /tmp/isoroot/live/rootfs.squashfs ]; then SRC=/tmp/isoroot; fi
fi
[ -n "$SRC" ] || { echo "未找到 live 介质 (rootfs.squashfs)"; exit 1; }
echo "===QYINSTALL=== 目标 $DISK  源 $SRC  （10 秒内 Ctrl+C 取消）"
$BUSY sleep 10
# 清理上次残留挂载
$BUSY umount /tmp/arctgt/efi /tmp/arctgt /tmp/arcsrc 2>/dev/null || true

# 1. 分区: p1 EFI 256M + p2 root 其余 (GPT)
echo "--- 分区 ---"
sfdisk --force "$DISK" <<EOF
label: gpt
name=EFI, size=256MiB, type=U
name=root, type=L
EOF
$BUSY sleep 2
P1="${DISK}p1"; P2="${DISK}p2"
[ -b "$P1" ] || P1=$($BUSY ls "${DISK}"* | grep -v "^${DISK}$" | head -1)
[ -b "$P2" ] || P2=$($BUSY ls "${DISK}"* | grep -v "^${DISK}$" | tail -1)
echo "p1=$P1 p2=$P2"

# 2. 格式化
echo "--- 格式化 ---"
$BUSY mkdosfs -F 32 -n QYEFI "$P1"
mke2fs -F -L qyroot "$P2"
tune2fs -c 0 -i 0 "$P2" 2>/dev/null || true

# 3. 挂载 + 复制
echo "--- 复制系统 ---"
$BUSY mkdir -p /tmp/arcsrc /tmp/arctgt
$BUSY mount -o loop,ro "$SRC/live/rootfs.squashfs" /tmp/arcsrc
$BUSY mount "$P2" /tmp/arctgt
$BUSY mkdir -p /tmp/arctgt/efi
$BUSY mount "$P1" /tmp/arctgt/efi
$BUSY cp -a /tmp/arcsrc/. /tmp/arctgt/
$BUSY rm -f /tmp/arctgt/etc/ssh/ssh_host_*
# 安装时重新生成 host key（ISO 中的 key 是公开的，不能带入新系统）
for _t in rsa ecdsa ed25519; do
  ssh-keygen -q -t $_t -f /tmp/arctgt/etc/ssh/ssh_host_${_t}_key -N "" >/dev/null 2>&1 || true
done
$BUSY ls /tmp/arctgt/etc/ssh/ | $BUSY grep -c host
$BUSY mkdir -p /tmp/arctgt/boot /tmp/arctgt/efi/EFI/BOOT /tmp/arctgt/home /tmp/arctgt/root /tmp/arctgt/tmp
$BUSY chmod 1777 /tmp/arctgt/tmp
$BUSY chmod 700 /tmp/arctgt/root

# 4. fstab
RUUID=$(/bin/blkid -s UUID -o value "$P2")
EUUID=$(/bin/blkid -s UUID -o value "$P1")
cat > /tmp/arctgt/etc/fstab <<EOF
UUID=$RUUID  /        ext4  defaults  0 1
UUID=$EUUID  /boot/efi vfat defaults  0 2
EOF

# 5. 安装版 initramfs: 优先用介质里预制的（root=LABEL 直挂），退化为现场生成
if [ -f "$SRC/live/initramfs-install.img" ]; then
    $BUSY cp "$SRC/live/initramfs-install.img" /tmp/arctgt/boot/initramfs.img
    echo "initramfs: 取自介质"
else
    $BUSY mkdir -p /tmp/irfs && cd /tmp/irfs
    cat > init <<'INITEOF'
#!/bin/busybox sh
/bin/busybox mkdir -p /proc /sys /dev /newroot /run
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev
ROOT=""
for o in $(cat /proc/cmdline); do case "$o" in root=*) ROOT="${o#root=}";; esac; done
i=0
while [ $i -lt 15 ]; do /bin/busybox mount -t ext4 "$ROOT" /newroot 2>/dev/null && break; i=$((i+1)); /bin/busybox sleep 1; done
[ -x /newroot/usr/bin/qyinit ] || exec /bin/busybox sh
for d in proc sys dev run; do /bin/busybox mkdir -p /newroot/$d; /bin/busybox mount --move /$d /newroot/$d; done
exec /bin/busybox switch_root /newroot /usr/bin/qyinit
INITEOF
    chmod +x init
    find . | $BUSY cpio -o -H newc 2>/dev/null | gzip -9 > /tmp/arctgt/boot/initramfs.img
    echo "initramfs: 现场生成"
fi

# 6. EFI: EFI_STUB 内核直接作为 BOOTX64.EFI
KERN=$(ls /tmp/arcsrc/boot/vmlinuz-* 2>/dev/null | head -1)
if [ -f "$SRC/BOOTX64.EFI" ]; then
  $BUSY cp "$SRC/BOOTX64.EFI" /tmp/arctgt/efi/EFI/BOOT/BOOTX64.EFI
elif [ -f /tmp/BOOTX64.EFI ]; then
  $BUSY cp /tmp/BOOTX64.EFI /tmp/arctgt/efi/EFI/BOOT/BOOTX64.EFI
else
  $BUSY cp "$KERN" /tmp/arctgt/efi/EFI/BOOT/BOOTX64.EFI
fi
echo "BOOTX64.EFI installed"

# 7. 摘载
$BUSY umount /tmp/arctgt/efi /tmp/arctgt /tmp/arcsrc /tmp/isoroot 2>/dev/null || true
echo "===QYINSTALL-DONE=== root=UUID=$RUUID efi=$EUUID"
