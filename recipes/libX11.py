"""libX11 —— X11 客户端核心库


许可证：MIT
"""

name = "libX11"
version = "1.8.12"
release = 1
summary = "X11 客户端核心库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libX11
source = ["https://www.x.org/archive/individual/lib/libX11-1.8.12.tar.xz"]
sha256 = ["fa026f9bb0124f4d6c808f9aef4057aad65e7b35d8ff43951cef0abe06bb9a9a"]

depends = ["xorgproto", "libxcb", "libXau", "libXdmcp", "xtrans"]
makedepends = ["xtrans", "xorg-macros", "inputproto", "kbproto", "xextproto", "xorgproto", "libxcb", "libXau", "libXdmcp"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
