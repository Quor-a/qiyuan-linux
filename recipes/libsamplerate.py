"""libsamplerate —— 采样率转换库


许可证：BSD-2-Clause
"""

name = "libsamplerate"
version = "0.2.2"
release = 1
summary = "采样率转换库"
homepage = ""
license = "BSD-2-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libsamplerate
source = ["https://example.org/src/libsamplerate-0.2.2.tar.xz"]
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
