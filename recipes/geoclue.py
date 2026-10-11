"""geoclue —— 地理定位服务（WiFi/基站/GPS 混合定位）

许可证：LGPL-2.1-or-later
"""

name = "geoclue"
version = "2.7.1"
release = 1
summary = "地理定位服务（WiFi/基站/GPS 混合定位）"
license = "LGPL-2.1-or-later"

source = ["https://example.org/src/geoclue-2.7.1.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["dbus", "glib", "libsoup", "json-c"]
makedepends = ["meson", "ninja", "dbus", "glib", "libsoup", "json-c"]
provides = ["location"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dsystemd=disabled -D3g-source=false " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
