"""libogg —— Ogg 容器格式库


许可证：BSD-3-Clause
"""

name = "libogg"
version = "1.3.5"
release = 1
summary = "Ogg 容器格式库"
homepage = ""
license = "BSD-3-Clause"

source = ["https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.xz"]
sha256 = ["c4d91be36fc8e54deae7575241e03f4211eb102afb3fc0775fbbc1b740016705"]

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
