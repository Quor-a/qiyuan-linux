"""libXfont2 —— X 服务器字体库


许可证：MIT
"""

name = "libXfont2"
version = "2.0.7"
release = 1
summary = "X 服务器字体库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXfont2
source = ["https://example.org/src/libXfont2-2.0.7.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["freetype", "fontconfig"]
makedepends = ["freetype", "fontconfig"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
