"""libev —— 事件循环库

许可证：BSD-2-Clause
"""

name = "libev"
version = "4.33"
release = 1
summary = "事件循环库"
license = "BSD-2-Clause"

source = ["https://deb.debian.org/debian/pool/main/libe/libev/libev_4.33.orig.tar.gz"]
sha256 = ["507eb7b8d1015fbec5b935f34ebed15bf346bed04a11ab82b8eee848c4205aea"]
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
