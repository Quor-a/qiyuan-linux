"""libXcursor —— X 光标管理库


许可证：MIT
"""

name = "libXcursor"
version = "1.2.3"
release = 1
summary = "X 光标管理库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXcursor
source = ["https://www.x.org/archive/individual/lib/libXcursor-1.2.3.tar.xz"]
sha256 = ["fde9402dd4cfe79da71e2d96bb980afc5e6ff4f8a7d74c159e1966afb2b2c2c0"]

depends = ["libX11", "libXrender", "libXfixes"]
makedepends = ["libX11", "libXrender", "libXfixes"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
