"""libvorbis —— Vorbis 音频编解码库


许可证：BSD-3-Clause
"""

name = "libvorbis"
version = "1.3.7"
release = 1
summary = "Vorbis 音频编解码库"
homepage = ""
license = "BSD-3-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libvorbis
source = ["https://example.org/src/libvorbis-1.3.7.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libogg"]
makedepends = ["libogg"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
