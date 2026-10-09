"""libassuan —— GnuPG IPC 库


许可证：LGPL-2.1-or-later
"""

name = "libassuan"
version = "3.0.2"
release = 1
summary = "GnuPG IPC 库"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libassuan
source = ["https://example.org/src/libassuan-3.0.2.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libgpg-error"]
makedepends = ["libgpg-error"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
