"""libXft —— X 字体渲染库（FreeType 与 X 的桥接）


许可证：MIT
"""

name = "libXft"
version = "2.3.8"
release = 1
summary = "X 字体渲染库（FreeType 与 X 的桥接）"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXft
source = ["https://example.org/src/libXft-2.3.8.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libX11", "libXrender", "freetype", "fontconfig"]
makedepends = ["libX11", "libXrender", "freetype", "fontconfig"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
