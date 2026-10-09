"""xorg-macros —— X.Org 公共 m4/pkgconfig 宏（X11 栈 configure 依赖）

许可证：MIT
"""

name = "xorg-macros"
version = "1.20.2"
release = 1
summary = "X.Org 公共 m4/pkgconfig 宏"
license = "MIT"

source = ["https://xorg.freedesktop.org/archive/individual/util/util-macros-1.20.2.tar.xz"]
sha256 = ["9ac269eba24f672d7d7b3574e4be5f333d13f04a7712303b1821b2a51ac82e8e"]

depends = []
makedepends = ["meson", "ninja"]
provides = ["util-macros"]

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
