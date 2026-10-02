"""upower —— 电源设备管理（电池/唤醒）

许可证：GPL-2.0-or-later
"""

name = "upower"
version = "1.90.7"
release = 1
summary = "电源设备管理（电池/唤醒）"
license = "GPL-2.0-or-later"

source = ["https://example.org/src/upower-1.90.7.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["dbus", "glib", "libudev"]
makedepends = ["meson", "ninja", "gobject-introspection", "dbus", "glib", "libudev"]
provides = ["power-manager"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dsystemd=disabled -Ddocs=false")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
