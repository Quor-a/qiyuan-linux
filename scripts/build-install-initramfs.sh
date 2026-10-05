#!/bin/bash
# build-install-initramfs.sh — 安装版 initrd（root=LABEL 直挂 ext4，非 live overlay）
set -e
LIVE=/tmp/live-initramfs.img
[ -f "$LIVE" ] || { echo "缺 $LIVE"; exit 1; }
rm -rf /tmp/irfs-build && mkdir /tmp/irfs-build
cd /tmp/irfs-build
zcat "$LIVE" | cpio -id 2>/dev/null
cat > init <<'EOF'
#!/bin/busybox sh
/bin/busybox mkdir -p /proc /sys /dev /newroot /run
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev
ROOT=""
for o in $(cat /proc/cmdline); do case "$o" in root=*) ROOT="${o#root=}";; esac; done
echo "[qy-init] mount $ROOT"
i=0
while [ $i -lt 15 ]; do /bin/busybox mount -t ext4 "$ROOT" /newroot 2>/dev/null && break; i=$((i+1)); /bin/busybox sleep 1; done
[ -x /newroot/usr/bin/qyinit ] || { echo "[qy-init] mount $ROOT failed"; exec /bin/busybox sh; }
for d in proc sys dev run; do /bin/busybox mkdir -p /newroot/$d; /bin/busybox mount --move /$d /newroot/$d; done
exec /bin/busybox switch_root /newroot /usr/bin/qyinit
EOF
chmod 755 init
find . | cpio -o -H newc 2>/dev/null | gzip -9 > /tmp/initramfs-install.img
ls -la /tmp/initramfs-install.img
