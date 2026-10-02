"""bluez —— 蓝牙协议栈

许可证：GPL-2.0-or-later AND LGPL-2.1-or-later
"""

name = "bluez"
version = "5.82"
release = 1
summary = "蓝牙协议栈"
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

source = ["https://example.org/src/bluez-5.82.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["dbus", "glib", "readline", "libudev"]
makedepends = ["meson", "ninja", "dbus", "glib", "readline", "libudev"]
provides = ["bluetooth"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dsystemd=false -Dudevdir=/usr/lib/udev -Dmesh=false -Dmidi=false")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
