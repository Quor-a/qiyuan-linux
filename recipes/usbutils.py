"""usbutils —— lsusb / USB ID 数据库

许可证：GPL-2.0-or-later（工具）/ GPL-2.0（hid2hc）
与 pciutils 成对：查"插的什么 USB 设备"用 lsusb。
"""
from __future__ import annotations

name = "usbutils"
version = "018"
release = 1
summary = "USB 总线诊断工具（lsusb）与 USB ID 库"
homepage = "https://git.kernel.org/pub/linux/utils/usb/usbutils/"
license = "GPL-2.0-or-later"

source = ["https://mirrors.edge.kernel.org/pub/linux/utils/usb/usbutils/usbutils-018.tar.xz"]
sha256 = ["83f68b59b58547589c00266e82671864627593ab4362d8c807f50eea923cad93"]
checksum_pending = False

depends = ["glibc", "libudev", "zlib"]
makedepends = ["meson", "ninja", "libudev"]
provides = ["lsusb"]

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.out_of_tree()
    # 018 上游 meson.build 无 usbids 选项（ID 数据由 /usr/share/hwdata 惯例路径提供）
    ctx.run("meson " + str(ctx.srcdir) + " --prefix=/usr")
    ctx.run("ninja")


def package(ctx):
    ctx.run("DESTDIR={} ninja install".format(ctx.destdir))
