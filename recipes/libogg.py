"""libogg —— Ogg 容器格式库


许可证：BSD-3-Clause
"""

name = "libogg"
version = "1.3.5"
release = 1
summary = "Ogg 容器格式库"
homepage = ""
license = "BSD-3-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libogg
source = ["https://example.org/src/libogg-1.3.5.tar.xz"]
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
