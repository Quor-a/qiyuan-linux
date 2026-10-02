"""libqmi —— QMI 协议库（高通调制解调器）

许可证：LGPL-2.1-or-later
"""

name = "libqmi"
version = "1.34.0"
release = 1
summary = "QMI 协议库（高通调制解调器）"
license = "LGPL-2.1-or-later"

source = ["https://example.org/src/libqmi-1.34.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["glib", "libmbim"]
makedepends = ["meson", "ninja", "glib", "libmbim"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Ddocs=false")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
