"""modemmanager —— 移动网络（2G/3G/4G/5G）调制解调器管理

许可证：GPL-2.0-or-later AND LGPL-2.1-or-later
"""

name = "modemmanager"
version = "1.24.0"
release = 1
summary = "移动网络（2G/3G/4G/5G）调制解调器管理"
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

source = ["https://example.org/src/modemmanager-1.24.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["dbus", "glib", "libmbim", "libqmi", "libudev"]
makedepends = ["meson", "ninja", "gobject-introspection", "dbus", "glib", "libmbim", "libqmi", "libudev"]
provides = ["mobile-data"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dsystemd=false -Ddocs=false")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
