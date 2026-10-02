"""cmake —— 跨平台构建系统


许可证：BSD-3-Clause
"""

name = "cmake"
version = "3.31.6"
release = 1
summary = "跨平台构建系统"
homepage = ""
license = "BSD-3-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums cmake
source = ["https://example.org/src/cmake-3.31.6.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["curl", "libarchive", "zlib", "expat"]
makedepends = ["openssl", "curl", "libarchive", "zlib", "expat"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --system-curl --system-expat --system-zlib --no-system-jsoncpp --no-system-librhash")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
