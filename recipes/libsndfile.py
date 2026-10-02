"""libsndfile —— 音频文件读写库


许可证：LGPL-2.1-or-later
"""

name = "libsndfile"
version = "1.2.2"
release = 1
summary = "音频文件读写库"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libsndfile
source = ["https://example.org/src/libsndfile-1.2.2.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libsamplerate", "flac", "libogg", "libvorbis", "opus"]
makedepends = ["libsamplerate", "flac", "libogg", "libvorbis", "opus"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
