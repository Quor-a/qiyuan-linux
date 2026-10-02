"""xtrans —— X 传输层库（X11 连接抽象，纯头文件+宏）

许可证：MIT
"""

name = "xtrans"
version = "1.6.0"
release = 1
summary = "X 传输层库"
license = "MIT"

source = ["https://xorg.freedesktop.org/archive/individual/lib/xtrans-1.6.0.tar.xz"]
sha256 = ["faafea166bf2451a173d9d593352940ec6404145c5d1da5c213423ce4d359e92"]

depends = ["xorg-macros"]
makedepends = ["xorg-macros"]
provides = []

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
