"""libusb —— 用户态 USB 访问

许可证：LGPL-2.1-or-later

ADB、刷机工具、USB 转串口、软件定义无线电都依赖它。
没有它，插上设备系统识别得到但程序访问不了。
"""
from __future__ import annotations

name = "libusb"
version = "1.0.29"
release = 1
summary = "用户态 USB 设备访问"
homepage = "https://libusb.info/"
license = "LGPL-2.1-or-later"

source = ["https://ghproxy.net/https://github.com/libusb/libusb/releases/download/v1.0.29/libusb-1.0.29.tar.bz2"]
sha256 = ["5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85"]

depends = []
makedepends = ["pkgconf"]
provides = ["libusb-1.0.so.0"]
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
