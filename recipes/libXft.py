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
source = ["https://xorg.freedesktop.org/archive/individual/lib/libXft-2.3.8.tar.xz"]
sha256 = ["5e8c3c4bc2d4c0a40aef6b4b38ed2fb74301640da29f6528154b5009b1c6dd49"]
checksum_pending = False

depends = ["libX11", "libXrender", "freetype", "fontconfig"]
makedepends = ["libX11", "libXrender", "freetype", "fontconfig"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
