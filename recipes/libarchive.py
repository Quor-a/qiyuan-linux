"""libarchive —— 多格式归档读写库


许可证：BSD-2-Clause
"""

name = "libarchive"
version = "3.7.8"
release = 1
summary = "多格式归档读写库"
homepage = ""
license = "BSD-2-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libarchive
source = ["https://example.org/src/libarchive-3.7.8.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["zlib", "xz", "zstd", "openssl", "libxml2"]
makedepends = ["zlib", "xz", "zstd", "openssl", "libxml2"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
