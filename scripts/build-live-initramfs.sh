#!/bin/bash
# build-live-initramfs.sh — 生成 live initrd（busybox 脚本 init + squashfs overlay）
# 依赖: 先跑 qyos.initramfs.build 生成基础 initrd（含静态 busybox）: 
#   python3 -c "from qyos.initramfs import build; build(root_target='/dev/sr0', out_path=Path('/tmp/base-initramfs.img'))"
set -e
Q="$(cd "$(dirname "$0")/.." && pwd)"
cd "$Q"
[ -f /tmp/base-initramfs.img ] || python3 -c "
import sys; sys.path.insert(0,'.')
from pathlib import Path
from qyos.initramfs import build
build(root_target='/dev/sr0', out_path=Path('/tmp/base-initramfs.img'))"
rm -rf /tmp/lirfs && mkdir /tmp/lirfs && cd /tmp/lirfs
zcat /tmp/base-initramfs.img | cpio -id 2>/dev/null
ln -sf sh bin/busybox 2>/dev/null || true
cp "$Q/scripts/live-init.sh" init
chmod 755 init
find . | cpio -o -H newc 2>/dev/null | gzip -9 > /tmp/live-initramfs.img
ls -la /tmp/live-initramfs.img
