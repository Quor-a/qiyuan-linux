"""pciutils —— lspci / setpci / PCI ID 数据库

许可证：GPL-2.0-or-later
硬件诊断基础：用户报障第一步是 `lspci -nn`，没有它
连"这台机器是什么网卡"都查不出来。
"""
from __future__ import annotations

name = "pciutils"
version = "3.14.0"
release = 1
summary = "PCI 总线诊断工具（lspci/setpci）与 PCI ID 库"
homepage = "https://mj.ucw.cz/sw/pciutils/"
license = "GPL-2.0-or-later"

source = ["https://mj.ucw.cz/download/linux/pci/pciutils-3.14.0.tar.gz"]
sha256 = ["e31c79722dbbe9d2906b92996ce295268e54d4342fefe3ff476caa613e51be2a"]
checksum_pending = False

depends = ["glibc", "zlib"]
makedepends = ["glibc", "zlib"]
provides = ["lspci"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # 上游 Makefile 是自写的，不走 configure；交叉参数用变量传
    ctx.run("make -j2 PREFIX=/usr SHAREDIR=/usr/share/hwdata "
            "MANDIR=/usr/share/man SBINDIR=/usr/bin "
            "CC=gcc CFLAGS='-O2 -pipe' "
            "IDSDIR=/usr/share/hwdata")
    ctx.run("make PREFIX=/usr SHAREDIR=/usr/share/hwdata "
            "MANDIR=/usr/share/man SBINDIR=/usr/bin "
            "IDSDIR=/usr/share/hwdata update-pciids DESTDIR=" + str(ctx.destdir),
            check=False)  # 联网更新 ID 库失败不致命，用随包带的


def package(ctx):
    ctx.run("make install PREFIX=/usr SHAREDIR=/usr/share/hwdata "
            "MANDIR=/usr/share/man SBINDIR=/usr/bin "
            "IDSDIR=/usr/share/hwdata DESTDIR=" + str(ctx.destdir))
