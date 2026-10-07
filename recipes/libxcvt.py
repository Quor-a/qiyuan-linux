"""libxcvt —— VESA CVT 标准模型计算库（xorg-server 21.1+ 硬依赖）

许可证：MIT
"""

name = "libxcvt"
version = "0.1.2"
release = 1
summary = "VESA CVT 标准模型计算库"
license = "MIT"

source = ["https://www.x.org/releases/individual/lib/libxcvt-0.1.2.tar.xz"]
sha256 = ["0561690544796e25cfbd71806ba1b0d797ffe464e9796411123e79450f71db38"]

depends = []
makedepends = ["meson", "ninja"]
provides = []

requires_build_machine = True

network = False
compression = "xz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
