"""libxshmfence —— 共享内存同步原语（X 的 GLX 用）


许可证：MIT
"""

name = "libxshmfence"
version = "1.3.3"
release = 1
summary = "共享内存同步原语（X 的 GLX 用）"
homepage = ""
license = "MIT"

source = ["https://www.x.org/archive/individual/lib/libxshmfence-1.3.3.tar.xz"]
sha256 = ["d4a4df096aba96fea02c029ee3a44e11a47eb7f7213c1a729be83e85ec3fde10"]

depends = ["xorgproto"]
makedepends = ["xorgproto", "xorg-macros"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
