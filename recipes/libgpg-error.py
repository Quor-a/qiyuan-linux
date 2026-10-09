"""libgpg-error —— GnuPG 错误码库


许可证：GPL-2.0-or-later AND LGPL-2.1-or-later
"""

name = "libgpg-error"
version = "1.51"
release = 1
summary = "GnuPG 错误码库"
homepage = ""
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libgpg-error
source = ["https://example.org/src/libgpg-error-1.51.tar.xz"]
sha256 = []
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
