#!/bin/sh
# 澜岫 live init: 挂 ISO → squashfs → overlay(tmpfs) → switch_root qyinit
/bin/busybox mkdir -p /proc /sys /dev /newroot /run /media
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev
echo "[live-init] 查找 live 介质..."
for i in $(seq 1 10); do
  if /bin/busybox mount -t iso9660 -o ro /dev/sr0 /media 2>/dev/null; then break; fi
  /bin/busybox sleep 1
done
if [ ! -f /media/live/rootfs.squashfs ]; then
  echo "[live-init] 未找到 rootfs.squashfs，进入救援 shell"
  exec /bin/busybox sh
fi
echo "[live-init] 挂载 live 系统"
/bin/busybox mkdir -p /ro /tmp/upper /tmp/work
/bin/busybox mount -t squashfs -o loop,ro /media/live/rootfs.squashfs /ro || exec /bin/busybox sh
/bin/busybox mount -t tmpfs -o size=512m tmpfs /tmp/upper
/bin/busybox mkdir -p /tmp/upper/upper /tmp/upper/work /newroot
/bin/busybox mount -t overlay overlay -o lowerdir=/ro,upperdir=/tmp/upper/upper,workdir=/tmp/upper/work /newroot || exec /bin/busybox sh
for d in proc sys dev run; do /bin/busybox mkdir -p /newroot/$d; /bin/busybox mount --move /$d /newroot/$d; done
echo "[live-init] switch_root 到澜岫系统"
exec /bin/busybox switch_root /newroot /usr/bin/qyinit
echo "[live-init] switch_root 失败，救援 shell"
exec /bin/busybox sh
