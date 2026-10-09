"""libndp —— 邻居发现协议库（NetworkManager 依赖）

许可证：LGPL-2.1-or-later
"""

name = "libndp"
version = "1.9"
release = 1
summary = "IPv6 邻居发现协议库"
license = "LGPL-2.1-or-later"

source = ["https://github.com/jpirko/libndp/archive/refs/tags/v1.9.tar.gz"]
sha256 = ["f6ca0bb2fce7e93f3276636c889919f85e68abc43d96024cf52c4e91c08da9ce"]

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # github tarball 无预生成 configure，需要 autoreconf
    ctx.run("./autogen.sh --prefix=/usr")
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
