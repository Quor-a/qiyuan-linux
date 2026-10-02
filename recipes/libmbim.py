"""libmbim —— MBIM 协议库（移动宽带调制解调器）

许可证：LGPL-2.1-or-later
"""

name = "libmbim"
version = "1.30.0"
release = 1
summary = "MBIM 协议库（移动宽带调制解调器）"
license = "LGPL-2.1-or-later"

source = ["https://example.org/src/libmbim-1.30.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["glib"]
makedepends = ["meson", "ninja", "glib"]
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
