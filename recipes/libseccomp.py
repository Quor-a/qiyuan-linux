"""libseccomp —— seccomp 系统调用过滤库


许可证：LGPL-2.1-or-later
"""

name = "libseccomp"
version = "2.6.0"
release = 1
summary = "seccomp 系统调用过滤库"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libseccomp
source = ["https://example.org/src/libseccomp-2.6.0.tar.xz"]
sha256 = []
checksum_pending = True

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
